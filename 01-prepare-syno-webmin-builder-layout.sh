#!/usr/bin/env bash
set -euo pipefail

# Syno-Webmin -> synology-package-builder layout helper
# Run from the root of your Syno-Webmin repository.

PKG_NAME="webmin"
PKG_VERSION="${PKG_VERSION:-2.651}"
DISPLAY_NAME="Webmin"
TARGET_DIR="src"
SYN_DIR="synology"

echo "==> Checking repo root..."
if [ ! -d ".git" ]; then
  echo "ERROR: Run this from the root of the Syno-Webmin git repo."
  exit 1
fi

echo "==> Creating builder layout..."
mkdir -p "$TARGET_DIR" "$SYN_DIR/conf" "$SYN_DIR/WIZARD_UIFILES" ".github/workflows"

# Move existing package payload folders into src if they exist at repo root.
for d in etc man reset scripts ui update usr webmin webmin-"$PKG_VERSION"; do
  if [ -e "$d" ] && [ ! -e "$TARGET_DIR/$d" ]; then
    echo "Moving $d -> $TARGET_DIR/$d"
    mv "$d" "$TARGET_DIR/"
  fi
done

# If webmin-$version exists, normalize it to src/webmin.
if [ -d "$TARGET_DIR/webmin-$PKG_VERSION" ] && [ ! -d "$TARGET_DIR/webmin" ]; then
  echo "Normalizing $TARGET_DIR/webmin-$PKG_VERSION -> $TARGET_DIR/webmin"
  mv "$TARGET_DIR/webmin-$PKG_VERSION" "$TARGET_DIR/webmin"
fi

# If no src/webmin exists yet, try to locate downloaded/extracted Webmin folder.
if [ ! -f "$TARGET_DIR/webmin/miniserv.pl" ]; then
  found="$(find . -maxdepth 4 -type f -name miniserv.pl 2>/dev/null | head -1 || true)"
  if [ -n "$found" ]; then
    webmin_dir="$(dirname "$found")"
    if [ "$webmin_dir" != "./$TARGET_DIR/webmin" ]; then
      echo "Copying detected Webmin tree $webmin_dir -> $TARGET_DIR/webmin"
      rm -rf "$TARGET_DIR/webmin"
      mkdir -p "$TARGET_DIR"
      cp -a "$webmin_dir" "$TARGET_DIR/webmin"
    fi
  fi
fi

if [ ! -f "$TARGET_DIR/webmin/miniserv.pl" ]; then
  echo "WARNING: $TARGET_DIR/webmin/miniserv.pl not found."
  echo "Place the extracted Webmin 2.651 tree at: $TARGET_DIR/webmin/"
fi

echo "==> Creating DSM-safe etc/start and etc/stop..."
mkdir -p "$TARGET_DIR/etc" "$TARGET_DIR/var"

cat > "$TARGET_DIR/etc/start" <<'EOF'
#!/bin/sh
exec /usr/bin/perl /var/packages/webmin/target/webmin/miniserv.pl /var/packages/webmin/target/etc/miniserv.conf
EOF

cat > "$TARGET_DIR/etc/stop" <<'EOF'
#!/bin/sh

/bin/ps aux | /bin/grep '[m]iniserv.pl' | /usr/bin/awk '{print $2}' | while read PID; do
  /bin/kill "$PID" 2>/dev/null || true
done

sleep 2

/bin/ps aux | /bin/grep '[m]iniserv.pl' | /usr/bin/awk '{print $2}' | while read PID; do
  /bin/kill -9 "$PID" 2>/dev/null || true
done

/bin/rm -f /var/packages/webmin/target/var/miniserv.pid
/bin/rm -f /var/log/webmin/miniserv.pid

exit 0
EOF

chmod +x "$TARGET_DIR/etc/start" "$TARGET_DIR/etc/stop"

echo "$PKG_VERSION" > "$TARGET_DIR/etc/version"

echo "==> Ensuring miniserv.conf root path if config exists..."
if [ -f "$TARGET_DIR/etc/miniserv.conf" ]; then
  if grep -q '^root=' "$TARGET_DIR/etc/miniserv.conf"; then
    sed -i.bak 's#^root=.*#root=/var/packages/webmin/target/webmin#' "$TARGET_DIR/etc/miniserv.conf"
  else
    echo 'root=/var/packages/webmin/target/webmin' >> "$TARGET_DIR/etc/miniserv.conf"
  fi
fi

echo "==> Creating package.json..."
cat > package.json <<EOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "description": "Webmin for Synology DSM",
  "author": "iamjairo",
  "license": "GPL-3.0-or-later",
  "synology": {
    "maintainer": "iamjairo",
    "arch": "noarch",
    "displayName": "$DISPLAY_NAME",
    "os_min_ver": "7.0-40337",
    "os_max_ver": "7"
  },
  "target": "./$TARGET_DIR"
}
EOF

echo "==> Creating minimal Synology conf files..."
cat > "$SYN_DIR/conf/privilege" <<'EOF'
{
  "defaults": {
    "run-as": "root"
  },
  "username": "root"
}
EOF

cat > "$SYN_DIR/conf/resource" <<'EOF'
{
  "usr-local-linker": {
    "bin": [],
    "lib": []
  },
  "service": {
    "is_startable": true
  }
}
EOF

# Avoid missing folder warnings.
touch "$SYN_DIR/WIZARD_UIFILES/install_uifiles"
touch "$SYN_DIR/WIZARD_UIFILES/uninstall_uifiles"

echo "==> Creating GitHub Actions builder workflow..."
cat > .github/workflows/build-spk.yml <<'EOF'
name: Build SPK

on:
  workflow_dispatch:
  push:
    branches:
      - main

jobs:
  build:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        dsm: ["7.0"]
        arch: ["noarch"]

    steps:
      - uses: actions/checkout@v4

      - name: Build Synology package
        uses: tomgrv/synology-package-builder@v1
        with:
          dsm: ${{ matrix.dsm }}
          arch: ${{ matrix.arch }}
          projects: ./
          output: ./dist

      - name: Upload SPK artifact
        uses: actions/upload-artifact@v4
        with:
          name: webmin-spk
          path: ./dist/*.spk
EOF

echo "==> Done."
echo
echo "Next:"
echo "  git status"
echo "  git add package.json synology src .github/workflows/build-spk.yml"
echo "  git commit -m 'Rebuild Webmin SPK with DSM-safe layout'"
echo "  git push"
