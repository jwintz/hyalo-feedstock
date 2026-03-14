# Hyalo Feedstock - Emacs Build System for macOS

This repository provides a reproducible build system for GNU Emacs targeting macOS (as Emacs.app) using the [Pixi](https://pixi.sh) package manager.

**[Documentation](https://jwintz.github.io/hyalo-feedstock)**

## Quick Start

### Prerequisites

- macOS 26+ with Apple Silicon (arm64)
- [Pixi](https://pixi.sh) installed (`curl -fsSL https://pixi.sh/install.sh | bash`)

### Setup

```bash
git clone --recurse-submodules https://github.com/jwintz/hyalo-feedstock
cd hyalo-feedstock
pixi install
```

## Build Workflow

The build follows a sequence of `pixi` tasks. Each task depends on the previous one.

### 1. Prepare and Patch
Prepare a dedicated build directory by copying the pristine Emacs source and applying patches.

```bash
pixi run prep    # Create emacs-build-macos/ from emacs/
pixi run patch   # Apply transparency and appearance patches
```

### 2. Configure and Build
Generate the build system and compile Emacs. This uses dependencies (gnutls, libxml2, tree-sitter, etc.) provided by the Pixi environment.

```bash
pixi run autogen    # Run ./autogen.sh
pixi run configure  # Configure with --with-ns support
pixi run build      # Build using all available CPU cores
```

### 3. Install and Run
Package the build into a signed `Emacs.app` and launch it.

```bash
pixi run install    # Create and codesign nextstep/Emacs.app
pixi run run        # Launch the built application
```

## Project Structure

```
hyalo-feedstock/
├── emacs/              # Pristine Emacs source (git submodule)
├── emacs-build-macos/  # Active build directory (ephemeral)
├── icons/              # macOS application icons
├── patches/            # Patches for transparency, appearance, and fixes
├── pixi.toml           # Build task definitions and dependencies
└── README.md
```

### Key Design: Pristine Source
The `emacs/` directory is never modified. All work happens in `emacs-build-macos/`. If the build directory becomes inconsistent, you can reset it by running `pixi run prep`.

## Available Tasks

| Task | Description |
|------|-------------|
| `prep` | Sync `emacs/` to `emacs-build-macos/` |
| `patch` | Apply macOS-specific patches |
| `autogen` | Run `./autogen.sh` |
| `configure` | Run `./configure` with optimal macOS flags |
| `build` | Compile Emacs |
| `install` | Create signed `Emacs.app` bundle |
| `run` | Launch the built `Emacs.app` |
| `check` | Run the Emacs test suite |
| `clean-builds` | Remove the `emacs-build-macos/` directory |
| `clean` | Clean build artifacts |
| `distclean` | Run `make distclean` inside the build directory |

## License

This build system is provided under the same license as GNU Emacs (GPLv3+).
