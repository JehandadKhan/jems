# jems — repo notes for Claude

This repo is a single-file Bash installer (`install-lazyvim.sh`) that sets up
the **prerequisites** for a Neovim + LazyVim + Jupyter notebook stack on a
fresh Ubuntu/WSL2 box or a fresh macOS (14+, Apple Silicon or Intel) box.
"Prerequisites" means anything that is not a dotfile: apt/brew packages, the
nvim binary, Node.js, clangd, pyright, fzf binaries, the Python venv that
molten-nvim depends on, and a couple of environment-specific symlinks under
`~/.local/bin`. Linux uses apt + a from-source nvim build and runs under
`sudo`; macOS uses Homebrew and runs as the user (brew refuses sudo). The
OS is detected via `uname -s` at the top and platform-specific blocks
branch on `$OS` (`linux` | `macos`).

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

## Single source of truth
Everything install-side lives in `install-lazyvim.sh`. There is no Ansible,
no Makefile. If you find yourself wanting to add a second file, push back
— keep the install path one curl-able script.

## Re-run contract
The script is designed to be run repeatedly on the same box:
- apt/brew / node / nvim / fzf / clangd / pyright / venv steps are
  idempotent. Brew installs are gated on `brew list --formula <name>` so
  we never gratuitously upgrade a tool the user is pinning.
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
- Comments at the top of the script enumerate every persistent system
  change per OS (apt sources, brew formulae, symlinks, alternatives) and
  how to undo them. Keep that list accurate when you add steps.

## Testing changes
There is no CI. Validate with:
```
bash -n install-lazyvim.sh        # syntax
shellcheck install-lazyvim.sh     # if available
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
