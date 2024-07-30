CROSS_COMPILE ?=
CC := $(CROSS_COMPILE)gcc
SRC = writer.c
OBJS = $(SRC:.c=.o)

all: writer

%.o: %.c
	$(CC) -c -o $(@F) $(CFLAGS) $<

writer: $(OBJS)
	$(CC) -o $(@F) $(OBJS)

clean:
	rm -f $(OBJS)
	rm -f writer
