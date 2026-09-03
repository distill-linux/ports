#!/bin/sh
set -e

REPO_DIR="${1:-.}"
mkdir -p "$REPO_DIR"
INDEX_TSV="$REPO_DIR/index.tsv"
INDEX_HTML="$REPO_DIR/index.html"

echo "==> Scanning $REPO_DIR for .drop packages..."

# Start index.tsv
printf "# Distill Linux Package Catalog\n# NAME\tVERSION\tSHA256\tSIZE\tFILENAME\tDEPENDS\n" > "$INDEX_TSV"

# Start index.html (Arch/AUR Package Search interface)
cat << 'HTMLEOF' > "$INDEX_HTML"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Packages - Distill Linux</title>
  <link rel="stylesheet" href="/style.css" type="text/css">
  <style>
    body {
        margin: 1.5em 2.5em;
        font-family: sans-serif;
        background: #b4bbed;
        color: #101426;
    }
    .pkg-search-box {
        background: rgba(255, 255, 255, 0.45);
        border: 1px solid rgba(0, 0, 0, 0.22);
        border-radius: 4px;
        margin: 1em 0 1.5em 0;
        overflow: hidden;
    }
    .pkg-search-title {
        background: rgba(44, 54, 99, 0.12);
        border-bottom: 1px solid rgba(0, 0, 0, 0.18);
        padding: 0.5em 1em;
        font-weight: bold;
        color: #0c142e;
        font-size: 1.05em;
    }
    .pkg-search-form {
        padding: 0.8em 1em;
        display: grid;
        grid-template-columns: 2fr 1fr 1fr;
        gap: 1em;
        align-items: end;
    }
    @media (max-width: 750px) {
        .pkg-search-form {
            grid-template-columns: 1fr;
        }
    }
    .pkg-form-group {
        display: flex;
        flex-direction: column;
    }
    .pkg-form-group label {
        font-size: 0.85em;
        font-weight: bold;
        margin-bottom: 0.3em;
        color: #2c3663;
    }
    .pkg-form-group input, .pkg-form-group select {
        padding: 0.45em 0.6em;
        border: 1px solid rgba(0, 0, 0, 0.25);
        border-radius: 3px;
        background: #ffffff;
        font-size: 0.9em;
        box-sizing: border-box;
        width: 100%;
    }
    .pkg-stats {
        font-size: 0.9em;
        margin: 1.2em 0 0.6em 0;
        color: #101426;
    }
    .pkg-table {
        width: 100%;
        border-collapse: collapse;
        margin: 0.5em 0 1.5em 0;
        font-size: 0.9em;
        background: rgba(255, 255, 255, 0.5);
        border: 1px solid rgba(0, 0, 0, 0.18);
    }
    .pkg-table th {
        background: rgba(44, 54, 99, 0.12);
        border: 1px solid rgba(0, 0, 0, 0.18);
        padding: 0.6em 0.8em;
        text-align: left;
        color: #0c142e;
        white-space: nowrap;
    }
    .pkg-table td {
        border: 1px solid rgba(0, 0, 0, 0.18);
        padding: 0.6em 0.8em;
        vertical-align: top;
    }
    .pkg-table tr:hover {
        background: rgba(255, 255, 255, 0.75);
    }
    .pkg-name {
        font-weight: bold;
        font-size: 1.05em;
    }
    .pkg-desc {
        color: #1f293d;
        margin-top: 0.2em;
    }
    .pkg-tag {
        display: inline-block;
        padding: 0.15em 0.45em;
        background: rgba(170, 32, 34, 0.12);
        color: #aa2022;
        border-radius: 3px;
        font-size: 0.8em;
        font-family: monospace;
    }
    .pkg-meta {
        font-size: 0.8em;
        color: #555;
        white-space: nowrap;
    }
    .pkg-cmd {
        font-family: monospace;
        font-size: 0.8em;
        background: #ffffff;
        border: 1px solid rgba(0,0,0,0.18);
        padding: 0.2em 0.4em;
        border-radius: 3px;
        cursor: pointer;
        user-select: all;
    }
    .catalog-link {
        float: right;
        font-size: 0.85em;
        margin-top: 0.5em;
    }
  </style>
</head>
<body>
  <span class="catalog-link">Raw catalog: <a href="index.tsv" style="color: #aa2022;">index.tsv</a></span>
  <h1 style="border-bottom: 1px solid rgba(0,0,0,0.22); padding-bottom: 0.4em;"><a href="/" style="color: #101426; text-decoration: none;">distill</a> / packages</h1>

  <div class="pkg-search-box">
      <div class="pkg-search-title">Search Criteria</div>
      <div class="pkg-search-form">
          <div class="pkg-form-group">
              <label for="pkg-keywords">Keywords</label>
              <input type="text" id="pkg-keywords" placeholder="Search by name or description..." oninput="filterPackages()">
          </div>
          <div class="pkg-form-group">
              <label for="pkg-searchby">Search by</label>
              <select id="pkg-searchby" onchange="filterPackages()">
                  <option value="all">Name, Description</option>
                  <option value="name">Name Only</option>
                  <option value="desc">Description Only</option>
              </select>
          </div>
          <div class="pkg-form-group">
              <label for="pkg-sort">Sort by</label>
              <select id="pkg-sort" onchange="sortPackages()">
                  <option value="name-asc">Name (A-Z)</option>
                  <option value="name-desc">Name (Z-A)</option>
                  <option value="date-desc">Last Updated</option>
                  <option value="size-desc">Size (Largest)</option>
              </select>
          </div>
      </div>
  </div>

  <div class="pkg-stats" id="pkg-stats">
HTMLEOF

COUNT=0
ROWS_HTML=""
for f in "$REPO_DIR"/*.drop; do
    [ -e "$f" ] || continue
    FILENAME=$(basename "$f")
    SIZE=$(wc -c < "$f" | tr -d ' ')
    SHA=$(sha256sum "$f" | awk '{print $1}')
    
    # Extract package name and version from first tar header (.PORT)
    PORT_TEXT=$(tar -xzf "$f" .PORT -O 2>/dev/null || true)
    NAME=$(echo "$PORT_TEXT" | grep -E "^(PORT_)?NAME=" | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')
    VER=$(echo "$PORT_TEXT" | grep -E "^(PORT_)?VERSION=" | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')
    REL=$(echo "$PORT_TEXT" | grep -E "^(PORT_)?RELEASE=" | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')
    DESC=$(echo "$PORT_TEXT" | grep -E "^(PORT_)?DESC=" | head -n 1 | cut -d'=' -f2- | tr -d '"'\'')
    DEPS=$(echo "$PORT_TEXT" | grep -E "^(RUN_DEPS|DEPENDS)=" | head -n 1 | cut -d'=' -f2 | tr -d '"'\'' ')
    URL=$(echo "$PORT_TEXT" | grep -E "^(PORT_)?URL=" | head -n 1 | cut -d'=' -f2- | tr -d '"'\'' ')

    if [ -z "$NAME" ]; then
        NAME=$(echo "$FILENAME" | sed 's/-[0-9].*//')
    fi
    if [ -z "$VER" ]; then
        VER=$(echo "$FILENAME" | sed -n 's/^[^-]*-//; s/\.drop$//p')
    fi
    if [ -z "$REL" ]; then
        REL="1"
    fi
    if [ -z "$DESC" ]; then
        DESC="No description available."
    fi

    # Determine source code link
    SRC_URL="$URL"
    if [ -z "$SRC_URL" ]; then
        SRC_URL="https://github.com/distill-linux/ports/blob/main/recipes/${NAME}.port"
    elif echo "$SRC_URL" | grep -q "^http.*\.git$"; then
        SRC_URL=$(echo "$SRC_URL" | sed 's/\.git$//')
    fi

    # Append to index.tsv
    printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$NAME" "$VER" "$SHA" "$SIZE" "$FILENAME" "$DEPS" >> "$INDEX_TSV"

    # Human size
    if [ "$SIZE" -ge 1048576 ]; then
        HUMAN_SIZE="$(awk "BEGIN {printf \"%.1f MB\", $SIZE/1048576}")"
    elif [ "$SIZE" -ge 1024 ]; then
        HUMAN_SIZE="$(awk "BEGIN {printf \"%.1f KB\", $SIZE/1024}")"
    else
        HUMAN_SIZE="${SIZE} B"
    fi

    ROWS_HTML="$ROWS_HTML
        <tr class=\"pkg-row\" data-name=\"$NAME\" data-desc=\"$(echo "$DESC" | tr '[:upper:]' '[:lower:]')\" data-date=\"2026-09-02\" data-size=\"$SIZE\">
            <td><a class=\"pkg-name\" href=\"$SRC_URL\" target=\"_blank\" rel=\"noopener\" style=\"color: #aa2022; text-decoration: none;\" title=\"View source code\">$NAME</a></td>
            <td><span class=\"pkg-tag\">$VER-$REL</span></td>
            <td>
                <div class=\"pkg-desc\">$DESC</div>
                <div style=\"margin-top: 0.3em;\"><code class=\"pkg-cmd\">drop in $NAME</code></div>
            </td>
            <td class=\"pkg-meta\">distill-core</td>
            <td class=\"pkg-meta\">2026-09-02 (UTC)</td>
            <td>
                <a href=\"$FILENAME\" download style=\"color: #aa2022; font-weight: bold;\">$FILENAME</a><br>
                <span style=\"font-size: 0.8em; color: #666;\">$HUMAN_SIZE</span>
            </td>
        </tr>"
    COUNT=$((COUNT + 1))
done

if [ "$COUNT" -eq 1 ]; then
    echo "      <strong>1 package found.</strong> Page 1 of 1." >> "$INDEX_HTML"
else
    echo "      <strong>$COUNT packages found.</strong> Page 1 of 1." >> "$INDEX_HTML"
fi

cat << HTMLEOF2 >> "$INDEX_HTML"
  </div>

  <table class="pkg-table" id="pkg-table">
      <thead>
          <tr>
              <th style="width: 18%;">Name</th>
              <th style="width: 10%;">Version</th>
              <th>Description</th>
              <th style="width: 14%;">Maintainer</th>
              <th style="width: 14%;">Last Updated</th>
              <th style="width: 12%;">Package</th>
          </tr>
      </thead>
      <tbody id="pkg-body">
$ROWS_HTML
      </tbody>
  </table>

  <script>
  function filterPackages() {
      var query = document.getElementById('pkg-keywords').value.toLowerCase().trim();
      var mode = document.getElementById('pkg-searchby').value;
      var rows = document.querySelectorAll('#pkg-body .pkg-row');
      var visible = 0;
      rows.forEach(function(row) {
          var name = row.getAttribute('data-name') || '';
          var desc = row.getAttribute('data-desc') || '';
          var match = false;
          if (!query) match = true;
          else if (mode === 'name') match = name.indexOf(query) !== -1;
          else if (mode === 'desc') match = desc.indexOf(query) !== -1;
          else match = (name.indexOf(query) !== -1) || (desc.indexOf(query) !== -1);
          if (match) { row.style.display = ''; visible++; }
          else { row.style.display = 'none'; }
      });
      var stats = document.getElementById('pkg-stats');
      stats.innerHTML = '<strong>' + visible + ' package' + (visible === 1 ? '' : 's') + ' found.</strong> Page 1 of 1.';
  }
  function sortPackages() {
      var sort = document.getElementById('pkg-sort').value;
      var tbody = document.getElementById('pkg-body');
      var rows = Array.from(tbody.querySelectorAll('.pkg-row'));
      rows.sort(function(a, b) {
          var nameA = a.getAttribute('data-name') || '';
          var nameB = b.getAttribute('data-name') || '';
          var sizeA = parseInt(a.getAttribute('data-size') || '0', 10);
          var sizeB = parseInt(b.getAttribute('data-size') || '0', 10);
          var dateA = a.getAttribute('data-date') || '';
          var dateB = b.getAttribute('data-date') || '';
          if (sort === 'name-asc') return nameA.localeCompare(nameB);
          if (sort === 'name-desc') return nameB.localeCompare(nameA);
          if (sort === 'size-desc') return sizeB - sizeA;
          if (sort === 'date-desc') return dateB.localeCompare(dateA);
          return 0;
      });
      rows.forEach(function(row) { tbody.appendChild(row); });
  }
  </script>
</body>
</html>
HTMLEOF2

echo "==> Generated Arch/AUR-style index.tsv and index.html ($COUNT packages registered)."
