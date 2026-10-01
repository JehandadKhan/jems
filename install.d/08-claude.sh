# Step 08 — Claude Code CLI, native build. Anthropic's installer
# (claude.ai/install.sh) puts the binary under ~/.local/share/claude/versions/
# and a launcher symlink at ~/.local/bin/claude. Everything is user-owned, so
# Claude's built-in auto-updater works without sudo — the reason this moved
# off 'npm i -g', whose Linux prefix (/usr) needed root for every upgrade.
# The installer refuses to run under sudo, hence run_as_user.

CLAUDE_BIN="$USER_HOME/.local/bin/claude"

if [ "$INSTALL_CLAUDE" = "1" ]; then
    # Retire an earlier npm-global install so it doesn't linger as a second
    # `claude` on PATH (and trip `claude doctor`'s multiple-installs check).
    if command -v npm >/dev/null 2>&1 \
        && npm ls -g --depth=0 @anthropic-ai/claude-code >/dev/null 2>&1; then
        echo "==> Removing npm-global @anthropic-ai/claude-code (replaced by native install)"
        npm uninstall -g @anthropic-ai/claude-code >/dev/null
    fi

    if [ -x "$CLAUDE_BIN" ]; then
        echo "==> Claude Code native install present; running 'claude update'"
        run_as_user "$CLAUDE_BIN" update >/dev/null \
            || echo "    warning: 'claude update' failed; the auto-updater will retry"
    else
        echo "==> Installing Claude Code (native) via claude.ai/install.sh"
        curl -fsSL https://claude.ai/install.sh | run_as_user bash
    fi
    echo "    claude: $(run_as_user "$CLAUDE_BIN" --version 2>/dev/null || echo unknown)"
else
    echo "==> INSTALL_CLAUDE=0; skipping Claude Code CLI install"
fi
