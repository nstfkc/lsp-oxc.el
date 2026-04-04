;;; lsp-oxc.el --- LSP client for Oxc tools (Oxlint & Oxfmt) -*- lexical-binding: t -*-

;; Author: Enes Tufekci
;; URL: https://github.com/nstfkc/lsp-oxc.el
;; Keywords: languages, tools, javascript, typescript, lsp
;; Version: 0.2.0
;; Package-Requires: ((emacs "27.1") (lsp-mode "8.0.0"))

;; This file is not part of GNU Emacs.

;;; Commentary:

;; This package provides LSP clients for Oxlint (linter) and Oxfmt (formatter),
;; fast JavaScript/TypeScript tools from the Oxc toolchain written in Rust.
;; It integrates with lsp-mode to provide real-time linting diagnostics,
;; code actions, and formatting.
;;
;; Features:
;; - Automatic activation for JS/TS/MD files when oxlint/oxfmt are available
;; - Supports: .js, .jsx, .ts, .tsx, .mjs, .cjs, .mts, .cts, .md, .mdx
;; - Monorepo support (searches upward for config and binary)
;; - Auto-fix on save support (oxlint)
;; - Format on save support (oxfmt)
;; - Runs as an add-on alongside other LSP servers (e.g., typescript-language-server)
;; - Auto-loads when lsp-mode is enabled (no manual require needed)
;;
;; Usage:
;; 1. Install tools in your project: npm install -D oxlint oxfmt
;; 2. Create .oxlintrc.json and/or .oxfmtrc.json in your project root
;; 3. Open a supported file and run M-x lsp
;;
;; Configuration:
;; (setq lsp-oxlint-autofix-on-save t)  ; Enable auto-fix on save
;; (setq lsp-oxfmt-format-on-save t)    ; Enable format on save
;;
;; Commands:
;; M-x lsp-oxlint-fix  - Apply fixable issues in current buffer
;; M-x lsp-oxfmt-format - Format current buffer
;; M-x lsp-oxc-verify-setup - Debug activation issues

;;; Code:

(require 'lsp-mode)

(defgroup lsp-oxc nil
  "LSP support for Oxc tools."
  :group 'lsp-mode
  :link '(url-link "https://oxc.rs"))

(defcustom lsp-oxc-active-file-types
  (list (rx "." (or "tsx" "jsx" "ts" "js" "mts" "mjs" "cts" "cjs" "md" "mdx") eos))
  "File types that lsp-oxc should activate for."
  :type '(repeat regexp)
  :group 'lsp-oxc)

;;; Oxlint

(defgroup lsp-oxlint nil
  "LSP support for Oxlint."
  :group 'lsp-oxc
  :link '(url-link "https://oxc.rs/docs/guide/usage/linter"))

(defcustom lsp-oxlint-autofix-on-save nil
  "When non-nil, automatically apply oxlint fixes before saving."
  :type 'boolean
  :group 'lsp-oxlint)

(defcustom lsp-oxlint-config-file ".oxlintrc.json"
  "Name of the oxlint configuration file."
  :type 'string
  :group 'lsp-oxlint)

;;; Oxfmt

(defgroup lsp-oxfmt nil
  "LSP support for Oxfmt."
  :group 'lsp-oxc
  :link '(url-link "https://oxc.rs/docs/guide/usage/formatter"))

(defcustom lsp-oxfmt-config-file ".oxfmtrc.json"
  "Name of the oxfmt configuration file."
  :type 'string
  :group 'lsp-oxfmt)

(defcustom lsp-oxfmt-format-on-save nil
  "When non-nil, automatically format buffer with oxfmt before saving."
  :type 'boolean
  :group 'lsp-oxfmt)

;;; Internal variables

(defvar-local lsp-oxlint--bin-path nil
  "Buffer-local path to the oxlint binary.")

(defvar-local lsp-oxlint--activated-p nil
  "Buffer-local flag indicating if oxlint LSP is active.")

(defvar-local lsp-oxfmt--bin-path nil
  "Buffer-local path to the oxfmt binary.")

(defvar-local lsp-oxfmt--activated-p nil
  "Buffer-local flag indicating if oxfmt LSP is active.")

;;; Discovery functions

(defun lsp-oxc--file-can-be-activated (filename)
  "Check if FILENAME matches any of the active file types."
  (seq-some (lambda (pattern) (string-match-p pattern filename))
            lsp-oxc-active-file-types))

(defun lsp-oxlint--find-config (start-dir)
  "Find oxlint config file starting from START-DIR and searching upward."
  (locate-dominating-file start-dir lsp-oxlint-config-file))

(defun lsp-oxlint--find-bin (start-dir)
  "Find oxlint binary starting from START-DIR and searching upward.
Searches for node_modules/.bin/oxlint in parent directories."
  (when-let* ((bin-root (locate-dominating-file
                         start-dir "node_modules/.bin/oxlint")))
    (expand-file-name "node_modules/.bin/oxlint" bin-root)))

(defun lsp-oxlint--activate-p (filename &optional _)
  "Check if oxlint LSP should activate for FILENAME.
Returns non-nil if:
- File type is supported
- Config file exists in project tree
- Oxlint binary is found in node_modules"
  (when-let* ((file-dir (file-name-directory filename))
              ((lsp-oxc--file-can-be-activated filename))
              ((lsp-oxlint--find-config file-dir))
              (bin (lsp-oxlint--find-bin file-dir)))
    (setq-local lsp-oxlint--bin-path bin)
    t))

(defun lsp-oxfmt--find-config (start-dir)
  "Find oxfmt config file starting from START-DIR and searching upward."
  (locate-dominating-file start-dir lsp-oxfmt-config-file))

(defun lsp-oxfmt--find-bin (start-dir)
  "Find oxfmt binary starting from START-DIR and searching upward.
Searches for node_modules/.bin/oxfmt in parent directories."
  (when-let* ((bin-root (locate-dominating-file
                         start-dir "node_modules/.bin/oxfmt")))
    (expand-file-name "node_modules/.bin/oxfmt" bin-root)))

(defun lsp-oxfmt--activate-p (filename &optional _)
  "Check if oxfmt LSP should activate for FILENAME.
Returns non-nil if:
- File type is supported
- Config file exists in project tree
- Oxfmt binary is found in node_modules"
  (when-let* ((file-dir (file-name-directory filename))
              ((lsp-oxc--file-can-be-activated filename))
              ((lsp-oxfmt--find-config file-dir))
              (bin (lsp-oxfmt--find-bin file-dir)))
    (setq-local lsp-oxfmt--bin-path bin)
    t))

;;; User commands

;;;###autoload
(defun lsp-oxlint-fix ()
  "Apply all fixable oxlint issues in the current buffer."
  (interactive)
  (condition-case nil
      (lsp-execute-code-action-by-kind "source.fixAll.oxlint")
    (lsp-no-code-actions
     (when (called-interactively-p 'any)
       (message "Oxlint: No fixes available")))))

;;;###autoload
(defun lsp-oxfmt-format ()
  "Format the current buffer using oxfmt.
Calls the oxfmt binary directly via stdin/stdout to avoid LSP
TextEdit range issues that can truncate file content."
  (interactive)
  (if lsp-oxfmt--activated-p
      (let ((original-point (point))
            (original-buffer (current-buffer)))
        (with-temp-buffer
          (let ((temp-buf (current-buffer))
                (exit-code
                 (with-current-buffer original-buffer
                   (call-process-region (point-min) (point-max)
                                        lsp-oxfmt--bin-path
                                        nil temp-buf nil
                                        "--stdin-filepath"
                                        (buffer-file-name original-buffer)))))
            (if (zerop exit-code)
                (let ((formatted-text (buffer-string)))
                  (with-current-buffer original-buffer
                    (unless (string= formatted-text (buffer-string))
                      (erase-buffer)
                      (insert formatted-text)
                      (goto-char (min original-point (point-max))))))
              (message "Oxfmt: formatting failed (exit code %d)" exit-code)))))
    (message "Oxfmt: Not active in this buffer")))

;;;###autoload
(defun lsp-oxc-verify-setup ()
  "Verify oxlint and oxfmt LSP setup and display diagnostic information.
Useful for debugging activation issues."
  (interactive)
  (let* ((filename (buffer-file-name))
         (file-dir (and filename (file-name-directory filename)))
         (file-type-ok (and filename (lsp-oxc--file-can-be-activated filename)))
         ;; Oxlint checks
         (oxlint-config-dir (and file-dir (lsp-oxlint--find-config file-dir)))
         (oxlint-config-path (and oxlint-config-dir
                                  (expand-file-name lsp-oxlint-config-file oxlint-config-dir)))
         (oxlint-bin-path (and file-dir (lsp-oxlint--find-bin file-dir)))
         (oxlint-bin-exists (and oxlint-bin-path (file-exists-p oxlint-bin-path)))
         (oxlint-bin-executable (and oxlint-bin-exists (file-executable-p oxlint-bin-path)))
         ;; Oxfmt checks
         (oxfmt-config-dir (and file-dir (lsp-oxfmt--find-config file-dir)))
         (oxfmt-config-path (and oxfmt-config-dir
                                 (expand-file-name lsp-oxfmt-config-file oxfmt-config-dir)))
         (oxfmt-bin-path (and file-dir (lsp-oxfmt--find-bin file-dir)))
         (oxfmt-bin-exists (and oxfmt-bin-path (file-exists-p oxfmt-bin-path)))
         (oxfmt-bin-executable (and oxfmt-bin-exists (file-executable-p oxfmt-bin-path))))
    (with-current-buffer (get-buffer-create "*lsp-oxc-verify*")
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "=== Oxc Tools LSP Setup Verification ===\n\n")
        (insert (format "Current file: %s\n" (or filename "N/A")))
        (insert (format "File directory: %s\n\n" (or file-dir "N/A")))
        ;; Oxlint section
        (insert "--- Oxlint (Linter) ---\n\n")
        (insert (format "[%s] File type supported: %s\n"
                        (if file-type-ok "OK" "FAIL")
                        (if filename (file-name-extension filename) "no file")))
        (insert (format "[%s] Config file (%s): %s\n"
                        (if oxlint-config-path "OK" "FAIL")
                        lsp-oxlint-config-file
                        (or oxlint-config-path "not found")))
        (insert (format "[%s] Binary found: %s\n"
                        (if oxlint-bin-exists "OK" "FAIL")
                        (or oxlint-bin-path "not found")))
        (insert (format "[%s] Binary executable: %s\n"
                        (if oxlint-bin-executable "OK" "FAIL")
                        (if oxlint-bin-executable "yes" "no")))
        ;; Oxfmt section
        (insert "\n--- Oxfmt (Formatter) ---\n\n")
        (insert (format "[%s] File type supported: %s\n"
                        (if file-type-ok "OK" "FAIL")
                        (if filename (file-name-extension filename) "no file")))
        (insert (format "[%s] Config file (%s): %s\n"
                        (if oxfmt-config-path "OK" "FAIL")
                        lsp-oxfmt-config-file
                        (or oxfmt-config-path "not found")))
        (insert (format "[%s] Binary found: %s\n"
                        (if oxfmt-bin-exists "OK" "FAIL")
                        (or oxfmt-bin-path "not found")))
        (insert (format "[%s] Binary executable: %s\n"
                        (if oxfmt-bin-executable "OK" "FAIL")
                        (if oxfmt-bin-executable "yes" "no")))
        ;; Summary
        (insert "\n--- Summary ---\n\n")
        (let ((oxlint-ok (and file-type-ok oxlint-config-path oxlint-bin-exists oxlint-bin-executable))
              (oxfmt-ok (and file-type-ok oxfmt-config-path oxfmt-bin-exists oxfmt-bin-executable)))
          (cond
           ((and oxlint-ok oxfmt-ok)
            (insert "All checks passed for both tools! Run M-x lsp to start.\n"))
           ((or oxlint-ok oxfmt-ok)
            (insert (format "%s is ready. Run M-x lsp to start.\n"
                            (if oxlint-ok "Oxlint" "Oxfmt")))
            (insert "\nTo set up the other tool:\n")
            (unless oxlint-ok
              (unless oxlint-config-path
                (insert (format "  - Create %s in your project root\n" lsp-oxlint-config-file)))
              (unless oxlint-bin-exists
                (insert "  - Run: npm install -D oxlint\n")))
            (unless oxfmt-ok
              (unless oxfmt-config-path
                (insert (format "  - Create %s in your project root\n" lsp-oxfmt-config-file)))
              (unless oxfmt-bin-exists
                (insert "  - Run: npm install -D oxfmt\n"))))
           (t
            (insert "Issues found:\n")
            (unless file-type-ok
              (insert "  - Open a supported file (.js, .ts, .md, .mdx, etc.)\n"))
            (insert "\nFor Oxlint:\n")
            (unless oxlint-config-path
              (insert (format "  - Create %s in your project root\n" lsp-oxlint-config-file)))
            (unless oxlint-bin-exists
              (insert "  - Run: npm install -D oxlint\n"))
            (insert "\nFor Oxfmt:\n")
            (unless oxfmt-config-path
              (insert (format "  - Create %s in your project root\n" lsp-oxfmt-config-file)))
            (unless oxfmt-bin-exists
              (insert "  - Run: npm install -D oxfmt\n"))))))
      (special-mode)
      (goto-char (point-min))
      (display-buffer (current-buffer)))))

;;; Hook functions

(defun lsp-oxlint--workspace-p (workspace)
  "Return non-nil if WORKSPACE is an oxlint workspace."
  (eq (lsp--client-server-id (lsp--workspace-client workspace)) 'oxlint))

(defun lsp-oxlint--before-save-hook ()
  "Hook function to run oxlint fixes before save."
  (when lsp-oxlint-autofix-on-save
    (ignore-errors
      (lsp-oxlint-fix))))

(defun lsp-oxlint--setup-hooks ()
  "Set up buffer-local hooks for oxlint."
  (when lsp-oxlint-autofix-on-save
    (add-hook 'before-save-hook #'lsp-oxlint--before-save-hook nil t)))

(defun lsp-oxlint--teardown-hooks ()
  "Remove buffer-local hooks for oxlint."
  (remove-hook 'before-save-hook #'lsp-oxlint--before-save-hook t))

(defun lsp-oxfmt--workspace-p (workspace)
  "Return non-nil if WORKSPACE is an oxfmt workspace."
  (eq (lsp--client-server-id (lsp--workspace-client workspace)) 'oxfmt))

(defun lsp-oxfmt--before-save-hook ()
  "Hook function to format buffer with oxfmt before save."
  (when lsp-oxfmt-format-on-save
    (ignore-errors
      (lsp-oxfmt-format))))

(defun lsp-oxfmt--setup-hooks ()
  "Set up buffer-local hooks for oxfmt."
  (when lsp-oxfmt-format-on-save
    (add-hook 'before-save-hook #'lsp-oxfmt--before-save-hook nil t)))

(defun lsp-oxfmt--teardown-hooks ()
  "Remove buffer-local hooks for oxfmt."
  (remove-hook 'before-save-hook #'lsp-oxfmt--before-save-hook t))

;;; LSP client registration

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection
                   (lambda ()
                     (setq-local lsp-oxlint--activated-p t)
                     (list lsp-oxlint--bin-path "--lsp")))
  :activation-fn #'lsp-oxlint--activate-p
  :server-id 'oxlint
  :priority -1
  :add-on? t))

(lsp-register-client
 (make-lsp-client
  :new-connection (lsp-stdio-connection
                   (lambda ()
                     (setq-local lsp-oxfmt--activated-p t)
                     (list lsp-oxfmt--bin-path "--lsp")))
  :activation-fn #'lsp-oxfmt--activate-p
  :server-id 'oxfmt
  :priority -1
  :add-on? t))

(with-eval-after-load 'lsp-mode
  (add-hook 'lsp-after-open-hook
            (lambda ()
              (when (and lsp-oxlint--activated-p
                         (lsp-oxlint--workspace-p lsp--cur-workspace))
                (lsp-oxlint--setup-hooks))
              (when (and lsp-oxfmt--activated-p
                         (lsp-oxfmt--workspace-p lsp--cur-workspace))
                (lsp-oxfmt--setup-hooks))))

  (add-hook 'lsp-after-uninitialized-functions
            (lambda (workspace)
              (when (lsp-oxlint--workspace-p workspace)
                (lsp-oxlint--teardown-hooks)
                (setq-local lsp-oxlint--activated-p nil))
              (when (lsp-oxfmt--workspace-p workspace)
                (lsp-oxfmt--teardown-hooks)
                (setq-local lsp-oxfmt--activated-p nil)))))

(provide 'lsp-oxc)
;;; lsp-oxc.el ends here
