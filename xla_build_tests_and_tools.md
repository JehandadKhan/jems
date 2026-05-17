# Building XLA Tests and Tools

A quick reference for building and running XLA's test and tool targets with Bazel.

XLA uses **Bazel**. Run all commands from the repo root (the directory containing `WORKSPACE`, `MODULE.bazel`, and `configure.py`).

## 1. Configure once

```sh
./configure.py --backend=CPU
# or for GPU:
./configure.py --backend=CUDA --cuda_compute_capabilities="9.0"
```

This writes a Bazel rc file that subsequent `bazel` commands pick up automatically. Re-run only when you change backend or CUDA capabilities.

## 2. Build everything (tests + tools + libs)

```sh
bazel build //xla/...
```

`//xla/...` is the wildcard for every target under `xla/`. First build takes a long time (LLVM + MLIR + StableHLO).

### A note on `--spawn_strategy=sandboxed`

The XLA docs suggest `--spawn_strategy=sandboxed`, but on hosts where the Linux sandbox can't run every action (older kernels, restricted user namespaces, AppArmor policies on Ubuntu 24.04+) you'll see errors like:

> CppCompile spawn cannot be executed with any of the available strategies: [processwrapper-sandbox]. Your --spawn_strategy, --genrule_strategy and/or --strategy flags are probably too strict.

If that happens, drop the strict pin or allow a local fallback:

```sh
bazel build --spawn_strategy=sandboxed,local //xla/...   # sandbox when possible
bazel build --spawn_strategy=local //xla/...             # no sandbox at all
bazel build //xla/...                                    # let Bazel pick
```

Bazel's action cache survives the failure, so a re-run skips everything that already compiled.

If you want to fix sandboxing rather than work around it (Ubuntu 24.04+ commonly disables unprivileged user namespaces via AppArmor):

```sh
# Quick checks
ls /proc/self/ns/
unshare --user --pid echo ok   # if this fails, user namespaces are restricted

# Re-enable (requires sudo)
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

## 3. Build only the tests

`bazel build //xla/...` already builds test binaries, but if you want to filter:

```sh
# Build every cc_test / xla_cc_test under xla/
bazel build //xla/... --build_tests_only

# Build a single test
bazel build //xla:array_test
bazel build //xla/service:hlo_module_test
```

## 4. Run the tests

```sh
# Run all tests in a package
bazel test //xla/service/...

# Run one test with full output
bazel test //xla:array_test --test_output=all

# Run only tests tagged for CPU
bazel test //xla/... --test_tag_filters=-gpu,-requires-gpu

# GPU tests
bazel test //xla/... --test_tag_filters=gpu --config=cuda
```

Useful flags:

- `--test_output=errors|all|streamed`
- `--runs_per_test=N`
- `--test_filter=Foo.Bar`
- `--cache_test_results=no`

## 5. Build the tools

The CLI tools live under `xla/tools/`. Common ones:

```sh
# HLO compiler/pass driver — the workhorse
bazel build //xla/tools:hlo-opt
bazel build //xla/tools/hlo_opt:opt_main

# Multihost HLO runner (used for replaying dumped HLO on real hardware)
bazel build //xla/tools/multihost_hlo_runner:hlo_runner_main

# Cost / analysis tools
bazel build //xla/tools:compute_cost
bazel build //xla/tools:compute_xspace_stats_main

# HLO graph / extraction utilities
bazel build //xla/tools:hlo_extractor_main
bazel build //xla/tools:hlo_expand_main

# Whole tools tree at once
bazel build //xla/tools/...
```

Built binaries land in `bazel-bin/xla/tools/<name>`. Run them directly:

```sh
./bazel-bin/xla/tools/hlo_opt/opt_main --help
./bazel-bin/xla/tools/multihost_hlo_runner/hlo_runner_main --help
```

## 6. Handy variants

```sh
# Optimized build
bazel build -c opt //xla/tools:hlo-opt

# Show what would build without compiling
bazel query 'tests(//xla/...)'                       # list all test targets
bazel query 'kind("cc_binary", //xla/tools/...)'     # list tool binaries

# Clean if config changes
bazel clean --expunge
```

## Tip

When you want both tests and tools in one shot, `bazel build //xla/...` covers it. Use the narrower targets above when iterating on a single component to keep build times down.

## References

- `docs/developer_guide.md` — getting-started build instructions
- `docs/build_from_source.md` — detailed build configurations (CPU, CUDA, Docker, JAX CI container)
- `docs/tools.md` — descriptions of the XLA tools
- [Bazel issue #7480](https://github.com/bazelbuild/bazel/issues/7480) — context on sandbox strategy failures
