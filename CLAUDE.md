# jems — repo notes for Claude

This repo is a Bash installer that sets up the **prerequisites** for a
Neovim + LazyVim + Jupyter notebook stack on a fresh Ubuntu/WSL2 box or a
fresh macOS (14+, Apple Silicon or Intel) box. "Prerequisites" means
anything that is not a dotfile: apt/brew packages, the nvim binary,
Node.js, clangd, basedpyright, the Claude Code CLI, fzf binaries, the
Python venv that molten-nvim depends on, the
hedronvision/bazel-compile-commands-extractor clone + helper, and a couple
of environment-specific symlinks under `~/.local/bin`. Linux uses apt + a
from-source nvim build and runs under `sudo`; macOS uses Homebrew and runs
as the user (brew refuses sudo). The OS is detected via `uname -s` at the
top and platform-specific blocks branch on `$OS` (`linux` | `macos`).

## Layout
- `install.sh` is the **driver**: env-var toggles, OS detect, preflight,
  `run_as_user`, helpers (`brew_install_if_missing`, `nvim_version_ok`,
  `nerd_font_cask`), shared path constants (`NVIM_VENV`, `HEDRON_DIR`,
  `HELPER_BIN`), the final summary, and the comment block enumerating every
  persistent system change. Anything reused by more than one step belongs
  here, not in a subscript.
- `install.d/NN-<step>.sh` — one file per install step (system prereqs,
  node, nvim, fzf, clangd, bazel helper, basedpyright, claude, chezmoi, gh,
  bw, tmux, starship, nerd-font, nvim-venv, and the interactive bootstrap
  prompts at `99-`). Subscripts are **sourced**, not exec'd, so they
  inherit the driver's variables and helpers. Numeric prefix is also the
  run order — node before anything that shells out to npm, nvim before the
  vim/vi symlinks, etc.
- `install.d/files/bazel-compile-commands` — the runtime helper installed
  to `~/.local/bin/bazel-compile-commands`. Edited as a real script (not a
  heredoc) so syntax highlighting and shellcheck work; the bazel-helper
  step `install -m 0755`'s it into place.
- Hard rule: **at most two levels of scripts** (`install.sh` →
  `install.d/*.sh`). Subscripts must not source other subscripts. If a
  helper is reused, lift it into `install.sh`.

## Out of scope: dotfiles

Anything under the user's `$HOME` that is a config file is managed by
**chezmoi**, not this script. That includes `~/.config/nvim/**`,
`~/.tmux.conf`, `~/.bashrc`/`~/.zshrc`, `~/.config/ImageMagick-7/type.xml`,
and any LazyVim plugin specs. The script must never read, edit, or write
those paths. If a future task seems to require touching one of them, push
back and route it through chezmoi instead.

## Contract with the chezmoi config

The script and the chezmoi config meet at a small set of well-known paths.
Don't break these without updating both sides:

- `~/.local/share/nvim-venv` — the script creates this venv with pynvim,
  jupyter_client, ipykernel, jupytext, etc. The chezmoi'd nvim config is
  expected to set
  `vim.g.python3_host_prog = "$HOME/.local/share/nvim-venv/bin/python"`
  so molten-nvim can find pynvim.
- `~/.local/bin/{clangd,jupytext,vim,vi}` — the script symlinks these
  (clangd from brew's keg-only llvm; jupytext from the nvim venv; vim/vi
  from nvim when `LINK_VIM=1`). The chezmoi'd shell rc is expected to
  prepend `~/.local/bin` to PATH (macOS doesn't do this by default the
  way Ubuntu's `~/.profile` does).
- `~/.fzf/` — the script clones fzf and runs its installer with
  `--no-update-rc`. The chezmoi'd bashrc/zshrc is expected to source
  `~/.fzf.bash` / `~/.fzf.zsh`.
- macOS only: brew's `imagemagick` ships an empty `type.xml` so SVG
  rendering blows up with `unable to read font ''`. The chezmoi config
  must drop a user-level `~/.config/ImageMagick-7/type.xml` registering
  some system fonts AND set
  `vim.env.MAGICK_CONFIGURE_PATH = "$HOME/.config/ImageMagick-7:<brew-prefix>/etc/ImageMagick-7"`
  inside nvim (brew's IM does not auto-search `~/.config`). This used to
  live in this script; now the install side just installs `imagemagick`
  via brew.
- tmux: image.nvim needs `set -gq allow-passthrough on` (tmux 3.3+) when
  nvim is launched inside tmux, otherwise `:checkhealth image.nvim` errors
  with "tmux does not have allow-passthrough enabled" and plots never
  render. The chezmoi'd `~/.tmux.conf` is expected to set this.
- basedpyright vs pyright: this script installs `basedpyright` globally via
  npm (and uninstalls any old `pyright` it finds). The chezmoi'd
  `lua/plugins/lspconfig.lua` is expected to disable `pyright` in its
  servers table — running both against the same buffer leads to duplicate
  diagnostics if LazyVim's `lang.python` extra is enabled.
- bazel helper: `~/.local/bin/bazel-compile-commands` is installed by this
  script and references `~/.local/share/bazel-compile-commands-extractor`
  via a Bazel `local_path_override`, so it has no network deps at run time.
  It writes a fenced managed block into the Bazel workspace's
  `MODULE.bazel`/`WORKSPACE`, plus `tools/clangd/BUILD.bazel`. None of
  those paths are dotfiles, so they belong here, not in chezmoi. The
  install script also patches the local hedron clone's
  `refresh_compile_commands.bzl` to load `py_binary` from `@rules_python`
  rather than calling `native.py_binary`. Without this, WORKSPACE-mode
  workspaces (notably XLA, which pins `common --noenable_bzlmod`) route
  hedron's macro to Bazel's built-in py_binary, which can't substitute
  rules_python's bash bootstrap placeholders (`%interpreter_args%` etc.)
  and the launcher dies trying to exec a literal `%interpreter_args%`
  path. See hedron issue #168. The patch is idempotent and re-applied
  on every `install.sh` run, so a `git pull` of hedron that reverts it
  gets re-fixed.
  - Host↔container gotcha (not install-side, but bites the bazel-compile-commands
    workflow): when running the extractor inside a `docker run -u $(id -u):$(id -g)`
    container (the chezmoi'd `drun` alias), the container must (a) bind-mount
    `/etc/passwd` + `/etc/group` read-only and/or set `-e USER="$USER"` so Bazel
    resolves the same `~/.cache/bazel/_bazel_$USER` output base as the host —
    otherwise `$USER` is empty inside, Bazel picks a fresh output base, and every
    external repo (notably the multi-GB LLVM toolchain) re-downloads from cold.
    (b) `--group-add` the GPU device GIDs *numerically* — `/dev/kfd` and
    `/dev/dri/renderD*` are group `render` (GID 109 on this host, but `render` is
    a dynamic ≥100 allocation and can differ per machine), `/dev/dri/card*` is
    `video` (GID 44, a Debian static alloc). Name-based `--group-add video`
    resolves against the image's `/etc/group`, misses `render`, and breaks
    `rocminfo`. The robust form derives them at runtime:
    `--group-add "$(stat -c %g /dev/kfd)" --group-add "$(stat -c %g /dev/dri/renderD128)"`.
    All of this lives in the chezmoi'd `~/.bashrc` (`private_dot_bashrc`), not
    here — this note is just a pointer for the next "clangd can't find headers /
    rocminfo fails in the container" triage.
  - `--config` passthrough: the helper takes `--config NAME` (repeatable; or the
    `BAZEL_CONFIG` env var) and applies it both to its `bazel run` and — past a
    `--` — to hedron's internal `bazel aquery` (refresh.template.py does
    `additional_flags = shlex.split(flags) + sys.argv[1:]`). This exists because
    the helper otherwise runs *bare* `bazel run`, which on repos that need a
    named toolchain config falls back to Bazel's auto-detected `local` toolchain.
    On an Ubuntu host that toolchain assumes GCC and injects
    `-fno-canonical-system-headers`; with a clang compiler (e.g. XLA's
    `/usr/lib/llvm-18/bin/clang`) clang rejects that flag and hedron's
    `print_args.cpp` fails to compile before extraction even starts. Fix: pass
    the repo's build config — for XLA on ROCm,
    `bazel-compile-commands --config rocm_clang_local <root> //xla/...`
    (`rocm_clang_local` = `rocm_base` + `clang_local` + the ROCm crosstool, and
    pins `CLANG_COMPILER_PATH=/usr/lib/llvm-18/bin/clang` — which only exists
    inside the ROCm container, so run the extractor there). The equivalent
    repo-local alternative is a gitignored `.tf_configure.bazelrc` with
    `common --config=rocm_clang_local` (XLA's `try-import` slot), but the
    `--config` flag keeps the toolchain choice explicit on the command line.
- Claude Code CLI: installed globally via `npm i -g @anthropic-ai/claude-code`
  (gated by `INSTALL_CLAUDE`, default 1). The CLI itself stores its config
  under `~/.claude/`, which is chezmoi's territory if you want to manage it.
- carbonyl: `install.d/17-carbonyl.sh` installs the upstream
  Chromium-in-the-terminal release (Linux only — no macOS upstream).
  Bundle goes to `~/.local/share/carbonyl/` (a flat dir of binary +
  shared libs, ~150 MB extracted) with `~/.local/bin/carbonyl` as a
  symlink — same user-local-binary pattern as jupytext and the
  bazel helper. Idempotency via `$CARBONYL_DIR/.installed_version`;
  bump `CARBONYL_VERSION` in the step when upstream cuts a new
  release (currently pinned at 0.0.3, the only release available).
  Gated by `INSTALL_CARBONYL` (default 1). The chezmoi'd bashrc and
  zshrc define `alias carbonyl='carbonyl --user-data-dir=…'` pointing
  at `~/.local/share/carbonyl-profile` so cookies / logins / history
  survive restarts (carbonyl uses an ephemeral Chromium profile by
  default). No vim keybindings inside carbonyl; for vim-style movement
  use `w3m` instead.
- Terraform stack: `install.d/16-terraform.sh` installs the `terraform`
  CLI, `terraform-ls` LSP, and `tflint` linter. Linux pulls `terraform`
  and `terraform-ls` from `apt.releases.hashicorp.com` (persistent apt
  source) and `tflint` via terraform-linters' official installer to
  `/usr/local/bin`. macOS uses `brew install hashicorp/tap/terraform
  hashicorp/tap/terraform-ls tflint`. Gated by `INSTALL_TERRAFORM`
  (default 1). The chezmoi'd `lazyvim.json` enables
  `lazyvim.plugins.extras.lang.terraform` and `private_terraform.lua`
  (a) disables Mason for `terraformls` so this script's binary wins,
  (b) strips `tflint` from Mason's `ensure_installed`, (c) strips
  `hcl`/`terraform` from `nvim-treesitter`'s `ensure_installed`, and
  (d) adds `hashivim/vim-terraform` for syntax highlighting. The
  treesitter exclusion is load-bearing on Ubuntu 22.04: nvim-treesitter
  (main branch) compiles parsers via a `tree-sitter` CLI; the Mason
  and npm prebuilt binaries both link against glibc 2.39+ and fail on
  jammy's glibc 2.35, and building tree-sitter-cli from source also
  fails because current transitive deps need cargo 1.85+ while jammy
  ships cargo 1.75. Rather than fight that, we let `vim-terraform`
  handle highlighting (pure vimscript, no compile) and skip the
  treesitter parser for hcl/terraform entirely.

## Single source of truth
Everything install-side lives under `install.sh` + `install.d/`. There is
no Ansible, no Makefile, no nested install directories. The two-level
limit (driver → step) is intentional; if you find yourself wanting a
third level, lift the shared code into `install.sh` instead.

## Re-run contract
The script is designed to be run repeatedly on the same box:
- Each step is gated by a per-tool **`MIN_*` floor** declared at the top of
  `install.sh` (`MIN_NVIM_VERSION`, `MIN_FZF_VERSION`, `MIN_CLANGD_VERSION`,
  etc.). If the installed tool is at or above the floor, the step is a
  no-op; if it's below, the step reinstalls/upgrades. Don't go back to
  gating on bare `command -v <tool>` or `brew list --formula <name>` —
  those let stale pre-existing binaries win and reintroduce the version
  trap. Bump the floor when a chezmoi-side config (or another step) starts
  relying on a feature that's only in a newer release.
- `version_ge CUR MIN` and `tool_version_ok CMD MIN` in `install.sh` are
  the canonical version helpers — call them rather than open-coding awk
  comparisons. `brew_ensure FORMULA [MIN_VER]` is the macOS equivalent of
  "install or upgrade to the floor"; passing no MIN keeps the legacy
  install-if-missing behavior for prereqs that don't have a feature floor.
- `npm i -g` for basedpyright/claude/bw(Linux) is unconditional — npm
  always installs the latest, so a floor would just be noise.
- The Python venv at `~/.local/share/nvim-venv` is reused if it exists;
  pip dependencies inside it are upgraded on every run.
- Symlinks under `~/.local/bin` are re-pointed each run with `ln -sf` so
  brew prefix changes (e.g. Apple Silicon → Intel) are picked up.

## Conventions
- Bash strict mode (`set -euo pipefail`).
- Toggles are env vars with documented defaults; never positional args.
- `run_as_user` wraps any command that touches `$USER_HOME` so files don't
  end up owned by root. On Linux it's `sudo -u $TARGET_USER -H --`; on
  macOS it's a passthrough (we're already the user). New code that writes
  into `$USER_HOME` should go through `run_as_user` even though it's a
  no-op on macOS — that's how we keep the Linux path correct without
  branching at every call site.
- Comments at the top of `install.sh` enumerate every persistent system
  change per OS (apt sources, brew formulae, symlinks, alternatives) and
  how to undo them. Keep that list accurate when you add steps — it lives
  in the driver, not the per-step files.

## Testing changes
There is no CI. Validate with:
```
bash -n install.sh                          # syntax
for f in install.d/*.sh; do bash -n "$f"; done
shellcheck install.sh install.d/*.sh install.d/files/* 2>/dev/null  # if available
```
For end-to-end testing on Linux, the cheap path is a throwaway WSL distro
or a Docker container running Ubuntu 22.04 — the Linux path is destructive
(apt sources, /usr/local, /usr/bin alternatives) so don't smoke-test it on
a machine you care about. The macOS path is much less destructive (only
brew installs + user-local symlinks under `~/.local/bin`), but smoke-test
on a spare account or VM if you want to be safe.

## Jupyter stack notes
The notebook workflow is `jupytext.nvim` (open `.ipynb` as hydrogen-style
`# %%` cells) + `molten-nvim` (run cells against a Jupyter kernel) +
`image.nvim` (render plot output). Molten requires `pynvim` and
`jupyter_client` reachable from the python that nvim spawns; the script
solves the binary half by creating a dedicated venv at
`~/.local/share/nvim-venv`. The wiring half (`vim.g.python3_host_prog`)
lives in the chezmoi'd nvim config. If a future task involves "molten
can't find pynvim" or `:checkhealth provider.python` complaints, the
venv and that one `vim.g` are the first two places to look.

molten-nvim is a **python remote plugin**, so `:MoltenInit` and friends
only become editor commands after `:UpdateRemotePlugins` writes a
manifest to `~/.local/share/nvim/rplugin.vim`. The chezmoi'd molten
plugin spec uses `build = ":UpdateRemotePlugins"`, which lazy.nvim fires
during sync — and lazy.nvim runs sync the first time the user launches
`nvim` interactively. **The script does not run `nvim --headless +Lazy!
sync` itself anymore** (see hang note below); plugin bootstrap is the
user's first `nvim` run. If `:MoltenInit` is undefined after that, grep
`~/.local/share/nvim/rplugin.vim` for `molten` — a missing block means
pynvim isn't reachable from `vim.g.python3_host_prog`.

### Why we don't run headless sync from this script
Earlier triage on macOS: `nvim --headless +Lazy! sync +qa` hung for >2
minutes at 0% CPU. `sample` showed the stack ending in
`getchar_common → os_inchar → loop_poll_events → kevent`. Verbose
logging (`-V15/tmp/nvim-verbose.log`) eventually surfaced this:

    LazyVim requires Neovim >= 0.11.2
    For more info, see: https://github.com/LazyVim/LazyVim/issues/6421
    Press any key to exit

The user's brew had `neovim 0.10.2` lingering from an earlier install.
LazyVim's startup compatibility check fires `getchar()` to wait for an
ack, kevent on `/dev/null` blocks forever (it doesn't return EOF the way
read(2) on a closed fd would), and headless nvim never exits. With
`brew upgrade neovim` the same headless sync command finished in 10s. So:

- The script enforces `MIN_NVIM_VERSION` (set to LazyVim's current
  minimum, 0.11.2 at time of writing) via an awk-based version compare
  in `nvim_version_ok()`. macOS upgrades through `brew upgrade neovim`;
  Linux rebuilds from `-b stable`.
- Bump `MIN_NVIM_VERSION` when LazyVim bumps its requirement.
- Don't try to "fix" a hang by piping stdin from `/dev/null` — that
  doesn't help, because the block is in libuv's kevent, not in a
  `read()` syscall.

The script used to do a headless `nvim --headless +Lazy! sync +qa` (and a
forced `Lazy! load molten-nvim +UpdateRemotePlugins`) at install time,
but separately from the version-mismatch hang above, headless sync of
the LazyVim default plugin set has shown other intermittent hangs inside
`os_inchar`/kevent. Don't re-add headless sync — let the user's first
interactive `nvim` do it, which is what lazy.nvim is designed for anyway.

Image rendering only works in graphics-capable terminals (kitty, wezterm,
ghostty; on macOS iTerm2 also works). Default Windows Terminal in WSL and
macOS Terminal.app won't render plots — that's a terminal limitation, not
a config bug.

### macOS clangd discovery
On macOS, brew's `llvm` formula is keg-only (not auto-linked) so the
script symlinks `~/.local/bin/clangd -> $(brew --prefix llvm)/bin/clangd`
rather than `brew link --force llvm` (which would clobber Apple's
clang/clang++ on PATH). For nvim/lspconfig to find it, `~/.local/bin`
needs to be on PATH — and that's the chezmoi'd shell rc's job. If a
future task is "clangd LSP not attaching on macOS", the first thing to
check is `which clangd` from the same shell that launches nvim — if it
returns nothing, the chezmoi config isn't putting `~/.local/bin` on PATH.
