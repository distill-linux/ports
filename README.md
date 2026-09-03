# Distill Linux Ports & Package Recipes

Official package recipes and repository catalog generator for **Distill Linux**.

## Native Package Tooling
Distill package management is split across dedicated repositories:
- **[`drop`](https://github.com/distill-linux/drop)**: Minimal binary package manager (<40 KB stripped, musl + zlib).
- **[`sink`](https://github.com/distill-linux/sink)**: Community source builder and ports engine (libgit2 + libcurl + zlib).
- **[`ports`](https://github.com/distill-linux/ports)** (this repo): Official package recipes and repository catalog tooling.

Official package repository catalog is published live at:
**[https://distill-linux.github.io/pkgs/](https://distill-linux.github.io/pkgs/)**

---

## 1. Quick Usage

### In Distill Linux (`drop`):
```sh
# Configure repository
export DROP_REPO_URL="https://distill-linux.github.io/pkgs"

# Update package catalog
drop update

# Install a package
drop in samurai

# Verify package integrity against stored SHA-256 hashes
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

## 2. Available Recipes

| Recipe | Description | Upstream Source |
|---|---|---|
| [`recipes/samurai.port`](recipes/samurai.port) | Ninja-compatible build tool written in C | [michaelforney/samurai](https://github.com/michaelforney/samurai) |
| [`recipes/drop.port`](recipes/drop.port) | Native binary package manager for Distill Linux | [distill-linux/drop](https://github.com/distill-linux/drop) |
| [`recipes/sink.port`](recipes/sink.port) | Community source builder & ports engine | [distill-linux/sink](https://github.com/distill-linux/sink) |

---

## 3. The `.PORT` Specification

All packages produce `.drop` containers (streaming zlib-compressed POSIX `ustar`) where entry #1 is the `.PORT` file.

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
make CC=clang PREFIX=/usr
make DESTDIR="$PKG_FAKEROOT" PREFIX=/usr install

FILES:
/usr/bin/samu:8a0b2a40...
/usr/share/man/man1/samu.1:3fb96b...
```

---

## 4. Contributing New Recipes

To add a new package:
1. Create `recipes/<pkgname>.port`.
2. Test build locally with `sink make recipes/<pkgname>.port`.
3. Verify installation with `drop in <pkgname>-<version>.drop` and `drop check <pkgname>`.
4. Open a Pull Request to this repository.
