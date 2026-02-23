# Separate Build Directories Implementation

## Summary

Implemented separate build directories for macOS and iOS builds to allow parallel builds without conflict.

## New Directory Structure

```
hyalo-feedstock-unified/
├── emacs/                    # Pristine git submodule (never touched)
├── emacs-build-macos/        # Copied from emacs/, patched for macOS
├── emacs-build-ios-sim/      # Copied from emacs/, patched for iOS Simulator
├── emacs-build-ios-device/   # Copied from emacs/, patched for iOS Device
├── pixi.toml                 # Tasks use respective build dirs
└── ...
```

## Key Changes

### 1. New Prep Tasks

Added prep tasks that copy from pristine `emacs/` to build directories:

- `mac_prep`: rsync emacs/ to emacs-build-macos/
- `ios_sim_prep`: rsync emacs/ to emacs-build-ios-sim/
- `ios_device_prep`: rsync emacs/ to emacs-build-ios-device/

### 2. Updated Task Directories

All tasks now use their respective build directories:

- macOS tasks: `cwd = "emacs-build-macos"`
- iOS Simulator tasks: `cwd = "emacs-build-ios-sim"`
- iOS Device tasks: `cwd = "emacs-build-ios-device"`

### 3. Updated Dependencies

Patch tasks now depend on prep tasks:

- `mac_patch` depends on `mac_prep`
- `ios_patch` depends on `ios_sim_prep`
- `ios_device_patch` depends on `ios_device_prep`

### 4. Updated Scripts

- `install-ios-src.sh` now accepts `BUILD_DIR` environment variable
- Defaults to `emacs-build-ios-sim` if not specified

### 5. Updated Path References

- `ios_copy_resources` task now references `emacs-build-ios-sim/` paths
- Output paths updated to include build directory prefix

## New Workflow

### macOS Build

```bash
pixi run mac_prep      # Copy emacs/ to emacs-build-macos/
pixi run mac_patch     # Apply macOS patches
pixi run mac_configure # Configure build
pixi run mac_build     # Build Emacs.app
```

### iOS Simulator Build

```bash
pixi run ios_sim_prep      # Copy emacs/ to emacs-build-ios-sim/
pixi run ios_patch         # Apply iOS patches
pixi run ios_sim_configure # Configure build
pixi run ios_sim_build     # Build temacs
```

### Parallel Builds

Both builds can now proceed independently:

```bash
# Terminal 1 - macOS
pixi run mac_prep && pixi run mac_patch && pixi run mac_configure

# Terminal 2 - iOS Simulator (concurrently)
pixi run ios_sim_prep && pixi run ios_patch && pixi run ios_sim_configure
```

## Cleaning Up

Use the new clean-builds task to remove all build directories:

```bash
pixi run clean-builds
```

The pristine `emacs/` directory is never modified, so no git checkout is needed.

## Benefits

1. **Parallel builds**: macOS and iOS builds can run simultaneously
2. **No conflicts**: Each build has its own directory
3. **Clean separation**: Source (emacs/) is never modified
4. **Deterministic**: Fresh copy for each build ensures clean state
