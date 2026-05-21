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

## carbonyl (Chromium-in-the-terminal browser)

`carbonyl URL` renders any web page directly in the terminal (great for
a tmux pane next to nvim). The chezmoi'd bashrc/zshrc aliases the
command to pin `--user-data-dir="$HOME/.local/share/carbonyl-profile"`
so cookies, logins, and history persist across restarts.

Carbonyl v0.0.3 has a **minimal** keymap — no address bar, no tab UI,
no find-on-page. The browser is intentionally close to "headless
Chromium with a TUI viewport." Confirmed bindings (from
`src/input/parser.rs` upstream):

| Key             | Action                                          |
| --------------- | ----------------------------------------------- |
| `Ctrl+C`        | Quit (the only quit key — not `Ctrl+Q`)         |
| `Alt+←` / `Alt+→` | Back / forward                                |
| `←` `→` `↑` `↓` | Scroll the page                                 |
| `Tab` / `S-Tab` | Move DOM focus (next / previous link or input)  |
| `Enter`         | Submit form / follow focused link               |
| Typing          | Goes to the focused `<input>` field             |
| Mouse click     | Click links / buttons                           |
| Mouse wheel     | Scroll                                          |

**Not implemented in v0.0.3** despite Chrome-style expectations: `Ctrl+L`
(focus address bar), `Ctrl+T` (new tab), `Ctrl+R` (reload), `Ctrl+F`
(find), `Ctrl+W` (close tab), `Ctrl+Q` (quit). They're either silently
forwarded to the page (most pages don't handle them) or eaten by the
terminal / tmux.

To go to a different URL, **quit with `Ctrl+C` and re-launch** with the
new URL, or click a link on the current page.

Useful flags (append to the alias if you want them default):

| Flag             | Effect                                                       |
| ---------------- | ------------------------------------------------------------ |
| `--zoom=80`      | Shrink to fit more content in narrow tmux panes              |
| `--fps=30`       | Cap framerate (saves CPU on heavy pages)                     |
| `--bitmap`       | Render text as bitmaps — sharper in kitty/wezterm/ghostty    |
| `--debug`        | Log to console (useful when a page hangs)                    |
| `--user-agent=…` | Any Chromium flag is passed through                          |

**What works**: most modern websites — GitHub, MDN, HN, Reddit, search
engines, dashboards. Cookies persist (via the alias), TOTP / magic-link
auth flows work fine. Mouse interaction is the primary input model.

**What doesn't**: WebAuthn / hardware keys / passkeys, browser
extensions (1Password, Bitwarden), most captchas (reCAPTCHA, Cloudflare
Turnstile). For GitHub specifically, `gh auth login` handles the OAuth
dance outside the browser; carbonyl then just renders the pages.

`vim` keybindings: carbonyl does **not** have them and the project
hasn't shipped a release since Feb 2023. If `j`/`k`/`gg` matter to you,
use `w3m` instead — same tmux-pane workflow but text-only and
configurable via `~/.w3m/keymap`.
