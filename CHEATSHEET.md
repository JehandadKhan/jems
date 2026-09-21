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

## Code review (octo.nvim + diffview.nvim)

The chezmoi'd config enables LazyVim's `util.octo` extra (octo.nvim,
wired to the fzf-lua picker) plus `lua/plugins/code-review.lua`
(diffview.nvim). octo authenticates through the `gh` CLI that the
installer provisions — no extra token setup.

**GitHub PR / issue review (octo).** The full flow lives in nvim buffers:

| Action                              | Command / Key        |
| ----------------------------------- | -------------------- |
| List PRs                            | `:Octo pr list`      |
| List issues                         | `:Octo issue list`   |
| Start a review on the open PR       | `:Octo review start` |
| Add an inline comment (cursor line) | `:Octo comment add`  |
| Add an inline comment (range)       | visual-select, `:Octo comment add` |
| Submit the review (approve / comment / request-changes) | `:Octo review submit` |
| Discard the in-progress review      | `:Octo review discard` |

octo also registers `<leader>g` keymaps from the extra: `<leader>gi` list
issues, `<leader>gI` search issues, `<leader>gp` list PRs, `<leader>gP`
search PRs, `<leader>gr` list repos, `<leader>gS` search. `:Octo` with no
args lists every subcommand.

**Diff / file-history viewer (diffview).** Standalone side-by-side diffs
of any git revision — also the UI octo drops you into during a review.
All under the `<leader>gv` ("view") group, chosen to avoid clashes:
`gd`/`gD` are LSP go-to-definition/declaration (see Code navigation
above) and `<leader>gd`/`<leader>gD` are the fzf-lua git-diff pickers, so
diffview gets its own namespace.

| Action                              | Key                  |
| ----------------------------------- | -------------------- |
| Open diffview (working tree vs HEAD)| `<leader>gvo`        |
| Close diffview                      | `<leader>gvc`        |
| File history of current file        | `<leader>gvh`        |
| File history of the whole branch    | `<leader>gvH`        |

Inside diffview: `<Tab>` / `<S-Tab>` cycle changed files, `g?` shows the
plugin's help. To diff against an arbitrary ref, call the command
directly, e.g. `:DiffviewOpen origin/main...HEAD` or
`:DiffviewOpen HEAD~3`.

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

### Picking a kernel

`<leader>mi` (bare `:MoltenInit`) opens a kernel picker. It lists
kernelspec **directory names, not display names** — a kernel registered as
`--name su_venv --display-name "Python (OpenAI SpinningUP)"` shows up only
as `su_venv`. That's the usual "my kernel isn't in the list". `:NotebookKernels`
prints both columns.

Register a project kernel so the nvim venv can see it (`--user` matters;
`kernel.json` hardcodes the interpreter, so it still runs in the project venv):

```bash
/path/to/project/.venv/bin/python -m ipykernel install --user \
    --name myproj --display-name "My Project"
```

Debugging: query **the nvim venv's** jupyter, not brew's — that's the search
path molten uses. `~/.local/share/nvim-venv/bin/jupyter kernelspec list`,
and `jupyter --paths` for the dirs being searched.

### Connecting

`:MoltenInit` dispatches on the shape of its argument:

| Form                                      | What it does                                   |
| ----------------------------------------- | ---------------------------------------------- |
| `:MoltenInit` (no args)                   | Picker of available + running kernels          |
| `:MoltenInit su_venv`                     | Launch that kernelspec by directory name       |
| `:MoltenInit /path/to/kernel-<id>.json`   | Attach to an **already-running** kernel        |
| `:MoltenInit https://host:8888`           | Talk to a Jupyter **server** over its REST API |
| `:MoltenInit shared <kernel_id>`          | Reuse a kernel already running in this nvim    |

To share a live session with JupyterLab, point molten at the connection
file — `ls -t ~/Library/Jupyter/runtime/kernel-*.json` (newest first).
Variables are visible in both; it's one kernel process. These count as
*external* kernels, so `:MoltenDeinit` detaches without killing them.

### Running things

| Key / Command           | Action                                      |
| ----------------------- | ------------------------------------------- |
| `<leader>mi`            | Initialize a Jupyter kernel                 |
| `<leader>mc`            | Run the `# %%` cell under the cursor        |
| `<leader>mn`            | Run the cell, then jump to the next one     |
| `<leader>ml`            | Evaluate the current line                   |
| `<leader>me`            | Evaluate over a motion (e.g. `<leader>meip`)|
| `<leader>mv`            | Evaluate visual selection                   |
| `<leader>mr`            | Re-evaluate current cell (runs it if new)   |
| `<leader>mR`            | Re-evaluate every cell in the buffer        |
| `<leader>mo`            | Enter the output window                     |
| `<leader>mh`            | Hide output (float + inline)                |
| `<leader>mt`            | Toggle inline virtual-text output           |
| `<leader>md`            | Delete cell                                 |
| `:MoltenNext` / `:MoltenPrev` | Jump between cells that have output   |
| `:MoltenInterrupt`      | Send `SIGINT` to a runaway cell             |
| `:MoltenRestart`        | Restart the kernel (add `!` to also clear)  |
| `:MoltenInfo`           | Show attached kernels and their status      |
| `:MoltenDeinit`         | Detach (leaves an external kernel running)  |

#### "Not in a cell"

Molten has no idea what `# %%` means. A *cell*, to molten, is an
extmark-backed span created by an evaluate call, and `<leader>mr`
(`:MoltenReevaluateCell`) looks for a span containing the cursor — so
re-evaluating a cell you have never run errors with `Not in a cell`.
`<leader>mc` is what turns the `# %%` block under the cursor into such a
span; `<leader>mr` falls back to it automatically, so in practice either
key works. `:MoltenInfo` lists the spans molten is actually tracking.

The spans are extmarks, so they do not survive reopening the file: the
`# %%` markers come back but the tracking does not. Re-run the cell, or
persist the session with `:MoltenSave` / `:MoltenLoad`.

#### Hiding output

`<leader>mh` hides both the floating window and the inline text.
`:MoltenHideOutput` on its own only hides the *float* — with
`molten_virt_text_output` on (our default), molten repaints the inline
text on every interface update, including the one `:MoltenHideOutput`
itself triggers. `<leader>mt` toggles inline output off and on; toggling
it back on **re-runs the cells**, because molten exposes no way to
repaint virtual text without re-executing.

### Outputs and saving

Molten keeps outputs **in memory**, and jupytext writes back only code — so
a plain `:w` leaves `"outputs": []` in the `.ipynb`.

| Command                | Action                                         |
| ---------------------- | ---------------------------------------------- |
| `:MoltenExportOutput`  | Write molten's outputs into the `.ipynb`       |
| `:MoltenImportOutput`  | Load outputs from the `.ipynb` back into molten|
| `:MoltenSave` / `:MoltenLoad` | Persist molten's own session state       |

`:MoltenImportOutput` needs the kernel initialized and the cell structure to
still match the file.

### Creating a new notebook

```bash
nvim analysis.ipynb                    # just works — seeded on the fly
```

```vim
:NotebookNew analysis.ipynb            " same, but pick a kernel interactively
:NotebookNew analysis.ipynb su_venv    " or name one up front
```

Opening a nonexistent `.ipynb` seeds it before jupytext reads it: a
markdown cell with a one-glance cheatsheet (cell syntax + the molten keys
below), an empty code cell, and the default kernel (first kernelspec
alphabetically). Delete the markdown cell once the keys are muscle memory.
`:NotebookNew` is the version that lets you choose; it also appends the
`.ipynb` extension, creates missing parent dirs, and opens an existing
file rather than overwriting it.

Both go through `jupytext --to ipynb --set-kernel`. That flag is
load-bearing: a notebook with no `kernelspec` in its metadata makes
jupytext.nvim throw on open (`utils.lua:16`) and leaves you an empty
buffer. The hand-rolled equivalent:

```bash
printf '# %%%%\n' > seed.py
jupytext --to ipynb --set-kernel python3 seed.py -o new.ipynb && rm seed.py
```

Often easier: skip `.ipynb`, write a `# %%`-delimited `.py`, and pair it
when you need the notebook — much cleaner git diffs:

```bash
jupytext --set-formats ipynb,py:percent notebook.ipynb
jupytext --sync notebook.ipynb
```

The venv provides `jupyter_client` / `ipykernel`, not the JupyterLab
**server**; `jupyter lab` is a separate install. Molten only needs a kernel.

### Image rendering

Plots and other image outputs render via `image.nvim`, which needs a
terminal that speaks the Kitty graphics protocol — that means **kitty**,
**wezterm**, **ghostty**, or (on macOS) **iTerm2**. In other terminals
(default Windows Terminal, GNOME Terminal, macOS Terminal.app, etc.)
text output and DataFrames still display fine; only inline image
previews are disabled. Inside tmux you also need `allow-passthrough on`
in `~/.tmux.conf` (the chezmoi'd tmux config sets this).

### When `:MoltenInit` is undefined

molten is a python remote plugin — its commands only exist after
`:UpdateRemotePlugins` writes `~/.local/share/nvim/rplugin.vim`. If the
commands are missing, grep that file for `molten`; an absent block means
pynvim isn't reachable from `vim.g.python3_host_prog`. Check
`:checkhealth provider.python` — it should point at
`~/.local/share/nvim-venv/bin/python`.

### When completion in a notebook only offers words from the file

That is nvim-cmp falling back to its `buffer` source because **no LSP is
attached**. Check with `:lua =#vim.lsp.get_clients({bufnr=0})` inside the
notebook — `0` means the language server never started for that buffer.

The cause is a load-order trap: LazyVim lazy-loads `nvim-lspconfig` on
`BufReadPre`, but jupytext registers a `BufReadCmd` for `*.ipynb`, and a
`*Cmd` autocmd *takes over* the read — so `BufReadPre` never fires and
lspconfig is never loaded. The chezmoi'd `private_jupytext.lua` works
around this by force-loading lspconfig and re-firing `FileType` once the
buffer has been converted. If it regresses, note that the workaround needs
**two** entry points: `BufReadPost`/`BufAdd` for `:edit foo.ipynb`, and a
`VimEnter` + `vim.fn.argv()` sweep for `nvim foo.ipynb`, where the file is
read before any lazy-loaded plugin can register an autocmd. Testing only
the `:edit` path will look like success while the command-line path stays
broken.

Completions resolve against the interpreter basedpyright picks, so a venv
that is not discoverable from the project root gives stdlib completions but
none for third-party packages. Launch nvim from the project root.

## PDF viewing (pdfreader.nvim)

Just `nvim file.pdf` — the plugin hooks `BufEnter` on `*.pdf` and renders
the page, so there's no command to run first. Pages are rasterized with
ImageMagick (which shells out to ghostscript) and displayed through
`snacks.image`; `poppler` supplies the page count and the text mode.

| Key | Action                          |
| --- | ------------------------------- |
| `n` | Next page                       |
| `p` | Previous page                   |
| `z` | Zoom in                         |
| `q` | Zoom out (**not** quit)         |
| `e` | Zoom reset                      |

`q` is bound to zoom-out inside a PDF buffer, so use `:q` to close.

If `n` gives you `E486: Pattern not found` instead of turning the page,
pdfreader didn't attach to the buffer and `n` is still Vim's next-match.
Check `:lua print(vim.bo.filetype)` — it should say `pdf`; `markdown`
means `snacks.image` grabbed the file first. See the PDF section in
CLAUDE.md for the two spec settings that prevent this.

| Command                                     | Action                     |
| ------------------------------------------- | -------------------------- |
| `:PDFReader setViewMode {standard,dark,text}` | Switch render mode       |
| `:PDFReader setPage {n}`                    | Jump to page               |
| `:PDFReader showToc`                        | Table of contents          |
| `:PDFReader addBookmark [{n}][,comment]`    | Bookmark a page            |
| `:PDFReader showBookmarks`                  | Bookmark picker            |
| `:PDFReader showRecentBooks`                | Recently opened PDFs       |
| `:PDFReader redrawPage`                     | Re-render current page     |
| `:PDFReader setAutosave {on,off}`           | Toggle state autosave      |
| `:PDFReader saveState` / `clearState`       | Force save / wipe state    |

`setViewMode dark` inverts to a dark background — the one to use on
white-background papers. `setViewMode text` swaps the rendered page for
`pdftotext` output: no images and layout is approximated with spaces,
but it's searchable, yankable, and works in any terminal (including over
ssh). Text mode returns nothing on scanned PDFs, which have no text
layer to extract.

**Use kitty.** Rendering needs the Kitty graphics protocol *plus* its
unicode-placeholder extension, which anchors images to cells in the text
grid so the terminal clips them correctly. kitty and ghostty support
placeholders; **wezterm does not** (see `placeholders = false` in
snacks' `lua/snacks/image/terminal.lua`). Without them snacks falls back
to absolute positioning and pages get painted over the statusline,
splits, and tabline, with tmux making it worse. That's a terminal
capability gap, not a config error — text mode still behaves fine
everywhere.

Note pdfreader's own `validation.lua` hardcodes a `{ "kitty", "ghostty" }`
allowlist and matches it against `$TERM`, which fails inside tmux
(`$TERM=tmux-256color`) even in kitty. The chezmoi'd
`lua/plugins/pdfreader.lua` overrides that check to delegate to snacks'
terminal detection instead, which handles the tmux passthrough case.

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
