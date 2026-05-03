#!/usr/bin/env bash
# One-shot installer / updater for neovim + LazyVim with clangd/pyright LSP
# and a Jupyter notebook stack (molten-nvim + jupytext.nvim + image.nvim).
# Tested on Ubuntu 22.04 (jammy) x86_64 / WSL2 and macOS 14+ (Apple Silicon
# and Intel).
#
# Usage (Linux): sudo bash ~/install-lazyvim.sh
# Usage (macOS): bash ~/install-lazyvim.sh
#                MUST NOT be invoked under sudo — Homebrew refuses to run as
#                root, and the script has no system-wide writes on macOS.
# Re-run:   the same command. The script is designed to be safely re-run on
#           any machine to bring it up to date with the latest version of
#           this script: managed config files are rewritten, plugins are
#           refreshed via :Lazy sync, and Python deps in the nvim venv are
#           upgraded. Existing user edits to managed files are timestamp-
#           backed-up the first time the script overwrites them.
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
#         User-local; remove to undo. Requires ~/.local/bin on PATH (the
#         script appends a PATH line to ~/.bashrc / ~/.zshrc if missing).
#
#   Both:
#     - pyright via 'npm i -g pyright' (Linux: /usr/bin/pyright; macOS:
#         $(brew --prefix)/bin/pyright)
#     - fzf cloned to ~/.fzf; appends ONE line to ~/.bashrc and (if it
#         exists) ~/.zshrc. fish rc files are NOT modified.
#     - LazyVim starter cloned to ~/.config/nvim (preserved on re-run by
#         default; see FORCE_LAZYVIM)
#     - Python venv at ~/.local/share/nvim-venv with pynvim + jupyter deps,
#         wired via vim.g.python3_host_prog so molten-nvim works
#     - Symlink ~/.local/bin/jupytext -> nvim-venv's jupytext CLI, so
#         jupytext.nvim can find it on PATH (remove the symlink to undo)
#     - ~/.tmux.conf gets a fenced managed block enabling 'allow-passthrough'
#         (required so image.nvim's Kitty graphics escapes survive tmux).
#         Only the marked block is touched; the rest of tmux.conf is left
#         alone. Skipped entirely if tmux is not installed.
#
# Toggles (env vars; defaults shown — set to 0/1 as noted to flip):
#   LINK_VIM=0          Skip aliasing vim/vi to nvim. Default ON: vim and
#                         vi resolve to nvim. Linux: system-wide via
#                         update-alternatives (affects all users). macOS:
#                         user-local symlinks in ~/.local/bin.
#   FORCE_LAZYVIM=1     Wipe ~/.config/nvim, ~/.local/share/nvim, etc.
#                         and re-clone LazyVim starter. Default OFF:
#                         existing LazyVim configs are preserved across
#                         re-runs so plugin lockfiles and user edits in
#                         non-managed files survive. Set to 1 only when
#                         you want a clean reset (backups go to
#                         *.bak.<timestamp>).
#   UPDATE_PLUGINS=0    Skip the trailing 'nvim --headless +Lazy! sync'.
#                         Default ON: re-runs update plugins to latest and
#                         fire molten's :UpdateRemotePlugins build hook.
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
FORCE_LAZYVIM="${FORCE_LAZYVIM:-0}"
UPDATE_PLUGINS="${UPDATE_PLUGINS:-1}"
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

# ---------- managed-file helpers ----------
# A "managed" file is one this installer owns. On every re-run we rewrite it
# in place so config drifts when this script changes. If we encounter a file
# without our marker (i.e. user-authored), we move it aside before clobbering.
MANAGED_MARKER="install-lazyvim.sh: managed file (rewritten on every re-run)"

write_managed_file() {
    # Reads file content from stdin, writes to $1 with a marker comment on top.
    # $2 is the comment prefix (e.g. "--" for lua, "#" for shell).
    local path="$1" prefix="${2:---}"
    local dir; dir="$(dirname "$path")"
    install -d -m 0755 "$dir"
    chown "$TARGET_USER:$TARGET_USER" "$dir" 2>/dev/null || true

    if [ -f "$path" ] && ! head -1 "$path" 2>/dev/null | grep -qF "$MANAGED_MARKER"; then
        local backup="$path.bak.$(date +%Y%m%d-%H%M%S)"
        echo "   user-edited $(basename "$path") backed up -> $(basename "$backup")"
        mv "$path" "$backup"
        chown "$TARGET_USER:$TARGET_USER" "$backup" 2>/dev/null || true
    fi

    local tmp; tmp="$(mktemp)"
    { printf '%s %s\n\n' "$prefix" "$MANAGED_MARKER"; cat; } > "$tmp"
    mv "$tmp" "$path"
    chown "$TARGET_USER:$TARGET_USER" "$path" 2>/dev/null || true
}

update_managed_block() {
    # Replaces or appends a sentinel-delimited block in $1 with stdin.
    # Used for files we don't fully own (like LazyVim starter's options.lua,
    # or ~/.tmux.conf): we touch only the marked region, leaving the rest of
    # the file alone. $2 is the comment prefix for the marker lines (default
    # "--" for lua; pass "#" for shell/tmux configs).
    local path="$1" prefix="${2:---}"
    local begin="$prefix >>> install-lazyvim.sh managed block (do not edit between markers)"
    local end="$prefix <<< install-lazyvim.sh managed block"
    local block; block="$(cat)"

    install -d -m 0755 "$(dirname "$path")"
    [ -f "$path" ] || { : > "$path"; chown "$TARGET_USER:$TARGET_USER" "$path" 2>/dev/null || true; }

    local stripped; stripped="$(mktemp)"
    awk -v b="$begin" -v e="$end" '
        index($0, b) == 1 { skip=1; next }
        index($0, e) == 1 && skip { skip=0; next }
        !skip { print }
    ' "$path" > "$stripped"

    {
        cat "$stripped"
        printf '\n%s\n%s\n%s\n' "$begin" "$block" "$end"
    } > "$path"
    rm -f "$stripped"
    chown "$TARGET_USER:$TARGET_USER" "$path" 2>/dev/null || true
}

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

# ---------- 4. fzf (single-line rc append, no global rewrites) ----------
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

# Append fzf hook (and on macOS, a ~/.local/bin PATH line) to whichever shell
# rc files actually exist. Idempotent: only appends if the line is missing.
append_once() {
    local rc="$1" needle="$2" line="$3"
    [ -f "$rc" ] || return 0
    grep -qF "$needle" "$rc" 2>/dev/null && return 0
    printf '%s\n' "$line" >> "$rc"
    chown "$TARGET_USER:$TARGET_USER" "$rc" 2>/dev/null || true
}
BASHRC="$USER_HOME/.bashrc"
ZSHRC="$USER_HOME/.zshrc"
append_once "$BASHRC" '.fzf.bash' '[ -f "$HOME/.fzf.bash" ] && source "$HOME/.fzf.bash"'
append_once "$ZSHRC"  '.fzf.zsh'  '[ -f "$HOME/.fzf.zsh" ] && source "$HOME/.fzf.zsh"'

# macOS: ~/.local/bin isn't on PATH by default the way Ubuntu's ~/.profile
# adds it. We rely on it for jupytext/clangd/(vim,vi) symlinks, so make sure
# it'll be picked up next login.
if [ "$OS" = "macos" ]; then
    LOCAL_PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
    append_once "$BASHRC" '$HOME/.local/bin:$PATH' "$LOCAL_PATH_LINE"
    append_once "$ZSHRC"  '$HOME/.local/bin:$PATH' "$LOCAL_PATH_LINE"
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

# ---------- 5b. ImageMagick fonts (macOS only) ----------
# brew's imagemagick on macOS ships with an empty master type.xml — zero
# fonts get registered, and any SVG/text rendering fails with `unable to
# read font ''`. image.nvim hits this when converting an SVG (referenced
# from a markdown image, or from molten plot output) to PNG for the kitty
# graphics protocol. Workaround: drop a user-level type.xml that
# registers a couple of system fonts, and point ImageMagick at it via
# MAGICK_CONFIGURE_PATH (set inside nvim — see options.lua block below).
# Linux's apt imagemagick already pulls in ghostscript fonts and works
# out of the box, so this section is a no-op there.
if [ "$OS" = "macos" ]; then
    echo "==> Writing user-level ImageMagick type.xml (works around brew imagemagick's empty default)"
    run_as_user mkdir -p "$USER_HOME/.config/ImageMagick-7"
    cat > "$USER_HOME/.config/ImageMagick-7/type.xml" <<'EOF'
<?xml version="1.0"?>
<!-- Managed by install-lazyvim.sh: brew's imagemagick ships an empty
     type.xml on macOS so SVG/text rendering fails with "unable to read
     font ''". Registering a few macOS system fonts here gives magick a
     working default. Read by ImageMagick via MAGICK_CONFIGURE_PATH set
     in nvim's options.lua. -->
<typemap>
  <type format="ttc" name="Helvetica"   fullname="Helvetica"         family="Helvetica" foundry="Apple" weight="400" style="normal" stretch="normal" glyphs="/System/Library/Fonts/Helvetica.ttc" />
  <type format="ttc" name="HelveticaB"  fullname="Helvetica Bold"    family="Helvetica" foundry="Apple" weight="700" style="normal" stretch="normal" glyphs="/System/Library/Fonts/Helvetica.ttc" />
  <type format="ttc" name="HelveticaI"  fullname="Helvetica Oblique" family="Helvetica" foundry="Apple" weight="400" style="italic" stretch="normal" glyphs="/System/Library/Fonts/Helvetica.ttc" />
  <type format="ttc" name="Menlo"       fullname="Menlo Regular"     family="Menlo"     foundry="Apple" weight="400" style="normal" stretch="normal" glyphs="/System/Library/Fonts/Menlo.ttc" />
</typemap>
EOF
    chown "$TARGET_USER:$TARGET_USER" "$USER_HOME/.config/ImageMagick-7/type.xml" 2>/dev/null || true
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

# ---------- 8. LazyVim starter ----------
LAZYVIM_DIR="$USER_HOME/.config/nvim"
if [ -f "$LAZYVIM_DIR/init.lua" ] && [ "$FORCE_LAZYVIM" != "1" ]; then
    echo "==> LazyVim already at $LAZYVIM_DIR — preserving (FORCE_LAZYVIM=0)"
else
    echo "==> Setting up LazyVim starter (FORCE_LAZYVIM=$FORCE_LAZYVIM)"
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

# ---------- 9. managed configs (rewritten on every re-run) ----------
echo "==> Writing managed config files"

# options.lua: LazyVim ships its own; we touch only a fenced block.
# On macOS we also wire MAGICK_CONFIGURE_PATH so image.nvim's spawned
# magick subprocesses see our user-level type.xml (see section 5b).
# On Linux this block is empty since apt imagemagick works out of the box.
MAGICK_ENV_LUA=""
if [ "$OS" = "macos" ]; then
    MAGICK_ENV_LUA="
-- macOS only: brew imagemagick ships zero registered fonts, which makes
-- image.nvim's SVG->PNG conversion fail. Our type.xml at
-- ~/.config/ImageMagick-7 fills the gap; this env var tells magick to
-- read it. Set inside nvim so child processes inherit regardless of
-- launch path (shell, GUI, etc.).
vim.env.MAGICK_CONFIGURE_PATH = \"$USER_HOME/.config/ImageMagick-7:$BREW_PREFIX/etc/ImageMagick-7\""
fi
update_managed_block "$LAZYVIM_DIR/lua/config/options.lua" <<EOF
-- Disable format on save (override LazyVim default)
vim.g.autoformat = false

-- Point nvim at the dedicated venv so pynvim / jupyter_client are resolvable
-- (required for molten-nvim's :MoltenInit).
vim.g.python3_host_prog = "$NVIM_VENV/bin/python"
$MAGICK_ENV_LUA
EOF

# lspconfig.lua: keep clangd off mason (we install it system-wide).
write_managed_file "$LAZYVIM_DIR/lua/plugins/lspconfig.lua" "--" <<'EOF'
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

# molten.lua: interactive jupyter kernel inside nvim, with image.nvim outputs.
write_managed_file "$LAZYVIM_DIR/lua/plugins/molten.lua" "--" <<'EOF'
return {
  {
    "benlubas/molten-nvim",
    version = "^1.0.0",
    dependencies = { "3rd/image.nvim" },
    build = ":UpdateRemotePlugins",
    ft = { "python", "markdown", "quarto" },
    init = function()
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_output_win_max_height = 20
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_wrap_output = true
    end,
    keys = {
      { "<leader>mi", ":MoltenInit<CR>",                       desc = "Molten: init kernel" },
      { "<leader>me", ":MoltenEvaluateOperator<CR>",           desc = "Molten: eval operator" },
      { "<leader>ml", ":MoltenEvaluateLine<CR>",               desc = "Molten: eval line" },
      { "<leader>mr", ":MoltenReevaluateCell<CR>",             desc = "Molten: re-eval cell" },
      { "<leader>mv", ":<C-u>MoltenEvaluateVisual<CR>gv",      desc = "Molten: eval selection", mode = "v" },
      { "<leader>mo", ":noautocmd MoltenEnterOutput<CR>",      desc = "Molten: enter output" },
      { "<leader>mh", ":MoltenHideOutput<CR>",                 desc = "Molten: hide output" },
      { "<leader>md", ":MoltenDelete<CR>",                     desc = "Molten: delete cell" },
    },
  },
}
EOF

# jupytext.lua: open .ipynb as a hydrogen-style python file (# %% cells),
# saved back as .ipynb on :w.
write_managed_file "$LAZYVIM_DIR/lua/plugins/jupytext.lua" "--" <<'EOF'
return {
  {
    "GCBallesteros/jupytext.nvim",
    lazy = false,
    opts = {
      style = "hydrogen",
      output_extension = "auto",
      force_ft = nil,
    },
  },
}
EOF

# image.lua: image rendering for molten output and inline markdown images.
# Backend is "kitty" — works in kitty, wezterm, ghostty. Other terminals
# (incl. default Windows Terminal in WSL) will just not render images;
# molten text output still works fine.
write_managed_file "$LAZYVIM_DIR/lua/plugins/image.lua" "--" <<'EOF'
return {
  {
    "3rd/image.nvim",
    -- Don't try to build the magick luarock; we use the imagemagick CLI
    -- (apt 'imagemagick' package) instead via processor = "magick_cli".
    build = false,
    opts = {
      backend = "kitty",
      processor = "magick_cli",
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true,
          only_render_image_at_cursor = false,
          filetypes = { "markdown", "vimwiki", "quarto" },
        },
      },
      max_width = 100,
      max_height = 12,
      max_height_window_percentage = 30,
      max_width_window_percentage = 100,
      window_overlap_clear_enabled = true,
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "" },
    },
  },
}
EOF

# render-markdown.lua: in-buffer prettifying of markdown (headings, code
# blocks, tables, checkboxes). Works in any terminal — no graphics needed.
# Inline images still come from image.nvim's markdown integration above.
write_managed_file "$LAZYVIM_DIR/lua/plugins/render-markdown.lua" "--" <<'EOF'
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" },
    ft = { "markdown", "quarto" },
    opts = {
      file_types = { "markdown", "quarto" },
      completions = { lsp = { enabled = true } },
    },
  },
}
EOF

chown -R "$TARGET_USER:$TARGET_USER" "$LAZYVIM_DIR" 2>/dev/null || true

# ---------- 10. tmux passthrough (so image.nvim works inside tmux) ----------
# image.nvim emits Kitty/iTerm graphics escapes; tmux drops them by default,
# which makes :checkhealth image.nvim fail with "tmux does not have
# allow-passthrough enabled" and prevents molten plot output from rendering.
# Only meaningful if the user actually uses tmux, but the conf is harmless
# otherwise — we still write it so a later 'apt install tmux' just works.
if command -v tmux >/dev/null 2>&1; then
    TMUX_VER="$(tmux -V 2>/dev/null | awk '{print $2}')"
    case "$TMUX_VER" in
        1.*|2.*|3.0|3.1|3.2)
            echo "==> tmux $TMUX_VER predates allow-passthrough (need >=3.3); skipping tmux conf"
            ;;
        *)
            echo "==> Writing tmux passthrough config to $USER_HOME/.tmux.conf (tmux $TMUX_VER)"
            update_managed_block "$USER_HOME/.tmux.conf" "#" <<'EOF'
# image.nvim renders graphics via Kitty/iTerm escape sequences; tmux blocks
# those by default. Required for plots in molten output / inline markdown
# images when nvim is launched inside a tmux session. Requires tmux 3.3+.
set -gq allow-passthrough on
set -g visual-activity off
EOF
            # Apply to any running tmux server owned by the target user, so
            # the change takes effect without forcing a detach/reattach.
            run_as_user tmux source-file "$USER_HOME/.tmux.conf" 2>/dev/null || true
            ;;
    esac
else
    echo "==> tmux not installed; skipping tmux conf (image.nvim only needs it inside tmux)"
fi

# ---------- 11. update plugins ----------
# Headless sync runs lazy.nvim non-interactively so the user's first real
# nvim launch is a working editor, not a plugin-install screen. The bang in
# 'Lazy! sync' makes it block until done; +qa quits when sync returns. We
# tested this hanging once — root cause was nvim being below LazyVim's
# minimum version (LazyVim's compatibility check fires vim.fn.getchar()
# waiting for "press any key", which kevent's on /dev/null and blocks
# forever). The version gate in section 3 prevents that. Stdin is wired to
# /dev/null as belt-and-suspenders against any other plugin prompts; stderr
# is *not* suppressed so real errors land in the install log.
#
# Note: molten-nvim's 'build = ":UpdateRemotePlugins"' fires here as part
# of sync, which writes ~/.local/share/nvim/rplugin.vim with all
# :Molten* command registrations. We grep for "molten" in that manifest
# afterward as a sanity check; if it's missing the user's :MoltenInit
# won't be defined and we surface that loudly.
if [ "$UPDATE_PLUGINS" = "1" ]; then
    echo "==> Syncing plugins ('nvim --headless +Lazy! sync')"
    run_as_user nvim --headless "+Lazy! sync" +qa </dev/null || \
        echo "   (lazy sync had non-zero exit; first 'nvim' run may need to bootstrap interactively)"
    if ! grep -q "molten" "$USER_HOME/.local/share/nvim/rplugin.vim" 2>/dev/null; then
        echo "   WARNING: molten not found in rplugin.vim — :MoltenInit will not be defined."
        echo "            Most likely cause: pynvim missing from \$NVIM_VENV/bin/python, or"
        echo "            vim.g.python3_host_prog not pointing at it. Check :checkhealth"
        echo "            provider.python in nvim, then re-run this script."
    fi
else
    echo "==> UPDATE_PLUGINS=0; skipping :Lazy sync"
fi

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
echo "  1. Open a new shell so the fzf hook (and PATH additions on macOS) load."
echo "  2. Run 'nvim path/to/notebook.ipynb' — jupytext converts it to a"
echo "     hydrogen-style buffer; <leader>mi to start a kernel,"
echo "     <leader>ml to evaluate a line, <leader>me<motion> to evaluate."
echo "  3. Image rendering needs a graphics-capable terminal (kitty,"
echo "     wezterm, ghostty; on macOS iTerm2 also works). In other"
echo "     terminals molten text output still works; plots just don't render."
echo "  4. If you run nvim inside tmux, ~/.tmux.conf now enables"
echo "     'allow-passthrough on'. Active sessions were reloaded; brand-new"
echo "     tmux servers pick it up automatically."
