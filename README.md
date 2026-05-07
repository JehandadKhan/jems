# jems

One Bash script that sets up a Neovim + LazyVim development environment on
**Ubuntu 22.04 / WSL2** or **macOS 14+** (Apple Silicon or Intel), including:

- **Neovim ≥ 0.11.2** (built from source on Linux, brew on macOS)
- **LazyVim** starter config
- **LSPs**: clangd-18 (C/C++) and basedpyright (Python)
- **Jupyter notebooks inside Neovim**: molten-nvim + jupytext.nvim + image.nvim
- **Bazel → clangd**: a `bazel-compile-commands` helper that produces
  `compile_commands.json` for any Bazel workspace (XLA, JAX/jaxlib, TF, …)
- **fzf**, ripgrep, Node.js 20, the **Claude Code** CLI

The same script installs from scratch on a new machine and updates an
existing install when re-run.

## Install

Linux (Ubuntu / WSL2) — must be invoked via `sudo` from a normal user
account; the script needs `$SUDO_USER` to know whose home to populate:

```bash
sudo bash install-lazyvim.sh
```

macOS — Homebrew must already be installed (https://brew.sh); do **not**
sudo, since brew refuses to run as root:

```bash
bash install-lazyvim.sh
```

Then open a new shell (so the `~/.bashrc` / `~/.zshrc` fzf hook loads) and
run `nvim`. LazyVim will bootstrap any remaining plugins on first launch.

## Re-run to update

Re-run the same command. Re-runs upgrade Python packages in the nvim venv
(`~/.local/share/nvim-venv`), rewrite the managed Lua plugin specs under
`~/.config/nvim/lua/plugins/`, and sync plugins via
`nvim --headless +Lazy! sync` (which also re-registers molten via its
`build = ":UpdateRemotePlugins"` hook).

Your LazyVim config directory is **preserved by default** — plugin
lockfile, non-managed Lua files, and any custom changes survive. Set
`FORCE_LAZYVIM=1` to wipe `~/.config/nvim` and re-clone the starter
(existing files are saved as `*.bak.<timestamp>`).

## Toggles

All flags are environment variables.

| Var                    | Default | Effect                                                                          |
| ---------------------- | ------- | ------------------------------------------------------------------------------- |
| `LINK_VIM`             | `1`     | Alias `vim` and `vi` to `nvim`. Set `0` to skip.                                |
| `FORCE_LAZYVIM`        | `0`     | When `1`, wipe `~/.config/nvim`, `~/.local/share/nvim`, etc. and re-clone the LazyVim starter. |
| `UPDATE_PLUGINS`       | `1`     | When `0`, skip the trailing `nvim --headless +Lazy! sync`.                      |
| `SKIP_NVIM_BUILD`      | `0`     | (Linux only) When `1`, don't rebuild Neovim from source even if the version check would. |
| `INSTALL_BAZEL_HELPER` | `1`     | When `0`, skip the bazel-compile-commands extractor + `bazel-compile-commands` helper. |
| `INSTALL_CLAUDE`       | `1`     | When `0`, skip the Claude Code CLI.                                             |

Example — re-run, leave the LazyVim config alone, skip plugin updates:

```bash
sudo UPDATE_PLUGINS=0 bash install-lazyvim.sh
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
  `llvm`; `~/.local/bin` prepended to PATH in your shell rc.
- **Both**: `basedpyright` and Claude Code CLI via `npm i -g`; `fzf` at
  `~/.fzf` with one rc-file line; Python venv at
  `~/.local/share/nvim-venv` for molten-nvim; bazel-compile-commands
  extractor at `~/.local/share/bazel-compile-commands-extractor`; tmux
  `allow-passthrough on` block in `~/.tmux.conf` (required by image.nvim
  inside tmux).

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
**wezterm**, **ghostty**, or (on macOS) **iTerm2**. In other terminals
(default Windows Terminal, GNOME Terminal, macOS Terminal.app, etc.)
text output and DataFrames still display fine; only inline image
previews are disabled. Inside tmux you also need `allow-passthrough on`,
which the script writes into a managed block in `~/.tmux.conf`.

## Caveats

- Linux path is tuned for Ubuntu 22.04 (jammy) / WSL2; other Debian-based
  releases will probably work but aren't tested. The clangd repo line is
  built from `lsb_release -cs`, so a non-jammy codename pulls a different
  LLVM toolchain.
- Re-running on a machine originally installed with a much older version
  of this script may produce one-time `*.bak.<timestamp>` files in
  `~/.config/nvim/lua/plugins/` the first time the new script claims
  ownership of those files. Review and delete once you're satisfied.
