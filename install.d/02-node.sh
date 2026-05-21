# Step 02 — Node.js >= MIN_NODE_VERSION. Several later steps (basedpyright,
# claude, bw on Linux) shell out to npm, so this runs before them. A pre-
# existing newer Node (v22, v24, ...) is left alone.

if tool_version_ok node "$MIN_NODE_VERSION" -v; then
    echo "==> Node.js already present: $(node -v)"
else
    CUR_NODE="$(node -v 2>/dev/null || echo 'not installed')"
    if [ "$OS" = "linux" ]; then
        echo "==> Installing Node.js 20 — current: $CUR_NODE, need >= v$MIN_NODE_VERSION"
        echo "    (NodeSource: curl|bash adds apt repo + key)"
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    else
        # On macOS go through brew_ensure so an old brew node gets upgraded
        # rather than skipped. No min passed means "install if missing"; we
        # pass MIN_NODE_VERSION so a stale brew node is upgraded too.
        echo "==> Ensuring Node.js >= $MIN_NODE_VERSION via brew (current: $CUR_NODE)"
        brew_ensure node "$MIN_NODE_VERSION"
    fi
fi
