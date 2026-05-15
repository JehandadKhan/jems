# jems cheat sheet

Editor key bindings and workflows for the Neovim + LazyVim + Jupyter stack
that `install-lazyvim.sh` (plus the chezmoi'd config) sets up. See
[README.md](README.md) for install instructions.

## Code navigation

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
