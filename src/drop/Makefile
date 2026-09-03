.POSIX:

CC ?= gcc
CFLAGS ?= -Os -fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections -Wall -Wextra -pedantic -Werror -std=c99 -I../common
LDFLAGS ?= -Wl,--gc-sections
LDADD ?= -lz

OBJS = main.o index.o db.o extractor.o ../common/port.o ../common/sha256.o ../common/spawn_util.o ../common/tar.o

all: drop

drop: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(LDADD)
	strip -s $@

.c.o:
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f drop $(OBJS)

.PHONY: all clean
