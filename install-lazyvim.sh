#!/usr/bin/env bash
# One-shot installer for neovim + LazyVim with clangd/pyright LSP.
# Tested on Ubuntu 22.04 (jammy) x86_64 / WSL2.
#
# Usage:  sudo bash ~/install-lazyvim.sh
#
# Persistent system changes this script makes (read before running as root):
#   - apt packages: build deps, ripgrep, gnupg helpers
#   - NodeSource apt repo + key (installed via 'curl | bash' from
#       deb.nodesource.com — a remote script piped to root bash)
#   - Node.js 20 from NodeSource
#   - Neovim (stable) built from source -> /usr/local/bin/nvim
#   - apt.llvm.org as a persistent apt source for clangd-18 (every future
#       'apt update' will hit it; the GPG key is NOT fingerprint-pinned —
#       trusts whatever the URL serves at install time)
#   - pyright via 'npm i -g pyright' -> /usr/bin/pyright
#   - fzf cloned to ~/.fzf; appends ONE line to ~/.bashrc (zsh/fish rc
#       files are NOT modified)
#   - LazyVim starter cloned to ~/.config/nvim (skipped on re-run if a
#       LazyVim config is already present, unless FORCE_LAZYVIM=1)
#
# Toggles (env vars; defaults ON — set to 0 to disable):
#   LINK_VIM=0        Skip update-alternatives for /usr/bin/{vim,vi}.
#                       Default ON: vim and vi are system-wide aliased
#                       to nvim (affects all users on this box).
#   FORCE_LAZYVIM=0   Skip wipe + re-clone if ~/.config/nvim already
#                       has a LazyVim init.lua. Default ON: existing
#                       configs are timestamp-backed-up and re-cloned
#                       on every run (you lose plugin state, lazy-lock,
#                       any local edits — backups are kept as
#                       *.bak.<timestamp>).
#
# Re-run safety: apt/node/nvim/fzf/clangd/pyright steps are idempotent.
# With FORCE_LAZYVIM=1 (default), the LazyVim section re-clones every run.
#
# To uninstall the apt sources later (clangd-18 binary will remain):
#   sudo rm /etc/apt/sources.list.d/llvm-18.list /etc/apt/keyrings/llvm.gpg
#   sudo rm /etc/apt/sources.list.d/nodesource.list

set -euo pipefail

LINK_VIM="${LINK_VIM:-1}"
FORCE_LAZYVIM="${FORCE_LAZYVIM:-1}"

# ---------- preflight ----------
if [ "$EUID" -ne 0 ]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-}"
if [ -z "$TARGET_USER" ] || [ "$TARGET_USER" = "root" ]; then
    echo "Could not determine non-root user. Invoke via 'sudo' from your normal account." >&2
    exit 1
fi
USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
echo "==> Installing for user: $TARGET_USER (home: $USER_HOME)"

# Run argv as the target user (argv passed straight through; no shell parsing).
run_as_user() { sudo -u "$TARGET_USER" -H -- "$@"; }

# ---------- 1. apt prereqs ----------
echo "==> apt prereqs"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
    ninja-build gettext cmake unzip curl wget git \
    build-essential ripgrep ca-certificates \
    gnupg lsb-release software-properties-common

# ---------- 2. Node 20+ ----------
# Accept any Node >=20 (so a pre-existing v22/v24 is left alone).
if ! command -v node >/dev/null 2>&1 || ! node -v 2>/dev/null | grep -qE '^v(2[0-9]|[3-9][0-9])'; then
    echo "==> Installing Node.js 20 (NodeSource: curl|bash adds apt repo + key)"
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
else
    echo "==> Node.js already present: $(node -v)"
fi

# ---------- 3. neovim (stable) from source ----------
need_nvim=true
if command -v nvim >/dev/null 2>&1 \
   && nvim --version | head -1 | grep -qE 'v(0\.(9|[1-9][0-9])|[1-9])\.'; then
    need_nvim=false
fi
if $need_nvim; then
    echo "==> Building neovim (stable) from source"
    BUILD_DIR=$(mktemp -d)
    git clone -b stable --depth 1 https://github.com/neovim/neovim "$BUILD_DIR/neovim"
    pushd "$BUILD_DIR/neovim" >/dev/null
    make CMAKE_BUILD_TYPE=RelWithDebInfo -j"$(nproc)"
    make install
    popd >/dev/null
    rm -rf "$BUILD_DIR"
else
    echo "==> nvim already installed: $(nvim --version | head -1)"
fi

# Optional: alias vim/vi -> nvim system-wide
if [ "$LINK_VIM" = "1" ]; then
    echo "==> Aliasing vim/vi -> nvim system-wide"
    update-alternatives --install /usr/bin/vim vim /usr/local/bin/nvim 100
    update-alternatives --install /usr/bin/vi  vi  /usr/local/bin/nvim 100
else
    echo "    (LINK_VIM=0; leaving vim/vi alone)"
fi

# ---------- 4. fzf (no rc rewrites) ----------
if [ ! -d "$USER_HOME/.fzf" ]; then
    echo "==> Installing fzf to $USER_HOME/.fzf"
    apt-get remove -y fzf >/dev/null 2>&1 || true
    run_as_user git clone --depth 1 https://github.com/junegunn/fzf.git "$USER_HOME/.fzf"
    run_as_user "$USER_HOME/.fzf/install" --key-bindings --completion --no-update-rc
    BASHRC="$USER_HOME/.bashrc"
    if [ -f "$BASHRC" ] && ! grep -q '\.fzf\.bash' "$BASHRC"; then
        echo '[ -f "$HOME/.fzf.bash" ] && source "$HOME/.fzf.bash"' >> "$BASHRC"
    fi
else
    echo "==> fzf already at $USER_HOME/.fzf"
fi

# ---------- 5. clangd-18 via apt.llvm.org ----------
if ! command -v clangd-18 >/dev/null 2>&1; then
    echo "==> Installing clangd-18 (adds apt.llvm.org as a persistent source)"
    CODENAME="$(lsb_release -cs)"
    install -d -m 0755 /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/llvm.gpg ]; then
        wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key \
            | gpg --dearmor -o /etc/apt/keyrings/llvm.gpg
    fi
    echo "deb [signed-by=/etc/apt/keyrings/llvm.gpg] http://apt.llvm.org/${CODENAME}/ llvm-toolchain-${CODENAME}-18 main" \
        > /etc/apt/sources.list.d/llvm-18.list
    apt-get update -y
    apt-get install -y clangd-18
fi
update-alternatives --install /usr/bin/clangd clangd /usr/bin/clangd-18 100

# ---------- 6. pyright (global via npm; sidesteps PEP 668) ----------
if ! command -v pyright >/dev/null 2>&1; then
    echo "==> Installing pyright via 'npm i -g pyright'"
    npm install -g pyright
else
    echo "==> pyright already present: $(pyright --version 2>/dev/null || echo unknown)"
fi

# ---------- 7. LazyVim starter ----------
LAZYVIM_DIR="$USER_HOME/.config/nvim"
if [ -f "$LAZYVIM_DIR/init.lua" ] && [ "$FORCE_LAZYVIM" != "1" ]; then
    echo "==> LazyVim already at $LAZYVIM_DIR — skipping (FORCE_LAZYVIM=0)"
else
    echo "==> Setting up LazyVim starter"
    TS="$(date +%Y%m%d-%H%M%S)"
    for d in "$USER_HOME/.config/nvim" \
             "$USER_HOME/.local/share/nvim" \
             "$USER_HOME/.local/state/nvim" \
             "$USER_HOME/.cache/nvim"; do
        if [ -e "$d" ]; then
            echo "   backup: $d -> $d.bak.$TS"
            mv "$d" "$d.bak.$TS"
        fi
    done
    run_as_user git clone https://github.com/LazyVim/starter "$LAZYVIM_DIR"
    rm -rf "$LAZYVIM_DIR/.git"
fi

# ---------- 8. customizations (only if missing) ----------
OPTIONS_LUA="$LAZYVIM_DIR/lua/config/options.lua"
if [ -f "$OPTIONS_LUA" ] && ! grep -q 'vim.g.autoformat = false' "$OPTIONS_LUA"; then
    echo "==> Appending autoformat=false to options.lua"
    cat >> "$OPTIONS_LUA" <<'EOF'

-- Disable format on save (override LazyVim default)
vim.g.autoformat = false
EOF
fi

LSPCFG="$LAZYVIM_DIR/lua/plugins/lspconfig.lua"
if [ ! -f "$LSPCFG" ]; then
    echo "==> Writing lua/plugins/lspconfig.lua (clangd: mason=false)"
    cat > "$LSPCFG" <<'EOF'
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      clangd = {
        mason = false,
      },
    },
  },
}
EOF
fi

chown -R "$TARGET_USER:$TARGET_USER" "$LAZYVIM_DIR" 2>/dev/null || true

# ---------- summary ----------
echo
echo "==> Done."
printf "    %-9s %s\n" "nvim:"    "$(nvim --version | head -1)"
printf "    %-9s %s\n" "node:"    "$(node -v 2>/dev/null || echo missing)"
printf "    %-9s %s\n" "clangd:"  "$(clangd --version 2>/dev/null | head -1 || echo missing)"
printf "    %-9s %s\n" "pyright:" "$(pyright --version 2>/dev/null || echo missing)"
printf "    %-9s %s\n" "fzf:"     "$("$USER_HOME/.fzf/bin/fzf" --version 2>/dev/null || echo missing)"
echo
echo "Persistent apt sources added (remove manually to undo):"
echo "    /etc/apt/sources.list.d/llvm-18.list"
echo "    /etc/apt/keyrings/llvm.gpg"
echo "    /etc/apt/sources.list.d/nodesource.list"
echo
echo "Next:"
echo "  1. Open a new shell so ~/.bashrc fzf hook loads."
echo "  2. Run 'nvim' — LazyVim will bootstrap plugins on first launch."
