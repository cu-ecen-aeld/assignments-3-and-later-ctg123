# Compiler settings
CC = $(CROSS_COMPILE)gcc
CFLAGS = -Wall -Wextra -std=c11
LDFLAGS =

# Source files
SRCS := writer.c

# Object files
OBJS = $(SRCS:.c=.o)

# Target executable name
TARGET = writer

# Default target builds the native or cross-compiled version of the application
all: $(TARGET)

# Linking rule for creating the executable
$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS)

# Compilation rule for object files
%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

# Cross-compile target for aarch64 architecture
cross-compile:
	$(MAKE) CROSS_COMPILE=aarch64-none-linux-gnu-

# Clean target to remove the application and all object files
clean:
	rm -f $(TARGET) $(OBJS)

# Phony targets declaration
.PHONY: all clean cross

