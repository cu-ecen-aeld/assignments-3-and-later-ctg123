#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <arpa/inet.h>
#include <syslog.h>
#include <signal.h>
#include <fcntl.h>
#include <pthread.h>
#include <time.h>
#include <stdbool.h>
#include <errno.h>

#define PORT 9000
#define BUFFER_SIZE 1024
#define TIMESTAMP_INTERVAL 10 // 10 seconds

// File path
const char *filename = "/var/tmp/aesdsocketdata";

// Global variables
static int serverFD;
static FILE *file;
static volatile bool running = true;
static pthread_mutex_t file_mutex = PTHREAD_MUTEX_INITIALIZER;

// Thread node structure
typedef struct thread_node {
    pthread_t thread_id;
    int client_fd;
    struct sockaddr_in client_addr;
    struct thread_node *next;
} thread_node_t;

// Thread linked list
static thread_node_t *thread_list_head = NULL;
static pthread_mutex_t thread_list_mutex = PTHREAD_MUTEX_INITIALIZER;

// Function prototypes
void add_thread_to_list(thread_node_t *node);
void remove_thread_from_list(pthread_t thread_id);
void cleanup_all_threads();
void *handle_client(void *arg);
void *timestamp_thread(void *arg);
char *read_until_newline(int clientFD);
void handle_signals(int sig);
void create_daemon();

// Daemon creation function
void create_daemon() {
    pid_t pid;

    // Fork child process, and terminate parent process
    pid = fork();
    if (pid < 0) {
        perror("Fork failed");
        exit(EXIT_FAILURE);
    }
    if (pid > 0)
        exit(EXIT_SUCCESS);

    // Create new session
    if (setsid() < 0) {
        perror("Setsid failed");
        exit(EXIT_FAILURE);
    }

    // Fork again
    pid = fork();
    if (pid < 0) {
        perror("Fork failed");
        exit(EXIT_FAILURE);
    }
    if (pid > 0)
        exit(EXIT_SUCCESS);

    umask(0);

    // Close standard in, out, err
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);
    open("/dev/null", O_RDONLY);
    open("/dev/null", O_WRONLY);
    open("/dev/null", O_RDWR);
}

// Signal handler
void handle_signals(int sig) {
    syslog(LOG_DEBUG, "Caught signal, exiting");
    running = false;

    // Closing server socket
    if (serverFD > 0) {
        close(serverFD);
    }

    // Wait for all threads to complete
    cleanup_all_threads();

    // Delete the socket data file
    if (remove(filename) == 0) {
        syslog(LOG_DEBUG, "File %s deleted successfully.", filename);
    } else {
        syslog(LOG_ERR, "Error deleting the file %s: %s", filename, strerror(errno));
    }

    // Close syslog and exit
    closelog();
    exit(0);
}

// Add thread to linked list
void add_thread_to_list(thread_node_t *node) {
    pthread_mutex_lock(&thread_list_mutex);
    
    // Add at the beginning of the list
    if (thread_list_head == NULL) {
        thread_list_head = node;
    } else {
        node->next = thread_list_head;
        thread_list_head = node;
    }
    
    pthread_mutex_unlock(&thread_list_mutex);
}

// Remove thread from linked list
void remove_thread_from_list(pthread_t thread_id) {
    pthread_mutex_lock(&thread_list_mutex);
    
    thread_node_t *current = thread_list_head;
    thread_node_t *prev = NULL;
    
    // Search for the thread
    while (current != NULL) {
        if (pthread_equal(current->thread_id, thread_id)) {
            // Remove from list
            if (prev == NULL) {
                thread_list_head = current->next;
            } else {
                prev->next = current->next;
            }
            
            // Close client socket
            if (current->client_fd > 0) {
                close(current->client_fd);
            }
            
            free(current);
            break;
        }
        
        prev = current;
        current = current->next;
    }
    
    pthread_mutex_unlock(&thread_list_mutex);
}

// Clean up all threads
void cleanup_all_threads() {
    pthread_mutex_lock(&thread_list_mutex);
    
    thread_node_t *current = thread_list_head;
    thread_node_t *temp;
    
    while (current != NULL) {
        // Join thread
        if (pthread_join(current->thread_id, NULL) != 0) {
            syslog(LOG_ERR, "Error joining thread: %s", strerror(errno));
        }
        
        // Close client socket
        if (current->client_fd > 0) {
            close(current->client_fd);
        }
        
        temp = current;
        current = current->next;
        free(temp);
    }
    
    thread_list_head = NULL;
    pthread_mutex_unlock(&thread_list_mutex);
}

// Read data from client until newline
char *read_until_newline(int clientFD) {
    char buffer[BUFFER_SIZE] = {0};
    char *result = NULL;
    size_t totalSize = 0;

    while (1) {
        memset(buffer, 0, sizeof(buffer));
        ssize_t bytesNum = recv(clientFD, buffer, BUFFER_SIZE, 0);
        
        if (bytesNum < 0) {
            perror("Read error");
            free(result);
            return NULL;
        } else if (bytesNum == 0) {
            // Client was closed
            break;
        }

        // Expand buffer(result)
        char *temp = realloc(result, totalSize + bytesNum + 1); // +1 for '\0'
        if (temp == NULL) {
            perror("Memory allocation error");
            free(result);
            return NULL;
        }
        result = temp;

        // Copy to buffer(result)
        memcpy(result + totalSize, buffer, bytesNum);
        totalSize += bytesNum;
        
        if (buffer[bytesNum-1] == '\n') {
            // Found newline
            result[totalSize] = '\0';
            break;
        }
    }
    
    return result;
}

// Thread function to append timestamp
void *timestamp_thread(void *arg) {
    time_t rawtime;
    struct tm *timeinfo;
    char timestamp_buffer[100];

    while (running) {
        // Sleep for 10 seconds
        sleep(TIMESTAMP_INTERVAL);
        
        if (!running) break;

        // Get current time
        time(&rawtime);
        timeinfo = localtime(&rawtime);
        
        // Format timestamp according to RFC 2822
        strftime(timestamp_buffer, sizeof(timestamp_buffer), 
                 "timestamp:%a, %d %b %Y %H:%M:%S %z\n", timeinfo);

        // Append timestamp to file with mutex protection
        pthread_mutex_lock(&file_mutex);
        
        FILE *timestamp_file = fopen(filename, "a");
        if (timestamp_file != NULL) {
            fprintf(timestamp_file, "%s", timestamp_buffer);
            fclose(timestamp_file);
        } else {
            syslog(LOG_ERR, "Error opening file for timestamp: %s", strerror(errno));
        }
        
        pthread_mutex_unlock(&file_mutex);
    }
    
    return NULL;
}

// Thread function to handle client connection
void *handle_client(void *arg) {
    thread_node_t *thread_data = (thread_node_t *)arg;
    int clientFD = thread_data->client_fd;
    struct sockaddr_in client_addr = thread_data->client_addr;
    char clientIP[INET_ADDRSTRLEN];
    char buffer[BUFFER_SIZE] = {0};

    // Get client IP address
    inet_ntop(AF_INET, &client_addr.sin_addr, clientIP, sizeof(clientIP));
    syslog(LOG_DEBUG, "Accepted connection from %s", clientIP);

    // Receive data from client
    char *result = read_until_newline(clientFD);
    if (result != NULL) {
        // Write data to file with mutex protection
        pthread_mutex_lock(&file_mutex);
        
        FILE *client_file = fopen(filename, "a+");
        if (client_file != NULL) {
            fprintf(client_file, "%s", result);
            fclose(client_file);
        } else {
            syslog(LOG_ERR, "Error opening file for writing: %s", strerror(errno));
        }
        
        pthread_mutex_unlock(&file_mutex);

        // Send entire file back to client
        pthread_mutex_lock(&file_mutex);
        
        FILE *read_file = fopen(filename, "r");
        if (read_file != NULL) {
            while (fgets(buffer, BUFFER_SIZE, read_file) != NULL) {
                send(clientFD, buffer, strlen(buffer), 0);
                memset(buffer, 0, BUFFER_SIZE);
            }
            fclose(read_file);
        } else {
            syslog(LOG_ERR, "Error opening file for reading: %s", strerror(errno));
        }
        
        pthread_mutex_unlock(&file_mutex);

        free(result);
    }

    // Log connection close
    syslog(LOG_DEBUG, "Closed connection from %s", clientIP);
    
    // Remove thread from list and exit
    remove_thread_from_list(thread_data->thread_id);
    return NULL;
}

int main(int argc, const char* argv[]) {
    struct sockaddr_in server_addr;
    int one = 1;
    pthread_t timestamp_thread_id;

    // Register signal handlers
    if (signal(SIGINT, handle_signals) == SIG_ERR) {
        perror("Unable to set SIGINT handler");
        exit(1);
    }

    if (signal(SIGTERM, handle_signals) == SIG_ERR) {
        perror("Unable to set SIGTERM handler");
        exit(1);
    }

    // Create server socket
    if ((serverFD = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
        perror("Socket creation failed");
        return -1;
    }

    // Set socket options
    if (setsockopt(serverFD, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) < 0) {
        perror("Setsockopt failed");
        close(serverFD);
        return -1;
    }

    // Configure server address
    memset(&server_addr, 0, sizeof(server_addr));
    server_addr.sin_family = AF_INET;
    server_addr.sin_addr.s_addr = INADDR_ANY;
    server_addr.sin_port = htons(PORT);

    // Bind socket
    if (bind(serverFD, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
        perror("Bind failed");
        close(serverFD);
        return -1;
    }

    // Check for daemon mode
    if (argc == 2 && strcmp(argv[1], "-d") == 0) {
        create_daemon();
    }

    // Open syslog
    openlog("aesdsocket", LOG_PID | LOG_CONS, LOG_USER);

    // Create/truncate the output file
    file = fopen(filename, "w");
    if (file == NULL) {
        syslog(LOG_ERR, "Error creating file: %s", strerror(errno));
        close(serverFD);
        closelog();
        return -1;
    }
    fclose(file);

    // Listen for connections
    if (listen(serverFD, 10) < 0) {
        perror("Listen failed");
        close(serverFD);
        closelog();
        return -1;
    }

    // Start timestamp thread
    if (pthread_create(&timestamp_thread_id, NULL, timestamp_thread, NULL) != 0) {
        syslog(LOG_ERR, "Error creating timestamp thread: %s", strerror(errno));
        close(serverFD);
        closelog();
        return -1;
    }

    // Main server loop
    while (running) {
        // Allocate thread node
        thread_node_t *node = malloc(sizeof(thread_node_t));
        if (node == NULL) {
            syslog(LOG_ERR, "Memory allocation error");
            continue;
        }
        
        memset(node, 0, sizeof(thread_node_t));
        socklen_t addr_len = sizeof(node->client_addr);

        // Accept client connection
        node->client_fd = accept(serverFD, (struct sockaddr *)&node->client_addr, &addr_len);
        if (node->client_fd < 0) {
            if (errno == EINTR) {
                // Interrupted by signal, check if we should continue
                free(node);
                if (!running) break;
                continue;
            }
            
            syslog(LOG_ERR, "Accept failed: %s", strerror(errno));
            free(node);
            continue;
        }

        // Create thread to handle client
        if (pthread_create(&node->thread_id, NULL, handle_client, node) != 0) {
            syslog(LOG_ERR, "Error creating thread: %s", strerror(errno));
            close(node->client_fd);
            free(node);
            continue;
        }

        // Add thread to list
        add_thread_to_list(node);
    }

    // Wait for timestamp thread to finish
    if (pthread_join(timestamp_thread_id, NULL) != 0) {
        syslog(LOG_ERR, "Error joining timestamp thread: %s", strerror(errno));
    }

    // Clean up and exit
    close(serverFD);
    closelog();
    pthread_mutex_destroy(&file_mutex);
    pthread_mutex_destroy(&thread_list_mutex);

    return 0;
}