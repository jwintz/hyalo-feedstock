;;; ios-win.el --- iOS window system configuration  -*- lexical-binding: t -*-

;; Copyright (C) 2025 Free Software Foundation, Inc.

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or (at
;; your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This file handles the iOS window system initialization.
;; It is loaded during Emacs startup when the window-system is 'ios.

;;; Code:

(message "ios-win.el: LOADING - about to provide 'ios feature")

(eval-when-compile (require 'cl-lib))

;; Autoload cl-every from cl-extra (needed by help-fns.el for C-h v)
(autoload 'cl-every "cl-extra" nil nil)

;; Provide the ios feature so startup.el can find us
(provide 'ios)
(message "ios-win.el: PROVIDED 'ios feature")

(require 'frame)
(require 'mouse)
(require 'fontset)
(require 'dnd)

;; Load common window system code
(require 'term/common-win)

(declare-function x-handle-args "common-win" (args))
(declare-function x-open-connection "iosfns.m"
                  (display &optional xrm-string must-succeed))
(declare-function ios-own-selection-internal "iosfns.m" (selection value))
(declare-function ios-disown-selection-internal "iosfns.m" (selection))
(declare-function ios-get-selection "iosfns.m" (selection &optional target-type))

(defvar x-invocation-args)
(defvar x-command-line-resources)

(defvar ios-initialized nil
  "Non-nil if the iOS window system has been initialized.")

;; iOS-specific variables
(defvar ios-command-modifier 'super
  "The modifier key that maps to the iOS Command key.")

(defvar ios-option-modifier 'meta
  "The modifier key that maps to the iOS Option key.")

(defvar ios-control-modifier 'control
  "The modifier key that maps to the iOS Control key.")

;; Handle command-line arguments
(defun ios-handle-args (args)
  "Handle iOS-specific command line ARGS."
  ;; For now, just pass through to X handler
  (x-handle-args args))

;; Debug: Show user-emacs-directory, HOME, and load-path early
;; Note: keep this simple as cl-lib isn't loaded during pdmp generation
(message "ios-win.el: HOME=%s" (getenv "HOME"))
(message "ios-win.el: user-emacs-directory=%s" user-emacs-directory)
(message "ios-win.el: load-path count=%d" (length load-path))

;; Set up user-emacs-directory for iOS.
;; HOME is set to the app's Documents folder by main.m.
;; We use ~/.emacs.d/ which will be visible in Files app as "On My iPad" > "Emacs" > ".emacs.d"
;; Note: Files starting with . are hidden by default in Files app, but accessible.
;; For easier access, we also support ~/emacs.d/ (without the dot).
(defun ios-setup-user-directory ()
  "Set up user-emacs-directory for iOS."
  (let* ((home (getenv "HOME")))
    ;; XDG_CONFIG_HOME is set to HOME in main.m, so user-emacs-directory
    ;; will be $HOME/emacs/ (visible in Files app, no leading dot).
    ;; We just need to set default-directory for convenience.
    (setq default-directory (file-name-as-directory home))
    (message "ios-win.el: HOME=%s user-emacs-directory=%s" home user-emacs-directory)))

;; Run early so startup.el finds the right init file
;; Note: window-system may not be set yet during pdmp loading,
;; so we also run this via emacs-startup-hook as a fallback.
(when (eq window-system 'ios)
  (ios-setup-user-directory))

;; Fallback: also set up directory at startup if not already done
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (and (eq window-system 'ios)
                       (not (string-suffix-p "emacs.d/" user-emacs-directory)))
              (ios-setup-user-directory)))
          -90)  ;; Run early in the hook sequence

;; iCloud Documents support
;; The iCloud container path is provided by iOS at runtime.
;; We define a function to get it and set up shortcuts.
(defvar ios-icloud-path nil
  "Path to the iCloud Documents container, if available.
This is set during initialization if iCloud is available.")

(defun ios-init-icloud ()
  "Initialize iCloud Documents path if available.
The iCloud container is at ~/Library/Mobile Documents/iCloud~org~gnu~emacs/Documents/
but this path may not exist until iCloud syncs."
  (let* ((home (getenv "HOME"))
         ;; iOS stores iCloud containers in ~/Library/Mobile Documents/
         ;; The container ID dots are replaced with tildes
         (icloud-container "iCloud~org~gnu~emacs")
         (icloud-docs (expand-file-name
                       (format "Library/Mobile Documents/%s/Documents/" icloud-container)
                       home)))
    (if (file-directory-p icloud-docs)
        (progn
          (setq ios-icloud-path icloud-docs)
          (message "ios-win.el: iCloud Documents available at %s" icloud-docs))
      (message "ios-win.el: iCloud Documents not yet available (container not synced)"))))

(defun ios-open-icloud ()
  "Open iCloud Documents folder in Dired.
If iCloud is not available, show an error."
  (interactive)
  (if ios-icloud-path
      (dired ios-icloud-path)
    (if-let ((home (getenv "HOME"))
             (icloud-docs (expand-file-name
                          "Library/Mobile Documents/iCloud~org~gnu~emacs/Documents/"
                          home)))
        (if (file-directory-p icloud-docs)
            (progn
              (setq ios-icloud-path icloud-docs)
              (dired icloud-docs))
          (message "iCloud Documents not available. Check that iCloud is enabled in Settings."))
      (message "Cannot determine iCloud path."))))

(defun ios-open-local ()
  "Open the local Documents folder in Dired.
This folder is visible in Files app as 'On My iPad' > 'Emacs'."
  (interactive)
  (dired (getenv "HOME")))

;; Initialize the iOS window system
(cl-defmethod window-system-initialization (&context (window-system ios)
                                            &optional _display)
  "Initialize Emacs for the iOS window system."
  (message "ios-win.el: window-system-initialization starting")
  (cl-assert (not ios-initialized))

  ;; Set up user-emacs-directory FIRST, before anything else.
  ;; This must happen before startup.el looks for init files.
  (ios-setup-user-directory)

  ;; Handle command line arguments
  (setq command-line-args (ios-handle-args command-line-args))
  (message "ios-win.el: args handled")

  ;; Setup the default fontset
  (condition-case err
      (create-default-fontset)
    (error (message "ios-win.el: create-default-fontset error: %S" err)))
  (message "ios-win.el: fontset created")

  ;; Open connection to the iOS display
  (x-open-connection (or (system-name) "") x-command-line-resources t)
  (message "ios-win.el: x-open-connection done")

  ;; Font-related settings - enable scalable fonts
  (setq scalable-fonts-allowed t)
  (message "ios-win.el: faces setup done")

  ;; NOTE: display-type and background-mode are now automatically determined
  ;; by frame-set-background-mode in faces.el because:
  ;; 1. display-graphic-p returns t for iOS (via patched frame.el)
  ;; 2. display-color-p returns t for iOS (via xw-display-color-p returning Qt)
  ;; 3. iOS dpyinfo has color_p=YES and n_planes=24

  ;; Disable bidirectional text processing to avoid crashes during startup.
  (setq bidi-display-reordering nil)
  (setq-default bidi-display-reordering nil)
  (setq bidi-paragraph-direction 'left-to-right)
  (setq-default bidi-paragraph-direction 'left-to-right)
  ;; Also set in scratch buffer directly
  (when (get-buffer "*scratch*")
    (with-current-buffer "*scratch*"
      (setq bidi-display-reordering nil)
      (setq bidi-paragraph-direction 'left-to-right)))

  ;; Enable font-lock mode for syntax highlighting.
  ;; Do this directly here since hooks may not be processed.
  (require 'font-lock)
  (require 'jit-lock)
  (global-font-lock-mode 1)
  (setq font-lock-maximum-decoration t)
  ;; Disable jit-lock deferral - fontify immediately
  (setq jit-lock-defer-time nil)
  (setq jit-lock-stealth-time nil)
  ;; Use immediate fontification instead of deferred
  (setq font-lock-support-mode 'jit-lock-mode)
  
  ;; Force fontification when visiting files
  (add-hook 'find-file-hook
            (lambda ()
              (when (and font-lock-mode (not (memq major-mode '(fundamental-mode))))
                (message "ios: forcing fontification for %s" (buffer-name))
                (font-lock-ensure)
                (redisplay t))))
  
  (message "ios-win.el: font-lock enabled, global-font-lock-mode=%s"
           (if (bound-and-true-p global-font-lock-mode) "t" "nil"))

  ;; Register that we're initialized
  (setq ios-initialized t)
  
  ;; Initialize iCloud access
  (ios-init-icloud)
  
  (message "ios-win.el: initialization complete"))

;; Setup Info directory for iOS bundle
;; The info directory is bundled alongside lisp/ and etc/ in Resources/
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (featurep 'ios)
              (let ((info-dir (expand-file-name "../info" data-directory)))
                (when (file-directory-p info-dir)
                  (message "ios-win.el: adding info directory: %s" info-dir)
                  (require 'info)
                  ;; Ensure Info-default-directory-list is a list before adding
                  (unless (listp Info-default-directory-list)
                    (setq Info-default-directory-list nil))
                  (add-to-list 'Info-default-directory-list info-dir)
                  ;; Also set Info-directory-list directly if it exists
                  (when (boundp 'Info-directory-list)
                    (unless (listp Info-directory-list)
                      (setq Info-directory-list nil))
                    (add-to-list 'Info-directory-list info-dir))
                  (message "ios-win.el: Info-default-directory-list = %S" Info-default-directory-list)
                  )))))

;; Handle command line arguments for iOS
(cl-defmethod handle-args-function (args &context (window-system ios))
  (ios-handle-args args))

;; Create a frame for iOS
(cl-defmethod frame-creation-function (params &context (window-system ios))
  (x-create-frame-with-faces params))

;; Associate display names with iOS window system
(add-to-list 'display-format-alist '(".*" . ios))

;; GUI selection support
(cl-defmethod gui-backend-set-selection (selection value
                                         &context (window-system ios))
  (when value
    (ios-own-selection-internal selection value)))

(cl-defmethod gui-backend-selection-owner-p (selection
                                             &context (window-system ios))
  nil)

(cl-defmethod gui-backend-selection-exists-p (selection
                                              &context (window-system ios))
  nil)

(cl-defmethod gui-backend-get-selection (selection-symbol target-type
                                         &context (window-system ios))
  (ios-get-selection selection-symbol target-type))

;; Basic frame appearance
(setq frame-title-format "%b"
      icon-title-format "%b")

;; Enable global font-lock mode for syntax highlighting.
;; We do this via multiple mechanisms to ensure it takes effect:
;; 1. Directly in emacs-startup-hook (runs after command line processing)
;; 2. As a fallback in after-init-hook
(add-hook 'emacs-startup-hook
          (lambda ()
            (message "ios-win.el: enabling global-font-lock-mode via emacs-startup-hook...")
            (require 'font-lock)
            (global-font-lock-mode 1)
            (setq-default font-lock-maximum-decoration t)
            
            ;; Ensure all lisp subdirectories are in load-path
            ;; During bootstrap, only a subset are included
            (when data-directory
              (let ((lisp-dir (expand-file-name "../lisp" data-directory)))
                (when (file-directory-p lisp-dir)
                  (dolist (subdir '("calendar" "net" "mail" "gnus" "org" "cedet" "url"))
                    (let ((full-path (expand-file-name subdir lisp-dir)))
                      (when (and (file-directory-p full-path)
                                 (not (member full-path load-path)))
                        (add-to-list 'load-path full-path)))))))
            
            ;; Load cl-extra for cl-every (needed by help-fns.el)
            (condition-case err
                (progn
                  (require 'cl-lib)
                  (require 'cl-extra)
                  (message "ios-win.el: cl-extra loaded, cl-every=%s" (fboundp 'cl-every)))
              (error (message "ios-win.el: ERROR loading cl-extra: %s" err)))
            (message "ios-win.el: global-font-lock-mode enabled")))

;; Fallback: also add to after-init-hook
(add-hook 'after-init-hook
          (lambda ()
            (unless (bound-and-true-p global-font-lock-mode)
              (require 'font-lock)
              (global-font-lock-mode 1)
              (message "ios-win.el: enabled global-font-lock-mode via after-init-hook"))
            ;; Also try to load cl-extra here as backup
            (unless (fboundp 'cl-every)
              (condition-case err
                  (progn
                    (require 'cl-lib)
                    (require 'cl-extra)
                    (message "ios-win.el: cl-extra loaded via after-init-hook"))
                (error (message "ios-win.el: ERROR loading cl-extra in after-init: %s" err))))))

;; Provide the features
(provide 'ios-win)
(provide 'term/ios-win)

;;; ios-win.el ends here
