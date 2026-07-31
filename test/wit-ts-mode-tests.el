;;; wit-ts-mode-tests.el --- Tests for wit-ts-mode  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Markus Klink

;; SPDX-License-Identifier: Apache-2.0

;;; Commentary:

;; ERT test suite for `wit-ts-mode'.  Run in batch with:
;;
;;   emacs -Q --batch -L . -l test/wit-ts-mode-tests.el \
;;         -f ert-run-tests-batch-and-exit
;;
;; Every test is skipped (rather than failed) when the `wit' tree-sitter
;; grammar is unavailable, so the suite is safe to run where the grammar
;; or a C compiler is missing.

;;; Code:

(require 'ert)
(require 'ert-x)
(require 'cl-lib)
(require 'wit-ts-mode)
(require 'flymake)
(require 'which-func)

(defmacro wit-ts-mode-tests--with-file (file &rest body)
  "Visit FILE (a name under test/resources/) in `wit-ts-mode' and run BODY.
Skips the test if the WIT grammar is not ready."
  (declare (indent 1) (debug (form body)))
  `(progn
     (skip-unless (treesit-ready-p 'wit t))
     (with-temp-buffer
       (insert-file-contents (ert-resource-file ,file))
       (wit-ts-mode)
       ,@body)))

(defun wit-ts-mode-tests--face-at (needle)
  "Return the face at the start of the first match of NEEDLE."
  (goto-char (point-min))
  (when (search-forward needle nil t)
    (goto-char (match-beginning 0))
    (get-text-property (point) 'face)))

(defun wit-ts-mode-tests--diagnostics ()
  "Return the Flymake diagnostics reported for the current buffer."
  (let (out)
    (wit-ts-mode-flymake (lambda (diags) (setq out diags)))
    out))

;;; Mode setup

(ert-deftest wit-ts-mode-activates ()
  "The mode turns on and creates a parser without error."
  (wit-ts-mode-tests--with-file "sample.wit"
    (should (eq major-mode 'wit-ts-mode))
    (should (treesit-parser-list))
    (should-not (treesit-query-capture
                 (treesit-buffer-root-node) '((ERROR) @e) nil nil t))))

;;; Font-lock

(ert-deftest wit-ts-mode-fontifies-keywords-and-types ()
  "Keywords, types, constants, and functions get the expected faces."
  (wit-ts-mode-tests--with-file "sample.wit"
    (font-lock-ensure)
    (should (eq (wit-ts-mode-tests--face-at "interface")
                'font-lock-keyword-face))
    (should (eq (wit-ts-mode-tests--face-at "point")
                'font-lock-type-face))
    (should (eq (wit-ts-mode-tests--face-at "u32")
                'font-lock-type-face))
    (should (eq (wit-ts-mode-tests--face-at "red")
                'font-lock-constant-face))
    (should (eq (wit-ts-mode-tests--face-at "distance")
                'font-lock-function-name-face))))

;;; Indentation

(ert-deftest wit-ts-mode-indent-is-idempotent ()
  "Reindenting a correctly-indented file leaves it unchanged."
  (wit-ts-mode-tests--with-file "sample.wit"
    (setq-local wit-ts-mode-indent-offset 2)
    (let ((original (buffer-string)))
      (indent-region (point-min) (point-max))
      (should (equal original (buffer-string))))))

(ert-deftest wit-ts-mode-indent-reindents-flattened ()
  "A flattened buffer is restored to the original indentation."
  (wit-ts-mode-tests--with-file "sample.wit"
    (setq-local wit-ts-mode-indent-offset 2)
    (let ((original (buffer-string)))
      ;; Strip leading indentation from every line, then re-indent.
      (goto-char (point-min))
      (while (not (eobp))
        (delete-horizontal-space)
        (forward-line 1))
      (indent-region (point-min) (point-max))
      (should (equal original (buffer-string))))))

;;; Imenu

(ert-deftest wit-ts-mode-imenu-structure ()
  "Imenu groups worlds, interfaces, types, and functions."
  (wit-ts-mode-tests--with-file "sample.wit"
    (let* ((index (funcall imenu-create-index-function))
           (names (lambda (group)
                    (mapcar #'car (cdr (assoc group index))))))
      (should (equal (funcall names "World") '("app")))
      (should (equal (funcall names "Interface") '("things")))
      (should (equal (funcall names "Type")
                     '("point" "color" "shape" "coord")))
      (should (equal (funcall names "Function") '("distance"))))))

;;; Navigation & which-function

(ert-deftest wit-ts-mode-which-function-reports-nesting ()
  "`which-function' reports the enclosing declaration with nesting."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert-file-contents (ert-resource-file "sample.wit"))
    (wit-ts-mode)
    (goto-char (point-min))
    (search-forward "green")
    (should (equal (which-function) "things.color"))))

(ert-deftest wit-ts-mode-forward-sexp-spans-construct ()
  "`forward-sexp' steps over a whole identifier, not one character."
  (wit-ts-mode-tests--with-file "sample.wit"
    (goto-char (point-min))
    (search-forward "rectangle")
    (goto-char (match-beginning 0))
    (let ((start (point)))
      (forward-sexp)
      ;; Moves over the whole identifier as one sexp, not char-by-char.
      (should (>= (- (point) start) (length "rectangle"))))))

;;; Flymake diagnostics

(ert-deftest wit-ts-mode-flymake-clean-file ()
  "A valid file produces no diagnostics."
  (wit-ts-mode-tests--with-file "sample.wit"
    (should-not (wit-ts-mode-tests--diagnostics))))

(ert-deftest wit-ts-mode-flymake-missing-semicolon ()
  "A missing semicolon is reported as an expected-token diagnostic."
  (wit-ts-mode-tests--with-file "missing-semicolon.wit"
    (let ((diags (wit-ts-mode-tests--diagnostics)))
      (should diags)
      (should (seq-some
               (lambda (d)
                 (string-match-p "expected semicolon"
                                 (flymake-diagnostic-text d)))
               diags)))))

(ert-deftest wit-ts-mode-flymake-unterminated-block ()
  "An unterminated block reports an expected closing brace."
  (wit-ts-mode-tests--with-file "unterminated.wit"
    (let ((diags (wit-ts-mode-tests--diagnostics)))
      (should diags)
      (should (seq-some
               (lambda (d)
                 (string-match-p "expected closing brace"
                                 (flymake-diagnostic-text d)))
               diags)))))

(ert-deftest wit-ts-mode-flymake-stray-token ()
  "Unexpected input is quoted in the diagnostic."
  (wit-ts-mode-tests--with-file "stray-token.wit"
    (let ((diags (wit-ts-mode-tests--diagnostics)))
      (should diags)
      (should (seq-some
               (lambda (d)
                 (string-match-p "unexpected"
                                 (flymake-diagnostic-text d)))
               diags)))))

;;; Folding

(ert-deftest wit-ts-mode-hideshow-folds-blocks ()
  "`hs-minor-mode' can hide and show brace blocks."
  (wit-ts-mode-tests--with-file "sample.wit"
    (hs-minor-mode 1)
    (goto-char (point-min))
    ;; Position on the opening brace of the interface, then hide it.
    (search-forward "interface things {")
    (backward-char 1)
    (hs-hide-block)
    (should (seq-some (lambda (o) (overlay-get o 'hs))
                      (overlays-in (point-min) (point-max))))
    ;; Showing all removes the folding overlays.
    (hs-show-all)
    (should-not (seq-some (lambda (o) (overlay-get o 'hs))
                          (overlays-in (point-min) (point-max))))))

;;; Outline

(ert-deftest wit-ts-mode-outline-fold-does-not-swallow-siblings ()
  "Collapsing a block hides only its own body, not later declarations.
Regression test: a `flags' block must not swallow the `type'
declarations that follow it."
  (skip-unless (treesit-ready-p 'wit t))
  (require 'outline)
  (with-temp-buffer
    (insert "interface foo {\n"
            "  flags perm {\n    read,\n    write,\n  }\n"
            "  type after = u32;\n"
            "}\n")
    (wit-ts-mode)
    (outline-minor-mode 1)
    (goto-char (point-min))
    (search-forward "flags perm")
    (beginning-of-line)
    (outline-hide-subtree)
    ;; The line declaring `type after' must remain visible.
    (goto-char (point-min))
    (search-forward "type after")
    (should-not (get-char-property (line-beginning-position) 'invisible))))

(ert-deftest wit-ts-mode-outline-single-line-item-is-heading ()
  "A single-line declaration is recognized as its own outline heading.
Regression test: `outline-on-heading-p' must agree with the
display, otherwise folding a single-line item hides the line
above it."
  (skip-unless (treesit-ready-p 'wit t))
  (require 'outline)
  (with-temp-buffer
    (insert "interface foo {\n"
            "  type a = u32;\n"
            "  type b = u64;\n"
            "}\n")
    (wit-ts-mode)
    (outline-minor-mode 1)
    (goto-char (point-min))
    (search-forward "type b")
    (beginning-of-line)
    (should (outline-on-heading-p))
    ;; Collapsing a leaf item hides nothing (no line above it folds).
    (let ((line-a (progn (goto-char (point-min))
                         (search-forward "type a")
                         (line-beginning-position))))
      (goto-char (point-min))
      (search-forward "type b")
      (beginning-of-line)
      (outline-hide-subtree)
      (should-not (get-char-property line-a 'invisible)))))

;;; Completion

(ert-deftest wit-ts-mode-completion-includes-keywords-and-defs ()
  "Completion candidates include keywords, builtins, and definitions."
  (wit-ts-mode-tests--with-file "sample.wit"
    (let ((cands (wit-ts-mode--completion-candidates)))
      (should (member "interface" cands))   ; keyword
      (should (member "u32" cands))          ; builtin type
      (should (member "point" cands))        ; buffer definition
      (should (member "distance" cands)))))  ; buffer definition

(ert-deftest wit-ts-mode-completion-suppressed-in-comment ()
  "No completion is offered inside a comment."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert "interface foo {\n  // a comment here\n  type t = u32;\n}\n")
    (wit-ts-mode)
    (goto-char (point-min))
    (search-forward "comment here")
    (should-not (wit-ts-mode-completion-at-point))))

(ert-deftest wit-ts-mode-completion-prefix-filtering ()
  "The capf returns candidates matching the typed prefix."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert-file-contents (ert-resource-file "sample.wit"))
    (wit-ts-mode)
    (goto-char (point-max))
    (insert "\ninterface bar {\n  type x = poi")
    (let* ((capf (wit-ts-mode-completion-at-point))
           (prefix (buffer-substring-no-properties (nth 0 capf) (nth 1 capf)))
           (matches (all-completions prefix (nth 2 capf))))
      (should (equal prefix "poi"))
      (should (member "point" matches)))))

;;; Cross-file symbols

(defmacro wit-ts-mode-tests--with-project-file (relpath &rest body)
  "Visit RELPATH (under test/resources/) in `wit-ts-mode' with a file name.
Unlike `wit-ts-mode-tests--with-file', this sets `buffer-file-name'
so the `wit-deps' project-root detection can walk the directory
tree.  Skips the test if the WIT grammar is not ready."
  (declare (indent 1) (debug (form body)))
  `(progn
     (skip-unless (treesit-ready-p 'wit t))
     (let ((file (ert-resource-file ,relpath)))
       (with-temp-buffer
         (insert-file-contents file)
         (setq buffer-file-name file)
         (unwind-protect
             (progn (wit-ts-mode) ,@body)
           ;; Avoid `kill-buffer' prompting about the phantom file.
           (set-buffer-modified-p nil)
           (setq buffer-file-name nil))))))

(ert-deftest wit-ts-mode-wit-root-locates-managed-dir ()
  "`wit-ts-mode--wit-root' finds the deps.toml root and project root."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let* ((roots (wit-ts-mode--wit-root))
           (wit-root (car roots))
           (project-root (cdr roots)))
      (should roots)
      (should (file-exists-p (expand-file-name "deps.toml" wit-root)))
      (should (equal (file-name-nondirectory (directory-file-name wit-root))
                     "wit"))
      ;; Project root is the parent, where `wit-deps' would run.
      (should (equal (expand-file-name wit-root)
                     (expand-file-name "wit/" project-root))))))

(ert-deftest wit-ts-mode-file-definitions-parses-dep ()
  "`wit-ts-mode--file-definitions' returns names from an off-buffer file."
  (skip-unless (treesit-ready-p 'wit t))
  (let* ((dep (ert-resource-file "proj/wit/deps/dep/dep.wit"))
         (names (wit-ts-mode--file-definitions dep)))
    (should (member "dep-iface" names))
    (should (member "widget" names))
    (should (member "gadget" names))))

(ert-deftest wit-ts-mode-external-definitions-included-in-completion ()
  "Completion candidates include symbols defined only in a dep file."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((cands (wit-ts-mode--completion-candidates)))
      ;; Defined in the current buffer.
      (should (member "app" cands))
      ;; Defined only under wit/deps/.
      (should (member "widget" cands))
      (should (member "gadget" cands)))))

(ert-deftest wit-ts-mode-external-definitions-excludes-self ()
  "The current buffer's own file is not re-scanned as an external file."
  (skip-unless (treesit-ready-p 'wit t))
  ;; A file not inside any wit-deps project yields no external defs.
  (with-temp-buffer
    (insert "package a:b;\ninterface solo { type t = u32; }\n")
    (setq buffer-file-name (make-temp-file "wit-solo" nil ".wit"))
    (unwind-protect
        (progn
          (wit-ts-mode)
          (should-not (wit-ts-mode--external-definitions)))
      (ignore-errors (delete-file buffer-file-name))
      (set-buffer-modified-p nil)
      (setq buffer-file-name nil))))

;;; Dependency synchronisation

(ert-deftest wit-ts-mode-deps-sync-errors-without-executable ()
  "`wit-ts-deps-sync' signals a clear error when the CLI is absent."
  (skip-unless (treesit-ready-p 'wit t))
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil)))
      (should-error (wit-ts-deps-sync) :type 'user-error))))

(ert-deftest wit-ts-mode-deps-update-errors-without-executable ()
  "`wit-ts-deps-update' signals a clear error when the CLI is absent."
  (skip-unless (treesit-ready-p 'wit t))
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil)))
      (should-error (wit-ts-deps-update) :type 'user-error))))

(ert-deftest wit-ts-mode-deps-run-passes-args-and-dir ()
  "`wit-ts-mode--deps-run' runs the CLI with the right args in the root."
  (skip-unless (treesit-ready-p 'wit t))
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let (captured-command captured-dir)
      (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "wit-deps"))
                ((symbol-function 'make-process)
                 (lambda (&rest args)
                   (setq captured-command (plist-get args :command)
                         captured-dir default-directory)
                   ;; Return a dummy so the caller does not choke.
                   nil)))
        (wit-ts-deps-update)
        (should (equal captured-command '("wit-deps" "update")))
        ;; Runs in the project root (parent of the managed `wit' dir).
        (should (equal (file-name-nondirectory
                        (directory-file-name captured-dir))
                       "proj"))
        (wit-ts-deps-sync)
        (should (equal captured-command '("wit-deps")))))))

(provide 'wit-ts-mode-tests)

;;; wit-ts-mode-tests.el ends here
