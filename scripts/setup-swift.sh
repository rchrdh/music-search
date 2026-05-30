#!/usr/bin/env bash
# Installs a Swift toolchain so the MusicSearchCore package + musicsearch-eval
# harness can be built and tested in a Linux web session.
#
# Requires the environment network policy to allow:
#   - download.swift.org   (the toolchain tarball)
#   - the Ubuntu apt archive (runtime dependencies)
#
# Note: this builds the Swift PACKAGE only. The iOS app (MusicKit / Foundation
# Models / SwiftUI) still requires macOS + Xcode and cannot be built on Linux.
set -euo pipefail

SWIFT_RELEASE="swift-6.0.3-RELEASE"
SWIFT_DIR="/opt/${SWIFT_RELEASE}-ubuntu24.04"

echo "Installing Swift toolchain dependencies…"
apt-get update
apt-get install -y --no-install-recommends \
  binutils git curl ca-certificates \
  libc6-dev libcurl4-openssl-dev libedit2 libgcc-13-dev libpython3-dev \
  libstdc++-13-dev libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev

if [ ! -x "${SWIFT_DIR}/usr/bin/swift" ]; then
  echo "Downloading ${SWIFT_RELEASE}…"
  url="https://download.swift.org/${SWIFT_RELEASE,,}/ubuntu2404/${SWIFT_RELEASE}/${SWIFT_RELEASE}-ubuntu24.04.tar.gz"
  curl -fSL "$url" -o /tmp/swift.tar.gz
  mkdir -p /opt
  tar -xzf /tmp/swift.tar.gz -C /opt
  rm -f /tmp/swift.tar.gz
fi

# Make swift available on PATH for this and future shells.
export PATH="${SWIFT_DIR}/usr/bin:${PATH}"
if ! grep -q "${SWIFT_DIR}/usr/bin" "${HOME}/.bashrc" 2>/dev/null; then
  echo "export PATH=\"${SWIFT_DIR}/usr/bin:\$PATH\"" >> "${HOME}/.bashrc"
fi

swift --version
