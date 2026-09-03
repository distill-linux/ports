import os
import re
import sys

raw_list = """
Toolchain & Build Systems
    musl-dev
    musl-fts
    musl-obstack
    llvm
    clang
    lld
    compiler-rt
    libcxx
    libcxxabi
    binutils
    samurai
    meson
    pkgconf
    m4
    byacc
    flex
    autoconf
    automake
    libtool
    patch
    diffutils
    tcc
    qbe
    cproc
    nasm
    yasm
    rustc-bin
    cargo
    bsdmake
    pdpmake
    smake
    bsd-mk-files
    go
    python3
    python3-dev

Graphics, DRM & Mesa
    libdrm
    mesa
    libglvnd
    vulkan-loader
    vulkan-headers
    spirv-tools
    spirv-headers
    glslang
    libepoxy
    libva
    libva-utils
    libvdpau

Wayland Core & Desktop
    wayland
    wayland-scanner
    wayland-protocols
    wlr-protocols
    wlroots
    dwl
    river
    sway
    cage
    pixman
    libxkbcommon
    seatd
    yambar
    waybar
    wmenu
    fuzzel
    swaybg
    mako
    wl-clipboard
    slurp
    grim
    wtype
    wlsunset
    swaylock
    foot

X11Libre Core & Client Libraries
    xlibre-server
    xf86-video-modesetting
    xf86-input-libinput
    xorgproto
    libX11
    libXext
    libXau
    libXdmcp
    libxcb
    xcb-proto
    xcb-util-keysyms
    xcb-util-wm
    xcb-util-image
    xcb-util-renderutil
    xcb-util-cursor
    libXrender
    libXrandr
    libXfixes
    libXcomposite
    libXdamage
    libXcursor
    libXinerama
    libXi
    libXtst
    libXv
    libxshmfence
    libXt
    libXmu
    libXmuu
    libXaw
    libXaw3d
    libXpm
    libXft
    libXres
    libXScrnSaver
    luit

XApps & Classic Utilities
    xterm
    uxterm
    rxvt-unicode
    xclock
    oclock
    xcalc
    xedit
    xclipboard
    xcutsel
    xbiff
    xeyes
    xlogo
    xev
    xdpyinfo
    xwininfo
    xprop
    xkill
    xload
    xmag
    xmessage
    xfontsel
    xfd
    xlsfonts
    fslsfonts
    xrestop
    xwd
    xwud
    bitmap
    xrdb
    xmodmap
    setxkbmap
    xhost
    xrefresh
    xgamma
    twm
    dwm
    sdorfehs
    openbox
    dmenu
    slstatus
    picom
    slock
    st
    xclip
    xsel
    feh
    hsetroot
    xfe
    xarchiver
    azpainter

Terminals (Cross-Protocol)
    kitty
    kitty-terminfo
    alacritty
    simde
    xxhash
    librsync

Font & Text Rendering
    freetype
    fontconfig
    harfbuzz
    fribidi
    cairo
    pango
    libfontenc
    dejavu-fonts-ttf
    liberation-fonts-ttf
    terminus-font
    font-awesome

Media, Codecs & Audio
    libpng
    libjpeg-turbo
    libwebp
    giflib
    libtiff
    ffmpeg
    dav1d
    libvpx
    libogg
    libvorbis
    libopus
    flac
    alsa-lib
    alsa-utils
    pipewire
    wireplumber
    mpv
    moc
    nsxiv
    imv
    zathura
    zathura-pdf-mupdf

Browsers & Document Viewers
    netsurf
    badwolf
    dillo
    lynx
    w3m

Networking & Security
    libressl
    bearssl
    ca-certificates
    wpa_supplicant
    dhcpcd
    iproute2
    dropbear
    openssh
    curl

System Daemons & Base Plumbing
    eudev
    dbus
    openntpd
    chrony
    linux-pam
    shadow
    mandoc
    libarchive
    zstd
    xz-embedded
    lz4

Disk, Storage & Filesystems
    util-linux
    e2fsprogs
    dosfstools
    btrfs-progs
    xfsprogs
    efibootmgr
    cryptsetup
    lvm2
    gptfdisk

Framebuffer / Console Fallbacks
    fbv
    fim
    fbpad
    kmscon
"""

packages = []
for line in raw_list.splitlines():
    line = line.strip()
    if not line or "&" in line or line.startswith("X11") or line.startswith("Toolchain") or line.startswith("Graphics") or line.startswith("Wayland") or line.startswith("XApps") or line.startswith("Terminals") or line.startswith("Font") or line.startswith("Media") or line.startswith("Browsers") or line.startswith("Networking") or line.startswith("System") or line.startswith("Disk") or line.startswith("Framebuffer"):
        continue
    packages.append(line)

srcpkgs_dir = "/home/foggy/distill/void-packages/srcpkgs"
srcpkgs_entries = {}
for entry in os.listdir(srcpkgs_dir):
    srcpkgs_entries[entry.lower()] = entry

recipes_dir = "/home/foggy/distill/recipes"
os.makedirs(recipes_dir, exist_ok=True)

# Custom fallbacks for packages with distinct repositories
custom_data = {
    "musl-dev": {
        "desc": "The musl C standard library - development headers",
        "url": "https://git.musl-libc.org/git/musl",
        "ver": "1.2.5",
        "build_system": "make",
        "build": "./configure --prefix=/usr CC=clang\nmake -j$(nproc)\nmake DESTDIR=\"$PKG_FAKEROOT\" install-headers",
    },
    "python3-dev": {
        "desc": "Python 3 programming language - development headers",
        "url": "https://github.com/python/cpython.git",
        "ver": "3.12.2",
        "build_system": "make",
        "build": "./configure --prefix=/usr --enable-shared CC=clang\nmake -j$(nproc)\nmake DESTDIR=\"$PKG_FAKEROOT\" install",
    },
    "cproc": {
        "desc": "C11 compiler using QBE as backend written by Michael Forney",
        "url": "https://github.com/michaelforney/cproc.git",
        "ver": "main",
        "build_system": "make",
        "build": "./configure --prefix=/usr\nmake CC=clang\nmake DESTDIR=\"$PKG_FAKEROOT\" install",
    },
    "qbe": {
        "desc": "Quick Backend for compilers",
        "url": "https://c9x.me/git/qbe.git",
        "ver": "1.1",
        "build_system": "make",
        "build": "make CC=clang PREFIX=/usr\nmake DESTDIR=\"$PKG_FAKEROOT\" PREFIX=/usr install",
    },
    "dwl": {
        "desc": "Compact, hackable Wayland compositor based on wlroots",
        "url": "https://codeberg.org/dwl/dwl.git",
        "ver": "0.6",
        "build_system": "make",
        "build": "make CC=clang PREFIX=/usr\nmake DESTDIR=\"$PKG_FAKEROOT\" PREFIX=/usr install",
    },
    "wlr-protocols": {
        "desc": "Wayland protocols used by wlroots and associated compositors",
        "url": "https://gitlab.freedesktop.org/wlroots/wlr-protocols.git",
        "ver": "main",
        "build_system": "meson",
        "build": "meson setup build --prefix=/usr --buildtype=release\nsamu -C build\nDESTDIR=\"$PKG_FAKEROOT\" samu -C build install",
    },
    "wmenu": {
        "desc": "Dynamic menu for Wayland (dmenu clone for wlroots)",
        "url": "https://codeberg.org/adnano/wmenu.git",
        "ver": "0.1.8",
        "build_system": "meson",
        "build": "meson setup build --prefix=/usr --buildtype=release\nsamu -C build\nDESTDIR=\"$PKG_FAKEROOT\" samu -C build install",
    },
    "yambar": {
        "desc": "Modular status panel library and daemon for Wayland and X11",
        "url": "https://codeberg.org/dnkl/yambar.git",
        "ver": "1.10.0",
        "build_system": "meson",
        "build": "meson setup build --prefix=/usr --buildtype=release\nsamu -C build\nDESTDIR=\"$PKG_FAKEROOT\" samu -C build install",
    },
    "foot": {
        "desc": "Fast, lightweight, and minimalistic Wayland terminal emulator",
        "url": "https://codeberg.org/dnkl/foot.git",
        "ver": "1.17.2",
        "build_system": "meson",
        "build": "meson setup build --prefix=/usr --buildtype=release\nsamu -C build\nDESTDIR=\"$PKG_FAKEROOT\" samu -C build install",
    },
    "xlibre-server": {
        "desc": "X11Libre modern standalone X server without legacy cruft or systemd",
        "url": "https://github.com/X11Libre/xserver.git",
        "ver": "main",
        "build_system": "meson",
        "build": "meson setup build --prefix=/usr -Dxorg=true -Dxephyr=true -Dseatd=true -Dsystemd_logind=false\nsamu -C build\nDESTDIR=\"$PKG_FAKEROOT\" samu -C build install",
    },
    "xf86-video-modesetting": {
        "desc": "Generic modesetting video driver for X server (integrated)",
        "url": "https://github.com/X11Libre/xserver.git",
        "ver": "main",
        "build_system": "meta",
        "build": "mkdir -p \"$PKG_FAKEROOT/usr/share/doc/xf86-video-modesetting\"\necho \"Modesetting driver integrated into xlibre-server\" > \"$PKG_FAKEROOT/usr/share/doc/xf86-video-modesetting/README\"",
    },
    "sdorfehs": {
        "desc": "Tiling window manager derived from ratpoison with virtual screens",
        "url": "https://github.com/jcs/sdorfehs.git",
        "ver": "1.5",
        "build_system": "make",
        "build": "make CC=clang PREFIX=/usr\nmake DESTDIR=\"$PKG_FAKEROOT\" PREFIX=/usr install",
    },
    "rustc-bin": {
        "desc": "Rust compiler (precompiled binary bootstrap toolchain)",
        "url": "https://static.rust-lang.org/dist/rust-1.78.0-x86_64-unknown-linux-musl.tar.gz",
        "ver": "1.78.0",
        "build_system": "sh",
        "build": "./install.sh --destdir=\"$PKG_FAKEROOT\" --prefix=/usr",
    },
    "bsdmake": {
        "desc": "BSD Make (bmake) ported from NetBSD",
        "url": "https://github.com/crux-arm/bmake.git",
        "ver": "20240414",
        "build_system": "make",
        "build": "./configure --prefix=/usr\n./make-bootstrap.sh\ninstall -D -m 755 bmake \"$PKG_FAKEROOT/usr/bin/bmake\"",
    },
    "bsd-mk-files": {
        "desc": "System bmake mk files",
        "url": "https://github.com/crux-arm/mk-files.git",
        "ver": "20240414",
        "build_system": "make",
        "build": "mkdir -p \"$PKG_FAKEROOT/usr/share/mk\"\ncp *.mk \"$PKG_FAKEROOT/usr/share/mk/\"",
    },
    "wayland-scanner": {
        "desc": "Wayland XML protocol tool for generating C bindings",
        "url": "https://gitlab.freedesktop.org/wayland/wayland.git",
        "ver": "1.23.0",
        "build_system": "meson",
        "build": "meson setup build --prefix=/usr -Ddocumentation=false\nsamu -C build wayland-scanner\ninstall -D -m 755 build/wayland-scanner \"$PKG_FAKEROOT/usr/bin/wayland-scanner\"",
    }
}

alias_map = {
    "vulkan-headers": "Vulkan-Headers",
    "spirv-tools": "SPIRV-Tools",
    "spirv-headers": "SPIRV-Headers",
    "waybar": "Waybar",
    "uxterm": "xterm",
    "pdpmake": "pdp11-make",
    "smake": "smake",
    "azpainter": "azpainter",
}

created = 0

for pkg in packages:
    # Skip drop and sink since they have dedicated curated recipes
    if pkg in ["drop", "sink"]:
        continue

    port_file = os.path.join(recipes_dir, f"{pkg}.port")
    
    # Check custom data first
    if pkg in custom_data:
        d = custom_data[pkg]
        content = f'''PORT_NAME="{pkg}"
PORT_VERSION="{d.get('ver', '1.0')}"
PORT_RELEASE="1"
PORT_DESC="{d.get('desc', pkg)}"
PORT_URL="{d.get('url', '')}"
PORT_COMMIT="{d.get('ver', 'main')}"
BUILD_SYSTEM="{d.get('build_system', 'make')}"
BUILD_DEPS="{d.get('build_deps', '')}"
RUN_DEPS="{d.get('run_deps', '')}"

BUILD:
{d.get('build', 'make CC=clang PREFIX=/usr\nmake DESTDIR="$PKG_FAKEROOT" PREFIX=/usr install')}
'''
        with open(port_file, "w") as f:
            f.write(content)
        created += 1
        continue

    # Look up in void-packages
    lookup_name = alias_map.get(pkg, pkg)
    real_dir_name = srcpkgs_entries.get(lookup_name.lower())
    
    template_path = None
    if real_dir_name:
        candidate = os.path.join(srcpkgs_dir, real_dir_name)
        if os.path.islink(candidate):
            target = os.readlink(candidate)
            template_path = os.path.join(srcpkgs_dir, target, "template")
        elif os.path.isdir(candidate):
            template_path = os.path.join(candidate, "template")

    ver = "1.0"
    desc = f"{pkg} package for Distill Linux"
    homepage = f"https://github.com/distill-linux/{pkg}"
    build_style = "make"
    host_deps = ""
    run_deps = ""

    if template_path and os.path.exists(template_path):
        with open(template_path, "r", errors="replace") as f:
            tcontent = f.read()

        m_ver = re.search(r'^version=([^\n]+)', tcontent, re.M)
        if m_ver:
            ver = m_ver.group(1).strip('"\'')

        m_desc = re.search(r'^short_desc="([^"]+)"', tcontent, re.M)
        if not m_desc:
            m_desc = re.search(r"^short_desc='([^']+)'", tcontent, re.M)
        if m_desc:
            desc = m_desc.group(1).replace('"', '')

        m_home = re.search(r'^homepage="([^"]+)"', tcontent, re.M)
        if not m_home:
            m_home = re.search(r"^homepage='([^']+)'", tcontent, re.M)
        if m_home:
            homepage = m_home.group(1)

        m_style = re.search(r'^build_style=([^\n]+)', tcontent, re.M)
        if m_style:
            build_style = m_style.group(1).strip('"\'')

        m_host = re.search(r'^hostmakedepends="([^"]+)"', tcontent, re.M)
        if m_host:
            host_deps = m_host.group(1)

        m_run = re.search(r'^makedepends="([^"]+)"', tcontent, re.M)
        if m_run:
            run_deps = m_run.group(1)

    # Normalize build_style and commands
    if build_style == "meson":
        build_cmd = """meson setup build --prefix=/usr --buildtype=release
samu -C build
DESTDIR="$PKG_FAKEROOT" samu -C build install"""
    elif build_style == "cmake":
        build_cmd = """cmake -B build -G Ninja -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
samu -C build
DESTDIR="$PKG_FAKEROOT" samu -C build install"""
    elif build_style in ["gnu-configure", "configure"]:
        build_cmd = """./configure --prefix=/usr CC=clang
make -j$(nproc)
make DESTDIR="$PKG_FAKEROOT" install"""
    elif build_style == "cargo":
        build_cmd = """cargo build --release --locked
install -d "$PKG_FAKEROOT/usr/bin"
find target/release -maxdepth 1 -type f -executable -exec install -m 755 {} "$PKG_FAKEROOT/usr/bin/" \\;"""
    elif build_style == "go":
        build_cmd = f"""go build -v -ldflags="-s -w" -o {pkg}
install -D -m 755 {pkg} \"$PKG_FAKEROOT/usr/bin/{pkg}\""""
    else:
        build_cmd = """make CC=clang PREFIX=/usr
make DESTDIR="$PKG_FAKEROOT" PREFIX=/usr install"""

    content = f'''PORT_NAME="{pkg}"
PORT_VERSION="{ver}"
PORT_RELEASE="1"
PORT_DESC="{desc}"
PORT_URL="{homepage}"
PORT_COMMIT="{ver}"
BUILD_SYSTEM="{build_style}"
BUILD_DEPS="{host_deps}"
RUN_DEPS="{run_deps}"

BUILD:
{build_cmd}
'''
    with open(port_file, "w") as f:
        f.write(content)
    created += 1

print(f"Successfully generated {created} port recipes in {recipes_dir}!")
