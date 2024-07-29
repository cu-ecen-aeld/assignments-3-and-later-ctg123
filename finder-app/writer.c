#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <string.h>
#include <errno.h>
#include <libgen.h>

int main(int argc, char *argv[]) {
    // Setup syslog
    openlog(NULL, LOG_CONS | LOG_PID | LOG_PERROR, LOG_USER);

    // Check if both arguments are provided
    if (argc != 3) {
        syslog(LOG_ERR, "Error: Two arguments required.");
        fprintf(stderr, "Usage: %s <file_path> <string_to_write>\n", argv[0]);
        closelog();
        return 1;
    }

    const char *writefile = argv[1];
    const char *writestr = argv[2];

    // Open the file for writing
    FILE *file = fopen(writefile, "w");
    if (file == NULL) {
        syslog(LOG_ERR, "Error: Could not create file %s: %s", writefile, strerror(errno));
        fprintf(stderr, "Error: Could not create file %s\n", writefile);
        closelog();
        return 1;
    }

    // Write the content to the file
    if (fputs(writestr, file) == EOF) {
        syslog(LOG_ERR, "Error: Could not write to file %s: %s", writefile, strerror(errno));
        fprintf(stderr, "Error: Could not write to file %s\n", writefile);
        fclose(file);
        closelog();
        return 1;
    }

    // Close the file
    fclose(file);

    // Log success message
    syslog(LOG_DEBUG, "Writing %s to %s", writestr, writefile);
    printf("File created successfully: %s\n", writefile);

    closelog();
    return 0;
}