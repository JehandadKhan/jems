# Step 11 — Bitwarden CLI (`bw`).
#
# Pairs with chezmoi: chezmoi's `bitwarden` template function shells out to
# `bw` to fetch secrets out of the vault at apply time, so dotfiles can pull
# SSH keys / API tokens without committing them. Linux installs via npm
# (Node 20 is already in place from step 02); macOS uses brew. Re-running
# upgrades to the latest published version on Linux; brew is gated on
# 'brew list' so we don't gratuitously upgrade a pinned version.

if [ "$INSTALL_BW" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        echo "==> Installing/updating Bitwarden CLI via 'npm i -g @bitwarden/cli'"
        npm install -g @bitwarden/cli >/dev/null
        echo "    bw: $(bw --version 2>/dev/null || echo unknown)"
    else
        brew_install_if_missing bitwarden-cli
    fi
else
    echo "==> INSTALL_BW=0; skipping Bitwarden CLI install"
fi
