# Step 14 — Nerd Font (icons for starship/lualine/tmux status).
#
# Without a nerd font installed AND the terminal configured to use it, the
# glyphs in starship's two-line preset and lualine render as tofu. Installing
# the font is half the fix; the other half (terminal font setting) is on the
# user — we can't reach into kitty/wezterm/iTerm2/ghostty preferences from a
# shell script.
#
# Linux: pull the release zip from ryanoasis/nerd-fonts (user-local under
# ~/.local/share/fonts/) and run fc-cache. fontconfig (which provides
# fc-cache) is pulled in via apt if not already installed. The release tag
# is pinned in the driver (NERD_FONT_TAG) so re-runs across machines land
# on the same version, and the script doesn't randomly re-download when
# upstream publishes a new release.
#
# macOS: brew cask installs system-wide; idempotent via `brew list --cask`.

if [ "$INSTALL_NERD_FONT" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        FONT_DIR="$USER_HOME/.local/share/fonts/${NERD_FONT_NAME}NerdFont"
        # Detect prior install by looking for any .ttf with the font name —
        # robust to upstream renaming individual files between releases.
        if [ -d "$FONT_DIR" ] && ls "$FONT_DIR"/*.ttf >/dev/null 2>&1; then
            echo "==> Nerd font ${NERD_FONT_NAME} already present at $FONT_DIR"
        else
            echo "==> Installing nerd font ${NERD_FONT_NAME} (${NERD_FONT_TAG}) to $FONT_DIR"
            # fc-cache lives in fontconfig; ensure it's there.
            if ! command -v fc-cache >/dev/null 2>&1; then
                apt-get install -y fontconfig
            fi
            run_as_user mkdir -p "$FONT_DIR" "$USER_HOME/.cache"
            # Stage the download under the target user's home rather than /tmp.
            # mktemp under /tmp creates a 0700 root-owned dir when the script
            # runs via sudo, and `run_as_user unzip ...` (which drops privs)
            # then can't read inside it — unzip reports the file as missing
            # because open() fails with EACCES before any extension probing.
            FONT_TMP="$(run_as_user mktemp -d "$USER_HOME/.cache/nerd-font.XXXXXX")"
            FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_TAG}/${NERD_FONT_NAME}.zip"
            if run_as_user curl -fsSL --retry 3 -o "$FONT_TMP/font.zip" "$FONT_URL"; then
                # -o overwrite, -q quiet. Limit to .ttf so we don't litter
                # the install dir with readmes and license copies.
                run_as_user unzip -oq "$FONT_TMP/font.zip" '*.ttf' -d "$FONT_DIR"
                run_as_user fc-cache -f "$FONT_DIR" >/dev/null
                echo "    installed $(ls "$FONT_DIR"/*.ttf 2>/dev/null | wc -l) .ttf files"
            else
                echo "    WARNING: failed to download $FONT_URL; skipping font install"
                echo "             (check NERD_FONT_NAME — must match a release asset name)"
            fi
            run_as_user rm -rf "$FONT_TMP"
        fi
    else
        FONT_CASK="$(nerd_font_cask "$NERD_FONT_NAME")"
        if brew list --cask "$FONT_CASK" >/dev/null 2>&1; then
            echo "==> Nerd font cask $FONT_CASK already installed"
        else
            echo "==> Installing nerd font cask $FONT_CASK"
            if ! brew install --cask "$FONT_CASK"; then
                echo "    WARNING: brew install --cask $FONT_CASK failed"
                echo "             (check NERD_FONT_NAME — see 'brew search font-*-nerd-font')"
            fi
        fi
    fi
else
    echo "==> INSTALL_NERD_FONT=0; skipping nerd font install"
fi
