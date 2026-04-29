# jems

One Bash script that sets up a Neovim + LazyVim development environment on
Ubuntu 22.04 / WSL2, including:

- **Neovim stable** built from source
- **LazyVim** starter config
- **LSPs**: clangd-18 (C/C++) and pyright (Python)
- **Jupyter notebooks inside Neovim**: molten-nvim + jupytext.nvim + image.nvim
- **fzf**, ripgrep, Node.js 20, plus apt build deps

The same script installs from scratch on a new machine and updates an
existing install when re-run.

## Install

```bash
sudo bash install-lazyvim.sh
```

Then open a new shell (so the `~/.bashrc` fzf hook loads) and run `nvim`.
LazyVim will bootstrap remaining plugins on first launch.

## Update an existing install

Re-run the same command:

```bash
sudo bash install-lazyvim.sh
```

On a re-run the script:

- upgrades Python packages in the nvim venv (`~/.local/share/nvim-venv`)
- rewrites the managed Lua plugin specs under `~/.config/nvim/lua/plugins/`
  (so a newer version of this script propagates new plugin defaults)
- runs `nvim --headless +Lazy! sync` to pull plugin updates
- runs `:UpdateRemotePlugins` to re-register molten

Your LazyVim config directory is **preserved by default** — plugin lockfile,
non-managed Lua files, and any custom changes survive. To wipe everything
and re-clone the LazyVim starter, set `FORCE_LAZYVIM=1`.

## Toggles

All flags are environment variables.

| Var               | Default | Effect when set                                                                 |
| ----------------- | ------- | ------------------------------------------------------------------------------- |
| `LINK_VIM`        | `1`     | Aliases `/usr/bin/vim` and `/usr/bin/vi` to `nvim` system-wide. Set `0` to skip. |
| `FORCE_LAZYVIM`   | `0`     | When `1`, wipes `~/.config/nvim`, `~/.local/share/nvim`, etc. (with `*.bak.<timestamp>` backups) and re-clones the LazyVim starter. |
| `UPDATE_PLUGINS`  | `1`     | When `0`, skips the trailing `nvim --headless +Lazy! sync`.                      |
| `SKIP_NVIM_BUILD` | `0`     | When `1`, doesn't rebuild Neovim from source even if the version check thinks it should. |

Example: re-run, leave the LazyVim config alone, but skip plugin updates:

```bash
sudo UPDATE_PLUGINS=0 bash install-lazyvim.sh
```

## Persistent system changes

The script makes a few changes that outlive the script run. They are
listed at the top of `install-lazyvim.sh`; the highlights:

- Adds `apt.llvm.org` and `deb.nodesource.com` as apt sources (with keys
  in `/etc/apt/keyrings/`).
- Builds Neovim into `/usr/local/bin/nvim`.
- Installs `pyright` globally via `npm i -g`.
- Clones `fzf` to `~/.fzf` and appends one line to `~/.bashrc`.
- Creates a Python venv at `~/.local/share/nvim-venv` for the Neovim
  Python provider (used by molten-nvim).

To remove the apt sources later:

```bash
sudo rm /etc/apt/sources.list.d/llvm-18.list /etc/apt/keyrings/llvm.gpg
sudo rm /etc/apt/sources.list.d/nodesource.list
```

## Jupyter workflow

Open an `.ipynb` file in Neovim and `jupytext.nvim` converts it on the fly
to a hydrogen-style Python buffer (`# %%` cell markers). On `:w`, it saves
back to `.ipynb`.

Default keymaps (set by `lua/plugins/molten.lua`):

| Key            | Action                       |
| -------------- | ---------------------------- |
| `<leader>mi`   | Initialize a Jupyter kernel  |
| `<leader>ml`   | Evaluate the current line    |
| `<leader>me`   | Evaluate over a motion       |
| `<leader>mv`   | Evaluate visual selection    |
| `<leader>mr`   | Re-evaluate current cell     |
| `<leader>mo`   | Enter the output window      |
| `<leader>mh`   | Hide output                  |
| `<leader>md`   | Delete cell                  |

### Image rendering

Plots and other image outputs render via `image.nvim`, which needs a
terminal that speaks the Kitty graphics protocol — that means **kitty**,
**wezterm**, or **ghostty**. In other terminals (default Windows Terminal,
GNOME Terminal, etc.) text output and DataFrames still display fine; only
the inline image previews are disabled.

## Caveats

- Designed for Ubuntu 22.04 (jammy). Other Debian-based releases will
  probably work but aren't tested. The clangd repo line is built from
  `lsb_release -cs`, so a non-jammy codename will reach a different LLVM
  toolchain.
- Must be invoked via `sudo` from a normal user account — the script
  refuses to run as the actual root user, since it needs `$SUDO_USER` to
  know whose home directory to populate.
- Re-running on a machine that was originally installed with a much older
  version of this script may produce one-time `*.bak.<timestamp>` files in
  `~/.config/nvim/lua/plugins/` the first time the new script claims
  ownership of those files. That's expected — review and delete them once
  you're satisfied.
