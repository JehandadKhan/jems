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
# Structure: this file (the driver) handles OS detection, preflight, env-
# var toggles, common shell helpers, and the final summary. Each install
# step lives in its own script under ./install.d/ and is sourced (not
# exec'd) so it sees the driver's variables and helpers. The driver is the
# single source of truth for everything that's shared across steps; if you
# find yourself copy-pasting between subscripts, lift the helper here
# instead.
#
# Usage (Linux): sudo bash ~/install.sh
#                If you're already root (containers, bare VPSs, WSL distros
#                where root is the only user, or after 'su -'), just run
#                'bash ~/install.sh' — the script will detect the missing
#                $SUDO_USER and install for root. Override with
#                TARGET_USER=<user> to install into someone else's home
#                while running as root.
# Usage (macOS): bash ~/install.sh
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

# ---------- toggles ----------
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

# Pinned nerd-fonts release. Re-runs across machines land on the same
# version, and the installer doesn't randomly re-download when upstream
# publishes a new release.
NERD_FONT_TAG="v3.4.0"

# ---------- locate subscripts ----------
# resolve symlinks so install.d/ is found even when the script is invoked
# via a symlink (e.g. ~/bin/install.sh -> /path/to/jems/install.sh).
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_PATH" ]; do
    SCRIPT_DIR_TMP="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    case "$SCRIPT_PATH" in
        /*) ;;
        *) SCRIPT_PATH="$SCRIPT_DIR_TMP/$SCRIPT_PATH" ;;
    esac
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
STEPS_DIR="$SCRIPT_DIR/install.d"
if [ ! -d "$STEPS_DIR" ]; then
    echo "error: install steps directory not found at $STEPS_DIR" >&2
    echo "       this script expects ./install.d/ next to it." >&2
    exit 1
fi

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

# ---------- common helpers ----------
# Anything reused by more than one subscript lives here so the steps stay
# focused on what's specific to their tool. Add new helpers here rather
# than copy-pasting into install.d/.

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

# brew_install_if_missing FORMULA — install a brew formula only if it's not
# already present. Used by every macOS-only step that doesn't want to
# gratuitously upgrade a tool the user is pinning.
brew_install_if_missing() {
    local f="$1"
    if brew list --formula "$f" >/dev/null 2>&1; then
        echo "    $f already installed"
    else
        echo "    installing $f"
        brew install "$f"
    fi
}

# Returns 0 if nvim is on PATH and >= MIN_NVIM_VERSION, else 1. We compare
# major.minor.patch numerically via awk so we don't depend on GNU sort -V
# (BSD sort on macOS doesn't have it). Used by 03-nvim.sh; defined here
# because the summary at the end also wants to know.
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

# Map a CamelCase nerd-font name (e.g. JetBrainsMono) to a brew cask name
# (font-jet-brains-mono-nerd-font). Used by the nerd-font step and by the
# summary's status line so they agree on the cask name.
nerd_font_cask() {
    printf 'font-%s-nerd-font' \
        "$(echo "$1" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')"
}

# Path constants reused across steps and the summary.
NVIM_VENV="$USER_HOME/.local/share/nvim-venv"
HEDRON_DIR="$USER_HOME/.local/share/bazel-compile-commands-extractor"
HELPER_BIN="$USER_HOME/.local/bin/bazel-compile-commands"

# ---------- run install steps ----------
# Each step is a separate file in install.d/, sourced (not exec'd) so it
# sees the helpers and toggles above. Ordering matters in a couple of
# places (node before claude/basedpyright/bw; nvim before vim/vi symlinks)
# and is captured by the numeric prefix.
run_step() {
    local step="$STEPS_DIR/$1"
    if [ ! -f "$step" ]; then
        echo "error: install step not found: $step" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$step"
}

run_step 01-system-prereqs.sh
run_step 02-node.sh
run_step 03-nvim.sh
run_step 04-fzf.sh
run_step 05-clangd.sh
run_step 06-bazel-helper.sh
run_step 07-basedpyright.sh
run_step 08-claude.sh
run_step 09-chezmoi.sh
run_step 10-gh.sh
run_step 11-bw.sh
run_step 12-tmux.sh
run_step 13-starship.sh
run_step 14-nerd-font.sh
run_step 15-nvim-venv.sh

# ---------- summary ----------
# Resolve the clangd we actually wired up — on macOS that's brew's keg-only
# llvm, which won't be on root's PATH if we'd looked it up there.
if [ "$OS" = "macos" ]; then
    CLANGD_VERSION="$("$USER_HOME/.local/bin/clangd" --version 2>/dev/null | head -1 || echo missing)"
else
    CLANGD_VERSION="$(clangd --version 2>/dev/null | head -1 || echo missing)"
fi

if [ "$INSTALL_BAZEL_HELPER" = "1" ] && [ -x "$HELPER_BIN" ]; then
    BAZEL_HELPER_STATUS="$HELPER_BIN"
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
        FONT_CASK="$(nerd_font_cask "$NERD_FONT_NAME")"
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
        echo "    ~/.local/bin/{vim,vi}    -> $(command -v nvim)"
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
# Run last so the summary above is the user's takeaway if they Ctrl-C out
# of the prompts. Skipped silently when stdin isn't a TTY (curl|bash, CI).
run_step 99-bootstrap-prompts.sh
