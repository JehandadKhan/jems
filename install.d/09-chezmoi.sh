# Step 09 — chezmoi (dotfile manager).
#
# Ironic but useful: this script installs the *prerequisites* for the nvim/
# Jupyter stack and explicitly leaves dotfiles to chezmoi (see CLAUDE.md), so
# installing chezmoi itself is the bootstrap step that makes that contract
# work end-to-end. Linux uses the official get.chezmoi.io installer (writes a
# single binary to /usr/local/bin), macOS uses brew. Both are idempotent.

if [ "$INSTALL_CHEZMOI" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        if ! command -v chezmoi >/dev/null 2>&1; then
            echo "==> Installing chezmoi to /usr/local/bin (via get.chezmoi.io)"
            sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
        else
            echo "==> chezmoi already installed: $(chezmoi --version 2>/dev/null | head -1)"
        fi
    else
        brew_install_if_missing chezmoi
    fi
else
    echo "==> INSTALL_CHEZMOI=0; skipping chezmoi install"
fi
