---
title: About Hyalo Feedstock
description: Background and design philosophy of the hyalo-feedstock build system
icon: i-lucide-info
order: 99
navigation:
  title: About
  icon: i-lucide-info
  order: 99
---

Hyalo Feedstock (from *feedstock* — the raw material fed into a manufacturing process) is the build pipeline that turns pristine GNU Emacs source into a codesigned, native-compilation-enabled `Emacs.app` for macOS.

## Motivation

GNU Emacs ships no official macOS binaries with native compilation enabled. Third-party distributions exist, but they bundle their own opinions about patches and configuration. Hyalo Feedstock takes a different approach: a clean, reproducible build from source with exactly the patches Hyalo needs and nothing else.

The goals are:

1. **Reproducibility** — `pixi run prep && pixi run patch && pixi run autogen && pixi run configure && pixi run build && pixi run install` produces the same result every time on a clean machine
2. **Pristine source** — the `emacs/` submodule is never modified; all work happens in `emacs-build-macos/`, which is always derived from the pristine source via `pixi run prep`
3. **Minimal patches** — only patches that are strictly required for macOS integration or Hyalo's dynamic module are included

## Why Pixi

[Pixi](https://pixi.sh) provides a conda-forge-based environment with exact dependency pinning. This means `libgccjit`, `autoconf`, `automake`, and their transitive dependencies are the same on every machine — no system Homebrew interference, no version drift.

The build runs entirely inside the pixi environment. `which emacs`, `which autoconf`, and `which gcc` all resolve to pixi-managed binaries during the build.

## Relationship to Hyalo

Hyalo depends on this build for:

- **`--with-modules`** — required for `module-load` to work; the Swift `.dylib` cannot be loaded without it
- **`--with-native-compilation`** — Hyalo's `.el` files are compiled ahead of time; this eliminates startup latency and JIT pauses
- **Codesigning** — Hyalo's dynamic module loader requires a codesigned `Emacs.app` bundle on macOS

The output `Emacs.app` is installed at `emacs/nextstep/Emacs.app` and aliased in Hyalo's AGENTS.md as the `emacs` command.

## Patch Philosophy

Patches fall into three categories:

| Category | Examples |
|----------|---------|
| **Appearance** | Transparency support, native dark mode refinements |
| **Fix** | Known macOS-specific bugs not yet upstream |
| **Integration** | Hooks required by Hyalo's Swift module |

No aesthetic or workflow patches are included. If a change is not required for correctness or Hyalo integration, it does not belong here.

## Related

- [[1.guide/1.quickstart|Quick Start]]
- [[1.guide/3.patches|Patches]]
- [[1.guide/4.native-compilation|Native Compilation]]
