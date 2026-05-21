# Step 09 — chezmoi (dotfile manager).
#
# Ironic but useful: this script installs the *prerequisites* for the nvim/
# Jupyter stack and explicitly leaves dotfiles to chezmoi (see CLAUDE.md), so
# installing chezmoi itself is the bootstrap step that makes that contract
# work end-to-end. Linux uses the official get.chezmoi.io installer (writes a
# single binary to /usr/local/bin), macOS uses brew. Both are idempotent.

if [ "$INSTALL_CHEZMOI" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        if tool_version_ok chezmoi "$MIN_CHEZMOI_VERSION"; then
            echo "==> chezmoi already installed: $(chezmoi --version 2>/dev/null | head -1)"
        else
            CUR_CHEZMOI="$(chezmoi --version 2>/dev/null | head -1 || echo 'not installed')"
            echo "==> Installing chezmoi to /usr/local/bin — current: $CUR_CHEZMOI, need >= v$MIN_CHEZMOI_VERSION"
            echo "    (via get.chezmoi.io)"
            sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
        fi
    else
        brew_ensure chezmoi "$MIN_CHEZMOI_VERSION"
    fi
else
    echo "==> INSTALL_CHEZMOI=0; skipping chezmoi install"
fi
