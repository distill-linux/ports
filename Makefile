.POSIX:

all: packages

packages:
	mkdir -p dist-packages
	for r in recipes/*.port; do \
		[ -f "$$r" ] || continue; \
		sink --out dist-packages make "$$r"; \
	done
	./tools/gen-repo.sh dist-packages

clean:
	rm -rf dist-packages /tmp/sink

.PHONY: all packages clean
