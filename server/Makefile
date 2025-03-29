# Don't set CC directly, let the build system provide it
# CC := gcc
CFLAGS := -Wall -Werror
LDFLAGS := -lpthread

# Only set CC if CROSS_COMPILE is provided and CC isn't already set
ifdef CROSS_COMPILE
	CC ?= $(CROSS_COMPILE)gcc
endif

all: program

program: aesdsocket.c
	$(CC) $(CFLAGS) -c aesdsocket.c
	$(CC) -o aesdsocket aesdsocket.o $(LDFLAGS)

clean:
	rm -f aesdsocket aesdsocket.o