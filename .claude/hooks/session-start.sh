#!/bin/bash
# SessionStart hook: installs the Swift toolchain so `swift build`, `swift test`,
# and the musicsearch-eval harness work in Claude Code on the web sessions.
#
# The iOS app (MusicKit / Foundation Models / SwiftUI) still needs macOS + Xcode,
# so this only runs in the remote Linux environment.
set -euo pipefail

# Only needed in Claude Code on the web. Local macOS sessions use Xcode.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Install the Swift toolchain + build deps. Idempotent: skips the download if
# Swift is already present, and self-heals broken third-party apt PPAs.
"$CLAUDE_PROJECT_DIR/scripts/setup-swift.sh"

# Persist the Swift toolchain on PATH for the rest of the session, so build/test
# commands work without re-exporting it (the install script only writes ~/.bashrc,
# which a non-interactive shell may not source).
SWIFT_BIN="/opt/swift-6.0.3-RELEASE-ubuntu24.04/usr/bin"
if [ -d "$SWIFT_BIN" ]; then
  echo "export PATH=\"$SWIFT_BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi
