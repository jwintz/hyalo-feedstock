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

## Patch System

### Invariant: All Fixes Must Be Patches or ios/ Sources

Build directories (`emacs-build-ios-sim/`, `emacs-build-macos/`) are ephemeral. They are wiped and recreated by `pixi run ios_sim_prep` (rsync from pristine `emacs/`). **Any fix applied directly to a build directory will be lost on the next rebuild.** This is not acceptable.

All changes to Emacs source code must live in one of two places:

1. **`patches/`** -- Diff patches applied to the pristine `emacs/` source by `pixi run ios_patch`. These modify existing Emacs files (`emacs.c`, `macfont.m`, `font.h`, `dispnew.c`, etc.).
2. **`ios/`** -- New iOS-specific source files (`iosterm.m`, `iosfns.m`, `iosgui.h`, `iosdispatch.h`, etc.) copied into the build directory by `pixi run ios_install_src`.

### Reproducing a Build

A clean build must be reproducible by running these commands in sequence:

```bash
pixi run ios_sim_prep          # rsync pristine emacs/ -> emacs-build-ios-sim/
pixi run ios_patch             # apply ALL patches from patches/
pixi run ios_install_src       # copy ios/ source files into build dir
pixi run ios_sim_configure     # configure for iOS Simulator
pixi run ios_sim_build         # compile (temacs link failure is expected)
pixi run ios_sim_build_libemacs  # create libemacs.a from .o files
```

If any step requires a manual fix, that fix is a bug in the patch set.

### Adding or Updating a Patch

When you need to modify an existing Emacs source file for iOS:

1. Make the change in `emacs-build-ios-sim/src/` (the build directory)
2. Generate a diff: `diff -u emacs-build-ios-sim-BEFORE/src/file.c emacs-build-ios-sim/src/file.c`
3. The "BEFORE" baseline is the file after all prior patches in the sequence. The patch order in `pixi.toml` (`ios_patch` task) is the canonical order.
4. Update the corresponding patch in `patches/` or create a new one
5. Add the new patch to the `ios_patch` task in `pixi.toml`
6. Verify: `rm -rf emacs-build-ios-sim && pixi run ios_sim_prep && pixi run ios_patch && pixi run ios_install_src && pixi run ios_sim_configure && pixi run ios_sim_build && pixi run ios_sim_build_libemacs`

### iOS Patches

Patches are applied in order by `pixi run ios_patch`. Order matters because some patches modify the same files.

**Shared patches** (also used by macOS):
- `system-appearance.patch` -- System dark/light mode support
- `frame-transparency.patch` -- Frame alpha and transparency
- `unidata-gen-incf.patch` -- Unicode data generation fix
- `loaddefs-gen-fix.patch` -- Loaddefs generation fix
- `derived-fix.patch` -- Derived mode fix

**iOS build system patches:**
- `ios-build-system.patch` -- Makefile.in: IOS_OBJ, IOS_OBJC_OBJ variables
- `ios-libs.patch` -- Library linking adjustments
- `ios-configure-full.patch` -- configure.ac: `--with-ios` option, HAVE_IOS

**iOS core patches:**
- `ios-emacs-entry.patch` -- emacs.c: `ios_emacs_init` entry point, `syms_of_iosterm/iosfns/fontset` calls, pdmp loading, path setup
- `ios-dispnew.patch` -- dispnew.c: `init_display_interactive` iOS window system init
- `ios-terminal.patch` -- terminal.c: `output_ios` case in `terminal-live-p`
- `ios-epaths.patch` -- epaths.in: iOS path configuration
- `ios-frame.patch` -- frame.c/frame.h: iOS frame support, output_ios
- `ios-xfaces.patch` -- xfaces.c: iOS face support
- `ios-image.patch` -- image.c: iOS image support

**iOS font patches:**
- `ios-font-driver.patch` -- macfont.m: HAVE_IOS guards replacing AppKit with CoreText (NSFont->CTFont, NSFontManager->fixed weight, NSGraphicsContext->ios_frame_get_drawing_context, CTFontManagerCompareFontFamilyNames->CFStringCompare)
- `ios-font.patch` -- font.c/font.h: HAVE_IOS in conditional compilation, `syms_of_macfont` declaration under HAVE_IOS

**iOS safety patches:**
- `ios-compat.patch` -- buffer.c: nil directory fallback
- `ios-debug.patch` -- fileio.c, data.c, search.c: nil guards
- `ios-checkstring.patch` -- lisp.h: nil guard in CHECK_STRING
- `ios-bidi.patch` -- bidi.c: safety during early startup
- `ios-try-window.patch` -- xdisp.c: display safety during early startup
- `ios-character.patch` -- character.c: safety patch
- `ios-bootstrap-progress.patch` -- lread.c: progress callbacks
- `ios-loadup.patch` -- loadup.el: iOS loadup adjustments

**iOS Lisp patches:**
- `ios-macroexp.patch` -- macroexp.el
- `ios-frame-lisp.patch` -- frame.el
- `ios-faces-lisp.patch` -- faces.el
- `ios-cus-edit-lisp.patch` -- cus-edit.el

### iOS Source Files

New files in `ios/` are not patches -- they are standalone source files copied by `install-ios-src.sh`:

| File | Purpose |
|------|---------|
| `iosterm.m` | iOS terminal driver (event loop, display, frame creation). Calls `syms_of_macfont()` to register the CoreText font driver. |
| `iosfns.m` | iOS Lisp functions (x-create-frame, display metrics, clipboard, dispatch system) |
| `iosterm.h` | iOS terminal declarations, EmacsView @interface, display info structs |
| `iosgui.h` | iOS GUI types (event enums, modifier masks, color typedefs) |
| `iosdispatch.h` | Single dispatch system types and macros (DEFUN_IOS) |
| `hyalo-termstubs.c` | Stub functions for iOS terminal |
| `hyalo-win.el` | iOS window system initialization (lisp/term/) |

### Build Artifacts in libemacs.a

The `ios_sim_build_libemacs` task merges `src/*.o` with `lib/libgnu.a` objects. It excludes `regex.o` from libgnu.a because `regex-emacs.o` in `src/` provides the same symbols (`rpl_re_compile_pattern`, `rpl_re_search`, etc.).

## Cross-Repository Integration

This feedstock is designed to work with [hyalo-unified](https://github.com/jwintz/hyalo-unified):

```
~/Syntropment/
├── hyalo-unified/           # Swift/Lisp code, Xcode project
└── hyalo-feedstock-unified/ # This repository (C/Emacs builds)
```

The iOS Xcode project (`hyalo-unified/iOS/project.yml`) references:
- `../hyalo-feedstock-unified/emacs-build-ios-sim/src/libemacs.a` (simulator)
- `../hyalo-feedstock-unified/emacs-build-ios-device/src/libemacs.a` (device)
- `../hyalo-feedstock-unified/ios-sim-deps/lib/*.a` (simulator dependencies)
- `../hyalo-feedstock-unified/ios-deps/lib/*.a` (device dependencies)
- `../hyalo-feedstock-unified/ios/*.h` (header search path)

## Troubleshooting

### "No font backend available" Crash

Emacs crashes during frame creation with `error("No font backend available")`.

**Cause**: `syms_of_macfont()` was not called during initialization. This function sets `macfont_driver.type = Qmac_ct` and registers the CoreText font driver globally. On iOS, it must be called from `syms_of_iosterm()` in `ios/iosterm.m`. On macOS, it is called from `syms_of_nsterm()` in `nsterm.m`.

**Fix**: Ensure `ios/iosterm.m` contains `syms_of_macfont();` in `syms_of_iosterm()`, and ensure `ios-font.patch` declares `syms_of_macfont` under `#ifdef HAVE_IOS` in `font.h`.

### "standard input is not a tty" Error

This means the iOS patches haven't been applied. The critical missing patch is `ios-dispnew.patch` which adds the `#ifdef HAVE_IOS` block in `init_display_interactive()`. Run:

```bash
pixi run ios_sim_prep
pixi run ios_patch
pixi run ios_install_src
```

### Duplicate Symbol Errors When Linking

`-force_load libemacs.a` loads all symbols. Two known conflicts:

1. **`rpl_re_*` symbols**: Both `regex-emacs.o` (src/) and `regex.o` (libgnu.a) define these. The `ios_sim_build_libemacs` task excludes `regex.o` from the gnulib merge. If you build libemacs.a manually, exclude it: `rm -f regex.o` after extracting libgnu.a.

2. **`ios_set_main_emacs_view`**: Defined as `extern` in `iosterm.m` (no body). The real implementation is provided by Swift via `@_cdecl`. If you see a duplicate symbol, ensure `iosterm.m` has `extern void ios_set_main_emacs_view(...)` (declaration only, no function body).

### Missing Dependencies

If linking fails with missing symbols, ensure dependencies are built:

```bash
# For simulator
pixi run ios_sim_deps

# For device
./scripts/build-device-deps.sh
```

### temacs Link Failure

`make -C src bootstrap-emacs` may fail at the temacs link step with `building for 'iOS-simulator', but linking in dylib built for 'macOS'`. This is expected -- temacs cannot link as an iOS executable because the system libz is macOS-only. All `.o` files compile successfully and `ios_sim_build_libemacs` creates `libemacs.a` from them.

### Clean Build

To start fresh:

```bash
rm -rf emacs-build-ios-sim
pixi run ios_sim_prep
pixi run ios_patch
pixi run ios_install_src
pixi run ios_sim_configure
pixi run ios_sim_build
pixi run ios_sim_build_libemacs
```

## Development Notes

### Never Modify emacs/ Directly

The `emacs/` directory is a git submodule. Any manual edits will be lost when running `pixi run clean-builds` or `git submodule update`.

### Never Fix Bugs in Build Directories

Build directories (`emacs-build-ios-sim/`, `emacs-build-macos/`) are ephemeral. `pixi run ios_sim_prep` wipes and recreates them via rsync from `emacs/`. If you fix a bug by editing a file in the build directory, that fix will be lost on the next prep. All fixes must be committed as:
- A patch in `patches/` (for existing Emacs files)
- A source file in `ios/` (for new iOS-specific files)

### Testing Changes to Existing Emacs Source

1. Make the fix in the build directory (for immediate testing)
2. Verify the fix works
3. Generate a patch: `diff -u emacs-build-ios-sim-BASELINE/src/file.c emacs-build-ios-sim/src/file.c`
4. Update the corresponding patch in `patches/`
5. Verify reproducibility: `rm -rf emacs-build-ios-sim && pixi run ios_sim_prep && pixi run ios_patch && pixi run ios_install_src && pixi run ios_sim_configure && pixi run ios_sim_build && pixi run ios_sim_build_libemacs`

### Testing Changes to iOS-Specific Source

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
