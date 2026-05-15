# Step 06 — bazel-compile-commands helper (clangd index for Bazel C++).
#
# clangd's accuracy on a Bazel-built C++ codebase (XLA, JAX/jaxlib, TF, ...)
# depends entirely on a `compile_commands.json` at the workspace root: without
# it, header includes, defines, and toolchain flags are guessed and most
# cross-references break. Bazel doesn't produce that file natively. The
# de-facto generator is hedronvision/bazel-compile-commands-extractor, but
# bootstrapping it per-repo is fiddly (MODULE.bazel + a refresh BUILD target),
# so this step gives the user a one-shot helper:
#
#   1. Clones the extractor once to $HEDRON_DIR (we use a local_path_override
#      in MODULE.bazel rather than a git_override, so the helper has zero
#      network deps at run time and every box this script runs on stays in
#      sync via re-running the installer).
#   2. Installs $HELPER_BIN (the bazel-compile-commands wrapper). Run from any
#      Bazel workspace and it wires hedron in via a fenced managed block,
#      writes tools/clangd/BUILD.bazel with a refresh target, keeps the
#      generated junk out of `git status` via .git/info/exclude, then runs
#      `bazel run //tools/clangd:refresh_compile_commands`. On success
#      compile_commands.json appears at the repo root and clangd picks it up
#      on the next nvim launch.
#
# The helper itself lives at $STEPS_DIR/files/bazel-compile-commands so it can
# be edited as a real script (shellcheck, syntax highlighting) rather than a
# heredoc. We `install` (not `cp`) so permissions land at 0755 in one shot.

if [ "$INSTALL_BAZEL_HELPER" = "1" ]; then
    if [ -d "$HEDRON_DIR/.git" ]; then
        echo "==> Updating bazel-compile-commands-extractor at $HEDRON_DIR"
        run_as_user git -C "$HEDRON_DIR" pull --ff-only --quiet || \
            echo "   (git pull failed; keeping existing checkout)"
    else
        echo "==> Cloning hedronvision/bazel-compile-commands-extractor to $HEDRON_DIR"
        run_as_user mkdir -p "$(dirname "$HEDRON_DIR")"
        run_as_user git clone --depth 1 \
            https://github.com/hedronvision/bazel-compile-commands-extractor.git \
            "$HEDRON_DIR"
    fi

    # Patch hedron's refresh_compile_commands.bzl to load py_binary from
    # rules_python instead of calling native.py_binary. In WORKSPACE-mode
    # workspaces (XLA pins `common --noenable_bzlmod`), `native.py_binary`
    # routes to Bazel's built-in Java-side py_binary rather than the
    # rules_python autoloaded one. Bazel then renders rules_python's bash
    # bootstrap template with its own substitution dict and leaves
    # rules_python-specific placeholders (%interpreter_args%,
    # %stage2_bootstrap%, %recreate_venv_at_runtime%, ...) literal — the
    # launcher then tries to exec '%interpreter_args%' as a Python file
    # path and dies with `[Errno 2] No such file or directory`. See
    # https://github.com/hedronvision/bazel-compile-commands-extractor/issues/168
    # for the upstream issue. Re-run-safe: the Python script is idempotent.
    HEDRON_BZL="$HEDRON_DIR/refresh_compile_commands.bzl"
    if [ -f "$HEDRON_BZL" ]; then
        echo "==> Patching $HEDRON_BZL to use rules_python's py_binary"
        run_as_user python3 - "$HEDRON_BZL" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
src = p.read_text()
load_line = 'load("@rules_python//python:defs.bzl", "py_binary")'
anchor = 'load("@bazel_tools//tools/cpp:toolchain_utils.bzl", "find_cpp_toolchain")'
if load_line not in src and anchor in src:
    src = src.replace(anchor, anchor + "\n" + load_line, 1)
src = src.replace("native.py_binary(", "py_binary(")
p.write_text(src)
PY
    fi

    HELPER_SRC="$STEPS_DIR/files/bazel-compile-commands"
    if [ ! -f "$HELPER_SRC" ]; then
        echo "error: helper source missing at $HELPER_SRC" >&2
        exit 1
    fi
    echo "==> Installing $HELPER_BIN"
    run_as_user mkdir -p "$USER_HOME/.local/bin"
    # install(1) handles mode+ownership in one shot. -m 0755 makes it
    # executable; running it via run_as_user lands ownership on the target
    # user without a separate chown.
    run_as_user install -m 0755 "$HELPER_SRC" "$HELPER_BIN"
else
    echo "==> INSTALL_BAZEL_HELPER=0; skipping bazel-compile-commands setup"
fi
