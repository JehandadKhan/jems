# Step 07 — basedpyright (global via npm; sidesteps PEP 668).
#
# basedpyright is a maintained fork of pyright with stricter defaults, faster
# indexing on large dynamic codebases (notably JAX, where pyright sometimes
# stalls on heavy use of `jit`/decorators), and protocol-compatible LSP. The
# binary lspconfig invokes is `basedpyright-langserver`, also installed by
# this npm package. We disable pyright in lspconfig.lua so the two don't
# fight over the same buffer if LazyVim's lang.python extra is enabled.
#
# Roll back any prior pyright install BEFORE installing basedpyright.
# basedpyright ships its own `pyright`/`pyright-langserver` shims, so a
# leftover pyright (from an earlier version of this script that did
# `npm i -g pyright`) makes the basedpyright install fail with EEXIST on
# $(npm prefix -g)/bin/pyright. Order matters here: uninstall first, then
# install.
if npm ls -g --depth=0 pyright >/dev/null 2>&1; then
    echo "==> Removing previously-installed pyright (replaced by basedpyright)"
    npm uninstall -g pyright >/dev/null 2>&1 || true
fi
# Belt-and-braces: if the shim lingers (orphaned from a partial uninstall,
# or placed there by something other than npm), drop it directly so the
# basedpyright install below doesn't EEXIST.
NPM_GLOBAL_BIN="$(npm prefix -g 2>/dev/null || echo /usr)/bin"
for stale in pyright pyright-langserver; do
    if [ -e "$NPM_GLOBAL_BIN/$stale" ] || [ -L "$NPM_GLOBAL_BIN/$stale" ]; then
        echo "==> Removing stale $NPM_GLOBAL_BIN/$stale (conflicts with basedpyright)"
        rm -f "$NPM_GLOBAL_BIN/$stale"
    fi
done

echo "==> Installing/updating basedpyright via 'npm i -g basedpyright'"
npm install -g basedpyright >/dev/null
echo "    basedpyright: $(basedpyright --version 2>/dev/null || echo unknown)"
