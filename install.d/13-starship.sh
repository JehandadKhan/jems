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
        # Re-run unconditionally to pick up new releases; the installer's
        # -y flag overwrites any existing /usr/local/bin/starship in place.
        echo "==> Installing/updating starship to /usr/local/bin (via sh.starship.rs)"
        curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin
    else
        brew_install_if_missing starship
    fi
else
    echo "==> INSTALL_STARSHIP=0; skipping starship install"
fi
