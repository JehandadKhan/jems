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
- **Shell prompt + multiplexer**: `starship` (cross-shell prompt) and
  `tmux` with clipboard helpers (`xclip` + `wl-clipboard` on Linux; pbcopy
  is built into macOS)
- **JetBrainsMono Nerd Font** (or any other nerd font via `NERD_FONT_NAME`)
  for the icons starship / lualine / the tmux status bar use

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
| `INSTALL_CHEZMOI`      | `1`     | When `0`, skip installing chezmoi.                                              |
| `INSTALL_GH`           | `1`     | When `0`, skip installing the GitHub CLI (`gh`).                                |
| `INSTALL_BW`           | `1`     | When `0`, skip installing the Bitwarden CLI (`bw`).                             |
| `INSTALL_TMUX`         | `1`     | When `0`, skip installing tmux + clipboard helpers (xclip / wl-clipboard on Linux). |
| `INSTALL_STARSHIP`     | `1`     | When `0`, skip installing the starship prompt.                                  |
| `INSTALL_NERD_FONT`    | `1`     | When `0`, skip installing the nerd font.                                        |
| `NERD_FONT_NAME`       | `JetBrainsMono` | Which nerd font to install. Must match a release-asset name at [ryanoasis/nerd-fonts](https://github.com/ryanoasis/nerd-fonts/releases) (e.g. `FiraCode`, `Hack`, `Meslo`, `Iosevka`). On macOS it's mapped to brew cask `font-<kebab>-nerd-font`. |
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
  `~/.local/bin/bazel-compile-commands` helper; `starship` binary
  (Linux: `/usr/local/bin/starship`; macOS: brew); `tmux`; nerd font in
  `~/.local/share/fonts/<Font>NerdFont/` on Linux (user-local) or via
  brew cask on macOS (system-wide).

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

## Shell prompt, tmux, fonts

The script installs the **binaries**; the chezmoi config supplies the
**configuration**. To get the full experience you need both halves.

### Starship (shell prompt)

Linux installs starship to `/usr/local/bin/starship` via the official
`sh.starship.rs` installer (re-runs upgrade in place). macOS uses
`brew install starship`. The binary does nothing until your shell rc
runs `eval "$(starship init bash)"` (or `zsh`), which is the chezmoi'd
shell rc's job. Theme lives at `~/.config/starship.toml` (also
chezmoi-managed).

### tmux

Linux: `apt install tmux` + `xclip` + `wl-clipboard`. macOS: `brew install
tmux` (pbcopy is built in). The status bar styling, key bindings, and
`set -gq allow-passthrough on` (which image.nvim needs) all live in the
chezmoi'd `~/.tmux.conf`.

**Clipboard**: the chezmoi config turns on `set -s set-clipboard on` so
copies in tmux copy-mode (`prefix [`, select with `v`, yank with `y`)
land on the system clipboard via OSC 52 in modern terminals
(kitty / wezterm / ghostty / iTerm2 / Alacritty) — works over ssh, no
helper needed. The xclip / wl-clipboard binaries are the fallback for
terminals that don't honor OSC 52 (stock xterm, some VTE emulators);
the chezmoi'd config binds `y` to pipe through whichever helper is
present.

### Nerd font

The icons starship / lualine / the tmux status bar use only render if
your **terminal emulator's font** is a nerd font.

- Linux: this script drops `.ttf` files under
  `~/.local/share/fonts/<Font>NerdFont/` (user-local) and runs
  `fc-cache`. Default font: **JetBrainsMono Nerd Font** (override with
  `NERD_FONT_NAME=FiraCode`, `Hack`, `Meslo`, `Iosevka`, …). Pinned to
  release `v3.4.0` so re-runs across machines land on the same version.
- macOS: brew cask install (`font-jetbrains-mono-nerd-font`), system-wide.

Then set the font in your terminal preferences (kitty: `font_family` in
`kitty.conf`; ghostty / wezterm: their config files; iTerm2 /
Terminal.app: Preferences → Profiles → Text). Without this last step,
the binary is installed but starship still renders tofu.

If you don't want the nerd font, set `INSTALL_NERD_FONT=0` and replace
the chezmoi'd `~/.config/starship.toml` with the no-icons preset
(`starship preset plain-text-symbols -o ~/.config/starship.toml`).

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

Sanity check on a new repo: open a source file, then `:LspInfo` (should
list `clangd` or `basedpyright`) and `:checkhealth lsp`.

## File explorer (mini.files)

The chezmoi'd config enables LazyVim's `editor.mini-files` extra and
rebinds `<leader>e` to it, **replacing the default neo-tree sidebar**.
mini.files is a miller-columns explorer — each directory you descend
into opens as a new floating column to the right, so it looks like
cascading windows rather than a single tree pane. That's the intended
UI, not a misconfiguration.

Open:

| Key            | Opens mini.files at                  |
| -------------- | ------------------------------------ |
| `<leader>e`    | directory of the current buffer      |
| `<leader>E`    | current working directory            |
| `<leader>fm`   | LazyVim-detected project root        |

Inside mini.files (defaults from the plugin — verified against
`mini.files.lua` `MiniFiles.config.mappings`):

| Key       | Action                                                |
| --------- | ----------------------------------------------------- |
| `l`       | Enter directory / open file (`go_in`)                 |
| `L`       | `go_in_plus` — enter and close the explorer on a file |
| `h` / `H` | Go up one column (`go_out` / `go_out_plus`)           |
| `<BS>`    | Reset focus to the initial directory                  |
| `@`       | Reveal cwd                                            |
| `<` / `>` | Trim columns to the left / right of the focused one   |
| `m`       | Set a bookmark on the focused directory               |
| `'`       | Jump to a bookmark                                    |
| `=`       | Synchronize pending edits to the filesystem           |
| `g?`      | Show help                                             |
| `q`       | Close                                                 |

File manipulation is done by **editing the explorer buffer like text** and
then pressing `=` to commit:

- **Create a file**: open a new line and type the filename, then `=`.
- **Create a directory**: type the name with a trailing `/`, then `=`.
- **Rename**: edit the existing filename text, then `=`.
- **Delete**: delete the line (`dd`), then `=`.
- **Copy / move**: yank a line (`yy`) or cut it (`dd`), paste it in
  another column (`p`), then `=`. mini.files infers copy vs. move from
  whether the original line still exists.

There's no built-in "toggle hidden files" mapping — it's a config option
(`content.filter`); add a custom keymap if you need it.

To switch back to a tree-style sidebar: remove
`lazyvim.plugins.extras.editor.mini-files` from `lazyvim.json` and
delete `lua/plugins/extend-mini-files.lua` (both chezmoi-managed), then
optionally enable `lazyvim.plugins.extras.editor.neo-tree`. Update this
section if you do — it's the cheat sheet for the current setup.

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
