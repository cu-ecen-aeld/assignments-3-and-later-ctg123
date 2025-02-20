CC := gcc
CROSS_COMPILE :=

ifdef CROSS_COMPILE
	CC := $(CROSS_COMPILE)gcc
endif

all : program

program : aesdsocket.c
	$(CC) -c aesdsocket.c
	$(CC) -o aesdsocket aesdsocket.o

clean:
	rm -f aesdsocket aesdsocket.o