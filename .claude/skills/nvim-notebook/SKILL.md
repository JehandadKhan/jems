---
name: nvim-notebook
description: Notebook stack wiring and traps (molten/pynvim venv, jupytext new-notebook seeding, notebook LSP workaround, cells-as-extmarks, cell debugger <leader>mD, inlay hints). Load when touching .ipynb/molten/jupytext behaviour.
---
# Notebook stack: jupytext.nvim + molten-nvim + image.nvim

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

Image rendering only works in graphics-capable terminals (kitty, wezterm,
ghostty; on macOS iTerm2 also works). Default Windows Terminal in WSL and
macOS Terminal.app won't render plots — that's a terminal limitation, not
a config bug.

## New-notebook creation and the notebook LSP workaround

`jupytext --to ipynb` writes **no `kernelspec`**
into notebook metadata, and jupytext.nvim's `get_ipynb_metadata`
(`lua/jupytext/utils.lua:16-17`) indexes both the `io.open` result and
`metadata.kernelspec.language` unconditionally. So a missing *or*
kernelspec-less `.ipynb` throws in jupytext's `BufReadCmd` and opens as an
empty buffer. The chezmoi'd `private_jupytext.lua` fixes both halves:
- `init()` seeds any nonexistent `.ipynb` before it is read, via
  `jupytext --to ipynb --set-kernel`. Contents come from `SEED_LINES` at
  the top of the spec: a `# %% [markdown]` cheatsheet cell (cell syntax +
  the main molten keymaps) plus an empty `# %%` code cell. Keep that list
  in sync with the molten keymaps in `private_molten.lua` — it is the
  first thing a user reads in a new notebook. The `·` separators are
  written as `\194\183` byte escapes to keep the file plain ASCII.
  The seeding **must** be
  in `init`, not `config`: lazy.nvim runs `config` after the command-line
  buffer is already being read, so `nvim new.ipynb` would still emit the
  traceback and only recover afterwards. It sweeps `vim.fn.argv()` for
  the `nvim new.ipynb` case and registers `BufAdd` for `:edit new.ipynb`.
  `BufNewFile` does **not** work — jupytext registers `BufReadCmd`, which
  Neovim fires even for a nonexistent file (a `*Cmd` event takes over the
  read), so `BufNewFile` never runs.
- `config()` adds `:NotebookNew <path> [kernel]` (same seeding, but with a
  kernel picker, extension/parent-dir handling, and an existing-file
  guard) and `:NotebookKernels`.
- The same `BufReadCmd` takeover also stops the **LSP** from ever loading in
  a notebook. LazyVim lazy-loads `nvim-lspconfig` on `BufReadPre`; because
  jupytext's `*Cmd` handler takes over the read, `BufReadPre` never fires for
  `*.ipynb`, lspconfig is never loaded, no client attaches, and nvim-cmp
  silently degrades to buffer-word completion (the symptom is "autocomplete
  only offers words already in the file"). `init()` works around it by
  force-loading lspconfig and re-firing `FileType` on the converted buffer.
  Both halves are needed: loading lspconfig alone is too late (its own
  `FileType` hook already missed the buffer) and re-firing `FileType` alone
  does nothing while lspconfig is unloaded. It also needs **two** entry
  points — `BufReadPost`/`BufAdd` for `:edit foo.ipynb`, and `VimEnter` +
  a `vim.fn.argv()` sweep for `nvim foo.ipynb`, since a file named on the
  command line is read before any lazy-loaded plugin can register an
  autocmd. Testing only the `:edit` path will look like success while the
  command-line path stays broken; verify with
  `nvim foo.ipynb` then `:lua =#vim.lsp.get_clients({bufnr=0})`.
Both shell out to `~/.local/share/nvim-venv/bin/{jupyter,jupytext}` before
falling back to PATH, because the venv is what `vim.g.python3_host_prog`
points at and therefore the kernelspec search path molten resolves against
— a brew or project-env `jupyter` reports a different set. The kernel
argument is a kernelspec **directory name**, matching what `:MoltenInit`
takes; molten's own picker lists `find_kernel_specs().keys()` and never
shows `display_name`, which is why `:NotebookKernels` prints both columns.

## basedpyright inlay-hint keys (`<leader>ct` / `<leader>cT`)

The chezmoi'd `lua/plugins/lspconfig.lua` adds `<leader>ct`/`<leader>cT` (basedpyright server `keys`):
apply basedpyright's type inlay hints as annotations. basedpyright attaches
LSP `textEdits` to type hints (VS Code's double-click-to-insert); raw, each
hint also carries its own import edit aimed at line 0, so they are filtered
(type hints only, bare `Any` skipped), imports deduped/merged and moved after
the first import block (notebooks: under the first `# %%`). Two traps found
while testing: the inlayHint request range is fuzzy at its end (returns hints
on the line *after* `end`), so hints are filtered by position; and import
edits come as `"from x import Y\n\n\n"` or, once the file has imports,
`"\nfrom x import Y"` — match the trimmed text. Hints are requested directly,
not read from `vim.lsp.inlay_hint.get()`, whose cache covers only what has
been on screen.

## Molten cells are extmarks, not `# %%` markers
Molten has no parser for `# %%` — a *cell* is a `CodeCell` whose bounds are
`DynamicPosition`s, i.e. literal `nvim_buf_set_extmark` ids
(`rplugin/python3/molten/position.py`). `:MoltenReevaluateCell` searches those
spans for one containing the cursor and errors `Not in a cell` when none match
(`__init__.py`, `moltenbuffer.py:reevaluate_cell`). So a buffer full of `# %%`
markers has **zero** cells until something evaluates a range.

The chezmoi'd `private_molten.lua` bridges the two: it finds the `# %%` block
under the cursor and calls `vim.fn.MoltenEvaluateRange(start, stop)` (1-indexed,
inclusive), which is the documented entry point that routes to `_do_evaluate`
and registers the extmarks. Don't reach for `:MoltenEvaluateArgument` instead —
it goes to `_do_evaluate_expr`, which runs code with no buffer span and
therefore creates no cell.

Two consequences worth keeping in mind:
- Spans don't survive reopening the file; the markers come back, the tracking
  doesn't. `:MoltenSave` / `:MoltenLoad` is the persistence story.
- Anything that clears molten's extmark namespace wholesale destroys the cells.
  `molten-extmarks` holds both the output virt-text marks *and* the
  `DynamicPosition` cell bounds, so a blanket `nvim_buf_clear_namespace()`
  reintroduces `Not in a cell`. The three kinds are distinguishable: cell bounds
  are bare marks, float spacing carries `virt_lines` of empty strings, real
  output carries `virt_lines` with non-empty text.

## `:MoltenHideOutput` can't hide virtual-text output
It only sets `should_show_floating_win = False` — that is the *floating window*.
With `vim.g.molten_virt_text_output` on (our default), output is drawn as
virtual text by a separate path, and `update_interface()` unconditionally
re-runs `show_virtual_output()` for every cell while the option is set
(`moltenbuffer.py`). Since `:MoltenHideOutput` itself ends by calling
`_update_interface()`, it clears the float flag and immediately repaints the
inline text.

Hiding needs the option flipped off (`MoltenUpdateOption`) *and* the
already-drawn marks deleted — see the namespace note above for why that
deletion has to be selective. Toggling inline output back on re-runs the cells:
`show_virtual_output()` early-returns when a cell is DONE and still holds a
`virt_text_id`, and `clear_virt_output()` never resets that id, so molten
exposes no repaint-without-execute path. The upstream fix is a one-liner
(`self.virt_text_id = None` in `clear_virt_output`) if it's ever worth a PR.

## Debugging cells (`<leader>mD`)
Molten has no debugger; ipykernel does — the one JupyterLab drives, reached as
DAP messages wrapped in `debug_request` on the kernel's **control** channel. The
chezmoi'd config bridges nvim-dap to it, attached to the kernel molten already
started, so cells still run through molten and output still renders inline.
Built 2026-09-23, verified by driving nvim in tmux (breakpoint hit in the notebook
buffer, locals, step, continue, output, terminate, re-attach, edited cell).

Pieces (all chezmoi side; nothing install-side — `debugpy` is an ipykernel
dependency, so every kernel env and the nvim-venv already have it):
- `dot_config/nvim/scripts/nb_dap_bridge.py` — stdio DAP adapter, run with the
  nvim-venv python. Also maps lines: ipykernel compiles each cell as
  `$TMPDIR/ipykernel_<pid>/<murmur2(cell text)>.py`, so before every run Lua
  sends a custom `nbRegisterCells` request with each `# %%` cell's text + start
  line; the bridge `dumpCell`s them to learn the paths, splits `.ipynb`
  breakpoints across them, and rewrites stack frames back to notebook lines.
- `private_molten.lua` — `debug_cell()` on `<leader>mD`; finds molten's kernel
  via `ps` ancestry (the ipykernel whose `-f` connection file descends from this
  nvim's pid — molten exposes no API for it); `lazyvim.json` enables `dap.core`.
  It also carries the **molten patches** (see the `molten-patches` skill).
- `private_dap.lua` — dap-ui / virtual-text tuning for large values.

Traps found while building it — each one looked like success at first:
- **Cell text must match byte-for-byte** what molten sends
  (`MoltenEvaluateRange` over whole lines, `"\n"`-joined), or the hash differs
  and breakpoints silently don't bind. The bridge compares against the
  `execute_input` it sees on iopub and emits an `nbWarning` event on mismatch.
- **Molten marks cells Done early** — fixed by a local patch to molten; see
  the `molten-patches` skill before touching molten.
- **Terminate killed the kernel.** nvim-dap ends attach sessions with
  `terminate` or `disconnect{terminateDebuggee=true}`; debugpy obeys by killing
  the process it's in — the kernel. molten then shows `* On Hold` forever. The
  bridge always sends `disconnect{terminateDebuggee=false}` and hides
  `supportsTerminateRequest`.

Behavior to expect: while a session is attached, breakpoints also fire on a
plain `<leader>mc`, and on functions defined by cells run earlier (all cells are
registered, keyed by text) — but only for cells whose text hasn't changed since
they ran. `<leader>dt` detaches; the cell resumes and finishes.

Debugger UI (`private_dap.lua`): dap-ui's stock Scopes pane is a fixed 40
columns with unwrapped values, so big lists were cut at the border, and
nvim-dap-virtual-text wrote whole reprs inline into the code. The spec sets
dap-ui `wrap = true` (must be dap-ui's own option — it sets `'wrap'` per window
after the buffer is shown, so a `FileType`/`BufWinEnter` autocmd loses), makes
the sidebar 33% of the width with Scopes at 55% of it, and caps inline values
at 60 chars via `display_callback`. Children paging (100 + a `more` node) is
debugpy's behaviour, not a bug.
