# jems — repo notes for Claude

Bash installer for the **prerequisites** (not dotfiles) of a Neovim + LazyVim +
Jupyter stack on Ubuntu/WSL2 (apt, runs under `sudo`) and macOS 14+ (brew, runs
as the user). What each step does is in the `install.sh` header and the
per-step headers in `install.d/`; this file holds what the code can't tell you.

## Out of scope: dotfiles

Anything under the user's `$HOME` that is a config file is managed by
**chezmoi**, not this script. That includes `~/.config/nvim/**`,
`~/.tmux.conf`, `~/.bashrc`/`~/.zshrc`, `~/.config/ImageMagick-7/type.xml`,
and any LazyVim plugin specs. The script must never read, edit, or write
those paths. If a future task seems to require touching one of them, push
back and route it through chezmoi instead.

The chezmoi **source** (the editable templates that generate those
dotfiles) lives at `~/.local/share/chezmoi` — a git repo. Tracked names
are chezmoi-mangled: `dot_` → leading `.`, `private_` = restricted perms,
`.tmpl` = templated. So the live `~/.config/nvim/init.lua` is sourced from
`dot_config/nvim/init.lua`, `~/.bashrc` from `private_dot_bashrc.tmpl`,
etc. When a task legitimately needs the dotfile side, edit the source
there (not the rendered `$HOME` copy) and let `chezmoi apply` propagate.
If you're working that side, ask the user to
`/add-dir ~/.local/share/chezmoi` so it's in context.

## Contract with the chezmoi config

The script and the chezmoi config meet at a small set of well-known paths.
Don't break these without updating both sides:

- `~/.local/share/nvim-venv` — the script creates this venv with pynvim,
  jupyter_client, ipykernel, jupytext, etc. The chezmoi'd nvim config is
  expected to set
  `vim.g.python3_host_prog = "$HOME/.local/share/nvim-venv/bin/python"`
  so molten-nvim can find pynvim. The venv must be built on a python >=
  `MIN_PYTHON_VERSION` (3.10): molten's rplugin uses `match`, so on an
  older interpreter pynvim fails to import it, `:UpdateRemotePlugins`
  writes an empty python3 section into `~/.local/share/nvim/rplugin.vim`,
  and `:MoltenInit` is simply undefined (no error at startup). The
  installer picks the interpreter via `find_python` and rebuilds a venv
  that's below the floor; after a rebuild the user must run
  `:UpdateRemotePlugins` once in nvim. Don't go back to a bare `python3`
  here — on macOS that's Xcode CLT's 3.9.
- `~/.local/bin/{clangd,jupytext,vim,vi,fd}` — the script symlinks these
  (clangd from brew's keg-only llvm; jupytext from the nvim venv; vim/vi
  from nvim when `LINK_VIM=1`; fd -> apt's `fdfind` on Linux only, since
  LazyVim's pickers look for the `fd` name; brew's `fd` needs no link). The chezmoi'd shell rc is expected to
  prepend `~/.local/bin` to PATH (macOS doesn't do this by default the
  way Ubuntu's `~/.profile` does).
- `~/.fzf/` — the script clones fzf and runs its installer with
  `--no-update-rc`. The chezmoi'd bashrc/zshrc is expected to source
  `~/.fzf.bash` / `~/.fzf.zsh`.
- macOS only: brew's `imagemagick` ships an empty `type.xml` so SVG
  rendering blows up with `unable to read font ''`. The chezmoi config
  must drop a user-level `~/.config/ImageMagick-7/type.xml` registering
  some system fonts AND set
  `vim.env.MAGICK_CONFIGURE_PATH = "$HOME/.config/ImageMagick-7:<brew-prefix>/etc/ImageMagick-7"`
  inside nvim (brew's IM does not auto-search `~/.config`). This used to
  live in this script; now the install side just installs `imagemagick`
  via brew.
- tmux: image.nvim needs `set -gq allow-passthrough on` (tmux 3.3+) when
  nvim is launched inside tmux, otherwise `:checkhealth image.nvim` errors
  with "tmux does not have allow-passthrough enabled" and plots never
  render. The chezmoi'd `~/.tmux.conf` is expected to set this.
- tmux plugins: `install.d/12-tmux.sh` git-clones `tmux-plugins/tpm`,
  `tmux-resurrect` and `tmux-continuum` into `~/.tmux/plugins/<repo>` (TPM's
  own layout; skipped if already cloned). The chezmoi'd `~/.tmux.conf`
  declares the **same list** as `@plugin` lines and loads TPM last, guarded
  by `test -x` so a box without the clones still starts tmux. Add a plugin on
  both sides. The step must not call TPM's `bin/install_plugins`: it runs
  `tmux start-server`, which loads the conf, and continuum's auto-restore
  (`@continuum-restore on`) would replay the last save into that headless
  server whenever no other tmux server is running. Claude Code panes are
  pinned to their conversation by `~/.claude/tmux-resurrect-hook.sh`
  (chezmoi, `@resurrect-hook-post-save-layout`): it reads
  `~/.claude/sessions/<pid>.json` (`sessionId`, `tmux` pane id) for live
  interactive sessions and rewrites those panes' saved command to
  `claude --resume <id>`; `@resurrect-processes '"~claude --resume"'`
  makes restore re-run it.
- new-notebook creation and the notebook LSP workaround (jupytext's `BufReadCmd`
  takeover): `.claude/skills/nvim-notebook/SKILL.md`.
- basedpyright vs pyright: this script installs `basedpyright` globally via
  npm (and uninstalls any old `pyright` it finds). The chezmoi'd
  `lua/plugins/lspconfig.lua` is expected to disable `pyright` in its
  servers table — running both against the same buffer leads to duplicate
  diagnostics if LazyVim's `lang.python` extra is enabled. It must also set
  `basedpyright = { mason = false }` so the npm binary wins over a Mason
  copy. Note a missing `pyright = { enabled = false }` does **not** look
  broken: basedpyright's npm package ships its own `pyright` /
  `pyright-langserver` shims (symlinks into `node_modules/basedpyright`), so
  LazyVim's default pyright config resolves to a binary that runs — you just
  get basedpyright's engine under pyright's defaults instead of the fork's
  stricter ones. `:LspInfo` naming `pyright` is the tell.
  The same spec's `<leader>ct`/`<leader>cT` inlay-hint keys have their own
  traps — see the `nvim-notebook` skill.
- bazel helper: `~/.local/bin/bazel-compile-commands` is installed by this
  script (what it writes and the hedron `py_binary` patch are explained in
  `install.d/06-bazel-helper.sh` and `install.d/files/bazel-compile-commands`).
  None of the paths it writes are dotfiles, so they belong here, not in
  chezmoi. Container `$USER`/GID gotchas, the ROCm `--config` note and
  clangd-on-macOS triage: `.claude/skills/bazel-clangd-triage/SKILL.md`.
- Claude Code CLI: native build under `~/.local/share/claude/versions/<ver>`,
  launcher `~/.local/bin/claude` — same `~/.local/bin`-on-PATH contract as
  jupytext (install details in `install.d/08-claude.sh`). Config under `~/.claude/`.
  chezmoi manages that dir: `~/.claude/settings.json` wires `Stop` and
  `Notification` hooks to `~/.claude/notify.sh`, which rings the bell in the
  tmux pane that finished (`$TMUX_PANE`) and shows a `display-message`; the
  chezmoi'd `~/.tmux.conf` sets `window-status-bell-style` so that window's
  tab turns red. Install-side dependency: tmux ≥ 3.2 for
  `display-message -d` — already covered by `MIN_TMUX_VERSION` (3.3). Don't
  drop the floor below 3.2.
- Terraform: `install.d/16-terraform.sh` installs `terraform`, `terraform-ls`
  and `tflint` (gated by `INSTALL_TERRAFORM`). `tflint` comes from the pinned
  GitHub release zip on both OSes (`/usr/local/bin` on Linux, `~/.local/bin`
  on macOS) — homebrew-core dropped the formula, so `brew_ensure tflint`
  aborts the whole run with "No available formula". The chezmoi'd `lazyvim.json` enables
  `lazyvim.plugins.extras.lang.terraform` and `private_terraform.lua`
  (a) disables Mason for `terraformls` so this script's binary wins,
  (b) strips `tflint` from Mason's `ensure_installed`, (c) strips
  `hcl`/`terraform` from `nvim-treesitter`'s `ensure_installed`, and
  (d) adds `hashivim/vim-terraform` for syntax highlighting. The
  treesitter exclusion is load-bearing on Ubuntu 22.04: nvim-treesitter
  (main branch) compiles parsers via a `tree-sitter` CLI; the Mason
  and npm prebuilt binaries both link against glibc 2.39+ and fail on
  jammy's glibc 2.35, and building tree-sitter-cli from source also
  fails because current transitive deps need cargo 1.85+ while jammy
  ships cargo 1.75. Rather than fight that, we let `vim-terraform`
  handle highlighting (pure vimscript, no compile) and skip the
  treesitter parser for hcl/terraform entirely.
- `~/.cargo/bin` on PATH: the mermaid step (`install.d/18-mermaid.sh`) installs
  `mmdflux` via a user-local rustup/cargo toolchain, so the chezmoi'd shell rc
  is expected to prepend `~/.cargo/bin` — same contract as `~/.local/bin`.

## Single source of truth
Everything install-side lives under `install.sh` + `install.d/`. There is
no Ansible, no Makefile, no nested install directories. The two-level
limit (driver → step) is intentional; if you find yourself wanting a
third level, lift the shared code into `install.sh` instead.
Hard rule: at most two levels of scripts (`install.sh` → `install.d/*.sh`).
Subscripts are sourced by the driver and must not source other subscripts;
anything reused by more than one step belongs in `install.sh`.

## Re-run contract
The script is designed to be run repeatedly on the same box:
- Each step is gated by a per-tool **`MIN_*` floor** declared at the top of
  `install.sh` (`MIN_NVIM_VERSION`, `MIN_FZF_VERSION`, `MIN_CLANGD_VERSION`,
  etc.). If the installed tool is at or above the floor, the step is a
  no-op; if it's below, the step reinstalls/upgrades. Don't go back to
  gating on bare `command -v <tool>` or `brew list --formula <name>` —
  those let stale pre-existing binaries win and reintroduce the version
  trap. Bump the floor when a chezmoi-side config (or another step) starts
  relying on a feature that's only in a newer release.
- `version_ge CUR MIN` and `tool_version_ok CMD MIN` in `install.sh` are
  the canonical version helpers — call them rather than open-coding awk
  comparisons. `brew_ensure FORMULA [MIN_VER]` is the macOS equivalent of
  "install or upgrade to the floor"; passing no MIN keeps the legacy
  install-if-missing behavior for prereqs that don't have a feature floor.
- `npm i -g` for basedpyright/bw(Linux) is unconditional — npm
  always installs the latest, so a floor would just be noise. Claude Code
  is likewise floor-less: the native build auto-updates, and re-runs call
  `claude update`.

## Conventions
- Toggles are env vars with documented defaults; never positional args.
- `run_as_user` wraps any command that touches `$USER_HOME` so files don't
  end up owned by root. On Linux it's `sudo -u $TARGET_USER -H --`; on
  macOS it's a passthrough (we're already the user). New code that writes
  into `$USER_HOME` should go through `run_as_user` even though it's a
  no-op on macOS — that's how we keep the Linux path correct without
  branching at every call site.
- Comments at the top of `install.sh` enumerate every persistent system
  change per OS (apt sources, brew formulae, symlinks, alternatives) and
  how to undo them. Keep that list accurate when you add steps — it lives
  in the driver, not the per-step files.

## Testing changes
No CI: run `bash -n` + shellcheck on `install.sh`, `install.d/*.sh`,
`install.d/files/*` before finishing.
For end-to-end testing on Linux, the cheap path is a throwaway WSL distro
or a Docker container running Ubuntu 22.04 — the Linux path is destructive
(apt sources, /usr/local, /usr/bin alternatives) so don't smoke-test it on
a machine you care about. The macOS path is much less destructive (only
brew installs + user-local symlinks under `~/.local/bin`), but smoke-test
on a spare account or VM if you want to be safe.

## Jupyter stack notes
The notebook workflow is `jupytext.nvim` + `molten-nvim` + `image.nvim`. The
install side is the venv at `~/.local/share/nvim-venv`; the wiring
(`vim.g.python3_host_prog`, plugin specs) is chezmoi's. The details live in
skills under `.claude/skills/` — load the relevant one before touching that area:
- `nvim-notebook` — venv/pynvim triage, `:UpdateRemotePlugins`, cells are
  extmarks, `:MoltenHideOutput`, the cell debugger (`<leader>mD`), inlay hints,
  which terminals render images.
- `molten-patches` — molten-nvim carries local patches applied by the chezmoi'd
  `private_molten.lua`, so load `molten-patches` before updating or pinning
  molten or debugging vanished output or 100% CPU.
- `bazel-clangd-triage` — container `$USER`/GID gotchas, ROCm `--config`,
  clangd not attaching on macOS.
- `nvim-pdf` — PDF viewing wiring and traps (pdfreader.nvim, snacks.image,
  ghostscript).

### Don't run headless `nvim --headless +Lazy! sync` from this script
It hangs: LazyVim's startup version check fires `getchar()` and libuv's
kevent on `/dev/null` blocks forever (see the `MIN_NVIM_VERSION` comment in
`install.sh`), and the LazyVim default plugin set has shown other intermittent
hangs inside `os_inchar`/kevent even with a current nvim.
- Don't try to "fix" a hang by piping stdin from `/dev/null` — that
  doesn't help, because the block is in libuv's kevent, not in a
  `read()` syscall.

The script used to do a headless `nvim --headless +Lazy! sync +qa` (and a
forced `Lazy! load molten-nvim +UpdateRemotePlugins`) at install time,
but separately from the version-mismatch hang above, headless sync of
the LazyVim default plugin set has shown other intermittent hangs inside
`os_inchar`/kevent. Don't re-add headless sync — let the user's first
interactive `nvim` do it, which is what lazy.nvim is designed for anyway.
