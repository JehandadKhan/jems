# jems — repo notes for Claude

This repo is a single-file Bash installer (`install-lazyvim.sh`) that sets up
Neovim + LazyVim + LSPs + a Jupyter notebook stack on a fresh Ubuntu/WSL2 box
or a fresh macOS (14+, Apple Silicon or Intel) box, and is also re-runnable
to bring an existing install up to date. Linux uses apt + a from-source nvim
build and runs under `sudo`; macOS uses Homebrew and runs as the user (brew
refuses sudo). The OS is detected via `uname -s` at the top and platform-
specific blocks branch on `$OS` (`linux` | `macos`); everything below the
package-install layer (managed lua specs, venv, tmux block, plugin sync) is
shared.

## Single source of truth
Everything lives in `install-lazyvim.sh`. There is no Ansible, no Makefile,
no separate Lua repo. Lua plugin specs are written into `~/.config/nvim/lua/`
by heredocs inside the script itself. If you find yourself wanting to add a
second file, push back — keep the install path one curl-able script.

## Re-run contract
The script is designed to be run repeatedly on the same box:
- apt/brew / node / nvim / fzf / clangd / pyright / venv steps are idempotent.
  Brew installs are gated on `brew list --formula <name>` so we never
  gratuitously upgrade a tool the user is pinning.
- LazyVim starter is **preserved** across re-runs by default
  (`FORCE_LAZYVIM=0`). Only set `FORCE_LAZYVIM=1` for a clean reset.
- Files this script owns under `~/.config/nvim/lua/plugins/` are rewritten on
  every run. They carry a marker comment on line 1; if the marker is missing
  (user-edited), we move the file to `*.bak.<timestamp>` before clobbering.
- `~/.config/nvim/lua/config/options.lua` is not fully owned — we only
  replace a fenced block delimited by `-- >>> install-lazyvim.sh managed
  block` / `-- <<<` markers. Anything else in that file is left alone.

When adding a new plugin spec or config tweak, route it through
`write_managed_file` (whole file we own) or `update_managed_block` (fenced
region in a shared file). Don't use `if [ ! -f ... ]; then write` — that
pattern was removed because it stops re-runs from picking up changes.

## Conventions
- Bash strict mode (`set -euo pipefail`).
- Toggles are env vars with documented defaults; never positional args.
- `run_as_user` wraps any command that touches `$USER_HOME` so files don't
  end up owned by root. On Linux it's `sudo -u $TARGET_USER -H --`; on
  macOS it's a passthrough (we're already the user). New code that writes
  into `$USER_HOME` should go through `run_as_user` even though it's a
  no-op on macOS — that's how we keep the Linux path correct without
  branching at every call site.
- `chown` calls on managed files always trail `2>/dev/null || true`. On
  macOS the file is already user-owned (so the chown is a no-op), and the
  user's primary group typically isn't `$USER` (it's `staff`) so a
  `user:user` chown would otherwise fail noisily.
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
solves this by creating a dedicated venv at `~/.local/share/nvim-venv` and
setting `vim.g.python3_host_prog` to it. If a future task involves
"molten can't find pynvim" or `:checkhealth provider.python` complaints,
the venv is the first place to look.

molten-nvim is a **python remote plugin**, so `:MoltenInit` and friends
only become editor commands after `:UpdateRemotePlugins` writes its
manifest to `~/.local/share/nvim/rplugin.vim`. The molten spec uses
`build = ":UpdateRemotePlugins"`, which lazy.nvim fires during sync —
force-loading molten despite its `ft = { python, markdown, quarto }`
gate. The script's headless `nvim --headless +Lazy! sync +qa` therefore
both installs plugins and writes the molten manifest in a single shot.
We grep the manifest for "molten" afterward as a sanity check; a
missing block means pynvim isn't reachable from `vim.g.python3_host_prog`
and `:MoltenInit` won't exist.

### Headless-sync hang we hit during macOS bring-up
Earlier triage: `nvim --headless +Lazy! sync +qa` hung on macOS for >2
minutes at 0% CPU. `sample` showed the stack ending in
`getchar_common → os_inchar → loop_poll_events → kevent`. First
suspicion was a plugin calling `vim.fn.getchar()` during sync; verbose
logging (`-V15/tmp/nvim-verbose.log`) eventually surfaced this:

    LazyVim requires Neovim >= 0.11.2
    For more info, see: https://github.com/LazyVim/LazyVim/issues/6421
    Press any key to exit

The user's brew had `neovim 0.10.2` lingering from an earlier install.
LazyVim's startup compatibility check fires `getchar()` to wait for an
ack, kevent on `/dev/null` blocks forever (it doesn't return EOF the way
read(2) on a closed fd would), and headless nvim never exits. With
`brew upgrade neovim` to 0.12.x the same headless sync command finished
in 10s rc=0 with a fully populated `rplugin.vim`. So:

- The script enforces `MIN_NVIM_VERSION` (set to LazyVim's current
  minimum, 0.11.2 at time of writing) via an awk-based version compare
  in `nvim_version_ok()`. macOS upgrades through `brew upgrade neovim`;
  Linux rebuilds from `-b stable`.
- Bump `MIN_NVIM_VERSION` when LazyVim bumps its requirement. If you
  ever see the headless sync hanging again, the version gate is the
  first thing to recheck — `nvim --version` and `cat
  /tmp/nvim-verbose.log` (rerun with `-V15/tmp/nvim-verbose.log`) will
  show the LazyVim banner if it's the same root cause.
- Don't try to "fix" the hang by piping stdin from `/dev/null` — that
  was already in place when this happened and didn't help, because the
  block is in libuv's kevent, not in a `read()` syscall.

The script used to do a headless `nvim --headless +Lazy! sync +qa` (and a
forced `Lazy! load molten-nvim +UpdateRemotePlugins`) at install time, but
that reliably hung on macOS inside `os_inchar`/kevent — something in the
LazyVim default plugin set calls `vim.fn.getchar()` or `input()` during
sync, and even with `</dev/null` the kevent on the closed fd blocks
forever rather than returning EOF (`sample` confirmed the stack ended in
`getchar_common` → `os_inchar` → `loop_poll_events` → `kevent`). Don't
re-add headless sync. Plugin bootstrap is now deferred to the user's
first interactive `nvim` run, which is what lazy.nvim is designed for
anyway.

Image rendering only works in graphics-capable terminals (kitty, wezterm,
ghostty; on macOS iTerm2 also works). Default Windows Terminal in WSL and
macOS Terminal.app won't render plots — that's a terminal limitation, not
a config bug.

### macOS ImageMagick has no fonts by default
brew's `imagemagick` formula ships an **empty** master `type.xml`
(`/opt/homebrew/etc/ImageMagick-7/type.xml`) — `magick -list font` returns
zero registered fonts. Any path that needs to render text or rasterise an
SVG with `<text>` blows up with `magick: unable to read font ''`.
image.nvim's `magick_cli` processor hits this when converting an SVG
(referenced from a markdown image, or sometimes during its own setup
probe), surfacing as a "Lua callback" error in `:Noice errors` like:

    .../image.nvim/lua/image/processors/magick_cli.lua:76:
    magick: unable to read font `' @ error/annotate.c/RenderFreetype/1660.

The script works around this in two coordinated pieces (macOS only —
Linux's apt imagemagick pulls in fonts via ghostscript and is fine):
1. Section 5b writes `~/.config/ImageMagick-7/type.xml` registering a
   handful of macOS system fonts (Helvetica, Menlo) so ImageMagick has
   a non-empty default font list.
2. The managed block in `options.lua` sets
   `vim.env.MAGICK_CONFIGURE_PATH = "$HOME/.config/ImageMagick-7:$BREW_PREFIX/etc/ImageMagick-7"`
   inside nvim. Brew's IM does **not** auto-search `~/.config`, so this
   env var is what makes our type.xml visible. Setting it inside nvim
   (rather than in a shell rc) means image.nvim's spawned `magick`
   subprocesses inherit it regardless of how nvim was launched.

If `unable to read font ''` returns: confirm the env var is set
(`:lua print(vim.env.MAGICK_CONFIGURE_PATH)`), confirm the type.xml
exists, and confirm `magick -list font` lists the registered names when
run with that env. Don't try to fix it by editing
`/opt/homebrew/etc/ImageMagick-7/type.xml` — it's a brew-managed symlink
and gets reset on every `brew upgrade imagemagick`.

On macOS, brew's `llvm` formula is keg-only (not auto-linked) so the script
symlinks `~/.local/bin/clangd -> $(brew --prefix llvm)/bin/clangd` rather
than `brew link --force llvm` (which would clobber Apple's clang/clang++
on PATH). The script also prepends `~/.local/bin` to PATH in `~/.bashrc`
and `~/.zshrc` if the entry is missing, since unlike Ubuntu, macOS doesn't
auto-add it. If a future task is "clangd LSP not attaching on macOS", the
first thing to check is `which clangd` from the same shell that launches
nvim — `~/.local/bin` may not be on the user's PATH yet.

If nvim is launched inside tmux, image.nvim additionally requires tmux's
`allow-passthrough on` (tmux 3.3+); without it `:checkhealth image.nvim`
errors with "tmux does not have allow-passthrough enabled" and plots never
render. The script manages a fenced block in `~/.tmux.conf` (using `#` as
the comment prefix via `update_managed_block`) that sets
`allow-passthrough on` and `visual-activity off`, and runs
`tmux source-file` so live sessions pick the change up. The block is only
written if `tmux` is on PATH and the version is >=3.3 — older tmux silently
skips, since the option doesn't exist there. If a future task is "image.nvim
fails inside tmux" or "molten plots don't show under tmux", check that
managed block first.
