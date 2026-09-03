.POSIX:

all:
	cd src/drop && $(MAKE)
	cd src/sink && $(MAKE)

clean:
	cd src/drop && $(MAKE) clean
	cd src/sink && $(MAKE) clean

.PHONY: all clean
