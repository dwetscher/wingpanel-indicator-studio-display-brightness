#!/usr/bin/env bash
#
# install.sh — build and install the Studio Display Brightness wingpanel indicator.
#
# Steps:
#   1. Check build tools (and resolve asdbctl).
#   2. Build with meson/ninja and install the indicator module (needs sudo).
#   3. Ensure asdbctl is reachable + install the udev rule (needs sudo).
#   4. Restart wingpanel so it loads the new indicator.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$REPO_DIR/build"
WINGPANEL_BIN="io.elementary.wingpanel"

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
error() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. Dependency checks
# ---------------------------------------------------------------------------
info "Checking build tools…"
missing=()
for tool in meson ninja valac pkg-config; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
pkg-config --exists wingpanel 2>/dev/null || missing+=("libwingpanel-dev")
pkg-config --exists gudev-1.0 2>/dev/null || missing+=("libgudev-1.0-dev")
if [ "${#missing[@]}" -gt 0 ]; then
    error "Missing build dependencies: ${missing[*]}
Install them with:
  sudo apt install valac meson ninja-build build-essential pkg-config \\
                   libgtk-3-dev libwingpanel-dev libgudev-1.0-dev"
fi

# Resolve asdbctl even when ~/.cargo/bin isn't on this shell's PATH.
ASDBCTL_BIN="$(command -v asdbctl || true)"
if [ -z "$ASDBCTL_BIN" ] && [ -x "$HOME/.cargo/bin/asdbctl" ]; then
    ASDBCTL_BIN="$HOME/.cargo/bin/asdbctl"
fi
if [ -z "$ASDBCTL_BIN" ]; then
    warn "asdbctl is not installed. The indicator hides itself until it is.
Build it from https://github.com/juliuszint/asdbctl:
  sudo apt install libudev-dev
  git clone https://github.com/juliuszint/asdbctl && cd asdbctl && cargo install --path . --locked"
fi

# ---------------------------------------------------------------------------
# 2. Build & install the indicator module
# ---------------------------------------------------------------------------
info "Configuring and building…"
if [ ! -d "$BUILD_DIR" ]; then
    meson setup "$BUILD_DIR" "$REPO_DIR"
fi
ninja -C "$BUILD_DIR"

info "Installing indicator module (sudo)…"
sudo ninja -C "$BUILD_DIR" install

# Clean up artifacts from the earlier standalone-app version, if present.
sudo rm -f /usr/local/bin/studio-display-brightness \
           /usr/local/share/applications/io.github.dwetscher.StudioDisplayBrightness.desktop
rm -f "$HOME/.config/autostart/io.github.dwetscher.StudioDisplayBrightness.desktop"

# ---------------------------------------------------------------------------
# 3. asdbctl on the system PATH + udev rule for non-root HID access
# ---------------------------------------------------------------------------
# wingpanel runs asdbctl; apt's cargo does not put ~/.cargo/bin on the session
# PATH, so symlink it system-wide.
if [ -n "${ASDBCTL_BIN:-}" ]; then
    case "$ASDBCTL_BIN" in
        /usr/*|/bin/*|/sbin/*) : ;; # already on the system PATH
        *)
            info "Linking asdbctl into /usr/local/bin (sudo)…"
            sudo ln -sf "$ASDBCTL_BIN" /usr/local/bin/asdbctl
            ;;
    esac
fi

# The udev rule is installed by `meson install` (to /usr/lib/udev/rules.d);
# just reload so it applies to the already-connected display.
info "Reloading udev rules (sudo)…"
sudo udevadm control --reload-rules
sudo udevadm trigger
info "If brightness still needs sudo, replug the display once."

# ---------------------------------------------------------------------------
# 4. Reload wingpanel so it picks up the new indicator
# ---------------------------------------------------------------------------
info "Reloading wingpanel…"
if pgrep -x "$WINGPANEL_BIN" >/dev/null 2>&1; then
    killall "$WINGPANEL_BIN" 2>/dev/null || true
    sleep 1
fi
if ! pgrep -x "$WINGPANEL_BIN" >/dev/null 2>&1; then
    setsid "$WINGPANEL_BIN" >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null || true
fi
info "Done. The brightness icon should appear in the panel."
