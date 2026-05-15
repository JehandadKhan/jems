# Step 08 — Claude Code CLI (global via npm). Same npm-global story as
# basedpyright; piggybacks on Node 20+ from step 02. Re-running upgrades
# to the latest published version.

if [ "$INSTALL_CLAUDE" = "1" ]; then
    echo "==> Installing/updating Claude Code via 'npm i -g @anthropic-ai/claude-code'"
    npm install -g @anthropic-ai/claude-code >/dev/null
    echo "    claude: $(claude --version 2>/dev/null || echo unknown)"
else
    echo "==> INSTALL_CLAUDE=0; skipping Claude Code CLI install"
fi
