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

(provide 'wit-ts-mode-tests)

;;; wit-ts-mode-tests.el ends here
