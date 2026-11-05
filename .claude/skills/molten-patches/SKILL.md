---
name: molten-patches
description: The two local patches the chezmoi'd private_molten.lua applies to molten-nvim (own-execute iopub filter, highlight-leak fix): why, the diffs, lifecycle, and the update procedure. Load before updating or pinning molten.
---
# Local patches to molten-nvim — read before updating molten
Two **patches to molten's own source** are applied by the chezmoi'd
`private_molten.lua` (`MOLTEN_PATCHES`, `patch_molten`, `unpatch_molten`): the
own-execute filter in `runtime.py`, which the cell debugger depends on, and a
highlight-leak fix in `moltenbuffer.py` (below). Anyone updating
molten, pinning a new version, or debugging "cell output vanished" / "nvim at
100% CPU" must know they exist. `MOLTEN_PATCHES` is one entry per file
(`file`, `mark`, `warn`, `hunks`); each file is patched all-or-nothing and
independently of the other.

**Why.** molten's `JupyterRuntime.tick()` (`rplugin/python3/molten/runtime.py`)
feeds every iopub message to the current output with no `parent_header` check,
and any `status: idle` ends the current cell. With a debugger attached that is
wrong twice: every DAP request is a control message and publishes busy/idle,
and on attach ipykernel sends *itself* a silent `execute_request` (to start
debugpy) whose idle sits in molten's backlog until the next cell is queued.
Symptom without the patch: `Out[...]: ✓ Done` while paused at a breakpoint,
the real output dropped or pinned to the next cell. A msg_type filter was
tried and is **not** enough (the second case is an `execute_request`).

**What.** Two hunks, marked `# [nvim-config] own-execute filter`:
```diff
     def run_code(self, code: str) -> None:
-        self.kernel_client.execute(code)
+        msg_id = self.kernel_client.execute(code)
+        # [nvim-config] own-execute filter
+        if msg_id:
+            self.__dict__.setdefault("_nvim_own_ids", set()).add(msg_id)
 ...
                 if "content" not in message or "msg_type" not in message:
                     continue
+                # [nvim-config] own-execute filter
+                own = self.__dict__.get("_nvim_own_ids")
+                if own is not None and (message.get("parent_header") or {}).get("msg_id") not in own:
+                    continue
```
The remote jupyter-server client (`jupyter_server_api.py`) returns no msg_id
from `execute`, so `own` stays `None` there and that path is unfiltered, as
upstream.

**Lifecycle.**
- Applied from the spec's `init` on **every nvim startup** (idempotent: skipped
  if the marker is present). `init` runs before molten's python host imports
  the file, so the running host always has it.
- Reverted (`git checkout -- runtime.py moltenbuffer.py` in the plugin dir) on the
  `User LazyUpdatePre` / `LazySyncPre` / `LazyRestorePre` events, because
  lazy.nvim updates with a plain, non-forced `git checkout` that a dirty file
  would block. Consequence: right after a `:Lazy update` the *current* session
  may run unpatched molten code if the host restarts; the next startup
  re-patches.
- All-or-nothing per file: if any anchor in a file is missing (upstream edited
  those lines) that file is left alone and a startup warning names it —
  "molten iopub patch no longer applies" (only debugging loses cell output) or
  "molten highlight-leak patch no longer applies" (the CPU leak below returns).

## Highlight-leak patch (`moltenbuffer.py`)
**Why.** `update_interface()` runs on every cursor move and calls
`_show_selected()`, which adds one `nvim_buf_add_highlight` per line of the
current cell to the `molten-highlights` namespace. The old ones are cleared only
when the cursor moves to a *different* cell. Staying in one cell therefore
accumulates marks without bound. Found 2026-09-25: a 108-line notebook left open
~1.5 days held **971,568** marks in that namespace and nvim sat at 99% CPU
forever (`sample` stack: `update_screen → win_line → decor_redraw_col_impl →
decor_range_insert → memmove`). Diagnose a live instance via its
`nvim.<pid>.0` socket with `nvim --server … --remote-expr` counting
`nvim_buf_get_extmarks` per namespace; `:lua
vim.api.nvim_buf_clear_namespace(0, vim.api.nvim_get_namespaces()["molten-highlights"], 0, -1)`
recovers it without losing cells (bounds live in `molten-extmarks`).

**What.** One hunk, marked `# [nvim-config] highlight leak`, after the
buffer-membership guard in `_show_selected`:
```diff
         if buf.number not in [b.number for b in self.buffers]:
             return
 
+        # [nvim-config] highlight leak
+        self.nvim.funcs.nvim_buf_clear_namespace(buf.number, self.highlight_namespace, 0, -1)
+
         if span.begin.lineno == span.end.lineno:
```
Safe because that namespace only ever holds the selected cell's highlight.
Verified in tmux: a 3-line cell after 200 paced `j`/`k` moves went 27 → 123
marks unpatched, stayed at 3 patched; highlight still follows the cursor
across cells. (Moves must be paced — fast typeahead coalesces `CursorMoved`.)

**When molten updates.**
1. Start nvim; if a warning appears, open the new file it names and re-find the
   anchors — for `runtime.py` the `run_code` execute call and the
   `"content" not in message` guard in `tick`; for `moltenbuffer.py` the
   buffer guard at the top of `_show_selected` — and update `MOLTEN_PATCHES`.
2. Check upstream first: if molten now filters iopub by parent msg_id itself,
   or clears the highlight namespace in `_show_selected`, drop that entry.
3. Verify: `git -C ~/.local/share/nvim/lazy/molten-nvim diff` shows the three
   hunks across both files; count `molten-highlights` marks stays at the cell's
   line count while moving inside one cell; then in a notebook set a breakpoint, `<leader>mD`, and confirm the
   cell reads `... Running` while paused and shows its output after
   `<leader>dc`.

**Upstream.** Worth a PR to benlubas/molten-nvim: track the execute msg_id per
output and ignore foreign iopub messages. That also fixes molten sharing a
kernel with any other client (e.g. JupyterLab via `:MoltenInit <json>`).
The highlight leak is a separate one-line PR (clear the namespace in
`_show_selected`).
