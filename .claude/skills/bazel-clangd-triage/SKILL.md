---
name: bazel-clangd-triage
description: Triage for 'clangd can't find headers', 'rocminfo fails in the container', or clangd not attaching on macOS — bazel-compile-commands container $USER/GID gotchas, the ROCm --config note, PATH check. Load for those symptoms.
---
# bazel-compile-commands and clangd triage

The helper itself is documented in `install.d/06-bazel-helper.sh` and `install.d/files/bazel-compile-commands` (what it writes, the hedron `py_binary` patch, `--config` passthrough). This file holds the triage notes that live nowhere in the code.

## Host↔container gotcha

Not install-side, but it bites the bazel-compile-commands workflow: when running the extractor inside a `docker run -u $(id -u):$(id -g)`
container (the chezmoi'd `drun` alias), the container must (a) bind-mount
`/etc/passwd` + `/etc/group` read-only and/or set `-e USER="$USER"` so Bazel
resolves the same `~/.cache/bazel/_bazel_$USER` output base as the host —
otherwise `$USER` is empty inside, Bazel picks a fresh output base, and every
external repo (notably the multi-GB LLVM toolchain) re-downloads from cold.
(b) `--group-add` the GPU device GIDs *numerically* — `/dev/kfd` and
`/dev/dri/renderD*` are group `render` (GID 109 on this host, but `render` is
a dynamic ≥100 allocation and can differ per machine), `/dev/dri/card*` is
`video` (GID 44, a Debian static alloc). Name-based `--group-add video`
resolves against the image's `/etc/group`, misses `render`, and breaks
`rocminfo`. The robust form derives them at runtime:
`--group-add "$(stat -c %g /dev/kfd)" --group-add "$(stat -c %g /dev/dri/renderD128)"`.
All of this lives in the chezmoi'd `~/.bashrc` (`private_dot_bashrc`), not
here — this note is just a pointer for the next "clangd can't find headers /
rocminfo fails in the container" triage.

## ROCm container `--config`

For XLA on ROCm the helper is run as `bazel-compile-commands --config rocm_clang_local <root> //xla/...`
(`rocm_clang_local` = `rocm_base` + `clang_local` + the ROCm crosstool, and
pins `CLANG_COMPILER_PATH=/usr/lib/llvm-18/bin/clang` — which only exists
inside the ROCm container, so run the extractor there). The equivalent
repo-local alternative is a gitignored `.tf_configure.bazelrc` with
`common --config=rocm_clang_local` (XLA's `try-import` slot), but the
`--config` flag keeps the toolchain choice explicit on the command line.

## macOS: clangd LSP not attaching

On macOS `~/.local/bin/clangd` is a symlink into brew's keg-only llvm (see `install.d/05-clangd.sh`), so nvim/lspconfig only finds it if `~/.local/bin` is on PATH — the chezmoi'd shell rc's job. First check: `which clangd` from the same shell that launches nvim. If it returns nothing, the chezmoi config isn't putting `~/.local/bin` on PATH.
