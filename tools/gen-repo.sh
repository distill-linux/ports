#!/bin/sh
set -e

REPO_DIR="${1:-.}"
RECIPES_DIR="${2:-recipes}"
SITE_DIR="${3:-}"

python3 - "$REPO_DIR" "$RECIPES_DIR" "$SITE_DIR" << 'PYEOF'
import sys
import os
import glob
import tarfile
import hashlib

repo_dir = sys.argv[1]
recipes_dir = sys.argv[2] if len(sys.argv) > 2 else "recipes"
site_dir = sys.argv[3] if len(sys.argv) > 3 else ""

os.makedirs(repo_dir, exist_ok=True)
tsv_path = os.path.join(repo_dir, "index.tsv")
html_path = os.path.join(repo_dir, "index.html")

# Map of existing drop files
drop_files = {}

# 0. Check for pre-existing index.tsv in site_dir or repo_dir
candidate_tsvs = []
if site_dir:
    candidate_tsvs.append(os.path.join(site_dir, "static", "ports", "index.tsv"))
candidate_tsvs.append(tsv_path)

for c_tsv in candidate_tsvs:
    if os.path.exists(c_tsv):
        try:
            with open(c_tsv, "r", encoding="utf-8") as f:
                for line in f:
                    if line.startswith("#") or not line.strip():
                        continue
                    parts = line.strip().split("\t")
                    if len(parts) >= 5:
                        pname, pver, psha, psize, pfname = parts[0], parts[1], parts[2], int(parts[3]), parts[4]
                        drop_files[pname] = {
                            "filename": pfname,
                            "size": psize,
                            "sha256": psha,
                        }
        except Exception:
            pass

# Also scan filesystem directories for any .drop files
search_dirs = []
if site_dir and os.path.exists(os.path.join(site_dir, "static", "ports")):
    search_dirs.append(os.path.join(site_dir, "static", "ports"))
if os.path.exists(repo_dir):
    search_dirs.append(repo_dir)

for sdir in search_dirs:
    for fname in os.listdir(sdir):
        if fname.endswith(".drop"):
            fpath = os.path.join(sdir, fname)
            size = os.path.getsize(fpath)
            pname = fname.split("-")[0]
            try:
                with tarfile.open(fpath, "r:gz") as tar:
                    for member in tar.getmembers():
                        if member.name == ".PORT":
                            fobj = tar.extractfile(member)
                            if fobj:
                                for line in fobj.read().decode("utf-8", errors="replace").splitlines():
                                    if line.startswith("PORT_NAME=") or line.startswith("NAME="):
                                        pname = line.split("=", 1)[1].strip().strip('"').strip("'")
                                        break
                            break
            except Exception:
                pass
            if pname not in drop_files or drop_files[pname]["size"] == 0:
                with open(fpath, "rb") as f:
                    sha = hashlib.sha256(f.read()).hexdigest()
                drop_files[pname] = {
                    "filename": fname,
                    "size": size,
                    "sha256": sha,
                }

pkg_map = {}

# 1. First load from recipes if directory exists
if os.path.exists(recipes_dir):
    for rpath in sorted(glob.glob(os.path.join(recipes_dir, "*.port"))):
        try:
            with open(rpath, "r", errors="replace") as f:
                content = f.read()
            meta = {}
            for line in content.splitlines():
                if "=" in line and not line.startswith(" ") and not line.startswith("\t"):
                    k, v = line.split("=", 1)
                    meta[k.strip()] = v.strip().strip('"').strip("'")
                if line.strip() == "BUILD:":
                    break
            name = meta.get("PORT_NAME") or os.path.basename(rpath).replace(".port", "")
            ver = meta.get("PORT_VERSION") or "1.0"
            rel = meta.get("PORT_RELEASE") or "1"
            desc = meta.get("PORT_DESC") or f"{name} package for Distill Linux"
            deps = meta.get("RUN_DEPS") or meta.get("DEPENDS") or ""
            url = meta.get("PORT_URL") or ""
            pkg_map[name] = {
                "name": name,
                "version": ver,
                "release": rel,
                "desc": desc,
                "deps": deps,
                "url": url,
            }
        except Exception:
            pass

# 2. Add any drop files not in recipes
for pname, dinfo in drop_files.items():
    if pname not in pkg_map:
        pkg_map[pname] = {
            "name": pname,
            "version": "1.0",
            "release": "1",
            "desc": f"{pname} package for Distill Linux",
            "deps": "",
            "url": f"https://github.com/distill-linux/{pname}",
        }

packages = []
for name in sorted(pkg_map.keys()):
    p = pkg_map[name]
    dinfo = drop_files.get(name)
    
    src_url = p["url"]
    if not src_url:
        src_url = f"https://github.com/distill-linux/ports/blob/main/recipes/{name}.port"
    elif src_url.endswith(".git"):
        src_url = src_url[:-4]

    packages.append({
        "name": name,
        "version": p["version"],
        "release": p["release"],
        "desc": p["desc"],
        "deps": p["deps"],
        "src_url": src_url,
        "has_drop": dinfo is not None,
        "filename": dinfo["filename"] if dinfo else f"{name}-{p['version']}.drop",
        "size": dinfo["size"] if dinfo else 0,
        "sha256": dinfo["sha256"] if dinfo else "",
    })

# Write index.tsv
with open(tsv_path, "w", encoding="utf-8") as f:
    f.write("# Distill Linux Package Catalog\n# NAME\tVERSION\tSHA256\tSIZE\tFILENAME\tDEPENDS\n")
    for p in packages:
        f.write(f"{p['name']}\t{p['version']}\t{p['sha256']}\t{p['size']}\t{p['filename']}\t{p['deps']}\n")

# Format human size
def human_size(n):
    if n >= 1048576:
        return f"{n/1048576:.1f} MB"
    elif n >= 1024:
        return f"{n/1024:.1f} KB"
    elif n > 0:
        return f"{n} B"
    return "source"

rows_html = []
for p in packages:
    hsz = human_size(p['size'])
    desc_lower = p['desc'].lower().replace('"', '')
    if p['size'] > 0:
        pkg_cell = f'''<a href="{p['filename']}" download style="font-weight: bold; color: #aa2022;">{p['filename']}</a><br>
                <span style="font-size: 0.8em; color: #666;">{hsz}</span>'''
    else:
        pkg_cell = f'''<a href="{p['filename']}" download style="font-weight: bold; color: #aa2022;">{p['filename']}</a><br>
                <span style="font-size: 0.8em; color: #666;">prebuilt package</span>'''

    row = f'''        <tr class="pkg-row" data-name="{p['name']}" data-desc="{desc_lower}" data-date="2026-09-02" data-size="{p['size']}">
            <td><a class="pkg-name" href="{p['src_url']}" target="_blank" rel="noopener" style="color: #aa2022; text-decoration: none;" title="View source code">{p['name']}</a></td>
            <td><span class="pkg-tag">{p['version']}-{p['release']}</span></td>
            <td>
                <div class="pkg-desc">{p['desc']}</div>
                <div style="margin-top: 0.3em;"><code class="pkg-cmd" title="Click to copy">drop in {p['name']}</code></div>
            </td>
            <td class="pkg-meta">distill-core</td>
            <td class="pkg-meta">2026-09-02 (UTC)</td>
            <td>
                {pkg_cell}
            </td>
        </tr>'''
    rows_html.append(row)

count = len(packages)
stats_text = f"<strong>{count} package{'s' if count != 1 else ''} found.</strong> Page 1 of 1."

html_content = f'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Packages - Distill Linux</title>
  <link rel="stylesheet" href="/style.css" type="text/css">
  <script>
    (function() {{
        if (localStorage.getItem('distill-inverted') === 'true') {{
            document.documentElement.classList.add('inverted');
        }}
    }})();
    function toggleInvert() {{
        var isInv = document.documentElement.classList.toggle('inverted');
        try {{
            localStorage.setItem('distill-inverted', isInv ? 'true' : 'false');
        }} catch (e) {{}}
    }}
  </script>
  <style>
    body {{
        margin: 1.5em 2.5em;
        font-family: sans-serif;
        background: #b4bbed;
        color: #101426;
    }}
    .pkg-search-box {{
        background: rgba(255, 255, 255, 0.45);
        border: 1px solid rgba(0, 0, 0, 0.22);
        border-radius: 4px;
        margin: 1em 0 1.5em 0;
        overflow: hidden;
    }}
    .pkg-search-title {{
        background: rgba(44, 54, 99, 0.12);
        border-bottom: 1px solid rgba(0, 0, 0, 0.18);
        padding: 0.5em 1em;
        font-weight: bold;
        color: #0c142e;
        font-size: 1.05em;
    }}
    .pkg-search-form {{
        padding: 0.8em 1em;
        display: grid;
        grid-template-columns: 2fr 1fr 1fr;
        gap: 1em;
        align-items: end;
    }}
    @media (max-width: 750px) {{
        .pkg-search-form {{
            grid-template-columns: 1fr;
        }}
    }}
    .pkg-form-group {{
        display: flex;
        flex-direction: column;
    }}
    .pkg-form-group label {{
        font-size: 0.85em;
        font-weight: bold;
        margin-bottom: 0.3em;
        color: #2c3663;
    }}
    .pkg-form-group input, .pkg-form-group select {{
        padding: 0.45em 0.6em;
        border: 1px solid rgba(0, 0, 0, 0.25);
        border-radius: 3px;
        background: #ffffff;
        font-size: 0.9em;
        box-sizing: border-box;
        width: 100%;
    }}
    .pkg-stats {{
        font-size: 0.9em;
        margin: 1.2em 0 0.6em 0;
        color: #101426;
    }}
    .pkg-table {{
        width: 100%;
        border-collapse: collapse;
        margin: 0.5em 0 1.5em 0;
        font-size: 0.9em;
        background: rgba(255, 255, 255, 0.5);
        border: 1px solid rgba(0, 0, 0, 0.18);
    }}
    .pkg-table th {{
        background: rgba(44, 54, 99, 0.12);
        border: 1px solid rgba(0, 0, 0, 0.18);
        padding: 0.6em 0.8em;
        text-align: left;
        color: #0c142e;
        white-space: nowrap;
    }}
    .pkg-table td {{
        border: 1px solid rgba(0, 0, 0, 0.18);
        padding: 0.6em 0.8em;
        vertical-align: top;
    }}
    .pkg-table tr:hover {{
        background: rgba(255, 255, 255, 0.75);
    }}
    .pkg-name {{
        font-weight: bold;
        font-size: 1.05em;
    }}
    .pkg-desc {{
        color: #1f293d;
        margin-top: 0.2em;
    }}
    .pkg-tag {{
        display: inline-block;
        padding: 0.15em 0.45em;
        background: rgba(170, 32, 34, 0.12);
        color: #aa2022;
        border-radius: 3px;
        font-size: 0.8em;
        font-family: monospace;
    }}
    .pkg-meta {{
        font-size: 0.8em;
        color: #555;
        white-space: nowrap;
    }}
    .pkg-cmd {{
        font-family: monospace;
        font-size: 0.82em;
        background: rgba(255, 255, 255, 0.65);
        border: 1px solid rgba(0, 0, 0, 0.18);
        color: #0c142e;
        padding: 0.2em 0.5em;
        border-radius: 3px;
        cursor: pointer;
        user-select: all;
        display: inline-block;
    }}
    .pkg-cmd:hover {{
        background: rgba(255, 255, 255, 0.95);
        border-color: #aa2022;
    }}
    .catalog-link {{
        float: right;
        font-size: 0.85em;
        margin-top: 0.5em;
    }}
  </style>
</head>
<body>
  <span class="catalog-link">Raw catalog: <a href="index.tsv" style="color: #aa2022;">index.tsv</a> | <a href="javascript:void(0)" onclick="toggleInvert()" style="color: #aa2022;">invert</a></span>
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
    {stats_text}
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
{"\n".join(rows_html)}
      </tbody>
  </table>

  <script>
  function filterPackages() {{
      var query = document.getElementById('pkg-keywords').value.toLowerCase().trim();
      var mode = document.getElementById('pkg-searchby').value;
      var rows = document.querySelectorAll('#pkg-body .pkg-row');
      var visible = 0;
      rows.forEach(function(row) {{
          var name = row.getAttribute('data-name') || '';
          var desc = row.getAttribute('data-desc') || '';
          var match = false;
          if (!query) match = true;
          else if (mode === 'name') match = name.indexOf(query) !== -1;
          else if (mode === 'desc') match = desc.indexOf(query) !== -1;
          else match = (name.indexOf(query) !== -1) || (desc.indexOf(query) !== -1);
          if (match) {{ row.style.display = ''; visible++; }}
          else {{ row.style.display = 'none'; }}
      }});
      var stats = document.getElementById('pkg-stats');
      stats.innerHTML = '<strong>' + visible + ' package' + (visible === 1 ? '' : 's') + ' found.</strong> Page 1 of 1.';
  }}
  function sortPackages() {{
      var sort = document.getElementById('pkg-sort').value;
      var tbody = document.getElementById('pkg-body');
      var rows = Array.from(tbody.querySelectorAll('.pkg-row'));
      rows.sort(function(a, b) {{
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
      }});
      rows.forEach(function(row) {{ tbody.appendChild(row); }});
  }}
  </script>
</body>
</html>'''

with open(html_path, "w", encoding="utf-8") as f:
    f.write(html_content)

# If site_dir was passed, write content/ports/_index.md and copy static files
if site_dir and os.path.exists(site_dir):
    static_ports_dir = os.path.join(site_dir, "static", "ports")
    os.makedirs(static_ports_dir, exist_ok=True)
    # Copy all drop files and index.tsv to static/ports (skip index.html so Hugo template is used)
    import shutil
    for fname in os.listdir(repo_dir):
        if fname == "index.html":
            continue
        src = os.path.join(repo_dir, fname)
        dst = os.path.join(static_ports_dir, fname)
        if os.path.isfile(src):
            shutil.copy2(src, dst)
    
    # Generate content/ports/_index.md for Hugo
    md_content = f'''---
title: "ports"
---

<style>
/* Spread ports page to the edge of the screen */
article {{
    max-width: none !important;
    margin-right: 2em !important;
}}
@media (max-width: 650px) {{
    article {{
        margin-right: 0 !important;
    }}
}}

/* Arch/AUR Search Criteria Box */
.pkg-search-box {{
    background: rgba(255, 255, 255, 0.45);
    border: 1px solid rgba(0, 0, 0, 0.22);
    border-radius: 4px;
    margin: 1em 0 1.5em 0;
    overflow: hidden;
}}
.pkg-search-title {{
    background: rgba(44, 54, 99, 0.12);
    border-bottom: 1px solid rgba(0, 0, 0, 0.18);
    padding: 0.5em 1em;
    font-weight: bold;
    color: #0c142e;
    font-size: 1.05em;
}}
.pkg-search-form {{
    padding: 0.8em 1em;
    display: grid;
    grid-template-columns: 2fr 1fr 1fr;
    gap: 1em;
    align-items: end;
}}
@media (max-width: 750px) {{
    .pkg-search-form {{
        grid-template-columns: 1fr;
    }}
}}
.pkg-form-group {{
    display: flex;
    flex-direction: column;
}}
.pkg-form-group label {{
    font-size: 0.85em;
    font-weight: bold;
    margin-bottom: 0.3em;
    color: #2c3663;
}}
.pkg-form-group input, .pkg-form-group select {{
    padding: 0.45em 0.6em;
    border: 1px solid rgba(0, 0, 0, 0.25);
    border-radius: 3px;
    background: #ffffff;
    font-size: 0.9em;
    box-sizing: border-box;
    width: 100%;
}}
.pkg-stats {{
    font-size: 0.9em;
    margin: 1.2em 0 0.6em 0;
    color: #101426;
}}
.pkg-table {{
    width: 100%;
    border-collapse: collapse;
    margin: 0.5em 0 1.5em 0;
    font-size: 0.9em;
    background: rgba(255, 255, 255, 0.5);
    border: 1px solid rgba(0, 0, 0, 0.18);
}}
.pkg-table th {{
    background: rgba(44, 54, 99, 0.12);
    border: 1px solid rgba(0, 0, 0, 0.18);
    padding: 0.6em 0.8em;
    text-align: left;
    color: #0c142e;
    white-space: nowrap;
}}
.pkg-table td {{
    border: 1px solid rgba(0, 0, 0, 0.18);
    padding: 0.6em 0.8em;
    vertical-align: top;
}}
.pkg-table tr:hover {{
    background: rgba(255, 255, 255, 0.75);
}}
.pkg-name {{
    font-weight: bold;
    font-size: 1.05em;
}}
.pkg-desc {{
    color: #1f293d;
    margin-top: 0.2em;
}}
.pkg-tag {{
    display: inline-block;
    padding: 0.15em 0.45em;
    background: rgba(170, 32, 34, 0.12);
    color: #aa2022;
    border-radius: 3px;
    font-size: 0.8em;
    font-family: monospace;
}}
.pkg-meta {{
    font-size: 0.8em;
    color: #555;
    white-space: nowrap;
}}
.pkg-cmd {{
    font-family: monospace;
    font-size: 0.82em;
    background: rgba(255, 255, 255, 0.65);
    border: 1px solid rgba(0, 0, 0, 0.18);
    color: #0c142e;
    padding: 0.2em 0.5em;
    border-radius: 3px;
    cursor: pointer;
    user-select: all;
    display: inline-block;
}}
.pkg-cmd:hover {{
    background: rgba(255, 255, 255, 0.95);
    border-color: #aa2022;
}}
.catalog-link {{
    float: right;
    font-size: 0.85em;
    margin-top: -2.2em;
}}
</style>

<span class="catalog-link">Raw catalog: <a href="index.tsv" style="color: #aa2022;">index.tsv</a></span>

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
  {stats_text}
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
{"\n".join(rows_html)}
    </tbody>
</table>

<script>
function filterPackages() {{
    var query = document.getElementById('pkg-keywords').value.toLowerCase().trim();
    var mode = document.getElementById('pkg-searchby').value;
    var rows = document.querySelectorAll('#pkg-body .pkg-row');
    var visible = 0;
    rows.forEach(function(row) {{
        var name = row.getAttribute('data-name') || '';
        var desc = row.getAttribute('data-desc') || '';
        var match = false;
        if (!query) match = true;
        else if (mode === 'name') match = name.indexOf(query) !== -1;
        else if (mode === 'desc') match = desc.indexOf(query) !== -1;
        else match = (name.indexOf(query) !== -1) || (desc.indexOf(query) !== -1);
        if (match) {{ row.style.display = ''; visible++; }}
        else {{ row.style.display = 'none'; }}
    }});
    var stats = document.getElementById('pkg-stats');
    stats.innerHTML = '<strong>' + visible + ' package' + (visible === 1 ? '' : 's') + ' found.</strong> Page 1 of 1.';
}}
function sortPackages() {{
    var sort = document.getElementById('pkg-sort').value;
    var tbody = document.getElementById('pkg-body');
    var rows = Array.from(tbody.querySelectorAll('.pkg-row'));
    rows.sort(function(a, b) {{
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
    }});
    rows.forEach(function(row) {{ tbody.appendChild(row); }});
}}
</script>
'''
    ports_md_path = os.path.join(site_dir, "content", "ports", "_index.md")
    os.makedirs(os.path.dirname(ports_md_path), exist_ok=True)
    with open(ports_md_path, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"==> Updated {ports_md_path} with {count} packages.")

print(f"==> Generated index.tsv and index.html ({count} packages registered).")
PYEOF
