CC := gcc
CROSS_COMPILE :=
CFLAGS := -Wall -Werror
LDFLAGS := -lpthread

ifdef CROSS_COMPILE
	CC := $(CROSS_COMPILE)gcc
endif

all: program

program: aesdsocket.c
	$(CC) $(CFLAGS) -c aesdsocket.c
	$(CC) -o aesdsocket aesdsocket.o $(LDFLAGS)

clean:
	rm -f aesdsocket aesdsocket.o