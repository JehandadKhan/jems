# Step 16 — terraform (CLI) + terraform-ls (LSP) + tflint (linter).
#
# terraform and terraform-ls also back LazyVim's lang.terraform extra
# (enabled in the chezmoi'd lazyvim.json). The extra defaults to
# installing the LSP through Mason; private_terraform.lua disables that
# so the system-managed binaries below are what nvim picks up — same
# pattern as clangd.
#
# Linux:
#   - terraform and terraform-ls both come from
#     apt.releases.hashicorp.com (persistent apt source, same caveat as
#     cli.github.com for gh and apt.llvm.org for clangd: every future
#     'apt update' will hit it; key is fetched at install time, not
#     fingerprint-pinned).
#   - tflint has no HashiCorp apt repo and the upstream tflint-bundle
#     deb is unmaintained; install via the official installer script
#     which drops a binary at /usr/local/bin/tflint (matches the
#     starship / chezmoi-linux pattern).
# macOS:
#   - terraform and terraform-ls via brew tap hashicorp/tap; tflint is
#     in core brew.

if [ "$INSTALL_TERRAFORM" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        # Add HashiCorp apt source if any of {terraform, terraform-ls} is
        # missing — both ship from the same repo so we set it up once.
        if ! command -v terraform >/dev/null 2>&1 || ! command -v terraform-ls >/dev/null 2>&1; then
            echo "==> Adding apt.releases.hashicorp.com as a persistent apt source"
            install -d -m 0755 /etc/apt/keyrings
            if [ ! -f /etc/apt/keyrings/hashicorp.gpg ]; then
                wget -qO- https://apt.releases.hashicorp.com/gpg \
                    | gpg --dearmor > /etc/apt/keyrings/hashicorp.gpg
                chmod 0644 /etc/apt/keyrings/hashicorp.gpg
            fi
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
                > /etc/apt/sources.list.d/hashicorp.list
            apt-get update -y
        fi

        for pkg in terraform terraform-ls; do
            if command -v "$pkg" >/dev/null 2>&1; then
                echo "==> $pkg already installed: $($pkg --version 2>/dev/null | head -1)"
            else
                echo "==> Installing $pkg from apt.releases.hashicorp.com"
                apt-get install -y "$pkg"
                echo "    $pkg installed: $($pkg --version 2>/dev/null | head -1)"
            fi
        done

        if command -v tflint >/dev/null 2>&1; then
            echo "==> tflint already installed: $(tflint --version 2>/dev/null | head -1)"
        else
            echo "==> Installing tflint to /usr/local/bin (official installer)"
            curl -fsSL https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
        fi
    else
        if ! brew tap | grep -qx hashicorp/tap; then
            echo "==> Tapping hashicorp/tap for terraform + terraform-ls"
            brew tap hashicorp/tap
        fi
        brew_ensure hashicorp/tap/terraform
        brew_ensure hashicorp/tap/terraform-ls
        brew_ensure tflint
    fi
else
    echo "==> INSTALL_TERRAFORM=0; skipping terraform + terraform-ls + tflint install"
fi
