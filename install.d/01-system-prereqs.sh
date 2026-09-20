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
        build-essential ripgrep ca-certificates \
        gnupg lsb-release \
        imagemagick \
        python3-venv python3-pip python3-dev
else
    # macOS: install only what's missing so we don't gratuitously upgrade
    # tools the user is pinning. Xcode CLT (git, curl, make) is pulled in
    # by brew on its first install.
    echo "==> brew prereqs"
    BREW_FORMULAE=(ninja cmake gettext ripgrep imagemagick)
    if ! command -v python3 >/dev/null 2>&1; then
        BREW_FORMULAE+=(python)
    fi
    for f in "${BREW_FORMULAE[@]}"; do
        brew_install_if_missing "$f"
    done
fi
