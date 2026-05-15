# Step 99 — optional interactive bootstrap.
#
# Offer to run the two follow-ups that almost always come right after this
# script: cloning the chezmoi dotfile source, and pointing the Bitwarden CLI
# at the user's vault server. Both are skipped silently when stdin isn't a
# TTY (curl|bash flows, CI, etc.) so re-runs from automation don't block.

if [ -t 0 ] && [ -t 1 ]; then
    if [ "$INSTALL_CHEZMOI" = "1" ] && command -v chezmoi >/dev/null 2>&1; then
        echo
        if [ -d "$USER_HOME/.local/share/chezmoi" ]; then
            echo "==> chezmoi source already exists at $USER_HOME/.local/share/chezmoi; skipping init prompt."
            echo "    (Run 'chezmoi update' or 'chezmoi apply' from your shell to refresh.)"
        else
            printf "Run 'chezmoi init' now to clone your dotfile repo? [y/N] "
            read -r ANSWER || ANSWER=""
            if [[ "$ANSWER" =~ ^[Yy] ]]; then
                printf "  Source repo (e.g. github-user, or git@github.com:user/dotfiles.git): "
                read -r CHEZMOI_REPO || CHEZMOI_REPO=""
                if [ -n "$CHEZMOI_REPO" ]; then
                    run_as_user chezmoi init --apply -- "$CHEZMOI_REPO"
                else
                    echo "    (empty repo; skipping)"
                fi
            fi
        fi
    fi

    if [ "$INSTALL_BW" = "1" ] && command -v bw >/dev/null 2>&1; then
        echo
        printf "Configure Bitwarden CLI server URL now? [y/N] "
        read -r ANSWER || ANSWER=""
        if [[ "$ANSWER" =~ ^[Yy] ]]; then
            printf "  Server URL [default: https://vault.bitwarden.com]: "
            read -r BW_SERVER || BW_SERVER=""
            BW_SERVER="${BW_SERVER:-https://vault.bitwarden.com}"
            run_as_user bw config server "$BW_SERVER" || \
                echo "    (bw config server failed; you may already be logged in — run 'bw logout' first)"
            echo "    Server set. Run 'bw login' from your shell to authenticate"
            echo "    (intentionally not run here so the master password stays off this transcript)."
        fi
    fi
fi
