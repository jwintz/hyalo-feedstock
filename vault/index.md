---
title: Hyalo Feedstock
description: A reproducible Emacs build system for macOS using Pixi
navigation: false
---

::u-page-hero
---
title: Hyalo Feedstock
description: A reproducible build system for GNU Emacs targeting macOS. Pristine source, custom patches, native compilation, and a codesigned Emacs.app — all driven by Pixi tasks.
links:
  - label: Get Started
    to: /home
    icon: i-lucide-arrow-right
    color: neutral
    size: xl
  - label: View on GitHub
    to: https://github.com/jwintz/hyalo-feedstock
    icon: simple-icons-github
    color: neutral
    variant: outline
    size: xl
---
::

::u-page-grid{class="lg:grid-cols-3 max-w-(--ui-container) mx-auto px-4 pb-24"}

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-1
to: /guide/quickstart
icon: i-lucide-package
---
#title
Pixi-Powered

#description
All build steps as `pixi run` tasks. `prep`, `patch`, `autogen`, `configure`, `build`, `install` — a clean dependency chain from source to app.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-1
to: /guide/native-compilation
icon: i-lucide-zap
---
#title
Native Compilation

#description
Built with `--with-native-compilation` via libgccjit. Every `.el` file compiles ahead-of-time. The result launches in milliseconds and never stutters.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-1
to: /guide/patches
icon: i-lucide-git-merge
---
#title
macOS Patches

#description
Transparency, appearance, and fix patches applied to a pristine Emacs source. The `emacs/` submodule is never modified — all work happens in `emacs-build-macos/`.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-1
to: /guide/quickstart
icon: i-lucide-shield-check
---
#title
Codesigned Bundle

#description
`pixi run install` creates and codesigns `Emacs.app` from the compiled nextstep build. Ready for Hyalo's dynamic module loading.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-1
to: /guide/quickstart
icon: i-lucide-refresh-cw
---
#title
Pristine Reset

#description
The build directory is always derived from the pristine source. `pixi run prep` resets everything. No stale artifacts, no manual cleanup.
:::

:::u-page-card
---
spotlight: true
class: col-span-3 lg:col-span-1
to: /guide/quickstart
icon: i-lucide-cpu
---
#title
Module Support

#description
Built with `--with-modules` — required for Hyalo's Swift dynamic module. Load native `.dylib` modules directly into the Emacs process.
:::

::
