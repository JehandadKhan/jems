# Step 05 — clangd (>= MIN_CLANGD_VERSION). Linux pulls clangd-18 from
# apt.llvm.org; macOS uses brew's keg-only llvm and symlinks just the
# clangd binary to avoid clobbering Apple's clang/clang++.
#
# The Linux side is naturally floor-pinned by the apt source name
# (llvm-toolchain-${CODENAME}-18) — apt won't downgrade us below 18 from
# that source. On macOS brew tracks the latest llvm major (currently 19+)
# so the floor is just a safety net for stale brew formulae.

if [ "$OS" = "linux" ]; then
    # apt.llvm.org pin gets us a current clangd on jammy/focal-era distros
    # whose stock clangd is several majors behind.
    if ! tool_version_ok clangd-18 "$MIN_CLANGD_VERSION"; then
        echo "==> Installing clangd-18 (adds apt.llvm.org as a persistent source)"
        CODENAME="$(lsb_release -cs)"
        install -d -m 0755 /etc/apt/keyrings
        if [ ! -f /etc/apt/keyrings/llvm.gpg ]; then
            wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key \
                | gpg --dearmor -o /etc/apt/keyrings/llvm.gpg
        fi
        echo "deb [signed-by=/etc/apt/keyrings/llvm.gpg] http://apt.llvm.org/${CODENAME}/ llvm-toolchain-${CODENAME}-18 main" \
            > /etc/apt/sources.list.d/llvm-18.list
        apt-get update -y
        apt-get install -y clangd-18
    fi
    update-alternatives --install /usr/bin/clangd clangd /usr/bin/clangd-18 100
else
    # macOS: brew's `llvm` formula is keg-only (not auto-linked) so it doesn't
    # collide with Apple's clang. Symlink only the clangd binary into
    # ~/.local/bin so nvim/lspconfig finds it on PATH. Pass MIN_CLANGD_VERSION
    # so brew_ensure upgrades a stale llvm rather than skipping on presence.
    brew_ensure llvm "$MIN_CLANGD_VERSION"
    LLVM_PREFIX="$(brew --prefix llvm)"
    if [ ! -x "$LLVM_PREFIX/bin/clangd" ]; then
        echo "    WARNING: $LLVM_PREFIX/bin/clangd not found after brew install"
    fi
    run_as_user mkdir -p "$USER_HOME/.local/bin"
    run_as_user ln -sf "$LLVM_PREFIX/bin/clangd" "$USER_HOME/.local/bin/clangd"
fi
