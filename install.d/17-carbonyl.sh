# Step 17 — carbonyl (Chromium-in-the-terminal browser).
#
# carbonyl is a single bundle: a stripped Chromium plus its shared
# libraries (icudtl.dat, libcarbonyl.so, libEGL.so, …). The release zip
# only ships these as a flat directory; there's no installer or .deb.
# Drop the whole bundle into ~/.local/share/carbonyl/ and symlink
# ~/.local/bin/carbonyl -> there (same user-local-binary pattern jems
# uses for jupytext and clangd). Linux-only release; macOS users would
# install via brew if they want it (left as a future toggle).
#
# Idempotent: the version file at $CARBONYL_DIR/.installed_version is
# the source of truth. If it matches $CARBONYL_VERSION, the step is a
# no-op. Bump $CARBONYL_VERSION when upstream cuts a new release.

CARBONYL_VERSION="0.0.3"
CARBONYL_DIR="$USER_HOME/.local/share/carbonyl"
CARBONYL_BIN="$USER_HOME/.local/bin/carbonyl"

if [ "$INSTALL_CARBONYL" = "1" ]; then
    if [ "$OS" = "linux" ]; then
        if [ -f "$CARBONYL_DIR/.installed_version" ] \
            && [ "$(cat "$CARBONYL_DIR/.installed_version" 2>/dev/null)" = "$CARBONYL_VERSION" ] \
            && [ -x "$CARBONYL_DIR/carbonyl" ]; then
            echo "==> carbonyl $CARBONYL_VERSION already installed at $CARBONYL_DIR"
        else
            echo "==> Installing carbonyl $CARBONYL_VERSION to $CARBONYL_DIR"
            # Stage the download under the target user's home, not /tmp.
            # A bare `mktemp` under /tmp creates a 0700 root-owned path when
            # the script runs via sudo, and the later `run_as_user cp/unzip`
            # (which drops privs) then can't read inside it (EACCES). Same
            # gotcha the nerd-font step documents.
            run_as_user mkdir -p "$USER_HOME/.cache"
            TMP_DIR="$(run_as_user mktemp -d "$USER_HOME/.cache/carbonyl.XXXXXX")"
            run_as_user curl -fsSL --retry 3 -o "$TMP_DIR/carbonyl.zip" \
                "https://github.com/fathyb/carbonyl/releases/download/v${CARBONYL_VERSION}/carbonyl.linux-amd64.zip"
            run_as_user install -d -m 0755 "$CARBONYL_DIR"
            # The zip wraps everything in carbonyl-<version>/; extract and
            # locate the carbonyl binary, then copy its directory's contents
            # into $CARBONYL_DIR so the binary lands at $CARBONYL_DIR/carbonyl
            # regardless of the zip's internal layout in future versions.
            run_as_user unzip -q -o "$TMP_DIR/carbonyl.zip" -d "$TMP_DIR"
            SRC_BIN="$(find "$TMP_DIR" -maxdepth 2 -name carbonyl -type f -print -quit)"
            if [ -z "$SRC_BIN" ]; then
                echo "    ERROR: no 'carbonyl' binary found in the release zip" >&2
                run_as_user rm -rf "$TMP_DIR"
                exit 1
            fi
            run_as_user cp -r "$(dirname "$SRC_BIN")"/. "$CARBONYL_DIR/"
            echo "$CARBONYL_VERSION" | run_as_user tee "$CARBONYL_DIR/.installed_version" >/dev/null
            run_as_user rm -rf "$TMP_DIR"
        fi

        run_as_user install -d -m 0755 "$USER_HOME/.local/bin"
        run_as_user ln -sf "$CARBONYL_DIR/carbonyl" "$CARBONYL_BIN"
        echo "    carbonyl: $("$CARBONYL_BIN" --version 2>/dev/null || echo unknown)"
    else
        echo "==> Skipping carbonyl on macOS (no official release; use brew if needed)"
    fi
else
    echo "==> INSTALL_CARBONYL=0; skipping carbonyl install"
fi
