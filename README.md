# Distill Linux Ports & Package Management Infrastructure

This repository contains the core native package management infrastructure and official source recipes for **Distill Linux**, a minimal Linux distribution built on `musl libc`, `Toybox`, and strict POSIX compliance.

The ecosystem consists of two separate, native C utilities:
1. **`drop`**: Official precompiled binary package manager (ultra-minimal, <40 KB, pure musl + zlib).
2. **`sink`**: Community user repository helper and build engine (libgit2 + libcurl + musl + zlib).

Official package repository is published live at:
**[https://distill-linux.github.io/](https://distill-linux.github.io/)**

---

## 1. Quick Usage

### In Distill Linux (`drop`):
```sh
# Configure repository
export DROP_REPO_URL="https://distill-linux.github.io"

# Update package catalog
drop update

# Install samurai
drop in samurai

# Verify package integrity
drop check samurai

# List installed packages
drop ls

# Uninstall
drop rm samurai
```

### Building Packages from Source (`sink`):
```sh
# Build from a recipe file
sink make recipes/samurai.port

# Build and automatically install
sink make -i recipes/samurai.port

# Inspect recipe metadata
sink info recipes/samurai.port

# Clean temporary build workspace
sink clean
```

---

## 2. The `.PORT` Specification

All packages use `.drop` containers (streaming zlib-compressed POSIX `ustar`) where the very first entry is the `.PORT` file.

```ini
PORT_NAME="samurai"
PORT_VERSION="1.2"
PORT_RELEASE="1"
PORT_DESC="Ninja-compatible build tool written in C"
PORT_URL="https://github.com/michaelforney/samurai.git"
PORT_COMMIT="1.2"
BUILD_SYSTEM="make"
BUILD_DEPS=""
RUN_DEPS=""

BUILD:
make PREFIX=/usr
make DESTDIR="$PKG_FAKEROOT" PREFIX=/usr install

FILES:
/usr/bin/samu:6a6ca06b2dc038299ddb2843144fb160f4818b3f42a9ae6839843f3d1aba39a4
/usr/share/man/man1/samu.1:b4f535...
```

---

## 3. Building `drop` and `sink`

GNU `make` is strictly forbidden. The codebase builds with **Samurai (`samu`)** by default, or BSD `bmake`:

```sh
# Build with samurai
samu -v

# Or build with BSD make
bmake
```

### Running Test Suite:
```sh
./tests/run_all.sh
```

---

## 4. Contributing New Recipes

To add a new package:
1. Create `recipes/<pkgname>.port`.
2. Test build locally with `sink make recipes/<pkgname>.port`.
3. Verify installation with `drop in <pkgname>-<version>.drop` and `drop check <pkgname>`.
4. Open a Pull Request to this repository. Upon merge to `main`, GitHub Actions automatically builds the package and updates `https://distill-linux.github.io/`.
