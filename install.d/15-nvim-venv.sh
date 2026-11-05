# Step 15 — nvim Python venv (for molten-nvim + jupyter).
#
# Path ($NVIM_VENV) is exported by the driver since the summary references
# it too. The chezmoi'd nvim config is expected to set
#   vim.g.python3_host_prog = "$HOME/.local/share/nvim-venv/bin/python"
# so molten-nvim can find pynvim.

# Interpreter must meet MIN_PYTHON_VERSION (molten-nvim needs 3.10+; the
# bare `python3` on macOS is Xcode CLT's 3.9 — see find_python in install.sh).
VENV_PYTHON="$(find_python)" || {
    echo "error: no python3 >= $MIN_PYTHON_VERSION on PATH; molten-nvim needs it" >&2
    exit 1
}

# Re-run contract: the venv directory existing is not enough. Rebuild it if
# its interpreter is below the floor, or if bin/python is a dangling symlink
# (brew removed the framework the venv was created from).
NVIM_VENV_REBUILT=0
if [ -d "$NVIM_VENV" ] && ! tool_version_ok "$NVIM_VENV/bin/python" "$MIN_PYTHON_VERSION"; then
    echo "==> Rebuilding $NVIM_VENV: its python ($("$NVIM_VENV/bin/python" --version 2>&1 || echo missing)) is below $MIN_PYTHON_VERSION"
    run_as_user rm -rf "$NVIM_VENV"
    NVIM_VENV_REBUILT=1
fi
if [ ! -d "$NVIM_VENV" ]; then
    echo "==> Creating Python venv for nvim at $NVIM_VENV (using $VENV_PYTHON)"
    run_as_user "$VENV_PYTHON" -m venv "$NVIM_VENV"
fi
echo "==> Updating Python packages in $NVIM_VENV"
run_as_user "$NVIM_VENV/bin/pip" install --quiet --upgrade pip wheel
run_as_user "$NVIM_VENV/bin/pip" install --quiet --upgrade \
    pynvim jupyter_client nbformat ipykernel jupytext \
    Pillow cairosvg pyperclip

# jupytext.nvim shells out to the `jupytext` CLI on PATH; expose the venv's
# copy via ~/.local/bin so nvim (which doesn't have the venv on PATH) finds it.
run_as_user mkdir -p "$USER_HOME/.local/bin"
run_as_user ln -sf "$NVIM_VENV/bin/jupytext" "$USER_HOME/.local/bin/jupytext"

# jupyter_client writes each kernel's connection file into the Jupyter
# runtime dir (~/Library/Jupyter/runtime on macOS, ~/.local/share/jupyter/
# runtime on Linux) but never creates that dir — only the jupyter *apps*
# do, on their first run. On a box that has never launched jupyter,
# :MoltenInit fails with "[Errno 2] No such file or directory:
# .../runtime/kernel-<id>.json". Create it up front.
run_as_user mkdir -p "$(run_as_user "$NVIM_VENV/bin/jupyter" --runtime-dir)"

# Register a default ipykernel against the user's regular environment,
# so notebooks can be evaluated against the system python out of the box.
run_as_user "$NVIM_VENV/bin/python" -m ipykernel install --user --name=python3 --display-name "Python 3 (nvim venv)" >/dev/null 2>&1 || true
