.POSIX:

CC ?= clang
CFLAGS ?= -Os -fno-asynchronous-unwind-tables -ffunction-sections -fdata-sections -Wall -Wextra -pedantic -Werror -std=c99 -I../common
LDFLAGS ?= -Wl,--gc-sections
LDADD ?= -lgit2 -lcurl -lz

OBJS = main.o deps.o git_util.o elf_strip.o builder.o ../common/port.o ../common/sha256.o ../common/spawn_util.o ../common/tar.o

all: sink

sink: $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) $(LDADD)
	strip -s $@

.c.o:
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -f sink $(OBJS)

.PHONY: all clean
