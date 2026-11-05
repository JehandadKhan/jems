# Step 01 — system package prerequisites (apt on Linux, brew on macOS).
# Sourced from install.sh; uses $OS and brew_install_if_missing.

if [ "$OS" = "linux" ]; then
    echo "==> apt prereqs"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    # NB: no software-properties-common — nothing here uses
    # add-apt-repository (every extra apt source is added via a keyring +
    # .list file in its own step), and the package drags in
    # packagekit -> polkitd, whose postinst creates the 'polkitd' group by
    # rename()-ing a temp file over /etc/group. Under the `drun` container
    # alias /etc/group is a read-only bind mount, so that rename fails with
    # EBUSY ("Device or resource busy") and aborts the whole apt step. See
    # the bind-mount preflight guard in install.sh.
    apt-get install -y \
        ninja-build gettext cmake unzip curl wget git \
        build-essential ripgrep fd-find ca-certificates \
        gnupg lsb-release \
        imagemagick \
        poppler-utils \
        python3-venv python3-pip python3-dev
    # Debian/Ubuntu ship fd as `fdfind` (the `fd` name is taken by another
    # package). LazyVim's pickers look for `fd` first, so expose it under
    # that name via ~/.local/bin (same PATH contract as clangd/jupytext).
    run_as_user mkdir -p "$USER_HOME/.local/bin"
    run_as_user ln -sf "$(command -v fdfind)" "$USER_HOME/.local/bin/fd"
else
    # macOS: install only what's missing so we don't gratuitously upgrade
    # tools the user is pinning. Xcode CLT (git, curl, make) is pulled in
    # by brew on its first install.
    echo "==> brew prereqs"
    BREW_FORMULAE=(ninja cmake gettext ripgrep fd imagemagick poppler)
    # Xcode CLT always provides a `python3`, but it's 3.9 — too old for
    # molten-nvim (see MIN_PYTHON_VERSION). Only pull brew's python when
    # nothing on PATH meets the floor; brew links it as `python3.13`.
    if ! find_python >/dev/null; then
        BREW_FORMULAE+=(python@3.13)
    fi
    for f in "${BREW_FORMULAE[@]}"; do
        brew_install_if_missing "$f"
    done
fi
