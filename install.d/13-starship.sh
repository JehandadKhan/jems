# Step 13 — starship (shell prompt).
#
# Cross-shell prompt with git branch, user, host, language/runtime context,
# etc. The chezmoi'd shell rc must run `eval "$(starship init bash)"`
# (or zsh) to actually wire it in; this step just installs the binary.
# Optional ~/.config/starship.toml for theming is also chezmoi's territory.
#
# Linux uses the official installer (https://starship.rs/install.sh) which
# drops a single binary at /usr/local/bin/starship — no apt repo to maintain.
# We pipe with `-y` so it doesn't prompt on re-runs. macOS uses brew.

if [ "$INSTALL_STARSHIP" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        if tool_version_ok starship "$MIN_STARSHIP_VERSION"; then
            echo "==> starship already installed: $(starship --version 2>/dev/null | head -1)"
        else
            CUR_STARSHIP="$(starship --version 2>/dev/null | head -1 || echo 'not installed')"
            echo "==> Installing/updating starship to /usr/local/bin — current: $CUR_STARSHIP, need >= v$MIN_STARSHIP_VERSION"
            echo "    (via sh.starship.rs; --yes overwrites existing binary)"
            curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin
        fi
    else
        brew_ensure starship "$MIN_STARSHIP_VERSION"
    fi
else
    echo "==> INSTALL_STARSHIP=0; skipping starship install"
fi
