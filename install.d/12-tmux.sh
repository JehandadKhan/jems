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
#
# Version floor: image.nvim's kitty backend refuses to start inside tmux
# unless `allow-passthrough` is set, and that option only exists in tmux
# >= 3.3. Ubuntu 22.04 (jammy) caps at 3.2a, so on jammy and older we
# build from source to /usr/local/bin/tmux (which precedes /usr/bin on
# PATH). The chezmoi'd ~/.tmux.conf uses `set -gq` (quiet), so a too-old
# tmux silently ignores the option instead of failing loudly — without
# this version check the symptom is "image.nvim still errors after I
# edited ~/.tmux.conf" with no obvious cause.

if [ "$INSTALL_TMUX" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        need_build=0
        if command -v tmux >/dev/null 2>&1; then
            cur="$(tmux -V 2>/dev/null | awk '{print $2}')"
            if tmux_version_ok "$cur"; then
                echo "==> tmux already installed: $(tmux -V)"
            else
                echo "==> tmux $cur is older than required $MIN_TMUX_VERSION"
                need_build=1
            fi
        else
            # No tmux yet — try apt first, only build if apt's candidate
            # is too old.
            apt_cand="$(apt-cache policy tmux 2>/dev/null | awk '/Candidate:/ {print $2}')"
            if tmux_version_ok "$apt_cand"; then
                echo "==> Installing tmux via apt (candidate $apt_cand)"
                apt-get install -y tmux
            else
                echo "==> apt tmux candidate $apt_cand is older than $MIN_TMUX_VERSION; will build from source"
                need_build=1
            fi
        fi

        if [ "$need_build" = "1" ]; then
            # Skip the build if a recent enough tmux is already at
            # /usr/local/bin/tmux from a previous run. PATH normally puts
            # /usr/local/bin before /usr/bin so `command -v tmux` above
            # would have found it — but if the user's PATH is unusual,
            # double-check the absolute path explicitly.
            if [ -x /usr/local/bin/tmux ] && \
                tmux_version_ok "$(/usr/local/bin/tmux -V 2>/dev/null | awk '{print $2}')"; then
                echo "==> /usr/local/bin/tmux already satisfies $MIN_TMUX_VERSION; skipping build"
            else
                echo "==> Building tmux $TMUX_SOURCE_VERSION from source"
                apt-get install -y libevent-dev libncurses-dev bison pkg-config build-essential ca-certificates curl
                tmpdir="$(mktemp -d)"
                trap 'rm -rf "$tmpdir"' RETURN
                tarball="$tmpdir/tmux-$TMUX_SOURCE_VERSION.tar.gz"
                curl -fsSL -o "$tarball" \
                    "https://github.com/tmux/tmux/releases/download/$TMUX_SOURCE_VERSION/tmux-$TMUX_SOURCE_VERSION.tar.gz"
                tar -xzf "$tarball" -C "$tmpdir"
                (
                    cd "$tmpdir/tmux-$TMUX_SOURCE_VERSION"
                    ./configure
                    make -j"$(nproc)"
                    make install
                )
                # /usr/local/bin is ahead of /usr/bin in the default PATH,
                # so a leftover apt tmux at /usr/bin/tmux is shadowed
                # without us touching it. Leave it in place — removing
                # apt's package would also yank /usr/share/tmux completions
                # and the manpage.
                echo "==> Built tmux: $(/usr/local/bin/tmux -V)"
            fi
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
        # Homebrew's tmux is always >= MIN_TMUX_VERSION so no version
        # check needed here.
    fi
else
    echo "==> INSTALL_TMUX=0; skipping tmux install"
fi
