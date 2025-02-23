#!/bin/sh

# Daemon configuration
DAEMON_NAME="aesdsocket"
DAEMON_PATH="./aesdsocket"

# Start the daemon
start() {
    echo "Starting ${DAEMON_NAME}..."
    # -S: start the daemon
    # -n: match process by name
    # -a: path to the executable
    # -- -d: pass -d argument to run in daemon mode
    start-stop-daemon -S -n ${DAEMON_NAME} -a ${DAEMON_PATH} -- -d
    
    if [ $? -eq 0 ]; then
        echo "${DAEMON_NAME} started successfully."
    else
        echo "Failed to start ${DAEMON_NAME}."
    fi
}

# Stop the daemon
stop() {
    echo "Stopping ${DAEMON_NAME}..."
    # -K: stop the daemon
    # -n: match process by name
    # Note: SIGTERM will trigger cleanup in the C program
    start-stop-daemon -K -n ${DAEMON_NAME}
    
    if [ $? -eq 0 ]; then
        echo "${DAEMON_NAME} stopped."
    else
        echo "Failed to stop ${DAEMON_NAME}."
    fi
}

# Handle command line arguments
case "$1" in
    start) start ;;
    stop)  stop ;;
    *)     echo "Usage: $0 {start|stop}" ; exit 1 ;;
esac

exit 0