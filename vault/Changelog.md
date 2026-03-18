---
title: Changelog
description: Release history and notable changes to Hyalo Feedstock
navigation:
  icon: i-lucide-history
  order: 98
order: 98
tags:
  - changelog
  - releases
---

All notable changes to Hyalo Feedstock are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

:changelog-versions{:versions='[{"title":"Unreleased","description":"Initial revision"}]'}

---

## Unreleased

### Added

- Reproducible build system for GNU Emacs on macOS using Pixi
- `prep` task — syncs pristine `emacs/` submodule to `emacs-build-macos/` via `rsync --delete`
- `patch` task — applies all macOS-specific patches in order
- `autogen` task — runs `./autogen.sh` to generate the configure script
- `configure` task — configures with `--with-ns --with-modules --with-native-compilation --with-gnutls --with-tree-sitter`
- `build` task — compiles Emacs using all available CPU cores
- `install` task — packages and codesigns `Emacs.app` from the nextstep build
- `run` task — launches the built `Emacs.app`
- `clean-builds` task — removes `emacs-build-macos/` without touching the pristine submodule
- `frame-transparency.patch` — adds `ns-background-blur` and `ns-alpha-elements` frame parameters
- `system-appearance.patch` — adds `ns-appearance-dark-aqua` enum variant
- `unidata-gen-incf.patch` — fixes incremental Unicode data generation on macOS
- `loaddefs-gen-fix.patch` — fixes loaddefs generation compatibility
- `derived-fix.patch` — fixes derived data generation issue
- Pixi environment pinning libgccjit ≥ 15.2.0 for native compilation
- Pixi environment pinning libtree-sitter ≥ 0.20.10 for syntax highlighting
- Custom Emacs icon (`icons/Emacs.icns`) applied during patch stage
- Documentation vault published via Lithos
