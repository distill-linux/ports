#!/bin/sh
set -e
echo "==> Validating recipes in recipes/..."
for r in recipes/*.port; do
    [ -f "$r" ] || continue
    echo "Checking $r..."
    grep -q "^PORT_NAME=" "$r" || { echo "Missing PORT_NAME in $r"; exit 1; }
    grep -q "^PORT_VERSION=" "$r" || { echo "Missing PORT_VERSION in $r"; exit 1; }
    grep -q "^PORT_RELEASE=" "$r" || { echo "Missing PORT_RELEASE in $r"; exit 1; }
    grep -q "^PORT_DESC=" "$r" || { echo "Missing PORT_DESC in $r"; exit 1; }
    grep -q "^PORT_URL=" "$r" || { echo "Missing PORT_URL in $r"; exit 1; }
    grep -q "^BUILD:" "$r" || { echo "Missing BUILD: in $r"; exit 1; }
done
echo "==> All recipes are valid!"
