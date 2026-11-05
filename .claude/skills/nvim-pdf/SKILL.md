---
name: nvim-pdf
description: PDF viewing in nvim via pdfreader.nvim and snacks.image — the four load-bearing config settings, the snacks BufReadCmd hijack, terminal requirements, ghostscript note. Load when PDFs render blank, wrong, or without keymaps.
---
# PDF viewing in nvim

Built 2026-09-20 (macOS, nvim 0.12.2). `nvim file.pdf` renders pages via
`r-pletnev/pdfreader.nvim`. User-facing keys and subcommands are in
CHEATSHEET.md; this section is the wiring and the traps.

Install side: `poppler` / `poppler-utils` come from `install.d/01-system-prereqs.sh`. **ghostscript was not added explicitly**: brew pulls `gs` in as an imagemagick dependency, and
ImageMagick's PDF delegate needs it to rasterize. Verified `magick
-density 200 'f.pdf[0]'` produces a PNG on this box with no explicit gs
install. If a future Linux run fails to rasterize, apt's imagemagick may
not pull ghostscript the same way — that's the first thing to check.

Config side (chezmoi, `dot_config/nvim/lua/plugins/private_pdfreader.lua`):
four things beyond the plugin spec, all load-bearing.

1. **`snacks.image` must be explicitly enabled.** LazyVim ships snacks
   but leaves the image module off (`snacks.config.image.enabled` is nil
   out of the box), and pdfreader renders through it. Without
   `opts = { image = { enabled = true } }` on `folke/snacks.nvim` you get
   a blank buffer.
2. **`pdf` must be removed from `snacks.image.formats`.** snacks claims
   `*.pdf` itself — `pdf` is in its default format list
   (`lua/snacks/image/init.lua`), and it builds a `BufReadCmd` pattern
   straight from that table, converting the PDF into its own preview
   buffer (`filetype` becomes `markdown`). It wins the race against
   pdfreader because `BufReadCmd` fires at read time. The failure is
   nasty because it *looks* like success: pages render, because snacks
   renders them. But pdfreader never sees the buffer, so no keymap is
   bound and `n` stays Vim's next-match — the tell is
   `E486: Pattern not found: <stale search text>` when you press `n`.
   Diagnose with `:lua print(vim.bo.filetype)` in a PDF buffer: `pdf` is
   correct, `markdown` means snacks hijacked it. The spec pins the full
   format list minus `pdf`, so if a snacks update adds a format, add it
   there too.
3. **`validation.is_supported_terminal` is overridden.** Upstream
   hardcodes `{ "kitty", "ghostty" }` and string-matches `$TERM`, then
   silently forces text mode on a miss. That check fails *inside tmux
   even in kitty*, because `$TERM` is `tmux-256color`. The override
   delegates to `require("snacks.image.terminal").env()` and treats
   `supported ~= false` as yes, so it tracks snacks' own table (which has
   a proper tmux entry that wraps escapes in the `\ePtmux;` passthrough)
   instead of pinning a second stale allowlist. Deliberately not a fork:
   lazy.nvim would clobber an in-place edit on the next update. Upstream
   fix is a one-line PR to that allowlist.
4. **`lazy = false`.** Not lazy-loadable at all. The plugin registers its
   `BufEnter *.pdf` autocmd — and the n/p/z/q/e keymaps — inside
   `setup()`, so it must be loaded *before* the PDF buffer is read.
   `event = "VeryLazy"` was tried and is too late: it fires after the
   file is already open, the autocmd misses that first `BufEnter`, and no
   keymap is bound (same `E486` symptom as above). `cmd = "PDFReader"` is
   later still. Verify with
   `:lua print(#vim.api.nvim_get_autocmds({event="BufEnter",pattern="*.pdf"}))`
   — 1 is right, 0 means it never loaded.

Don't add a `BufReadCmd *.pdf` autocmd for text extraction alongside it.
An earlier iteration of this work did exactly that (the "Route A" idea)
and it collides — two handlers on the same buffer fight over its
contents. `:PDFReader setViewMode text` covers that need.

**Terminal requirement is stricter than the rest of the image stack.**
Rendering needs the Kitty graphics protocol *plus* the unicode-
placeholder extension, which anchors images to text-grid cells so the
terminal clips them. kitty and ghostty have it; **wezterm does not**
(`placeholders = false` in snacks' `lua/snacks/image/terminal.lua`).
Without placeholders snacks blits at absolute screen coordinates and
pages paint over the statusline, splits, and tabline — tmux makes it
worse, since nvim's coordinates don't survive tmux's own layout.
Confirmed working in kitty; wezterm was tried and abandoned for this.
Note this is *narrower* than image.nvim's requirement — molten plots
render fine in wezterm via `backend = "kitty"`, so "images work in my
terminal" does not imply pdfreader will.

pdfreader is young (single upstream commit `f8c0676` at time of writing).
Two dead ends found while reading it, in case behavior changes: `q` is
bound to zoom-out inside a PDF buffer, not quit (use `:q`); and
`get_book_from_buffer_var` despite the name *creates* a book by falling
back to `expand("%:p")`, which is why the first `BufEnter` renders
without any explicit open step.

`StefanBartl/pdfport.nvim` is the other option; drags in the author's
`lib.nvim`, not worth it.
