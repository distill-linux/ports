#!/bin/sh
set -e

REPO_DIR="${1:-.}"
mkdir -p "$REPO_DIR"
INDEX_TSV="$REPO_DIR/index.tsv"
INDEX_HTML="$REPO_DIR/index.html"

echo "==> Scanning $REPO_DIR for .drop packages..."

# Start index.tsv
printf "# Distill Linux Package Catalog\n# NAME\tVERSION\tSHA256\tSIZE\tFILENAME\tDEPENDS\n" > "$INDEX_TSV"

# Start index.html
cat << 'HTMLEOF' > "$INDEX_HTML"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Distill Linux Package Repository</title>
  <style>
    :root { --bg: #0f1117; --card: #181b24; --text: #e1e4ea; --accent: #38bdf8; --border: #282d3d; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: var(--bg); color: var(--text); margin: 0; padding: 2rem; }
    .container { max-width: 960px; margin: 0 auto; }
    header { border-bottom: 1px solid var(--border); padding-bottom: 1.5rem; margin-bottom: 2rem; }
    h1 { margin: 0 0 0.5rem 0; color: var(--accent); }
    code, pre { font-family: ui-monospace, SFMono-Regular, Consolas, monospace; background: var(--card); border: 1px solid var(--border); border-radius: 4px; padding: 0.2rem 0.4rem; }
    pre { padding: 1rem; overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; margin-top: 1.5rem; background: var(--card); border-radius: 6px; overflow: hidden; border: 1px solid var(--border); }
    th, td { text-align: left; padding: 0.75rem 1rem; border-bottom: 1px solid var(--border); }
    th { background: #13161f; color: var(--accent); font-weight: 600; }
    tr:last-child td { border-bottom: none; }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    .btn { display: inline-block; padding: 0.25rem 0.5rem; background: #2563eb; color: #fff; border-radius: 4px; font-size: 0.85rem; }
    .sha { font-size: 0.75rem; color: #94a3b8; word-break: break-all; }
  </style>
</head>
<body>
  <div class="container">
    <header>
      <h1>Distill Linux Package Repository</h1>
      <p>Official binary package catalog. Powered by <code>drop</code> and GitHub Pages.</p>
      <div>
        <strong>Using in Distill Linux:</strong>
        <pre><code>export DROP_REPO_URL="https://&lt;username&gt;.github.io/&lt;repo&gt;"
drop update
drop in &lt;pkg&gt;</code></pre>
      </div>
      <p>Plain catalog for scripts: <a href="index.tsv"><code>index.tsv</code></a></p>
    </header>

    <h2>Available Packages</h2>
    <table>
      <thead>
        <tr>
          <th>Package</th>
          <th>Version</th>
          <th>Size</th>
          <th>SHA-256</th>
          <th>Action</th>
        </tr>
      </thead>
      <tbody>
HTMLEOF

COUNT=0
for f in "$REPO_DIR"/*.drop; do
    [ -e "$f" ] || continue
    FILENAME=$(basename "$f")
    SIZE=$(wc -c < "$f" | tr -d ' ')
    SHA=$(sha256sum "$f" | awk '{print $1}')
    
    # Extract package name and version from first tar header (.PORT)
    PORT_TEXT=$(tar -xzf "$f" .PORT -O 2>/dev/null || true)
    NAME=$(echo "$PORT_TEXT" | grep -E "^(PORT_)?NAME=" | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')
    VER=$(echo "$PORT_TEXT" | grep -E "^(PORT_)?VERSION=" | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')
    DEPS=$(echo "$PORT_TEXT" | grep -E "^(RUN_DEPS|DEPENDS)=" | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')

    if [ -z "$NAME" ]; then
        NAME=$(echo "$FILENAME" | sed 's/-[0-9].*//')
    fi
    if [ -z "$VER" ]; then
        VER=$(echo "$FILENAME" | sed -n 's/^[^-]*-//; s/\.drop$//p')
    fi

    # Append to index.tsv
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$NAME" "$VER" "$SHA" "$SIZE" "$FILENAME" "$DEPS" >> "$INDEX_TSV"

    # Format human-readable size
    if [ "$SIZE" -ge 1048576 ]; then
        HUMAN_SIZE="$(awk "BEGIN {printf \"%.1f MB\", $SIZE/1048576}")"
    elif [ "$SIZE" -ge 1024 ]; then
        HUMAN_SIZE="$(awk "BEGIN {printf \"%.1f KB\", $SIZE/1024}")"
    else
        HUMAN_SIZE="${SIZE} B"
    fi

    # Append to index.html
    cat << ROW >> "$INDEX_HTML"
        <tr>
          <td><strong>$NAME</strong></td>
          <td><code>$VER</code></td>
          <td>$HUMAN_SIZE</td>
          <td class="sha"><code>$SHA</code></td>
          <td><a class="btn" href="$FILENAME">Download</a></td>
        </tr>
ROW
    COUNT=$((COUNT + 1))
done

cat << 'FOOTER' >> "$INDEX_HTML"
      </tbody>
    </table>
  </div>
</body>
</html>
FOOTER

echo "==> Generated index.tsv and index.html ($COUNT packages registered)."
