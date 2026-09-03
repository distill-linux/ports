#!/bin/sh
set -e

DROP_BIN="/home/foggy/distill/src/drop/drop"
SINK_BIN="/home/foggy/distill/src/sink/sink"
TEST_ROOT="/tmp/sink_install_root"
SRC_REPO_DIR="/tmp/calc_src_repo"
RECIPES_DIR="/home/foggy/distill/tests/recipes"

echo "=== Starting sink Source Builder Integration Tests ==="
rm -rf "$TEST_ROOT" "$SRC_REPO_DIR" /tmp/sink-out
mkdir -p "$TEST_ROOT" "$SRC_REPO_DIR" /tmp/sink-out "$RECIPES_DIR"

# 1. Setup a Git repository for a real C program built with samurai
git init "$SRC_REPO_DIR"
git -C "$SRC_REPO_DIR" config user.name "Distill Dev"
git -C "$SRC_REPO_DIR" config user.email "dev@distilllinux.org"

cat << 'CCODE' > "$SRC_REPO_DIR/main.c"
#include <stdio.h>
int main(void) {
    printf("Distill Sink Calculator: 100\n");
    return 0;
}
CCODE

cat << 'NINJA' > "$SRC_REPO_DIR/build.ninja"
rule cc
  command = clang -Os -Wall -c $in -o $out
rule link
  command = clang $in -o $out
rule install
  command = install -D -m 755 distill-calc $$PKG_FAKEROOT/usr/bin/distill-calc && ln -s distill-calc $$PKG_FAKEROOT/usr/bin/calc-symlink

build main.o: cc main.c
build distill-calc: link main.o
build install: install distill-calc
default distill-calc
NINJA

git -C "$SRC_REPO_DIR" add main.c build.ninja
git -C "$SRC_REPO_DIR" commit -m "Initial commit for distill-calc"
COMMIT_HASH=$(git -C "$SRC_REPO_DIR" rev-parse HEAD)

# 2. Write the unified .PORT recipe
cat << RECP > "$RECIPES_DIR/distill-calc.port"
PORT_NAME="distill-calc"
PORT_VERSION="2.1.0"
PORT_RELEASE="1"
PORT_DESC="Distill Linux High-Precision Calculator"
PORT_URL="file://$SRC_REPO_DIR"
PORT_COMMIT="$COMMIT_HASH"
BUILD_SYSTEM="samu"
BUILD_DEPS="samurai"
RUN_DEPS="musl"

BUILD:
    samu -v
    DESTDIR=$PKG_FAKEROOT samu install
RECP

echo "--> Testing 'sink info <recipe>'"
"$SINK_BIN" info "$RECIPES_DIR/distill-calc.port"

echo "--> Testing 'sink make -i' with samurai, libgit2, ELF strip, and auto-install via drop"
"$SINK_BIN" --drop "$DROP_BIN" -r "$TEST_ROOT" --out /tmp/sink-out -i -y make "$RECIPES_DIR/distill-calc.port"

# 3. Verify archive exists with .drop extension
ARCHIVE="/tmp/sink-out/distill-calc-2.1.0.drop"
test -f "$ARCHIVE"

# 4. Verify installed binary and symlink
INSTALLED_BIN="$TEST_ROOT/usr/bin/distill-calc"
INSTALLED_LINK="$TEST_ROOT/usr/bin/calc-symlink"
test -f "$INSTALLED_BIN"
test -L "$INSTALLED_LINK"

echo "--> Running installed binary inside musl environment"
OUTPUT=$("$INSTALLED_BIN")
echo "Output: $OUTPUT"
echo "$OUTPUT" | grep "Distill Sink Calculator: 100"

echo "--> Verifying database registration via 'drop ls' and 'drop info'"
"$DROP_BIN" -r "$TEST_ROOT" ls | grep "distill-calc"
"$DROP_BIN" -r "$TEST_ROOT" info distill-calc | grep "Version:      2.1.0"
"$DROP_BIN" -r "$TEST_ROOT" info distill-calc | grep "Description:  Distill Linux High-Precision Calculator"

echo "--> Verifying SHA-256 integrity check on installed files ('drop check')"
"$DROP_BIN" -r "$TEST_ROOT" check distill-calc

echo "--> Testing 'sink clean' to purge scratch workspace"
"$SINK_BIN" clean

echo "--> Removing built package via 'drop rm'"
"$DROP_BIN" -r "$TEST_ROOT" rm distill-calc
if [ -f "$INSTALLED_BIN" ]; then
    echo "ERROR: distill-calc was not uninstalled"
    exit 1
fi

echo "=== All sink Integration Tests Passed! ==="
