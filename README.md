# Hyalo Feedstock - Emacs Build System for macOS and iOS

This repository provides a reproducible build system for GNU Emacs targeting both macOS (as Emacs.app) and iPadOS (as libemacs.a for embedding in Swift apps).

## Quick Start

### Prerequisites

- macOS 14+ with Apple Silicon (arm64)
- Xcode 15+ with iOS 17+ SDK
- [Pixi](https://pixi.sh) package manager installed

### Clone and Setup

```bash
git clone --recurse-submodules <repository-url>
cd hyalo-feedstock-unified
pixi install
```

## Build Workflows

### macOS Build (Emacs.app)

```bash
# Complete macOS build
pixi run mac_prep
pixi run mac_patch
pixi run mac_configure
pixi run mac_build
pixi run mac_install

# Run Emacs
pixi run mac_run
```

Output: `emacs-build-macos/nextstep/Emacs.app`

### iOS Simulator Build (libemacs.a)

```bash
# Complete iOS Simulator build
pixi run ios_sim_prep
pixi run ios_patch
pixi run ios_sim_configure
pixi run ios_sim_build
pixi run ios_sim_build_libemacs

# Copy resources for iOS app
pixi run ios_copy_resources
```

Output: `emacs-build-ios-sim/src/libemacs.a`

### iOS Device Build (libemacs.a)

```bash
# Complete iOS Device build
pixi run ios_device_prep
pixi run ios_device_patch
pixi run ios_device_configure
pixi run ios_device_build
pixi run ios_device_build_libemacs
```

Output: `emacs-build-ios-device/src/libemacs.a`

## Architecture

### Directory Structure

```
hyalo-feedstock-unified/
├── emacs/                    # Pristine git submodule (NEVER modify directly)
├── emacs-build-macos/        # macOS build directory (rsynced + patched)
├── emacs-build-ios-sim/      # iOS Simulator build directory
├── emacs-build-ios-device/   # iOS Device build directory
├── ios/                      # iOS-specific source files (iosterm.m, iosfns.m)
├── ios-sim-deps/            # Pre-built iOS Simulator dependencies
├── ios-deps/                # iOS Device dependencies (build on demand)
├── native-tools/            # Host-native build tools
├── patches/                 # Patch files for Emacs source
├── scripts/                 # Build helper scripts
└── pixi.toml               # Build task definitions
```

### Key Design: Separate Build Directories

Each target (macOS, iOS Simulator, iOS Device) has its own build directory:

- **Source of truth**: `emacs/` - pristine git submodule
- **macOS build**: `emacs-build-macos/` - rsynced from emacs/, then patched
- **iOS Simulator**: `emacs-build-ios-sim/` - rsynced from emacs/, then patched
- **iOS Device**: `emacs-build-ios-device/` - rsynced from emacs/, then patched

This allows:
- Parallel builds (macOS and iOS can build simultaneously)
- No `git checkout .` needed when switching targets
- Pristine source always available

## Build Tasks Reference

### Preparation Tasks

| Task | Description |
|------|-------------|
| `mac_prep` | rsync emacs/ → emacs-build-macos/ |
| `ios_sim_prep` | rsync emacs/ → emacs-build-ios-sim/ |
| `ios_device_prep` | rsync emacs/ → emacs-build-ios-device/ |

### Patch Tasks

| Task | Description |
|------|-------------|
| `mac_patch` | Apply macOS patches to emacs-build-macos/ |
| `ios_patch` | Apply iOS patches to current build directory |

### Configure Tasks

| Task | Description |
|------|-------------|
| `mac_configure` | Configure for macOS with --with-ns |
| `ios_sim_configure` | Configure for iOS Simulator (arm64-apple-ios17.0-simulator) |
| `ios_device_configure` | Configure for iOS Device (arm64-apple-ios) |

### Build Tasks

| Task | Description |
|------|-------------|
| `mac_build` | Build Emacs.app for macOS |
| `ios_sim_build` | Build temacs for iOS Simulator |
| `ios_device_build` | Build temacs for iOS Device |
| `ios_sim_build_libemacs` | Create libemacs.a for iOS Simulator |
| `ios_device_build_libemacs` | Create libemacs.a for iOS Device |

### Resource Tasks

| Task | Description |
|------|-------------|
| `ios_copy_resources` | Copy lisp/, etc/, pdmp to iOS app resources |
| `ios_install_src` | Install iOS source files into build directory |

### Cleanup Tasks

| Task | Description |
|------|-------------|
| `clean-builds` | Remove all build directories (emacs/ stays pristine) |
| `unpatch` | Revert patches in emacs/ (legacy, prefer clean-builds) |
| `clean` | Clean build artifacts in macOS directory |
| `distclean` | Deep clean including configure output |

## Dependencies

### Pre-built Dependencies (iOS Simulator)

Located in `ios-sim-deps/lib/`:
- libxml2.a
- libjansson.a
- libgmp.a
- libgnutls.a
- libnettle.a
- libhogweed.a
- libtasn1.a
- libtree-sitter.a

### Device Dependencies

Build device dependencies on demand:

```bash
./scripts/build-device-deps.sh
```

This populates `ios-deps/lib/` with arm64-apple-ios builds.

## iOS Patches

The iOS port requires 15 patches in `patches/`:

1. **ios-dispnew.patch** - iOS window system initialization (CRITICAL)
2. **ios-terminal.patch** - Terminal implementation for iOS
3. **ios-term.patch** - Terminal driver
4. **ios-epaths.patch** - Path configuration
5. **ios-libs.patch** - Library linking
6. **ios-frame.patch** - Frame support
7. **ios-xfaces.patch** - Face support
8. **ios-image.patch** - Image support
9. **ios-font-driver.patch** - Font driver
10. **ios-font.patch** - Font support
11. **ios-configure-full.patch** - Configure script changes
12. **ios-emacs-entry.patch** - Entry point
13. **ios-compat.patch** - Compatibility patches
14. **ios-macroexp.patch** - Macro expansion
15. **ios-checkstring.patch** - String checking

## Cross-Repository Integration

This feedstock is designed to work with [hyalo-unified](https://github.com/jwintz/hyalo-unified):

```
~/Syntropment/
├── hyalo-unified/           # Swift/Lisp code, Xcode project
└── hyalo-feedstock-unified/ # This repository (C/Emacs builds)
```

The iOS Xcode project references:
- `../hyalo-feedstock-unified/emacs/src/libemacs.a`
- `../hyalo-feedstock-unified/ios-sim-deps/lib/*.a`

## Troubleshooting

### "standard input is not a tty" Error

This means the iOS patches haven't been applied. Run:

```bash
pixi run ios_sim_prep
pixi run ios_patch
```

### Missing Dependencies

If linking fails with missing symbols, ensure dependencies are built:

```bash
# For simulator
pixi run ios_sim_deps

# For device
./scripts/build-device-deps.sh
```

### Clean Build

To start fresh:

```bash
pixi run clean-builds
pixi run ios_sim_prep
pixi run ios_patch
pixi run ios_sim_configure
pixi run ios_sim_build
pixi run ios_sim_build_libemacs
```

## Development Notes

### Never Modify emacs/ Directly

The `emacs/` directory is a git submodule. Any manual edits will be lost when running `pixi run clean-builds` or `git submodule update`.

Always use the build directories:
- Make changes to patches in `patches/`
- Apply via `pixi run ios_patch` (patches emacs-build-ios-sim/)
- Test in the build directory

### Testing Changes

When modifying iOS-specific code in `ios/`:

1. Edit files in `ios/` directory
2. Run `pixi run ios_install_src` to copy to build directory
3. Rebuild: `pixi run ios_sim_build`

## License

This build system is provided under the same license as GNU Emacs (GPLv3+).

The iOS port patches are derived from the Emacs iOS branch and maintained for compatibility with modern iOS SDKs.

## Contributing

1. Test changes with both macOS and iOS Simulator builds
2. Ensure `pixi run clean-builds` works (reproducible builds)
3. Update this README if adding new tasks or changing workflows
4. Document any new patches in `patches/README.md`

## References

- [GNU Emacs](https://www.gnu.org/software/emacs/)
- [Hyalo Project](https://github.com/jwintz/hyalo-unified)
- [Pixi Documentation](https://pixi.sh/latest/)
