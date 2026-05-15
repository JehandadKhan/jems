# Step 12 — tmux + clipboard helpers.
#
# Installs the tmux binary plus the OS bridges tmux copy-mode needs to land
# yanks on the system clipboard. The chezmoi'd ~/.tmux.conf carries the
# status-bar styling, allow-passthrough for image.nvim, and
# `set -s set-clipboard on` which makes OSC 52 put copies on the system
# clipboard in modern terminals (kitty/wezterm/ghostty/iTerm2) — those
# don't need the helpers at all. The helpers (xclip/wl-clipboard) are the
# fallback for terminals that don't honor OSC 52 (stock xterm, some
# VTE-based ones) and are what lets copy-mode `y` reach the clipboard
# regardless. macOS has pbcopy built in.

if [ "$INSTALL_TMUX" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        if ! command -v tmux >/dev/null 2>&1; then
            echo "==> Installing tmux via apt"
            apt-get install -y tmux
        else
            echo "==> tmux already installed: $(tmux -V 2>/dev/null)"
        fi
        # Clipboard helpers. xclip covers X11 and works under XWayland too;
        # wl-clipboard is the native Wayland path. Installing both is cheap
        # (~1MB combined) and means the same config works on either display
        # server. Both are idempotent under apt.
        echo "==> Installing clipboard helpers (xclip + wl-clipboard)"
        apt-get install -y xclip wl-clipboard
    else
        brew_install_if_missing tmux
        # macOS: pbcopy/pbpaste are part of the OS, nothing to install.
    fi
else
    echo "==> INSTALL_TMUX=0; skipping tmux install"
fi
