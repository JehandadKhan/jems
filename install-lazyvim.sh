#!/usr/bin/env bash
# Prerequisite installer for the neovim + LazyVim + Jupyter notebook stack.
# Tested on Ubuntu 22.04 (jammy) x86_64 / WSL2 and macOS 14+ (Apple Silicon
# and Intel).
#
# Scope: this script installs *only* the system-level prerequisites that
# can't be expressed as dotfiles — packages, language toolchains, the nvim
# binary, the Python venv that molten-nvim needs, and a couple of
# environment-specific symlinks under ~/.local/bin. All actual config
# files (~/.config/nvim/**, ~/.tmux.conf, ~/.bashrc, etc.) are managed by
# chezmoi out-of-band and are NOT touched here.
#
# Usage (Linux): sudo bash ~/install-lazyvim.sh
# Usage (macOS): bash ~/install-lazyvim.sh
#                MUST NOT be invoked under sudo — Homebrew refuses to run as
#                root, and the script has no system-wide writes on macOS.
# Re-run:        the same command. The script is designed to be safely
#                re-run on any machine to bring tools up to date. Python
#                deps in the nvim venv are upgraded; brew/apt installs are
#                gated on whether the formula/package is already present so
#                we don't gratuitously upgrade pinned versions.
#
# Prerequisite (macOS): Homebrew must be installed first (https://brew.sh).
#   Xcode Command Line Tools are pulled in by brew on first install.
#
# Persistent system changes this script makes (read before running):
#
#   Linux (Ubuntu/Debian, requires sudo):
#     - apt packages: build deps, ripgrep, gnupg helpers, imagemagick,
#         python3-venv / python3-pip / python3-dev
#     - NodeSource apt repo + key (installed via 'curl | bash' from
#         deb.nodesource.com — a remote script piped to root bash)
#     - Node.js 20 from NodeSource (only if no Node >=20 is present)
#     - Neovim (stable) built from source -> /usr/local/bin/nvim
#     - apt.llvm.org as a persistent apt source for clangd-18 (every future
#         'apt update' will hit it; the GPG key is NOT fingerprint-pinned —
#         trusts whatever the URL serves at install time)
#     - update-alternatives entries for /usr/bin/clangd (and optionally
#         /usr/bin/{vim,vi} when LINK_VIM=1) — affects all users on the box
#
#   macOS (Homebrew, runs as your user):
#     - brew formulae installed if missing: neovim, node, ripgrep, ninja,
#         cmake, gettext, imagemagick, llvm (for clangd). Existing versions
#         are left alone (the script does not 'brew upgrade').
#     - Symlink ~/.local/bin/clangd -> $(brew --prefix llvm)/bin/clangd
#         (brew does not link llvm by default to avoid clobbering Apple's
#         clang). Remove the symlink to undo.
#     - Symlinks ~/.local/bin/{vim,vi} -> nvim when LINK_VIM=1 (default).
#         User-local; remove to undo. Requires ~/.local/bin on PATH (your
#         chezmoi'd shell rc is expected to set that up).
#
#   Both:
#     - pyright via 'npm i -g pyright' (Linux: /usr/bin/pyright; macOS:
#         $(brew --prefix)/bin/pyright)
#     - fzf cloned to ~/.fzf and its install script run with
#         --no-update-rc (so no rc files are touched). Your chezmoi'd
#         bashrc/zshrc is expected to source ~/.fzf.bash / ~/.fzf.zsh.
#     - Python venv at ~/.local/share/nvim-venv with pynvim + jupyter deps.
#         Your chezmoi'd nvim config should set
#         vim.g.python3_host_prog = "$HOME/.local/share/nvim-venv/bin/python"
#         so molten-nvim can find pynvim.
#     - Symlink ~/.local/bin/jupytext -> nvim-venv's jupytext CLI, so
#         jupytext.nvim can find it on PATH (remove the symlink to undo).
#     - ipykernel registered against the nvim venv so notebooks have a
#         default kernel out of the box.
#
# Toggles (env vars; defaults shown — set to 0/1 as noted to flip):
#   LINK_VIM=0          Skip aliasing vim/vi to nvim. Default ON: vim and
#                         vi resolve to nvim. Linux: system-wide via
#                         update-alternatives (affects all users). macOS:
#                         user-local symlinks in ~/.local/bin.
#   SKIP_NVIM_BUILD=1   (Linux only) Skip rebuilding neovim from source
#                         even if the installed version is below the
#                         LazyVim minimum (see MIN_NVIM_VERSION). macOS
#                         always uses 'brew install/upgrade neovim'.
#                         Default OFF.
#
# To uninstall the apt sources later (Linux; clangd-18 binary will remain):
#   sudo rm /etc/apt/sources.list.d/llvm-18.list /etc/apt/keyrings/llvm.gpg
#   sudo rm /etc/apt/sources.list.d/nodesource.list

set -euo pipefail

LINK_VIM="${LINK_VIM:-1}"
SKIP_NVIM_BUILD="${SKIP_NVIM_BUILD:-0}"

# LazyVim's minimum supported neovim. Below this, LazyVim aborts with a
# "Press any key to exit" prompt during startup, which makes plugin sync
# (headless or not) hang forever — so we treat anything older as needing
# an install/upgrade. Bump this when LazyVim bumps its requirement.
# See https://github.com/LazyVim/LazyVim/issues/6421 for the symptom.
MIN_NVIM_VERSION="0.11.2"

# ---------- OS detection ----------
case "$(uname -s)" in
    Linux)  OS=linux ;;
    Darwin) OS=macos ;;
    *) echo "Unsupported OS: $(uname -s) — this script targets Linux (apt) and macOS (brew)." >&2; exit 1 ;;
esac

# ---------- preflight ----------
if [ "$OS" = "linux" ]; then
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
else
    # macOS: brew refuses to run as root and we have no system-wide writes,
    # so insist on running as the actual user.
    if [ "$EUID" -eq 0 ]; then
        echo "On macOS this script must NOT be run as root (Homebrew refuses sudo)." >&2
        echo "Re-run as: bash $0" >&2
        exit 1
    fi
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew is required on macOS but was not found on PATH." >&2
        echo "Install it first from https://brew.sh and re-run this script." >&2
        exit 1
    fi
    TARGET_USER="$USER"
    USER_HOME="$HOME"
    BREW_PREFIX="$(brew --prefix)"
fi
echo "==> Installing for user: $TARGET_USER on $OS (home: $USER_HOME)"

# Run argv as the target user. On Linux we're root and drop privileges via
# sudo; on macOS we're already the user, so it's a passthrough.
if [ "$OS" = "linux" ]; then
    run_as_user() { sudo -u "$TARGET_USER" -H -- "$@"; }
else
    run_as_user() { "$@"; }
fi

# ---------- 1. system prereqs ----------
if [ "$OS" = "linux" ]; then
    echo "==> apt prereqs"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y \
        ninja-build gettext cmake unzip curl wget git \
        build-essential ripgrep ca-certificates \
        gnupg lsb-release software-properties-common \
        imagemagick \
        python3-venv python3-pip python3-dev
else
    # macOS: install only what's missing so we don't gratuitously upgrade
    # tools the user is pinning. Xcode CLT (git, curl, make) is pulled in
    # by brew on its first install.
    echo "==> brew prereqs"
    BREW_FORMULAE=(ninja cmake gettext ripgrep imagemagick)
    if ! command -v python3 >/dev/null 2>&1; then
        BREW_FORMULAE+=(python)
    fi
    for f in "${BREW_FORMULAE[@]}"; do
        if brew list --formula "$f" >/dev/null 2>&1; then
            echo "    $f already installed"
        else
            echo "    installing $f"
            brew install "$f"
        fi
    done
fi

# ---------- 2. Node 20+ ----------
# Accept any Node >=20 (so a pre-existing v22/v24 is left alone).
if ! command -v node >/dev/null 2>&1 || ! node -v 2>/dev/null | grep -qE '^v(2[0-9]|[3-9][0-9])'; then
    if [ "$OS" = "linux" ]; then
        echo "==> Installing Node.js 20 (NodeSource: curl|bash adds apt repo + key)"
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    else
        echo "==> Installing Node.js via brew"
        brew install node
    fi
else
    echo "==> Node.js already present: $(node -v)"
fi

# ---------- 3. neovim ----------
# Returns 0 if nvim is on PATH and >= MIN_NVIM_VERSION, else 1. We compare
# major.minor.patch numerically via awk so we don't depend on GNU sort -V
# (BSD sort on macOS doesn't have it).
nvim_version_ok() {
    command -v nvim >/dev/null 2>&1 || return 1
    local cur
    cur="$(nvim --version 2>/dev/null | head -1 | awk '{print $2}' | sed 's/^v//')"
    [ -n "$cur" ] || return 1
    awk -v cur="$cur" -v min="$MIN_NVIM_VERSION" 'BEGIN {
        n = split(cur, c, "."); split(min, m, ".")
        for (i = 1; i <= 3; i++) {
            cv = (i <= n) ? c[i]+0 : 0
            mv = m[i]+0
            if (cv > mv) exit 0
            if (cv < mv) exit 1
        }
        exit 0
    }'
}

need_nvim=true
if nvim_version_ok; then
    need_nvim=false
fi
if [ "$OS" = "linux" ] && [ "$SKIP_NVIM_BUILD" = "1" ]; then
    need_nvim=false
    echo "==> SKIP_NVIM_BUILD=1; not rebuilding nvim ($(nvim --version 2>/dev/null | head -1 || echo missing))"
fi
if $need_nvim; then
    CUR_VER="$(nvim --version 2>/dev/null | head -1 || echo 'not installed')"
    if [ "$OS" = "linux" ]; then
        echo "==> Building neovim (stable) from source — current: $CUR_VER, need >= v$MIN_NVIM_VERSION"
        BUILD_DIR=$(mktemp -d)
        git clone -b stable --depth 1 https://github.com/neovim/neovim "$BUILD_DIR/neovim"
        pushd "$BUILD_DIR/neovim" >/dev/null
        make CMAKE_BUILD_TYPE=RelWithDebInfo -j"$(nproc)"
        make install
        popd >/dev/null
        rm -rf "$BUILD_DIR"
    else
        # macOS: install if missing, upgrade if too old. Both go through brew.
        if command -v nvim >/dev/null 2>&1; then
            echo "==> Upgrading neovim via brew — current: $CUR_VER, need >= v$MIN_NVIM_VERSION"
            brew upgrade neovim
        else
            echo "==> Installing neovim via brew (need >= v$MIN_NVIM_VERSION)"
            brew install neovim
        fi
    fi
else
    echo "==> nvim already installed: $(nvim --version | head -1)"
fi

# Resolve the absolute path to nvim once — used for symlinks below.
NVIM_BIN="$(command -v nvim || true)"

# Optional: alias vim/vi -> nvim. Linux uses update-alternatives (system-wide,
# affects all users). macOS uses user-local symlinks in ~/.local/bin since
# /usr/bin is SIP-protected and brew shouldn't fight system tools.
if [ "$LINK_VIM" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        echo "==> Aliasing vim/vi -> nvim system-wide"
        update-alternatives --install /usr/bin/vim vim /usr/local/bin/nvim 100
        update-alternatives --install /usr/bin/vi  vi  /usr/local/bin/nvim 100
    else
        echo "==> Aliasing vim/vi -> nvim via ~/.local/bin (user-local)"
        run_as_user mkdir -p "$USER_HOME/.local/bin"
        run_as_user ln -sf "$NVIM_BIN" "$USER_HOME/.local/bin/vim"
        run_as_user ln -sf "$NVIM_BIN" "$USER_HOME/.local/bin/vi"
    fi
else
    echo "    (LINK_VIM=0; leaving vim/vi alone)"
fi

# ---------- 4. fzf (binary install only; rc files are chezmoi's job) ----------
if [ ! -d "$USER_HOME/.fzf" ]; then
    echo "==> Installing fzf to $USER_HOME/.fzf"
    if [ "$OS" = "linux" ]; then
        # Ubuntu's apt fzf is too old; remove if present so the git copy wins.
        apt-get remove -y fzf >/dev/null 2>&1 || true
    fi
    run_as_user git clone --depth 1 https://github.com/junegunn/fzf.git "$USER_HOME/.fzf"
    run_as_user "$USER_HOME/.fzf/install" --key-bindings --completion --no-update-rc
else
    echo "==> Updating existing fzf at $USER_HOME/.fzf"
    run_as_user git -C "$USER_HOME/.fzf" pull --ff-only --quiet || true
    run_as_user "$USER_HOME/.fzf/install" --key-bindings --completion --no-update-rc >/dev/null
fi

# ---------- 5. clangd ----------
if [ "$OS" = "linux" ]; then
    # apt.llvm.org pin gets us a current clangd on jammy/focal-era distros
    # whose stock clangd is several majors behind.
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
else
    # macOS: brew's `llvm` formula is keg-only (not auto-linked) so it doesn't
    # collide with Apple's clang. Symlink only the clangd binary into
    # ~/.local/bin so nvim/lspconfig finds it on PATH.
    if ! brew list --formula llvm >/dev/null 2>&1; then
        echo "==> Installing llvm via brew (provides clangd; keg-only by design)"
        brew install llvm
    else
        echo "==> brew llvm already installed"
    fi
    LLVM_PREFIX="$(brew --prefix llvm)"
    if [ ! -x "$LLVM_PREFIX/bin/clangd" ]; then
        echo "    WARNING: $LLVM_PREFIX/bin/clangd not found after brew install"
    fi
    run_as_user mkdir -p "$USER_HOME/.local/bin"
    run_as_user ln -sf "$LLVM_PREFIX/bin/clangd" "$USER_HOME/.local/bin/clangd"
fi

# ---------- 6. pyright (global via npm; sidesteps PEP 668) ----------
echo "==> Installing/updating pyright via 'npm i -g pyright'"
npm install -g pyright >/dev/null
echo "    pyright: $(pyright --version 2>/dev/null || echo unknown)"

# ---------- 7. nvim Python venv (for molten-nvim + jupyter) ----------
NVIM_VENV="$USER_HOME/.local/share/nvim-venv"
if [ ! -d "$NVIM_VENV" ]; then
    echo "==> Creating Python venv for nvim at $NVIM_VENV"
    run_as_user python3 -m venv "$NVIM_VENV"
fi
echo "==> Updating Python packages in $NVIM_VENV"
run_as_user "$NVIM_VENV/bin/pip" install --quiet --upgrade pip wheel
run_as_user "$NVIM_VENV/bin/pip" install --quiet --upgrade \
    pynvim jupyter_client nbformat ipykernel jupytext \
    Pillow cairosvg pyperclip

# jupytext.nvim shells out to the `jupytext` CLI on PATH; expose the venv's
# copy via ~/.local/bin so nvim (which doesn't have the venv on PATH) finds it.
run_as_user mkdir -p "$USER_HOME/.local/bin"
run_as_user ln -sf "$NVIM_VENV/bin/jupytext" "$USER_HOME/.local/bin/jupytext"

# Register a default ipykernel against the user's regular environment,
# so notebooks can be evaluated against the system python out of the box.
run_as_user "$NVIM_VENV/bin/python" -m ipykernel install --user --name=python3 --display-name "Python 3 (nvim venv)" >/dev/null 2>&1 || true

# ---------- summary ----------
# Resolve the clangd we actually wired up — on macOS that's brew's keg-only
# llvm, which won't be on root's PATH if we'd looked it up there.
if [ "$OS" = "macos" ]; then
    CLANGD_VERSION="$("$USER_HOME/.local/bin/clangd" --version 2>/dev/null | head -1 || echo missing)"
else
    CLANGD_VERSION="$(clangd --version 2>/dev/null | head -1 || echo missing)"
fi

echo
echo "==> Done."
printf "    %-9s %s\n" "os:"      "$OS"
printf "    %-9s %s\n" "nvim:"    "$(nvim --version | head -1)"
printf "    %-9s %s\n" "node:"    "$(node -v 2>/dev/null || echo missing)"
printf "    %-9s %s\n" "clangd:"  "$CLANGD_VERSION"
printf "    %-9s %s\n" "pyright:" "$(pyright --version 2>/dev/null || echo missing)"
printf "    %-9s %s\n" "fzf:"     "$("$USER_HOME/.fzf/bin/fzf" --version 2>/dev/null || echo missing)"
printf "    %-9s %s\n" "venv:"    "$NVIM_VENV ($("$NVIM_VENV/bin/python" --version 2>/dev/null || echo missing))"
echo
if [ "$OS" = "linux" ]; then
    echo "Persistent apt sources added (remove manually to undo):"
    echo "    /etc/apt/sources.list.d/llvm-18.list"
    echo "    /etc/apt/keyrings/llvm.gpg"
    echo "    /etc/apt/sources.list.d/nodesource.list"
else
    echo "Brew formulae installed/used: neovim node ripgrep ninja cmake gettext imagemagick llvm"
    echo "User-local symlinks (delete to undo):"
    echo "    ~/.local/bin/clangd      -> $(brew --prefix llvm)/bin/clangd"
    echo "    ~/.local/bin/jupytext    -> $NVIM_VENV/bin/jupytext"
    if [ "$LINK_VIM" = "1" ]; then
        echo "    ~/.local/bin/{vim,vi}    -> $NVIM_BIN"
    fi
fi
echo
echo "Next:"
echo "  1. Apply your chezmoi config so ~/.config/nvim, ~/.tmux.conf and"
echo "     shell rc files are in place. The nvim config is expected to set"
echo "     vim.g.python3_host_prog = \"\$HOME/.local/share/nvim-venv/bin/python\""
echo "     and to put ~/.local/bin on PATH (for clangd/jupytext/vim symlinks)."
echo "  2. Open a new shell so PATH and fzf hooks load."
echo "  3. Run 'nvim' once to let lazy.nvim bootstrap plugins. After that,"
echo "     'nvim path/to/notebook.ipynb' opens via jupytext as a hydrogen-"
echo "     style buffer; <leader>mi starts a kernel, <leader>ml evaluates."
echo "  4. Image rendering needs a graphics-capable terminal (kitty,"
echo "     wezterm, ghostty; on macOS iTerm2 also works). In other"
echo "     terminals molten text output still works; plots just don't render."
