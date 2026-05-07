# jems

One Bash script that installs the **system-level prerequisites** for a
Neovim + LazyVim + Jupyter notebook stack on **Ubuntu 22.04 / WSL2** or
**macOS 14+** (Apple Silicon or Intel):

- **Neovim ≥ 0.11.2** (built from source on Linux, brew on macOS)
- **LSPs**: clangd-18 (C/C++) and basedpyright (Python)
- **Jupyter prerequisites** for molten-nvim + jupytext.nvim + image.nvim:
  Python venv at `~/.local/share/nvim-venv` with pynvim, jupyter_client,
  ipykernel, jupytext; ImageMagick; `~/.local/bin/jupytext` symlink
- **Bazel → clangd**: a `bazel-compile-commands` helper that produces
  `compile_commands.json` for any Bazel workspace (XLA, JAX/jaxlib, TF, …)
- **fzf**, ripgrep, Node.js 20, the **Claude Code** CLI

Dotfiles (`~/.config/nvim/**`, `~/.tmux.conf`, `~/.bashrc`/`~/.zshrc`,
`~/.config/ImageMagick-7/type.xml`, etc.) are managed separately via
**chezmoi** and are **not** touched by this script. The script installs
binaries; chezmoi installs config.

The same script installs from scratch on a new machine and updates an
existing install when re-run.

## Install

Linux (Ubuntu / WSL2) — invoke via `sudo`. Run from your normal user
account so `$SUDO_USER` resolves to whoever's home should be populated;
or, in a container / bare VPS / WSL distro where root is the only user,
just run as root and the script installs into root's home. Use
`TARGET_USER=<user>` to override.

```bash
sudo bash install-lazyvim.sh
```

macOS — Homebrew must already be installed (https://brew.sh); do **not**
sudo, since brew refuses to run as root:

```bash
bash install-lazyvim.sh
```

Then apply your chezmoi config so `~/.config/nvim/`, `~/.tmux.conf`, and
your shell rc files are in place. Open a new shell (so PATH and the fzf
hook load), then run `nvim` once — lazy.nvim bootstraps plugins on first
launch and fires molten's `:UpdateRemotePlugins` build hook.

## Re-run to update

Re-run the same command. Re-runs upgrade Python packages in the nvim venv
(`~/.local/share/nvim-venv`), refresh the bazel-compile-commands extractor
clone, and re-`npm i -g` the npm-installed CLIs (basedpyright, Claude
Code). Brew/apt installs are gated on whether the formula/package is
already present, so we don't gratuitously upgrade pinned versions.

## Toggles

All flags are environment variables.

| Var                    | Default | Effect                                                                          |
| ---------------------- | ------- | ------------------------------------------------------------------------------- |
| `LINK_VIM`             | `1`     | Alias `vim` and `vi` to `nvim`. Set `0` to skip.                                |
| `SKIP_NVIM_BUILD`      | `0`     | (Linux only) When `1`, don't rebuild Neovim from source even if the version check would. |
| `INSTALL_BAZEL_HELPER` | `1`     | When `0`, skip the bazel-compile-commands extractor + `bazel-compile-commands` helper. |
| `INSTALL_CLAUDE`       | `1`     | When `0`, skip the Claude Code CLI.                                             |
| `TARGET_USER`          | (auto)  | (Linux only) Force the target user when `$SUDO_USER` isn't set (e.g. running as root in a container). |

Example — re-run, skip the bazel helper:

```bash
sudo INSTALL_BAZEL_HELPER=0 bash install-lazyvim.sh
```

## Persistent system changes

Full list in the comment block at the top of `install-lazyvim.sh`. The
short version:

- **Linux**: apt sources for `apt.llvm.org` (clangd-18) and
  `deb.nodesource.com` (Node 20), keys in `/etc/apt/keyrings/`; Neovim
  built into `/usr/local/bin/nvim`; update-alternatives entries for
  `/usr/bin/clangd` (and `/usr/bin/{vim,vi}` if `LINK_VIM=1`).
- **macOS**: brew formulae installed only if missing (never upgraded out
  from under you); `~/.local/bin/clangd` symlink to brew's keg-only
  `llvm`. `~/.local/bin` must be on PATH for clangd / jupytext / vim to
  resolve — the chezmoi'd shell rc is expected to put it there.
- **Both**: `basedpyright` and Claude Code CLI via `npm i -g`; `fzf`
  cloned to `~/.fzf` and installed with `--no-update-rc` (chezmoi'd shell
  rc sources `~/.fzf.bash` / `~/.fzf.zsh`); Python venv at
  `~/.local/share/nvim-venv` for molten-nvim; bazel-compile-commands
  extractor at `~/.local/share/bazel-compile-commands-extractor` plus a
  `~/.local/bin/bazel-compile-commands` helper.

To remove the Linux-only apt sources later:

```bash
sudo rm /etc/apt/sources.list.d/llvm-18.list /etc/apt/keyrings/llvm.gpg
sudo rm /etc/apt/sources.list.d/nodesource.list
```

## Bazel C++ workflows: clangd + compile_commands.json

clangd's accuracy on Bazel-built C++ depends on a `compile_commands.json`
at the workspace root — Bazel doesn't produce one natively. The
`bazel-compile-commands` helper installed by this script wires
[hedronvision/bazel-compile-commands-extractor](https://github.com/hedronvision/bazel-compile-commands-extractor)
into any Bazel workspace and runs the extraction.

```bash
cd /path/to/xla        # or jax, tf, …
bazel-compile-commands //xla/...    # scope the build label set; default is //...
```

First run on a large repo (XLA: ~50k entries) takes 10-30 min. Re-run
after BUILD-file changes; source-only edits don't need a re-run. Remove
the wiring this helper added (managed `MODULE.bazel` block + `tools/clangd/`)
with `bazel-compile-commands --clean`.

### Caveat: XLA / TF emit combined `-isystem` args

XLA's Bazel toolchain emits stdlib `-isystem` flags as single argv
strings (`"-isystem external/sysroot_..."`) instead of separate tokens.
Bazel copes because its clang wrapper word-splits via unquoted `$@`, but
**clangd doesn't tokenize** — so it silently drops every libstdc++ /
clang resource-dir include path, and `<vector>`, `<string>`, etc. fail
to resolve. Symptoms: red-squiggly stdlib includes, no go-to-definition
into headers, "Lua callback" / "use of undeclared identifier" diagnostics
on standard types.

Fix by post-processing the JSON to split any argv entry beginning with
`-isystem `, `-iquote `, `-isysroot `, or `-I ` into two tokens, then
`:LspRestart` in nvim:

```python
# fix-bazel-isystem.py — run from the workspace root
import json, sys
PFX = ('-isystem ', '-iquote ', '-isysroot ', '-I ')
path = sys.argv[1] if len(sys.argv) > 1 else 'compile_commands.json'
with open(path) as f: data = json.load(f)
for e in data:
    out = []
    for a in e.get('arguments', []):
        if isinstance(a, str) and a.startswith(PFX):
            head, _, tail = a.partition(' ')
            out += [head, tail]
        else:
            out.append(a)
    e['arguments'] = out
with open(path, 'w') as f: json.dump(data, f)
```

## Code navigation cheatsheet

The script enables `clangd` and `basedpyright` against LazyVim defaults —
no custom LSP keymaps. The bindings you'll reach for most:

| Action                              | Key                  |
| ----------------------------------- | -------------------- |
| Go to definition                    | `gd`                 |
| Go to declaration                   | `gD`                 |
| References (list usages)            | `gr`                 |
| Implementations                     | `gI`                 |
| Type definition                     | `gy`                 |
| Hover docs                          | `K`                  |
| Signature help (insert mode)        | `<C-k>`              |
| Rename                              | `<leader>cr`         |
| Code action                         | `<leader>ca`         |
| Jump back / forward in nav stack    | `<C-o>` / `<C-i>`    |
| Document symbols (file outline)     | `<leader>ss`         |
| Workspace symbols (project-wide)    | `<leader>sS`         |
| Diagnostics list (Trouble)          | `<leader>xx`         |
| Inlay hints toggle                  | `<leader>uh`         |
| Switch `.cc` ↔ `.h` (clangd)        | `:LspClangdSwitchSourceHeader` |

Project-wide file / text search (Telescope / Snacks picker):

| Action                              | Key                  |
| ----------------------------------- | -------------------- |
| Fuzzy-find files                    | `<leader><space>`    |
| Live grep                           | `<leader>/`          |
| Grep word under cursor              | `<leader>sw`         |
| Recent files                        | `<leader>fr`         |
| File tree                           | `<leader>e`          |

Sanity check on a new repo: open a source file, then `:LspInfo` (should
list `clangd` or `basedpyright`) and `:checkhealth lsp`.

## Jupyter workflow

Open an `.ipynb` file in Neovim and `jupytext.nvim` converts it on the
fly to a hydrogen-style Python buffer (`# %%` cell markers). On `:w` it
saves back to `.ipynb`.

Default molten keymaps (set in the chezmoi'd `lua/plugins/molten.lua`):

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
**wezterm**, **ghostty**, or (on macOS) **iTerm2**. In other terminals
(default Windows Terminal, GNOME Terminal, macOS Terminal.app, etc.)
text output and DataFrames still display fine; only inline image
previews are disabled. Inside tmux you also need `allow-passthrough on`
in `~/.tmux.conf` (the chezmoi'd tmux config sets this).

## Caveats

- Linux path is tuned for Ubuntu 22.04 (jammy) / WSL2; other Debian-based
  releases will probably work but aren't tested. The clangd repo line is
  built from `lsb_release -cs`, so a non-jammy codename pulls a different
  LLVM toolchain.
- This script does not write any dotfiles, so on a fresh box the LSP
  keymaps and molten/jupytext bindings only appear after you apply your
  chezmoi config. If `:LspInfo` shows nothing or `:MoltenInit` is
  undefined after `nvim` bootstrap, that's almost always a missing
  chezmoi apply rather than a broken install.
