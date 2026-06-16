# Step 18 — Mermaid tooling: mermaid-cli (`mmdc`) + mmdflux.
#
# Two complementary Mermaid renderers:
#   - @mermaid-js/mermaid-cli ('mmdc'): the official CLI. Takes a .mmd
#     definition and produces SVG/PNG/PDF. It bundles puppeteer + a headless
#     Chromium to do the actual rendering, so it's a heavy npm install but
#     works the same on Linux and macOS. Pinned to $MERMAID_CLI_VERSION via
#     npm so re-runs across machines land on the same release.
#   - mmdflux (kevinswiber/mmdflux): a Rust CLI that renders Mermaid to
#     terminal text, SVG, and structured JSON (MMDS) — no browser, no
#     network at run time, fast. Built from crates.io via `cargo install`,
#     pinned to $MMDFLUX_VERSION. Lands in the target user's
#     ~/.cargo/bin/mmdflux (cargo's default bin dir), so ~/.cargo/bin must be
#     on PATH — that's the chezmoi'd shell rc's job, same as ~/.local/bin.
#
# cargo isn't part of any other jems step, so this step bootstraps a
# user-local Rust toolchain via rustup (into ~/.rustup + ~/.cargo) when no
# cargo >= $MIN_CARGO_VERSION is found, then `cargo install`s mmdflux. The
# toolchain is pinned to $RUST_TOOLCHAIN so the build is reproducible and
# isn't at the mercy of whatever stable rustup resolves to on the day.

if [ "$INSTALL_MERMAID" = "1" ]; then
    # ---- mermaid-cli (mmdc) via npm, pinned ----
    echo "==> Installing/updating mermaid-cli via 'npm i -g @mermaid-js/mermaid-cli@$MERMAID_CLI_VERSION'"
    npm install -g "@mermaid-js/mermaid-cli@$MERMAID_CLI_VERSION" >/dev/null
    echo "    mmdc: $(mmdc --version 2>/dev/null || echo unknown)"

    # ---- Rust toolchain (rustup) for the target user, if missing ----
    # cargo lives in the target user's ~/.cargo/bin. Resolve it explicitly
    # rather than trusting root's PATH — on Linux the install runs under sudo
    # and root almost certainly has no cargo even if the user does.
    CARGO_BIN="$USER_HOME/.cargo/bin/cargo"
    cargo_ok() {
        [ -x "$CARGO_BIN" ] || return 1
        version_ge "$(run_as_user "$CARGO_BIN" --version 2>/dev/null | awk '{print $2}')" \
                   "$MIN_CARGO_VERSION"
    }

    if cargo_ok; then
        echo "==> cargo already present: $(run_as_user "$CARGO_BIN" --version 2>/dev/null)"
    else
        echo "==> Installing Rust toolchain $RUST_TOOLCHAIN via rustup (user-local: ~/.rustup, ~/.cargo)"
        # rustup-init runs as the target user so ~/.rustup and ~/.cargo are
        # user-owned. --no-modify-path because the chezmoi'd shell rc owns
        # PATH; -y for non-interactive; pin the default toolchain.
        run_as_user env RUSTUP_HOME="$USER_HOME/.rustup" CARGO_HOME="$USER_HOME/.cargo" \
            bash -c 'curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path \
                --default-toolchain "$1" --profile minimal' _ "$RUST_TOOLCHAIN"
        echo "    cargo: $(run_as_user "$CARGO_BIN" --version 2>/dev/null || echo unknown)"
    fi

    # ---- mmdflux via cargo, pinned ----
    if [ -x "$CARGO_BIN" ]; then
        # Skip the (slow) build if the pinned version is already installed.
        # `cargo install --list` prints "mmdflux v2.5.0:" for an installed crate.
        if run_as_user "$CARGO_BIN" install --list 2>/dev/null \
            | grep -q "^mmdflux v${MMDFLUX_VERSION}:"; then
            echo "==> mmdflux $MMDFLUX_VERSION already installed via cargo"
        else
            echo "==> Installing mmdflux $MMDFLUX_VERSION via 'cargo install mmdflux --locked'"
            run_as_user env RUSTUP_HOME="$USER_HOME/.rustup" CARGO_HOME="$USER_HOME/.cargo" \
                "$CARGO_BIN" install mmdflux --version "$MMDFLUX_VERSION" --locked
        fi
        echo "    mmdflux: $(run_as_user "$USER_HOME/.cargo/bin/mmdflux" --version 2>/dev/null || echo unknown)"
    else
        echo "==> cargo unavailable; skipping mmdflux install"
    fi
else
    echo "==> INSTALL_MERMAID=0; skipping mermaid-cli + mmdflux install"
fi
