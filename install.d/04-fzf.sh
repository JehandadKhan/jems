# Step 04 — fzf binaries (rc-file integration is chezmoi's job).
#
# Floor: $MIN_FZF_VERSION. Without a floor here a stale ~/.fzf clone (or an
# even older apt-installed fzf in the user's PATH) could win — fzf-lua and
# the modern --tmux key-bindings rely on features only in recent fzf.

FZF_BIN="$USER_HOME/.fzf/bin/fzf"
fzf_ok=0
if [ -x "$FZF_BIN" ] && tool_version_ok "$FZF_BIN" "$MIN_FZF_VERSION"; then
    fzf_ok=1
fi

if [ "$fzf_ok" = "1" ]; then
    echo "==> fzf already at $USER_HOME/.fzf: $("$FZF_BIN" --version | head -1)"
    # Still re-run the installer so post-clone fixups (key-bindings,
    # completion scripts) line up with the current fzf tree.
    run_as_user "$USER_HOME/.fzf/install" --key-bindings --completion --no-update-rc >/dev/null
else
    if [ -d "$USER_HOME/.fzf" ]; then
        CUR_FZF="$("$FZF_BIN" --version 2>/dev/null | head -1 || echo 'not installed')"
        echo "==> Updating fzf at $USER_HOME/.fzf — current: $CUR_FZF, need >= $MIN_FZF_VERSION"
        run_as_user git -C "$USER_HOME/.fzf" pull --ff-only --quiet || \
            echo "    (git pull failed; trying installer anyway)"
    else
        echo "==> Installing fzf to $USER_HOME/.fzf (need >= $MIN_FZF_VERSION)"
        if [ "$OS" = "linux" ]; then
            # Ubuntu's apt fzf is too old; remove if present so the git copy wins.
            apt-get remove -y fzf >/dev/null 2>&1 || true
        fi
        run_as_user git clone --depth 1 https://github.com/junegunn/fzf.git "$USER_HOME/.fzf"
    fi
    run_as_user "$USER_HOME/.fzf/install" --key-bindings --completion --no-update-rc
fi
