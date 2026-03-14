---
title: Hyalo Feedstock
description: A reproducible Emacs build system for macOS
icon: i-lucide-package
order: 0
navigation:
  title: Home
  icon: i-lucide-home
  order: 0
---

Hyalo Feedstock provides a reproducible build system for GNU Emacs targeting macOS (as `Emacs.app`) using the [Pixi](https://pixi.sh) package manager. Pristine source, custom patches, native compilation via libgccjit, and a codesigned bundle.

## Quick Start

```bash
git clone --recurse-submodules <repository-url>
cd hyalo-feedstock
pixi install
pixi run prep && pixi run patch && pixi run autogen && pixi run configure && pixi run build && pixi run install
```

## Requirements

- macOS 14+ with Apple Silicon (arm64)
- [Pixi](https://pixi.sh) installed

## Build Tasks

| Task | Description |
|------|-------------|
| `prep` | Sync `emacs/` to `emacs-build-macos/` |
| `patch` | Apply macOS-specific patches |
| `autogen` | Run `./autogen.sh` |
| `configure` | Configure with `--with-ns --with-modules --with-native-compilation` |
| `build` | Compile Emacs |
| `install` | Create and codesign `Emacs.app` |
| `run` | Launch the built `Emacs.app` |

## Documentation

- [[1.guide/1.quickstart|Quick Start]]
- [[1.guide/2.tasks|Build Tasks]]
- [[1.guide/3.patches|Patches]]
- [[1.guide/4.native-compilation|Native Compilation]]
