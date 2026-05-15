# Step 10 — gh (GitHub CLI).
#
# Linux pulls from cli.github.com's apt repo (persistent — every future
# 'apt update' will hit it). macOS goes through brew. The GPG key is fetched
# at install time and not fingerprint-pinned, mirroring how this script
# handles apt.llvm.org for clangd.

if [ "$INSTALL_GH" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        if ! command -v gh >/dev/null 2>&1; then
            echo "==> Installing gh (adds cli.github.com as a persistent apt source)"
            install -d -m 0755 /etc/apt/keyrings
            if [ ! -f /etc/apt/keyrings/githubcli-archive-keyring.gpg ]; then
                wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                    > /etc/apt/keyrings/githubcli-archive-keyring.gpg
                chmod 0644 /etc/apt/keyrings/githubcli-archive-keyring.gpg
            fi
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
                > /etc/apt/sources.list.d/github-cli.list
            apt-get update -y
            apt-get install -y gh
        else
            echo "==> gh already installed: $(gh --version 2>/dev/null | head -1)"
        fi
    else
        brew_install_if_missing gh
    fi
else
    echo "==> INSTALL_GH=0; skipping gh install"
fi
