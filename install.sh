#!/usr/bin/env bash
# install.sh — install the lazy-zellij toolkit (lzj, zj, lzj-snapshot) and,
# optionally, the systemd --user units for session autostart + preview snapshots.
#
# Usage:
#   ./install.sh              # install scripts + systemd units, enable snapshot timer
#   ./install.sh --no-systemd # install scripts only (no systemd integration)
#   ./install.sh --uninstall  # remove everything this script installs
#
# Honors XDG_* and these overrides:
#   BIN_DIR     where scripts go            (default: ~/.local/bin)
#   ZELLIJ_BIN  path to the zellij binary   (default: autodetected)

set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR=${BIN_DIR:-$HOME/.local/bin}
UNIT_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user
ZELLIJ_BIN=${ZELLIJ_BIN:-$(command -v zellij 2>/dev/null || true)}

SCRIPTS=(lzj zj lzj-snapshot)
UNITS=(zellij@.service lzj-snapshot.service lzj-snapshot.timer)

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

have_systemd_user() {
    command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1
}

uninstall() {
    say "Removing lazy-zellij"
    if have_systemd_user; then
        systemctl --user disable --now lzj-snapshot.timer 2>/dev/null || true
        systemctl --user disable --now lzj-snapshot.service 2>/dev/null || true
    fi
    for s in "${SCRIPTS[@]}"; do rm -fv "$BIN_DIR/$s"; done
    for u in "${UNITS[@]}"; do rm -fv "$UNIT_DIR/$u"; done
    have_systemd_user && systemctl --user daemon-reload || true
    say "Done. (zellij@<name> sessions you enabled are left as-is; disable with: systemctl --user disable --now zellij@<name>)"
    exit 0
}

NO_SYSTEMD=0
for arg in "$@"; do
    case "$arg" in
        --uninstall) uninstall ;;
        --no-systemd) NO_SYSTEMD=1 ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) warn "unknown arg: $arg"; exit 2 ;;
    esac
done

# ── prerequisites ────────────────────────────────────────────────────────────
missing=()
command -v fzf    >/dev/null 2>&1 || missing+=(fzf)
command -v python3 >/dev/null 2>&1 || missing+=(python3)
[ -n "$ZELLIJ_BIN" ] || missing+=(zellij)
if [ ${#missing[@]} -gt 0 ]; then
    warn "missing dependencies: ${missing[*]}"
    warn "install them first (zellij + fzf are required; python3 powers the preview tree)."
    exit 1
fi
say "zellij:  $ZELLIJ_BIN"
say "fzf:     $(command -v fzf)"

# ── scripts ──────────────────────────────────────────────────────────────────
mkdir -p "$BIN_DIR"
for s in "${SCRIPTS[@]}"; do
    install -m 0755 "$SRC/bin/$s" "$BIN_DIR/$s"
    say "installed $BIN_DIR/$s"
done
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on your PATH — add it to your shell profile." ;;
esac

# ── systemd units ────────────────────────────────────────────────────────────
if [ "$NO_SYSTEMD" -eq 1 ]; then
    say "Skipping systemd integration (--no-systemd)."
elif ! have_systemd_user; then
    warn "systemd --user not available here; skipping unit install."
    warn "The scripts work fine without it — you just lose autostart + auto-snapshots."
else
    mkdir -p "$UNIT_DIR"
    for u in "${UNITS[@]}"; do
        # Substitute the zellij path into the templated unit.
        sed "s|@ZELLIJ_BIN@|$ZELLIJ_BIN|g" "$SRC/systemd/$u" > "$UNIT_DIR/$u"
        say "installed $UNIT_DIR/$u"
    done
    systemctl --user daemon-reload
    systemctl --user enable --now lzj-snapshot.timer
    say "enabled lzj-snapshot.timer (snapshots every 30s)"
    cat <<EOF

systemd is set up. Useful commands:
  systemctl --user enable --now zellij@work   # autostart a session named 'work' on boot
  lzj                                          # picker: ctrl-u enables a unit for the selected session
  loginctl enable-linger \$USER                 # (run once) keep user services alive after logout / on boot
EOF
fi

say "Installed. Run 'lzj' to open the picker, or 'lzj help' for usage."
