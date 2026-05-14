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
#                If you're already root (containers, bare VPSs, WSL distros
#                where root is the only user, or after 'su -'), just run
#                'bash ~/install-lazyvim.sh' — the script will detect the
#                missing $SUDO_USER and install for root. Override with
#                TARGET_USER=<user> to install into someone else's home
#                while running as root.
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
#         python3-venv / python3-pip / python3-dev, tmux (if INSTALL_TMUX=1)
#     - NodeSource apt repo + key (installed via 'curl | bash' from
#         deb.nodesource.com — a remote script piped to root bash)
#     - Node.js 20 from NodeSource (only if no Node >=20 is present)
#     - Neovim (stable) built from source -> /usr/local/bin/nvim
#     - apt.llvm.org as a persistent apt source for clangd-18 (every future
#         'apt update' will hit it; the GPG key is NOT fingerprint-pinned —
#         trusts whatever the URL serves at install time)
#     - cli.github.com as a persistent apt source for `gh` (same caveat:
#         every future 'apt update' will hit it; key not fingerprint-pinned).
#         Skipped if INSTALL_GH=0.
#     - chezmoi binary at /usr/local/bin/chezmoi via get.chezmoi.io
#         (no apt repo). Skipped if INSTALL_CHEZMOI=0.
#     - update-alternatives entries for /usr/bin/clangd (and optionally
#         /usr/bin/{vim,vi} when LINK_VIM=1) — affects all users on the box
#
#   macOS (Homebrew, runs as your user):
#     - brew formulae installed if missing: neovim, node, ripgrep, ninja,
#         cmake, gettext, imagemagick, llvm (for clangd), chezmoi, gh,
#         tmux, starship. Existing versions are left alone (the script does
#         not 'brew upgrade'). chezmoi/gh/tmux/starship are gated on their
#         respective INSTALL_* flags.
#     - Symlink ~/.local/bin/clangd -> $(brew --prefix llvm)/bin/clangd
#         (brew does not link llvm by default to avoid clobbering Apple's
#         clang). Remove the symlink to undo.
#     - Symlinks ~/.local/bin/{vim,vi} -> nvim when LINK_VIM=1 (default).
#         User-local; remove to undo. Requires ~/.local/bin on PATH (your
#         chezmoi'd shell rc is expected to set that up).
#
#   Both:
#     - basedpyright via 'npm i -g basedpyright' (Linux:
#         /usr/bin/basedpyright; macOS: $(brew --prefix)/bin/basedpyright).
#         Drop-in successor to pyright with stricter defaults and faster
#         indexing on big repos (e.g. JAX). The chezmoi'd lspconfig.lua is
#         expected to disable pyright so the two don't fight if LazyVim's
#         lang.python extra is later enabled. On re-run, any previously-
#         installed pyright is removed via 'npm uninstall -g pyright'.
#     - Claude Code CLI via 'npm i -g @anthropic-ai/claude-code' (provides
#         the `claude` command). Skipped if INSTALL_CLAUDE=0. Uninstall with
#         'npm uninstall -g @anthropic-ai/claude-code'.
#     - chezmoi (dotfile manager). Linux: official get.chezmoi.io install
#         script writes the binary to /usr/local/bin/chezmoi (no apt repo).
#         macOS: 'brew install chezmoi'. Skipped if INSTALL_CHEZMOI=0.
#     - gh (GitHub CLI). Linux: cli.github.com is added as a persistent apt
#         source (every future 'apt update' will hit it) and gh is installed
#         from there. macOS: 'brew install gh'. Skipped if INSTALL_GH=0.
#     - Bitwarden CLI ('bw'). Linux: 'npm i -g @bitwarden/cli'. macOS:
#         'brew install bitwarden-cli'. Pairs with chezmoi (chezmoi's
#         `bitwarden` template function shells out to it). Skipped if
#         INSTALL_BW=0.
#     - tmux (terminal multiplexer with bottom status line). Linux: apt
#         'tmux' + clipboard helpers ('xclip' for X11, 'wl-clipboard' for
#         Wayland) so tmux copy-mode's 'y' lands in the system clipboard.
#         macOS: 'brew install tmux' (pbcopy is built in). The chezmoi'd
#         ~/.tmux.conf is expected to configure the status bar and (per
#         CLAUDE.md) set 'set -gq allow-passthrough on' for image.nvim;
#         it also enables 'set -s set-clipboard on' so OSC 52 puts copies
#         on the system clipboard in modern terminals (kitty/wezterm/
#         ghostty/iTerm2) without needing the helpers at all. The helpers
#         are the fallback path for terminals that don't honor OSC 52
#         (xterm, some VTE-based emulators). Skipped if INSTALL_TMUX=0.
#     - starship (cross-shell prompt with git branch / user / context).
#         Linux: official sh.starship.rs installer drops a binary at
#         /usr/local/bin/starship. macOS: 'brew install starship'. The
#         chezmoi'd shell rc is expected to source it via
#         'eval "$(starship init bash)"' (or zsh). Skipped if
#         INSTALL_STARSHIP=0.
#     - JetBrainsMono Nerd Font (provides the glyphs starship/lualine/
#         tmux status icons use). macOS: 'brew install --cask
#         font-jetbrains-mono-nerd-font' (system-wide via brew cask).
#         Linux: downloads the official release zip from
#         github.com/ryanoasis/nerd-fonts into
#         ~/.local/share/fonts/JetBrainsMonoNerdFont/ and runs fc-cache
#         (user-local, no apt repo). On Linux the install also pulls in
#         'fontconfig' via apt so fc-cache is available. Idempotent: skips
#         the download if any JetBrainsMonoNerdFont*.ttf already exists
#         at the install path. Skipped if INSTALL_NERD_FONT=0. To actually
#         see the icons, set your terminal emulator's font to a
#         JetBrainsMono Nerd Font variant.
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
#     - hedronvision/bazel-compile-commands-extractor cloned to
#         ~/.local/share/bazel-compile-commands-extractor (~50MB) plus a
#         helper at ~/.local/bin/bazel-compile-commands that wires it into
#         any Bazel workspace and produces compile_commands.json so clangd
#         gives accurate cross-references on Bazel-built C++ (XLA,
#         JAX/jaxlib, TF, etc.). Skipped if INSTALL_BAZEL_HELPER=0. Remove
#         the clone + helper symlink to undo; per-repo wiring can be
#         removed via 'bazel-compile-commands --clean'.
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
#   INSTALL_BAZEL_HELPER=0
#                       Skip cloning hedronvision/bazel-compile-commands-
#                         extractor (~50MB) and installing the
#                         ~/.local/bin/bazel-compile-commands helper.
#                         Set to 0 if you don't work in any Bazel C++ repos.
#                         Default ON.
#   INSTALL_CLAUDE=0    Skip installing the Claude Code CLI
#                         (@anthropic-ai/claude-code) globally via npm.
#                         Default ON.
#   INSTALL_CHEZMOI=0   Skip installing chezmoi. Default ON. Linux: writes
#                         /usr/local/bin/chezmoi via get.chezmoi.io.
#                         macOS: 'brew install chezmoi'.
#   INSTALL_GH=0        Skip installing the GitHub CLI (`gh`). Default ON.
#                         Linux: adds cli.github.com as a persistent apt
#                         source. macOS: 'brew install gh'.
#   INSTALL_BW=0        Skip installing the Bitwarden CLI (`bw`). Default ON.
#                         Linux: 'npm i -g @bitwarden/cli'. macOS:
#                         'brew install bitwarden-cli'.
#   INSTALL_TMUX=0      Skip installing tmux. Default ON. Linux: apt 'tmux'.
#                         macOS: 'brew install tmux'. The chezmoi'd
#                         ~/.tmux.conf owns status-bar styling.
#   INSTALL_STARSHIP=0  Skip installing starship (shell prompt). Default ON.
#                         Linux: sh.starship.rs installer to /usr/local/bin.
#                         macOS: 'brew install starship'. The chezmoi'd
#                         shell rc must run 'eval "$(starship init <shell>)"'.
#   INSTALL_NERD_FONT=0 Skip installing JetBrainsMono Nerd Font. Default ON.
#                         Without a nerd font, the icons used by starship,
#                         lualine, and the tmux status bar render as tofu.
#                         Linux: ~/.local/share/fonts/. macOS: brew cask
#                         (system-wide). Override font choice with
#                         NERD_FONT_NAME (default: JetBrainsMono).
#   NERD_FONT_NAME=...  Which nerd font to install when INSTALL_NERD_FONT=1.
#                         Default: JetBrainsMono. Must match a release asset
#                         name at github.com/ryanoasis/nerd-fonts/releases
#                         (e.g. FiraCode, Hack, Meslo, Iosevka, CascadiaCode).
#                         On macOS the brew cask is
#                         'font-<lowercased>-nerd-font'.
#
# To uninstall the apt sources later (Linux; clangd-18 / gh binaries remain):
#   sudo rm /etc/apt/sources.list.d/llvm-18.list /etc/apt/keyrings/llvm.gpg
#   sudo rm /etc/apt/sources.list.d/nodesource.list
#   sudo rm /etc/apt/sources.list.d/github-cli.list /etc/apt/keyrings/githubcli-archive-keyring.gpg

set -euo pipefail

LINK_VIM="${LINK_VIM:-1}"
SKIP_NVIM_BUILD="${SKIP_NVIM_BUILD:-0}"
INSTALL_BAZEL_HELPER="${INSTALL_BAZEL_HELPER:-1}"
INSTALL_CLAUDE="${INSTALL_CLAUDE:-1}"
INSTALL_CHEZMOI="${INSTALL_CHEZMOI:-1}"
INSTALL_GH="${INSTALL_GH:-1}"
INSTALL_BW="${INSTALL_BW:-1}"
INSTALL_TMUX="${INSTALL_TMUX:-1}"
INSTALL_STARSHIP="${INSTALL_STARSHIP:-1}"
INSTALL_NERD_FONT="${INSTALL_NERD_FONT:-1}"
NERD_FONT_NAME="${NERD_FONT_NAME:-JetBrainsMono}"

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

# ---------- 5b. bazel-compile-commands helper (clangd index for Bazel C++) ----------
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

    # Patch hedron's refresh_compile_commands.bzl to load py_binary from
    # rules_python instead of calling native.py_binary. In WORKSPACE-mode
    # workspaces (XLA pins `common --noenable_bzlmod`), `native.py_binary`
    # routes to Bazel's built-in Java-side py_binary rather than the
    # rules_python autoloaded one. Bazel then renders rules_python's bash
    # bootstrap template with its own substitution dict and leaves
    # rules_python-specific placeholders (%interpreter_args%,
    # %stage2_bootstrap%, %recreate_venv_at_runtime%, ...) literal — the
    # launcher then tries to exec '%interpreter_args%' as a Python file
    # path and dies with `[Errno 2] No such file or directory`. See
    # https://github.com/hedronvision/bazel-compile-commands-extractor/issues/168
    # for the upstream issue. Re-run-safe: the Python script is idempotent.
    HEDRON_BZL="$HEDRON_DIR/refresh_compile_commands.bzl"
    if [ -f "$HEDRON_BZL" ]; then
        echo "==> Patching $HEDRON_BZL to use rules_python's py_binary"
        run_as_user python3 - "$HEDRON_BZL" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
src = p.read_text()
load_line = 'load("@rules_python//python:defs.bzl", "py_binary")'
anchor = 'load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")'
if load_line not in src and anchor in src:
    src = src.replace(anchor, anchor + "\n" + load_line, 1)
src = src.replace("native.py_binary(", "py_binary(")
p.write_text(src)
PY
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

# Normalize joined include flags. Some Bazel CC toolchains (notably XLA's
# rules_ml_toolchain) declare include flag_groups as `flags = ["-isystem
# %{path}"]` rather than `flags = ["-isystem", "%{path}"]`. Both produce
# the same final compile invocation because Bazel space-joins flags
# anyway, but `bazel aquery` (which hedron consumes) returns whichever
# token shape the toolchain handed it. The joined form lands in
# compile_commands.json as a single "-isystem /path" arg, which clang
# parses as `-isystem ` followed by a path with a literal leading space
# — silently ignored as nonexistent. The resulting JSON looks fine but
# clangd can't find <tuple> et al. We split joined include tokens here
# so the JSON is correct regardless of toolchain quirks. Drop this once
# https://github.com/hedronvision/bazel-compile-commands-extractor lands
# the same fix upstream.
python3 - "$ROOT/compile_commands.json" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f:
    db = json.load(f)
joined = ('-isystem ', '-iquote ', '-I ', '-isysroot ', '-imacros ', '-include ', '-Xclang ')
n = 0
for e in db:
    args = e.get('arguments')
    if not args:
        continue
    new = []
    for a in args:
        if a.startswith(joined):
            flag, _, rest = a.partition(' ')
            if rest:
                new.append(flag); new.append(rest); n += 1
                continue
        new.append(a)
    e['arguments'] = new
with open(p, 'w') as f:
    json.dump(db, f, indent=2)
print(f'==> normalized {n} joined include flags')
PY

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

# ---------- 6c. chezmoi (dotfile manager) ----------
# Ironic but useful: this script installs the *prerequisites* for the nvim/
# Jupyter stack and explicitly leaves dotfiles to chezmoi (see CLAUDE.md), so
# installing chezmoi itself is the bootstrap step that makes that contract
# work end-to-end. Linux uses the official get.chezmoi.io installer (writes a
# single binary to /usr/local/bin), macOS uses brew. Both are idempotent.
if [ "$INSTALL_CHEZMOI" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        if ! command -v chezmoi >/dev/null 2>&1; then
            echo "==> Installing chezmoi to /usr/local/bin (via get.chezmoi.io)"
            sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
        else
            echo "==> chezmoi already installed: $(chezmoi --version 2>/dev/null | head -1)"
        fi
    else
        if brew list --formula chezmoi >/dev/null 2>&1; then
            echo "==> chezmoi already installed via brew"
        else
            echo "==> Installing chezmoi via brew"
            brew install chezmoi
        fi
    fi
else
    echo "==> INSTALL_CHEZMOI=0; skipping chezmoi install"
fi

# ---------- 6d. gh (GitHub CLI) ----------
# Linux pulls from cli.github.com's apt repo (persistent — every future
# 'apt update' will hit it). macOS goes through brew. The GPG key is fetched
# at install time and not fingerprint-pinned, mirroring how this script
# handles apt.llvm.org for clangd.
if [ "$INSTALL_GH" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        if ! command -v gh >/dev/null 2>&1; then
            echo "==> Installing gh (adds cli.github.com as a persistent apt source)"
            install -d -m 0755 /etc/apt/keyrings
            if [ ! -f /etc/apt/keyrings/githubcli-archive-keyring.gpg ]; then
                wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                    > /etc/apt/keyrings/githubcli-archive-keyring.gpg
                chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
            fi
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                > /etc/apt/sources.list.d/github-cli.list
            apt-get update -y
            apt-get install -y gh
        else
            echo "==> gh already installed: $(gh --version 2>/dev/null | head -1)"
        fi
    else
        if brew list --formula gh >/dev/null 2>&1; then
            echo "==> gh already installed via brew"
        else
            echo "==> Installing gh via brew"
            brew install gh
        fi
    fi
else
    echo "==> INSTALL_GH=0; skipping gh install"
fi

# ---------- 6e. Bitwarden CLI (bw) ----------
# Pairs with chezmoi: chezmoi's `bitwarden` template function shells out to
# `bw` to fetch secrets out of the vault at apply time, so dotfiles can pull
# SSH keys / API tokens without committing them. Linux installs via npm
# (Node 20 is already in place from section 2); macOS uses brew. Re-running
# upgrades to the latest published version on Linux; brew is gated on
# 'brew list' so we don't gratuitously upgrade a pinned version.
if [ "$INSTALL_BW" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        echo "==> Installing/updating Bitwarden CLI via 'npm i -g @bitwarden/cli'"
        npm install -g @bitwarden/cli >/dev/null
        echo "    bw: $(bw --version 2>/dev/null || echo unknown)"
    else
        if brew list --formula bitwarden-cli >/dev/null 2>&1; then
            echo "==> Bitwarden CLI already installed via brew"
        else
            echo "==> Installing Bitwarden CLI via brew"
            brew install bitwarden-cli
        fi
    fi
else
    echo "==> INSTALL_BW=0; skipping Bitwarden CLI install"
fi

# ---------- 6f. tmux + clipboard helpers ----------
# Installs the tmux binary plus the OS bridges tmux copy-mode needs to land
# yanks on the system clipboard. The chezmoi'd ~/.tmux.conf carries the
# status-bar styling, allow-passthrough for image.nvim, and
# `set -s set-clipboard on` which makes OSC 52 put copies on the system
# clipboard in modern terminals (kitty/wezterm/ghostty/iTerm2) — those
# don't need the helpers at all. The helpers (xclip/wl-clipboard) are the
# fallback for terminals that don't honor OSC 52 (stock xterm, some
# VTE-based ones) and are what lets copy-mode `y` reach the clipboard
# regardless. macOS has pbcopy built in.
if [ "$INSTALL_TMUX" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        if ! command -v tmux >/dev/null 2>&1; then
            echo "==> Installing tmux via apt"
            apt-get install -y tmux
        else
            echo "==> tmux already installed: $(tmux -V 2>/dev/null)"
        fi
        # Clipboard helpers. xclip covers X11 and works under XWayland too;
        # wl-clipboard is the native Wayland path. Installing both is cheap
        # (~1MB combined) and means the same config works on either display
        # server. Both are idempotent under apt.
        echo "==> Installing clipboard helpers (xclip + wl-clipboard)"
        apt-get install -y xclip wl-clipboard
    else
        if brew list --formula tmux >/dev/null 2>&1; then
            echo "==> tmux already installed via brew"
        else
            echo "==> Installing tmux via brew"
            brew install tmux
        fi
        # macOS: pbcopy/pbpaste are part of the OS, nothing to install.
    fi
else
    echo "==> INSTALL_TMUX=0; skipping tmux install"
fi

# ---------- 6g. starship (shell prompt) ----------
# Cross-shell prompt with git branch, user, host, language/runtime context,
# etc. The chezmoi'd shell rc must run `eval "$(starship init bash)"`
# (or zsh) to actually wire it in; this section just installs the binary.
# Optional ~/.config/starship.toml for theming is also chezmoi's territory.
#
# Linux uses the official installer (https://starship.rs/install.sh) which
# drops a single binary at /usr/local/bin/starship — no apt repo to maintain.
# We pipe with `-y` so it doesn't prompt on re-runs. macOS uses brew.
if [ "$INSTALL_STARSHIP" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        # Re-run unconditionally to pick up new releases; the installer's
        # -y flag overwrites any existing /usr/local/bin/starship in place.
        echo "==> Installing/updating starship to /usr/local/bin (via sh.starship.rs)"
        curl -fsSL https://starship.rs/install.sh | sh -s -- --yes --bin-dir /usr/local/bin
    else
        if brew list --formula starship >/dev/null 2>&1; then
            echo "==> starship already installed via brew"
        else
            echo "==> Installing starship via brew"
            brew install starship
        fi
    fi
else
    echo "==> INSTALL_STARSHIP=0; skipping starship install"
fi

# ---------- 6h. Nerd Font (icons for starship/lualine/tmux status) ----------
# Without a nerd font installed AND the terminal configured to use it, the
# glyphs in starship's two-line preset and lualine render as tofu. Installing
# the font is half the fix; the other half (terminal font setting) is on the
# user — we can't reach into kitty/wezterm/iTerm2/ghostty preferences from a
# shell script.
#
# Linux: pull the release zip from ryanoasis/nerd-fonts (user-local under
# ~/.local/share/fonts/) and run fc-cache. fontconfig (which provides
# fc-cache) is pulled in via apt if not already installed. We pin a release
# tag rather than 'latest' so re-runs across machines land on the same
# version, and the script doesn't randomly re-download when upstream
# publishes a new release.
#
# macOS: brew cask installs system-wide; idempotent via `brew list --cask`.
NERD_FONT_TAG="v3.4.0"

if [ "$INSTALL_NERD_FONT" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        FONT_DIR="$USER_HOME/.local/share/fonts/${NERD_FONT_NAME}NerdFont"
        # Detect prior install by looking for any .ttf with the font name —
        # robust to upstream renaming individual files between releases.
        if [ -d "$FONT_DIR" ] && ls "$FONT_DIR"/*.ttf >/dev/null 2>&1; then
            echo "==> Nerd font ${NERD_FONT_NAME} already present at $FONT_DIR"
        else
            echo "==> Installing nerd font ${NERD_FONT_NAME} (${NERD_FONT_TAG}) to $FONT_DIR"
            # fc-cache lives in fontconfig; ensure it's there.
            if ! command -v fc-cache >/dev/null 2>&1; then
                apt-get install -y fontconfig
            fi
            run_as_user mkdir -p "$FONT_DIR" "$USER_HOME/.cache"
            # Stage the download under the target user's home rather than /tmp.
            # mktemp under /tmp creates a 0700 root-owned dir when the script
            # runs via sudo, and `run_as_user unzip ...` (which drops privs)
            # then can't read inside it — unzip reports the file as missing
            # because open() fails with EACCES before any extension probing.
            FONT_TMP="$(run_as_user mktemp -d "$USER_HOME/.cache/nerd-font.XXXXXX")"
            FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_TAG}/${NERD_FONT_NAME}.zip"
            if run_as_user curl -fsSL --retry 3 -o "$FONT_TMP/font.zip" "$FONT_URL"; then
                # -o overwrite, -q quiet. Limit to .ttf so we don't litter
                # the install dir with readmes and license copies.
                run_as_user unzip -oq "$FONT_TMP/font.zip" '*.ttf' -d "$FONT_DIR"
                run_as_user fc-cache -f "$FONT_DIR" >/dev/null
                echo "    installed $(ls "$FONT_DIR"/*.ttf 2>/dev/null | wc -l) .ttf files"
            else
                echo "    WARNING: failed to download $FONT_URL; skipping font install"
                echo "             (check NERD_FONT_NAME — must match a release asset name)"
            fi
            run_as_user rm -rf "$FONT_TMP"
        fi
    else
        # Map e.g. JetBrainsMono -> font-jetbrains-mono-nerd-font. Brew
        # cask names are kebab-cased lowercase with -nerd-font suffix.
        FONT_CASK="font-$(echo "$NERD_FONT_NAME" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')-nerd-font"
        if brew list --cask "$FONT_CASK" >/dev/null 2>&1; then
            echo "==> Nerd font cask $FONT_CASK already installed"
        else
            echo "==> Installing nerd font cask $FONT_CASK"
            if ! brew install --cask "$FONT_CASK"; then
                echo "    WARNING: brew install --cask $FONT_CASK failed"
                echo "             (check NERD_FONT_NAME — see 'brew search font-*-nerd-font')"
            fi
        fi
    fi
else
    echo "==> INSTALL_NERD_FONT=0; skipping nerd font install"
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

if [ "$INSTALL_CHEZMOI" = "1" ]; then
    CHEZMOI_STATUS="$(chezmoi --version 2>/dev/null | head -1 || echo missing)"
else
    CHEZMOI_STATUS="(skipped: INSTALL_CHEZMOI=0)"
fi

if [ "$INSTALL_GH" = "1" ]; then
    GH_STATUS="$(gh --version 2>/dev/null | head -1 || echo missing)"
else
    GH_STATUS="(skipped: INSTALL_GH=0)"
fi

if [ "$INSTALL_BW" = "1" ]; then
    BW_STATUS="$(bw --version 2>/dev/null || echo missing)"
else
    BW_STATUS="(skipped: INSTALL_BW=0)"
fi

if [ "$INSTALL_TMUX" = "1" ]; then
    TMUX_STATUS="$(tmux -V 2>/dev/null || echo missing)"
else
    TMUX_STATUS="(skipped: INSTALL_TMUX=0)"
fi

if [ "$INSTALL_STARSHIP" = "1" ]; then
    STARSHIP_STATUS="$(starship --version 2>/dev/null | head -1 || echo missing)"
else
    STARSHIP_STATUS="(skipped: INSTALL_STARSHIP=0)"
fi

if [ "$INSTALL_NERD_FONT" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        FONT_DIR="$USER_HOME/.local/share/fonts/${NERD_FONT_NAME}NerdFont"
        if [ -d "$FONT_DIR" ] && ls "$FONT_DIR"/*.ttf >/dev/null 2>&1; then
            NERD_FONT_STATUS="${NERD_FONT_NAME} ($(ls "$FONT_DIR"/*.ttf | wc -l) ttf in $FONT_DIR)"
        else
            NERD_FONT_STATUS="missing (download likely failed; see log above)"
        fi
    else
        FONT_CASK="font-$(echo "$NERD_FONT_NAME" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')-nerd-font"
        if brew list --cask "$FONT_CASK" >/dev/null 2>&1; then
            NERD_FONT_STATUS="${NERD_FONT_NAME} (brew cask $FONT_CASK)"
        else
            NERD_FONT_STATUS="missing (brew cask $FONT_CASK not installed)"
        fi
    fi
else
    NERD_FONT_STATUS="(skipped: INSTALL_NERD_FONT=0)"
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
printf "    %-13s %s\n" "chezmoi:"      "$CHEZMOI_STATUS"
printf "    %-13s %s\n" "gh:"           "$GH_STATUS"
printf "    %-13s %s\n" "bw:"           "$BW_STATUS"
printf "    %-13s %s\n" "tmux:"         "$TMUX_STATUS"
printf "    %-13s %s\n" "starship:"     "$STARSHIP_STATUS"
printf "    %-13s %s\n" "nerd font:"    "$NERD_FONT_STATUS"
echo
if [ "$OS" = "linux" ]; then
    echo "Persistent apt sources added (remove manually to undo):"
    echo "    /etc/apt/sources.list.d/llvm-18.list"
    echo "    /etc/apt/keyrings/llvm.gpg"
    echo "    /etc/apt/sources.list.d/nodesource.list"
    if [ "$INSTALL_GH" = "1" ]; then
        echo "    /etc/apt/sources.list.d/github-cli.list"
        echo "    /etc/apt/keyrings/githubcli-archive-keyring.gpg"
    fi
else
    echo "Brew formulae installed/used: neovim node ripgrep ninja cmake gettext imagemagick llvm chezmoi gh bitwarden-cli tmux starship"
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
if [ "$INSTALL_NERD_FONT" = "1" ]; then
    echo "  4a. Set your terminal emulator's font to '${NERD_FONT_NAME} Nerd Font'"
    echo "      (kitty: font_family in kitty.conf; ghostty/wezterm: their config files;"
    echo "      iTerm2/Terminal.app: Preferences > Profiles > Text). Otherwise"
    echo "      starship/lualine/tmux icons render as tofu."
fi
if [ "$INSTALL_BAZEL_HELPER" = "1" ]; then
    echo "  5. For C++ in a Bazel repo (XLA, jaxlib, TF), cd into the workspace and"
    echo "     run 'bazel-compile-commands' once — this generates compile_commands.json"
    echo "     so clangd gives accurate cross-references. First run on XLA can take"
    echo "     10-30 min; subsequent runs are minutes. Pass scoped targets like"
    echo "     '//xla/...' to limit extraction. 'bazel-compile-commands --clean'"
    echo "     reverts the per-repo wiring."
fi

# ---------- post-install: optional interactive bootstrap ----------
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
