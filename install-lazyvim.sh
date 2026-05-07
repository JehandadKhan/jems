#!/usr/bin/env bash
# One-shot installer / updater for neovim + LazyVim with clangd/pyright LSP
# and a Jupyter notebook stack (molten-nvim + jupytext.nvim + image.nvim).
# Tested on Ubuntu 22.04 (jammy) x86_64 / WSL2 and macOS 14+ (Apple Silicon
# and Intel).
#
# Usage (Linux): sudo bash ~/install-lazyvim.sh
#                If you're already root (containers, bare VPSs, WSL distros
#                where root is the only user, or after 'su -'), just run
#                'bash ~/install-lazyvim.sh' — the script will detect the
#                missing $SUDO_USER and install for root. Override with
#                TARGET_USER=<user> to install into someone else's home
#                while running as root.
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
#     - basedpyright via 'npm i -g basedpyright' (Linux: /usr/bin/basedpyright;
#         macOS: $(brew --prefix)/bin/basedpyright). Drop-in successor to
#         pyright with stricter defaults and faster indexing on big repos
#         (e.g. JAX). On re-run, any previously-installed pyright is removed
#         via 'npm uninstall -g pyright' so we don't end up with two competing
#         Python LSPs against the same buffer.
#     - Claude Code CLI via 'npm i -g @anthropic-ai/claude-code' (provides
#         the `claude` command). Skipped if INSTALL_CLAUDE=0. Uninstall with
#         'npm uninstall -g @anthropic-ai/claude-code'.
#     - fzf cloned to ~/.fzf; appends ONE line to ~/.bashrc and (if it
#         exists) ~/.zshrc. fish rc files are NOT modified.
#     - LazyVim starter cloned to ~/.config/nvim (preserved on re-run by
#         default; see FORCE_LAZYVIM)
#     - Python venv at ~/.local/share/nvim-venv with pynvim + jupyter deps,
#         wired via vim.g.python3_host_prog so molten-nvim works
#     - Symlink ~/.local/bin/jupytext -> nvim-venv's jupytext CLI, so
#         jupytext.nvim can find it on PATH (remove the symlink to undo)
#     - hedronvision/bazel-compile-commands-extractor cloned to
#         ~/.local/share/bazel-compile-commands-extractor (~50MB) plus a
#         helper at ~/.local/bin/bazel-compile-commands that wires it into
#         any Bazel workspace and produces compile_commands.json so clangd
#         gives accurate cross-references on Bazel-built C++ (XLA, JAX/jaxlib,
#         TF, etc.). Skipped if INSTALL_BAZEL_HELPER=0. Remove the clone +
#         helper symlink to undo; per-repo wiring can be removed via
#         'bazel-compile-commands --clean'.
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
#   INSTALL_BAZEL_HELPER=0
#                       Skip cloning hedronvision/bazel-compile-commands-
#                         extractor (~50MB) and installing the
#                         ~/.local/bin/bazel-compile-commands helper.
#                         Set to 0 if you don't work in any Bazel C++ repos.
#                         Default ON.
#   INSTALL_CLAUDE=0    Skip installing the Claude Code CLI
#                         (@anthropic-ai/claude-code) globally via npm.
#                         Default ON.
#
# To uninstall the apt sources later (Linux; clangd-18 binary will remain):
#   sudo rm /etc/apt/sources.list.d/llvm-18.list /etc/apt/keyrings/llvm.gpg
#   sudo rm /etc/apt/sources.list.d/nodesource.list

set -euo pipefail

LINK_VIM="${LINK_VIM:-1}"
FORCE_LAZYVIM="${FORCE_LAZYVIM:-0}"
UPDATE_PLUGINS="${UPDATE_PLUGINS:-1}"
SKIP_NVIM_BUILD="${SKIP_NVIM_BUILD:-0}"
INSTALL_BAZEL_HELPER="${INSTALL_BAZEL_HELPER:-1}"
INSTALL_CLAUDE="${INSTALL_CLAUDE:-1}"

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
    # Determine the user we're installing for. Priority:
    #   1. Explicit TARGET_USER env var (use this when there's no $SUDO_USER,
    #      e.g. after `su -` to root, or to install for someone else).
    #   2. $SUDO_USER (set when invoked via 'sudo bash ...' from a real user).
    #   3. Fall back to 'root' itself: containers, bare VPSs, and WSL distros
    #      where root IS the user. Files end up root-owned, which is correct
    #      in that scenario.
    TARGET_USER="${TARGET_USER:-${SUDO_USER:-root}}"
    if [ "$TARGET_USER" = "root" ]; then
        echo "==> No non-root user detected (\$SUDO_USER empty); installing for root."
        echo "    Set TARGET_USER=<user> if the install should land in another user's home."
    fi
    USER_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
    if [ -z "$USER_HOME" ]; then
        echo "Could not resolve home directory for '$TARGET_USER' via getent." >&2
        echo "Set TARGET_USER to a user that exists in /etc/passwd." >&2
        exit 1
    fi
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

# Run argv as the target user. On Linux we usually drop privileges via sudo,
# but skip that when target == 'root' (installing for root in a container /
# WSL distro): there's no privilege to drop, and minimal images often don't
# even have sudo on PATH. macOS is always a passthrough since we already run
# as the user there.
if [ "$OS" = "linux" ] && [ "$TARGET_USER" != "root" ]; then
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

# ---------- 5c. bazel-compile-commands helper (clangd index for Bazel C++) ----------
# clangd's accuracy on a Bazel-built C++ codebase (XLA, JAX/jaxlib, TF, ...)
# depends entirely on a `compile_commands.json` at the workspace root: without
# it, header includes, defines, and toolchain flags are guessed and most
# cross-references break. Bazel doesn't produce that file natively. The
# de-facto generator is hedronvision/bazel-compile-commands-extractor, but
# bootstrapping it per-repo is fiddly (MODULE.bazel + a refresh BUILD target),
# so this section gives the user a one-shot helper:
#
#   1. Clones the extractor once to ~/.local/share/bazel-compile-commands-
#      extractor (we use a local_path_override in MODULE.bazel rather than a
#      git_override, so the helper has zero network deps at run time and
#      every box this script runs on stays in sync via re-running the
#      installer).
#   2. Installs ~/.local/bin/bazel-compile-commands. Run from any Bazel
#      workspace (XLA, jaxlib, TF, ...) and it wires hedron in via a fenced
#      managed block, writes tools/clangd/BUILD.bazel with a refresh target,
#      keeps the generated junk out of `git status` via .git/info/exclude,
#      then runs `bazel run //tools/clangd:refresh_compile_commands`. On
#      success compile_commands.json appears at the repo root and clangd
#      picks it up on the next nvim launch.
#
# The helper is idempotent — re-run it whenever BUILD files change. Pass
# scoped targets (e.g. //xla/...) as positional args to limit extraction.
# `bazel-compile-commands --clean` removes the managed block + tools/clangd/
# from the current workspace.
HEDRON_DIR="$USER_HOME/.local/share/bazel-compile-commands-extractor"
HELPER_BIN="$USER_HOME/.local/bin/bazel-compile-commands"

if [ "$INSTALL_BAZEL_HELPER" = "1" ]; then
    if [ -d "$HEDRON_DIR/.git" ]; then
        echo "==> Updating bazel-compile-commands-extractor at $HEDRON_DIR"
        run_as_user git -C "$HEDRON_DIR" pull --ff-only --quiet || \
            echo "   (git pull failed; keeping existing checkout)"
    else
        echo "==> Cloning hedronvision/bazel-compile-commands-extractor to $HEDRON_DIR"
        run_as_user mkdir -p "$(dirname "$HEDRON_DIR")"
        run_as_user git clone --depth 1 \
            https://github.com/hedronvision/bazel-compile-commands-extractor.git \
            "$HEDRON_DIR"
    fi

    echo "==> Writing $HELPER_BIN"
    run_as_user mkdir -p "$USER_HOME/.local/bin"
    # Outer heredoc uses HELPER_EOF so the inner shell heredocs in the helper
    # (terminated by plain EOF) don't prematurely close the outer block.
    cat > "$HELPER_BIN" <<'HELPER_EOF'
#!/usr/bin/env bash
# bazel-compile-commands — wire hedronvision/bazel-compile-commands-extractor
# into a Bazel workspace and produce compile_commands.json at the repo root,
# so clangd gives accurate cross-references / completion in C/C++.
#
# Installed by install-lazyvim.sh (jems). The extractor itself lives at
# ~/.local/share/bazel-compile-commands-extractor (cloned at install time);
# this helper references it via a Bazel local_path_override, so no network
# is needed at run time.
#
# Usage:
#   bazel-compile-commands [--clean] [REPO_ROOT] [TARGETS...]
#
# Arguments (all optional):
#   REPO_ROOT  Path to the Bazel workspace. If omitted, walks up from PWD
#              looking for MODULE.bazel / WORKSPACE.
#   TARGETS    One or more Bazel labels (e.g. //xla/...). Defaults to //...
#              if omitted. Scope this if //... is too broad for your repo.
#
# Flags:
#   --clean    Remove the managed MODULE.bazel/WORKSPACE block and the
#              tools/clangd/ dir this helper added. Leaves
#              compile_commands.json in place.
#   --help     Show this message.
#
# Notes:
# - First run on a large repo (XLA: 6k+ files) takes 10-30 min while bazel
#   resolves and extracts. Subsequent runs are minutes.
# - Idempotent: re-running refreshes compile_commands.json against current
#   BUILD/source state. Source-only changes don't need a re-run.

set -euo pipefail

HEDRON_DIR="${HEDRON_DIR:-$HOME/.local/share/bazel-compile-commands-extractor}"
BLOCK_BEGIN="# >>> bazel-compile-commands managed block (do not edit between markers)"
BLOCK_END="# <<< bazel-compile-commands managed block"

usage() {
    cat <<'EOF'
Usage: bazel-compile-commands [--clean] [REPO_ROOT] [TARGETS...]

Generates compile_commands.json for a Bazel workspace via hedronvision/
bazel-compile-commands-extractor, so clangd gets accurate flags.

  REPO_ROOT  Bazel workspace path. Defaults to the workspace enclosing PWD.
  TARGETS    Bazel labels to extract. Defaults to //... (scope with e.g.
             //xla/... to skip third_party).

  --clean    Remove the managed MODULE.bazel/WORKSPACE block and tools/clangd/
             dir this helper added. compile_commands.json is left in place.
  --help     Show this help.

First run on a big repo (XLA, TF) takes 10-30 min. Re-run after BUILD changes.
EOF
}

CLEAN=0
case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --clean)   CLEAN=1; shift ;;
esac

# Resolve repo root: explicit arg if it looks like a Bazel workspace,
# otherwise walk up from PWD looking for MODULE.bazel / WORKSPACE.
ROOT=""
if [ "${1:-}" ] && [ -d "${1:-}" ] && \
   { [ -f "$1/MODULE.bazel" ] || [ -f "$1/WORKSPACE" ] || [ -f "$1/WORKSPACE.bazel" ]; }; then
    ROOT="$(cd "$1" && pwd)"
    shift
else
    cur="$PWD"
    while [ "$cur" != "/" ]; do
        if [ -f "$cur/MODULE.bazel" ] || [ -f "$cur/WORKSPACE" ] || [ -f "$cur/WORKSPACE.bazel" ]; then
            ROOT="$cur"
            break
        fi
        cur="$(dirname "$cur")"
    done
fi
if [ -z "$ROOT" ]; then
    echo "error: no Bazel workspace found (need MODULE.bazel or WORKSPACE in PWD or an ancestor)" >&2
    exit 1
fi
echo "==> Bazel workspace: $ROOT"

# Strip our fenced block (if any) from a file, in place.
strip_block() {
    local path="$1"
    [ -f "$path" ] || return 0
    local tmp; tmp="$(mktemp)"
    awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
        index($0, b) == 1 { skip=1; next }
        index($0, e) == 1 && skip { skip=0; next }
        !skip { print }
    ' "$path" > "$tmp"
    mv "$tmp" "$path"
}

if [ "$CLEAN" = "1" ]; then
    echo "==> Cleaning bazel-compile-commands wiring from $ROOT"
    [ -f "$ROOT/MODULE.bazel" ]    && strip_block "$ROOT/MODULE.bazel"
    [ -f "$ROOT/WORKSPACE" ]       && strip_block "$ROOT/WORKSPACE"
    [ -f "$ROOT/WORKSPACE.bazel" ] && strip_block "$ROOT/WORKSPACE.bazel"
    rm -rf "$ROOT/tools/clangd"
    echo "    Removed managed blocks and $ROOT/tools/clangd."
    echo "    (compile_commands.json left in place; delete it manually if you want.)"
    exit 0
fi

# Verify the extractor is locally available (cloned by install-lazyvim.sh).
if [ ! -f "$HEDRON_DIR/MODULE.bazel" ] && [ ! -f "$HEDRON_DIR/WORKSPACE" ]; then
    echo "error: hedron extractor not found at $HEDRON_DIR" >&2
    echo "       re-run install-lazyvim.sh with INSTALL_BAZEL_HELPER=1 (the default)," >&2
    echo "       or git clone the repo manually:" >&2
    echo "         git clone https://github.com/hedronvision/bazel-compile-commands-extractor.git $HEDRON_DIR" >&2
    exit 1
fi

# bazelisk preferred (handles .bazelversion); fall back to bazel.
if command -v bazelisk >/dev/null 2>&1; then BAZEL=bazelisk
elif command -v bazel >/dev/null 2>&1; then BAZEL=bazel
else
    echo "error: 'bazel' or 'bazelisk' not found on PATH" >&2
    echo "       install one (e.g. via your distro's package manager, brew, or" >&2
    echo "       https://github.com/bazelbuild/bazelisk/releases) and re-run." >&2
    exit 1
fi

# Targets default to //... (everything reachable). Pass scoped labels (e.g.
# //xla/...) to skip third_party or unbuildable corners.
if [ "$#" -gt 0 ]; then
    TARGETS=("$@")
else
    TARGETS=("//...")
fi

# bzlmod is the modern path (JAX, recent TF). A non-empty MODULE.bazel is
# necessary but not sufficient: some repos (notably XLA) ship both files
# and force legacy mode in .bazelrc with `common --noenable_bzlmod`, in
# which case Bazel never reads MODULE.bazel and bzlmod-style wiring there
# silently does nothing (the build fails with "Repository
# '@@hedron_compile_commands' is not defined"). Trust .bazelrc when it
# disables bzlmod unconditionally.
USE_BZLMOD=0
if [ -s "$ROOT/MODULE.bazel" ]; then
    USE_BZLMOD=1
    if [ -f "$ROOT/.bazelrc" ] && \
       awk '/^[[:space:]]*(common|build|run|test|query|fetch|info|aquery|cquery)[[:space:]]/ && /--noenable_bzlmod/ { found=1 } END { exit !found }' "$ROOT/.bazelrc"; then
        USE_BZLMOD=0
        echo "==> .bazelrc disables bzlmod unconditionally; using WORKSPACE wiring"
    fi
fi
if [ "$USE_BZLMOD" = "1" ]; then
    TARGET_FILE="$ROOT/MODULE.bazel"
    BLOCK_BODY=$(cat <<EOF
# Wires hedronvision/bazel-compile-commands-extractor (clangd index source).
# Path points at this machine's local clone — re-run install-lazyvim.sh to
# refresh hedron itself. dev_dependency keeps it invisible to downstream
# MODULE consumers.
bazel_dep(name = "hedron_compile_commands", dev_dependency = True)
local_path_override(
    module_name = "hedron_compile_commands",
    path = "$HEDRON_DIR",
)
EOF
)
elif [ -f "$ROOT/WORKSPACE" ] || [ -f "$ROOT/WORKSPACE.bazel" ]; then
    [ -f "$ROOT/WORKSPACE.bazel" ] && TARGET_FILE="$ROOT/WORKSPACE.bazel" || TARGET_FILE="$ROOT/WORKSPACE"
    BLOCK_BODY=$(cat <<EOF
# hedronvision/bazel-compile-commands-extractor (legacy WORKSPACE wiring).
local_repository(
    name = "hedron_compile_commands",
    path = "$HEDRON_DIR",
)
load("@hedron_compile_commands//:workspace_setup.bzl", "hedron_compile_commands_setup")
hedron_compile_commands_setup()
EOF
)
else
    echo "error: workspace at $ROOT has neither MODULE.bazel nor WORKSPACE" >&2
    exit 1
fi

# Idempotent rewrite: strip any prior block, then append the current one.
strip_block "$TARGET_FILE"
{ printf '\n%s\n%s\n%s\n' "$BLOCK_BEGIN" "$BLOCK_BODY" "$BLOCK_END"; } >> "$TARGET_FILE"
echo "==> Wrote managed block to $(basename "$TARGET_FILE")"

# tools/clangd/BUILD.bazel: refresh target with user-supplied target scope.
mkdir -p "$ROOT/tools/clangd"
{
    printf '# Generated by bazel-compile-commands (jems install-lazyvim.sh).\n'
    printf '# Re-run the helper to refresh after BUILD changes.\n'
    printf 'load("@hedron_compile_commands//:refresh_compile_commands.bzl", "refresh_compile_commands")\n\n'
    printf 'refresh_compile_commands(\n'
    printf '    name = "refresh_compile_commands",\n'
    printf '    targets = {\n'
    for t in "${TARGETS[@]}"; do
        printf '        "%s": "",\n' "$t"
    done
    printf '    },\n)\n'
} > "$ROOT/tools/clangd/BUILD.bazel"
echo "==> Wrote $ROOT/tools/clangd/BUILD.bazel (targets: ${TARGETS[*]})"

# Keep generated artifacts out of `git status`. .git/info/exclude is the
# right place for this — it's local, untracked, and doesn't fight upstream
# .gitignore. We avoid touching MODULE.bazel/WORKSPACE here since those
# files are tracked; the managed block is what the user reverts before
# upstreaming.
if [ -d "$ROOT/.git" ]; then
    install -d -m 0755 "$ROOT/.git/info"
    EXCLUDE="$ROOT/.git/info/exclude"
    [ -f "$EXCLUDE" ] || : > "$EXCLUDE"
    for path in compile_commands.json external/ tools/clangd/; do
        grep -qxF "$path" "$EXCLUDE" || echo "$path" >> "$EXCLUDE"
    done
fi

# Run the refresh. cd into the repo so bazel finds the workspace and writes
# compile_commands.json at the right root.
echo "==> $BAZEL run //tools/clangd:refresh_compile_commands"
echo "    (first run on a large repo can take 10-30 min)"
( cd "$ROOT" && "$BAZEL" run //tools/clangd:refresh_compile_commands )

if [ ! -f "$ROOT/compile_commands.json" ]; then
    echo "error: bazel ran but compile_commands.json was not produced at $ROOT" >&2
    echo "       check the bazel output above; common causes: target scope is" >&2
    echo "       unbuildable, or hedron's actions failed for a specific rule." >&2
    exit 1
fi
N="$(grep -c '"file":' "$ROOT/compile_commands.json" 2>/dev/null || echo 0)"
echo "==> Wrote $ROOT/compile_commands.json ($N entries)"
echo "    clangd will pick this up automatically on next nvim launch."
HELPER_EOF
    chmod +x "$HELPER_BIN"
    chown "$TARGET_USER:$TARGET_USER" "$HELPER_BIN" 2>/dev/null || true
else
    echo "==> INSTALL_BAZEL_HELPER=0; skipping bazel-compile-commands setup"
fi

# ---------- 6. basedpyright (global via npm; sidesteps PEP 668) ----------
# basedpyright is a maintained fork of pyright with stricter defaults, faster
# indexing on large dynamic codebases (notably JAX, where pyright sometimes
# stalls on heavy use of `jit`/decorators), and protocol-compatible LSP. The
# binary lspconfig invokes is `basedpyright-langserver`, also installed by
# this npm package. We disable pyright in lspconfig.lua so the two don't
# fight over the same buffer if LazyVim's lang.python extra is enabled.
echo "==> Installing/updating basedpyright via 'npm i -g basedpyright'"
npm install -g basedpyright >/dev/null
echo "    basedpyright: $(basedpyright --version 2>/dev/null || echo unknown)"

# Roll back the prior pyright install if present. Earlier versions of this
# script installed pyright; leaving it on disk after the switch causes PATH
# ordering surprises and the occasional dual-LSP if a user later enables
# LazyVim's lang.python extra. npm uninstall is a no-op when not installed.
if npm ls -g --depth=0 pyright >/dev/null 2>&1; then
    echo "    Removing previously-installed pyright (replaced by basedpyright)"
    npm uninstall -g pyright >/dev/null 2>&1 || true
fi

# ---------- 6b. Claude Code CLI (global via npm) ----------
# Anthropic's official CLI. Same npm-global story as basedpyright, so we
# piggyback on Node 20+ from section 2. Re-running just upgrades to the
# latest published version.
if [ "$INSTALL_CLAUDE" = "1" ]; then
    echo "==> Installing/updating Claude Code via 'npm i -g @anthropic-ai/claude-code'"
    npm install -g @anthropic-ai/claude-code >/dev/null
    echo "    claude: $(claude --version 2>/dev/null || echo unknown)"
else
    echo "==> INSTALL_CLAUDE=0; skipping Claude Code CLI install"
fi

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

# lspconfig.lua: keep clangd / basedpyright off mason (we install both
# system-wide via apt+brew / npm). pyright gets explicitly disabled here in
# case LazyVim's lang.python extra is later enabled — running pyright and
# basedpyright together against the same buffer leads to duplicate
# diagnostics and fights over hover.
write_managed_file "$LAZYVIM_DIR/lua/plugins/lspconfig.lua" "--" <<'EOF'
return {
  "neovim/nvim-lspconfig",
  opts = {
    servers = {
      clangd = {
        mason = false,
      },
      basedpyright = {
        mason = false,
        settings = {
          basedpyright = {
            analysis = {
              -- 'all' (basedpyright's default) is too noisy on big dynamic
              -- codebases like JAX; 'standard' matches typical pyright
              -- defaults and is a sane starting point.
              typeCheckingMode = "standard",
              -- 'openFilesOnly' avoids re-analyzing thousands of files on
              -- every keystroke; workspace symbols still resolve through
              -- the index.
              diagnosticMode = "openFilesOnly",
              autoSearchPaths = true,
              useLibraryCodeForTypes = true,
            },
          },
        },
      },
      pyright = { enabled = false },
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

if [ "$INSTALL_BAZEL_HELPER" = "1" ] && [ -x "$USER_HOME/.local/bin/bazel-compile-commands" ]; then
    BAZEL_HELPER_STATUS="$USER_HOME/.local/bin/bazel-compile-commands"
else
    BAZEL_HELPER_STATUS="(skipped: INSTALL_BAZEL_HELPER=$INSTALL_BAZEL_HELPER)"
fi

if [ "$INSTALL_CLAUDE" = "1" ]; then
    CLAUDE_STATUS="$(claude --version 2>/dev/null || echo missing)"
else
    CLAUDE_STATUS="(skipped: INSTALL_CLAUDE=0)"
fi

echo
echo "==> Done."
printf "    %-13s %s\n" "os:"           "$OS"
printf "    %-13s %s\n" "nvim:"         "$(nvim --version | head -1)"
printf "    %-13s %s\n" "node:"         "$(node -v 2>/dev/null || echo missing)"
printf "    %-13s %s\n" "clangd:"       "$CLANGD_VERSION"
printf "    %-13s %s\n" "basedpyright:" "$(basedpyright --version 2>/dev/null || echo missing)"
printf "    %-13s %s\n" "fzf:"          "$("$USER_HOME/.fzf/bin/fzf" --version 2>/dev/null || echo missing)"
printf "    %-13s %s\n" "venv:"         "$NVIM_VENV ($("$NVIM_VENV/bin/python" --version 2>/dev/null || echo missing))"
printf "    %-13s %s\n" "bazel helper:" "$BAZEL_HELPER_STATUS"
printf "    %-13s %s\n" "claude:"       "$CLAUDE_STATUS"
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
if [ "$INSTALL_BAZEL_HELPER" = "1" ]; then
    echo "Bazel clangd helper (delete to undo):"
    echo "    ~/.local/share/bazel-compile-commands-extractor"
    echo "    ~/.local/bin/bazel-compile-commands"
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
if [ "$INSTALL_BAZEL_HELPER" = "1" ]; then
    echo "  5. For C++ in a Bazel repo (XLA, jaxlib, TF), cd into the workspace and"
    echo "     run 'bazel-compile-commands' once — this generates compile_commands.json"
    echo "     so clangd gives accurate cross-references. First run on XLA can take"
    echo "     10-30 min; subsequent runs are minutes. Pass scoped targets like"
    echo "     '//xla/...' to limit extraction. 'bazel-compile-commands --clean'"
    echo "     reverts the per-repo wiring."
fi
