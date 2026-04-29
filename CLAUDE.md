# jems — repo notes for Claude

This repo is a single-file Bash installer (`install-lazyvim.sh`) that sets up
Neovim + LazyVim + LSPs + a Jupyter notebook stack on a fresh Ubuntu/WSL2
machine, and is also re-runnable to bring an existing install up to date.

## Single source of truth
Everything lives in `install-lazyvim.sh`. There is no Ansible, no Makefile,
no separate Lua repo. Lua plugin specs are written into `~/.config/nvim/lua/`
by heredocs inside the script itself. If you find yourself wanting to add a
second file, push back — keep the install path one curl-able script.

## Re-run contract
The script is designed to be run repeatedly on the same box:
- apt / node / nvim / fzf / clangd / pyright / venv steps are idempotent.
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
  end up owned by root.
- Comments at the top of the script enumerate every persistent system
  change (apt sources, alternatives, etc.) and how to undo them. Keep that
  list accurate when you add steps.

## Testing changes
There is no CI. Validate with:
```
bash -n install-lazyvim.sh        # syntax
shellcheck install-lazyvim.sh     # if available
```
For end-to-end testing, the cheap path is a throwaway WSL distro or a
Docker container running Ubuntu 22.04. The script is destructive (touches
apt sources, /usr/local, /usr/bin alternatives) so don't smoke-test it on
a machine you care about.

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
`ft = { python, markdown, quarto }` to lazy-load, which means a plain
`nvim --headless +UpdateRemotePlugins` registers nothing — molten isn't
in `runtimepath` yet, so the manifest comes out empty. The install script
works around this with `nvim --headless +'Lazy! load molten-nvim'
+UpdateRemotePlugins +qa` and then greps the manifest for "molten" to
verify. If a future task is "Not an editor command: MoltenInit", the
remote-plugin manifest is the first place to look — `cat
~/.local/share/nvim/rplugin.vim` and check for the molten registration
block. Don't relax the `ft` gate to "fix" this; force-loading during
registration is the right shape.

Image rendering only works in graphics-capable terminals (kitty, wezterm,
ghostty). Default Windows Terminal in WSL won't render plots — that's a
terminal limitation, not a config bug.

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
