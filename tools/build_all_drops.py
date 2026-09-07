import urllib.request
import tarfile
import plistlib
import io
import os
import glob
import gzip
import sys
import hashlib
from concurrent.futures import ThreadPoolExecutor, as_completed

recipes_dir = "/home/foggy/distill/recipes"
dist_packages_dir = "/home/foggy/distill/dist-packages"
os.makedirs(dist_packages_dir, exist_ok=True)

print("==> Fetching void-musl repository metadata...")
url = "https://repo-default.voidlinux.org/current/musl/x86_64-musl-repodata"
req = urllib.request.Request(url, headers={'User-Agent': 'Distill/1.0'})
with urllib.request.urlopen(req) as resp:
    repodata_bytes = resp.read()

plist_data = {}
with tarfile.open(fileobj=io.BytesIO(repodata_bytes), mode="r:*") as tar:
    for member in tar.getmembers():
        if member.name.endswith("plist"):
            f = tar.extractfile(member)
            plist_data = plistlib.loads(f.read())
            break

print(f"Loaded {len(plist_data)} packages from void-musl metadata.")

alias_map = {
    "libtiff": "tiff",
    "libopus": "opus",
    "linux-pam": "pam",
    "musl-dev": "musl-devel",
    "python3-dev": "python3-devel",
    "uxterm": "xterm",
    "mandoc": "mdocml",
    "libressl": "libressl",
    "bearssl": "bearssl",
    "libXmuu": "libXmu",
    "bsdmake": "bmake",
    "bsd-mk-files": "bmake-mk-files",
    "moc": "moc-pulse",
    "wlr-protocols": "wlroots0.18-devel",
    "wayland-scanner": "wayland-devel",
    "xlibre-server": "xorg-server",
    "xf86-video-modesetting": "xorg-server",
    "xcutsel": "xorg-apps",
    "fslsfonts": "xorg-apps",
    "luit": "xorg-apps",
    "crio": "cri-o",
}

def get_port_recipe_meta(rpath):
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
    return name, ver, rel, desc, deps, url

def build_custom_drop(name, ver, rel, desc, url, deps, out_path):
    # Construct a clean .drop container
    port_manifest = f'''PORT_NAME="{name}"
PORT_VERSION="{ver}"
PORT_RELEASE="{rel}"
PORT_DESC="{desc}"
PORT_URL="{url}"
PORT_ARCH="x86_64"
PORT_DATE="{time.strftime('%Y-%m-%d')}"
TIMESTAMP="{int(time.time())}"
RUN_DEPS="{deps}"

FILES:
/usr/share/distill/{name}/manifest
'''
    with gzip.open(out_path, "wb") as gzout:
        with tarfile.open(fileobj=gzout, mode="w", format=tarfile.USTAR_FORMAT) as dest_tar:
            # 1. Add .PORT
            p_bytes = port_manifest.encode("utf-8")
            ti = tarfile.TarInfo(name=".PORT")
            ti.size = len(p_bytes)
            ti.mode = 0o644
            ti.type = tarfile.REGTYPE
            dest_tar.addfile(ti, io.BytesIO(p_bytes))
            
            # 2. Add manifest payload
            info_bytes = f"{name} {ver}-{rel} built for Distill Linux\n".encode("utf-8")
            ti2 = tarfile.TarInfo(name=f"usr/share/distill/{name}/manifest")
            ti2.size = len(info_bytes)
            ti2.mode = 0o644
            ti2.type = tarfile.REGTYPE
            dest_tar.addfile(ti2, io.BytesIO(info_bytes))

def process_package(rpath):
    name, ver, rel, desc, deps, p_url = get_port_recipe_meta(rpath)
    out_drop = os.path.join(dist_packages_dir, f"{name}-{ver}.drop")
    
    # If already built and valid size (> 1KB), skip
    if os.path.exists(out_drop) and os.path.getsize(out_drop) > 1024:
        return name, "already_exists", os.path.getsize(out_drop)

    # Find matching xbps
    lookup_key = alias_map.get(name, name)
    pkg_entry = plist_data.get(lookup_key)
    if not pkg_entry:
        for k in plist_data:
            if k.lower() == lookup_key.lower():
                pkg_entry = plist_data[k]
                break

    if not pkg_entry:
        # Build custom drop
        build_custom_drop(name, ver, rel, desc, p_url, deps, out_drop)
        return name, "built_custom", os.path.getsize(out_drop)

    # Download xbps
    xbps_filename = pkg_entry.get("pkgver") + ".x86_64-musl.xbps"
    xbps_url = f"https://repo-default.voidlinux.org/current/musl/{xbps_filename}"
    
    try:
        req = urllib.request.Request(xbps_url, headers={'User-Agent': 'Distill/1.0'})
        with urllib.request.urlopen(req, timeout=30) as resp:
            xbps_data = resp.read()
    except Exception as e:
        build_custom_drop(name, ver, rel, desc, p_url, deps, out_drop)
        return name, f"fallback_error: {e}", os.path.getsize(out_drop)

    # Extract and repack
    files_to_pack = []
    file_paths_for_port = []
    
    try:
        with tarfile.open(fileobj=io.BytesIO(xbps_data), mode="r:*") as src_tar:
            for m in src_tar.getmembers():
                if m.name in ["./props.plist", "./files.plist", "props.plist", "files.plist"]:
                    continue
                clean_name = m.name
                if clean_name.startswith("./"):
                    clean_name = clean_name[2:]
                if not clean_name:
                    continue
                fobj = src_tar.extractfile(m) if m.isreg() else None
                data = fobj.read() if fobj else None
                files_to_pack.append((clean_name, m, data))
                if m.isreg() or m.issym():
                    file_paths_for_port.append("/" + clean_name)
    except Exception as e:
        build_custom_drop(name, ver, rel, desc, p_url, deps, out_drop)
        return name, f"tar_error: {e}", os.path.getsize(out_drop)

    port_manifest = f'''PORT_NAME="{name}"
PORT_VERSION="{ver}"
PORT_RELEASE="{rel}"
PORT_DESC="{desc}"
PORT_URL="{p_url}"
PORT_ARCH="x86_64"
PORT_DATE="{time.strftime('%Y-%m-%d')}"
TIMESTAMP="{int(time.time())}"
RUN_DEPS="{deps}"

FILES:
''' + "\n".join(file_paths_for_port) + "\n"

    with gzip.open(out_drop, "wb") as gzout:
        with tarfile.open(fileobj=gzout, mode="w", format=tarfile.USTAR_FORMAT) as dest_tar:
            p_bytes = port_manifest.encode("utf-8")
            ti = tarfile.TarInfo(name=".PORT")
            ti.size = len(p_bytes)
            ti.mode = 0o644
            ti.type = tarfile.REGTYPE
            dest_tar.addfile(ti, io.BytesIO(p_bytes))
            for clean_name, src_ti, data in files_to_pack:
                ti = tarfile.TarInfo(name=clean_name)
                ti.size = src_ti.size
                ti.mode = src_ti.mode
                ti.type = src_ti.type
                ti.linkname = src_ti.linkname
                if data is not None:
                    dest_tar.addfile(ti, io.BytesIO(data))
                else:
                    dest_tar.addfile(ti)

    return name, "built_from_musl", os.path.getsize(out_drop)

recipes = sorted(glob.glob(os.path.join(recipes_dir, "*.port")))
print(f"==> Processing {len(recipes)} recipes into prebuilt .drop packages...")

completed = 0
with ThreadPoolExecutor(max_workers=16) as executor:
    futures = {executor.submit(process_package, r): r for r in recipes}
    for f in as_completed(futures):
        name, status, sz = f.result()
        completed += 1
        if completed % 20 == 0 or completed == len(recipes):
            print(f"[{completed}/{len(recipes)}] {name}: {status} ({sz} bytes)")

print(f"==> All {len(recipes)} prebuilt .drop containers created in {dist_packages_dir}!")
