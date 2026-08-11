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

(defun wit-ts-mode-tests--diagnostic-texts (content)
  "Return the Flymake diagnostic messages for CONTENT in `wit-ts-mode'."
  (with-temp-buffer
    (insert content)
    (wit-ts-mode)
    (mapcar #'flymake-diagnostic-text (wit-ts-mode-tests--diagnostics))))

(ert-deftest wit-ts-mode-flymake-use-without-names-list ()
  "A bare `use path;' inside an interface/world is explained clearly."
  (skip-unless (treesit-ready-p 'wit t))
  (dolist (content '("interface i {\n  use foo;\n}\n"
                     "world w {\n  use wasi:clocks/x;\n}\n"))
    (let ((texts (wit-ts-mode-tests--diagnostic-texts content)))
      (should (seq-some (lambda (m) (string-match-p "needs a `.{\\.\\.\\.}' names list" m))
                        texts)))))

(ert-deftest wit-ts-mode-flymake-empty-use-names-list ()
  "An empty `use path.{}' names list gets a tailored message."
  (skip-unless (treesit-ready-p 'wit t))
  (dolist (content '("interface i {\n  use foo.{};\n}\n"
                     "interface i {\n  use foo.{ };\n}\n"))
    (let ((texts (wit-ts-mode-tests--diagnostic-texts content)))
      (should (seq-some (lambda (m) (string-match-p "Empty `use' names list" m))
                        texts)))))

(ert-deftest wit-ts-mode-flymake-valid-use-forms-clean ()
  "Valid `use' forms produce no diagnostics."
  (skip-unless (treesit-ready-p 'wit t))
  ;; Names list inside an interface, and a bare `use' at file top level.
  (should-not (wit-ts-mode-tests--diagnostic-texts
               "interface i {\n  use foo.{a, b};\n}\n"))
  (should-not (wit-ts-mode-tests--diagnostic-texts
               "use wasi:clocks/monotonic-clock@0.2.10;\n")))

(ert-deftest wit-ts-mode-flymake-import-at-top-level ()
  "`import'/`export'/`include' at file scope are flagged as world-only."
  (skip-unless (treesit-ready-p 'wit t))
  (dolist (case '(("import foo;\n" . "`import' is only valid inside a `world'")
                  ("export wasi:http/handler;\n"
                   . "`export' is only valid inside a `world'")
                  ("include other;\n"
                   . "`include' is only valid inside a `world'")))
    (let ((texts (wit-ts-mode-tests--diagnostic-texts (car case))))
      (should (seq-some (lambda (m) (string-search (cdr case) m)) texts)))))

(ert-deftest wit-ts-mode-flymake-inline-import-missing-type ()
  "An inline `import NAME:' with no type after the colon is explained."
  (skip-unless (treesit-ready-p 'wit t))
  (dolist (content '("world w {\n  import foo:\n}\n"
                     "world w {\n  export bar: \n}\n"))
    (let ((texts (wit-ts-mode-tests--diagnostic-texts content)))
      (should (seq-some
               (lambda (m) (string-search "must be followed by a type" m))
               texts)))))

(ert-deftest wit-ts-mode-flymake-import-missing-name ()
  "An `import: ...' with no name before the colon is explained."
  (skip-unless (treesit-ready-p 'wit t))
  (let ((texts (wit-ts-mode-tests--diagnostic-texts
                "world w {\n  import: bar;\n}\n")))
    (should (seq-some
             (lambda (m) (string-search "needs a name before `:'" m))
             texts))))

(ert-deftest wit-ts-mode-flymake-valid-import-forms-clean ()
  "Valid `import' forms inside a world produce no diagnostics."
  (skip-unless (treesit-ready-p 'wit t))
  (should-not (wit-ts-mode-tests--diagnostic-texts
               "world w {\n  import wasi:http/handler@0.2.0;\n}\n"))
  (should-not (wit-ts-mode-tests--diagnostic-texts
               "world w {\n  import foo: func();\n}\n"))
  (should-not (wit-ts-mode-tests--diagnostic-texts
               "world w {\n  import foo: interface { f: func(); }\n}\n")))

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
  "`wit-ts-mode--wit-root' finds the WIT directory and project root."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let* ((roots (wit-ts-mode--wit-root))
           (wit-root (car roots))
           (project-root (cdr roots)))
      (should roots)
      (should (equal (file-name-nondirectory (directory-file-name wit-root))
                     "wit"))
      ;; Project root is the parent, where the dependency tool would run.
      (should (equal (expand-file-name wit-root)
                     (expand-file-name "wit/" project-root))))))

(ert-deftest wit-ts-mode-wit-root-found-without-manifest ()
  "`wit-ts-mode--wit-root' recognises a `wit' directory with no `deps.toml'.
This is the layout a fresh `wkg' project has before dependencies
are fetched."
  (skip-unless (treesit-ready-p 'wit t))
  (let ((dir (make-temp-file "wit-ts-root-" t)))
    (unwind-protect
        (let ((wit-dir (expand-file-name "wit/" dir)))
          (make-directory wit-dir)
          (with-temp-file (expand-file-name "root.wit" wit-dir)
            (insert "package example:root;\n"))
          (should-not (file-exists-p (expand-file-name "deps.toml" wit-dir)))
          (with-temp-buffer
            (setq buffer-file-name (expand-file-name "root.wit" wit-dir))
            (unwind-protect
                (let ((roots (wit-ts-mode--wit-root)))
                  (should roots)
                  (should (equal (expand-file-name (car roots))
                                 (expand-file-name wit-dir))))
              (setq buffer-file-name nil))))
      (delete-directory dir t))))

(ert-deftest wit-ts-mode-parse-file-extracts-package-and-interfaces ()
  "`wit-ts-mode--parse-file' returns the package id, version, and interfaces."
  (skip-unless (treesit-ready-p 'wit t))
  (let* ((dep (ert-resource-file "proj/wit/deps/dep/dep.wit"))
         (info (wit-ts-mode--parse-file dep)))
    (should (equal (plist-get info :package) "example:dep"))
    (should (equal (plist-get info :version) "0.1.0"))
    ;; Interfaces/worlds are captured; nested records are not.
    (should (member "dep-iface" (plist-get info :interfaces)))
    (should-not (member "widget" (plist-get info :interfaces)))
    ;; Members are indexed per interface: `widget' (a record) but not the
    ;; `gadget' function.
    (let ((members (cdr (assoc "dep-iface" (plist-get info :members)))))
      (should (member "widget" members))
      (should-not (member "gadget" members)))))

(ert-deftest wit-ts-mode-package-id-reconstruction ()
  "`wit-ts-mode--package-id-from-decl-head' rebuilds ids, dropping @version."
  (skip-unless (treesit-ready-p 'wit t))
  (dolist (case '(("package wasi:http@0.2.10;" . "wasi:http")
                  ("package examples:http;" . "examples:http")
                  ("package foo:bar/baz@1.0.0;" . "foo:bar/baz")))
    (with-temp-buffer
      (insert (car case) "\n")
      (let* ((parser (treesit-parser-create 'wit))
             (head (car (treesit-query-capture
                         (treesit-parser-root-node parser)
                         wit-ts-mode--completion-packages-query nil nil t))))
        (should (equal (wit-ts-mode--package-id-from-decl-head head)
                       (cdr case)))))))

(ert-deftest wit-ts-mode-general-completion-excludes-foreign-names ()
  "Ordinary completion offers buffer defs but not other packages' symbols."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((cands (wit-ts-mode--completion-candidates)))
      ;; Defined in the current buffer.
      (should (member "app" cands))
      ;; Defined only under wit/deps/ (a foreign package) -- must NOT leak
      ;; into ordinary completion.
      (should-not (member "widget" cands))
      (should-not (member "gadget" cands))
      (should-not (member "dep-iface" cands)))))

(ert-deftest wit-ts-mode-path-candidates-local-and-foreign ()
  "Path candidates mix bare local names with foreign ns:pkg/iface@version."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((cands (wit-ts-mode--path-candidates)))
      ;; Current buffer's own interface -- bare local name.
      (should (member "app" cands))
      ;; Sibling file sharing package example:root -- bare local name.
      (should (member "sibling-iface" cands))
      ;; Foreign package -- full path with version, not a bare name.
      (should (member "example:dep/dep-iface@0.1.0" cands))
      (should-not (member "dep-iface" cands)))))

(ert-deftest wit-ts-mode-path-candidates-include-offers-only-worlds ()
  "An `include' path offers worlds, never interfaces."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((cands (wit-ts-mode--path-candidates "include")))
      ;; The dependency package's world -- full path with version.
      (should (member "example:dep/dep-world@0.1.0" cands))
      ;; Interfaces must NOT appear after `include'.
      (should-not (member "example:dep/dep-iface@0.1.0" cands))
      (should-not (member "app" cands))
      (should-not (member "sibling-iface" cands)))))

(ert-deftest wit-ts-mode-path-candidates-use-offers-only-interfaces ()
  "An `import'/`export'/`use' path offers interfaces, never worlds."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (dolist (keyword '("import" "export" "use"))
      (let ((cands (wit-ts-mode--path-candidates keyword)))
        (should (member "example:dep/dep-iface@0.1.0" cands))
        (should (member "app" cands))
        ;; The dependency package's world must NOT appear.
        (should-not (member "example:dep/dep-world@0.1.0" cands))))))

(ert-deftest wit-ts-mode-include-context-offers-worlds ()
  "The capf, after `include', offers worlds and filters out interfaces."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\nworld w {\n  include ")
    (should (equal (wit-ts-mode--in-use-path-p) "include"))
    (let* ((capf (wit-ts-mode-completion-at-point))
           (cands (all-completions "" (nth 2 capf))))
      (should (member "example:dep/dep-world@0.1.0" cands))
      (should-not (member "example:dep/dep-iface@0.1.0" cands)))))

(ert-deftest wit-ts-mode-in-use-path-returns-keyword ()
  "`wit-ts-mode--in-use-path-p' returns the introducing keyword."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (dolist (keyword '("import" "export" "use" "include"))
      (goto-char (point-max))
      (insert (format "\nworld probe {\n  %s " keyword))
      (should (equal (wit-ts-mode--in-use-path-p) keyword)))))

(ert-deftest wit-ts-mode-path-candidates-nil-without-project ()
  "`wit-ts-mode--path-candidates' returns nil outside a wit-deps project."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert "package a:b;\ninterface solo { type t = u32; }\n")
    (setq buffer-file-name (make-temp-file "wit-solo" nil ".wit"))
    (unwind-protect
        (progn
          (wit-ts-mode)
          (should-not (wit-ts-mode--path-candidates)))
      (ignore-errors (delete-file buffer-file-name))
      (set-buffer-modified-p nil)
      (setq buffer-file-name nil))))

(ert-deftest wit-ts-mode-import-context-uses-path-candidates ()
  "The capf switches to path candidates after `import'."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\nworld w {\n  import ")
    (should (wit-ts-mode--in-use-path-p))
    (let* ((capf (wit-ts-mode-completion-at-point))
           (cands (all-completions "" (nth 2 capf))))
      (should (member "example:dep/dep-iface@0.1.0" cands))
      (should (member "sibling-iface" cands))
      ;; Keywords are not offered in a use_path position.
      (should-not (member "interface" cands)))))

(ert-deftest wit-ts-mode-non-import-context-uses-default-candidates ()
  "Outside an import path the capf offers keywords, not foreign paths."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\ninterface bar {\n  type x = ")
    (should-not (wit-ts-mode--in-use-path-p))
    (let* ((capf (wit-ts-mode-completion-at-point))
           (cands (all-completions "" (nth 2 capf))))
      (should (member "u32" cands))
      (should-not (member "example:dep/dep-iface@0.1.0" cands)))))

(ert-deftest wit-ts-mode-import-context-detected-with-colon-prefix ()
  "A partial package path with `:'/`/' still counts as a use_path.
Regression: the context regexp must not stop at the `:' separator,
and the completion bounds must include it so the path filters."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\nworld w {\n  import example:d")
    (should (wit-ts-mode--in-use-path-p))
    (let* ((capf (wit-ts-mode-completion-at-point))
           (prefix (buffer-substring-no-properties (nth 0 capf) (nth 1 capf)))
           (matches (all-completions prefix (nth 2 capf))))
      (should (equal prefix "example:d"))
      (should (member "example:dep/dep-iface@0.1.0" matches)))))

(ert-deftest wit-ts-mode-inline-import-is-not-use-path ()
  "`import NAME: extern-type' (space after `:') is not a use_path."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\nworld w {\n  import my-thing: ")
    (should-not (wit-ts-mode--in-use-path-p))))

(ert-deftest wit-ts-mode-completion-candidates-are-sorted ()
  "The completion table returns candidates in alphabetical order and
advertises `identity' as its display sort so frontends preserve it."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\nworld w {\n  import ")
    (let* ((table (nth 2 (wit-ts-mode-completion-at-point)))
           (cands (all-completions "" table))
           (md (completion-metadata "" table nil)))
      (should (equal cands (sort (copy-sequence cands) #'string<)))
      (should (eq (completion-metadata-get md 'display-sort-function)
                  'identity)))))

(defun wit-ts-mode-tests--find-candidate (prefix table)
  "Return the completion from TABLE that is `equal' to PREFIX, with props."
  (seq-find (lambda (c) (equal c prefix)) (all-completions prefix table)))

(ert-deftest wit-ts-mode-candidates-carry-kind ()
  "Buffer definitions, keywords, and builtins are tagged with their kind."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert "package a:b;\n"
            "interface things {\n  type dist = u32;\n  record pt { x: u32 }\n"
            "  go: func();\n}\nworld srv {}\n")
    (wit-ts-mode)
    (let ((cands (wit-ts-mode--completion-candidates)))
      (cl-flet ((kind-of (name)
                  (wit-ts-mode--candidate-kind
                   (seq-find (lambda (c) (equal c name)) cands))))
        (should (eq (kind-of "things") 'interface))
        (should (eq (kind-of "srv") 'world))
        (should (eq (kind-of "pt") 'record))
        (should (eq (kind-of "dist") 'type))
        (should (eq (kind-of "go") 'func))
        (should (eq (kind-of "interface") 'keyword))
        (should (eq (kind-of "u32") 'builtin))))))

(ert-deftest wit-ts-mode-capf-exposes-kind-functions ()
  "The capf provides annotation and company-kind functions using the kind."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert "package a:b;\ninterface things {}\ninterface z {\n  ")
    (wit-ts-mode)
    (let* ((capf (wit-ts-mode-completion-at-point))
           (props (nthcdr 3 capf))
           (annfn (plist-get props :annotation-function))
           (kindfn (plist-get props :company-kind))
           (cand (wit-ts-mode-tests--find-candidate "things" (nth 2 capf))))
      (should (functionp annfn))
      (should (functionp kindfn))
      (should (equal (funcall annfn cand) " interface"))
      (should (eq (funcall kindfn cand) 'interface)))))

(ert-deftest wit-ts-mode-foreign-path-candidate-keeps-kind ()
  "A foreign ns:pkg/iface path candidate keeps the interface's kind."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((cand (seq-find
                 (lambda (c) (equal c "example:dep/dep-iface@0.1.0"))
                 (wit-ts-mode--path-candidates))))
      (should cand)
      (should (eq (wit-ts-mode--candidate-kind cand) 'interface)))))

;;; Feature gates (@since / @unstable / @deprecated)

(defun wit-ts-mode-tests--capf-candidates (content)
  "Insert CONTENT in a `wit-ts-mode' buffer and return capf candidates at end."
  (with-temp-buffer
    (insert content)
    (wit-ts-mode)
    (goto-char (point-max))
    (let* ((capf (wit-ts-mode-completion-at-point))
           (prefix (buffer-substring-no-properties (nth 0 capf) (nth 1 capf))))
      (mapcar #'substring-no-properties
              (all-completions prefix (nth 2 capf))))))

(ert-deftest wit-ts-mode-gate-completion-after-at ()
  "After `@' the three feature gates are offered, tagged `gate'."
  (skip-unless (treesit-ready-p 'wit t))
  (let ((cands (wit-ts-mode-tests--capf-candidates "interface i {\n  @")))
    (should (equal (sort (copy-sequence cands) #'string<)
                   '("deprecated" "since" "unstable"))))
  ;; A prefix narrows the set.
  (should (equal (wit-ts-mode-tests--capf-candidates "interface i {\n  @un")
                 '("unstable"))))

(ert-deftest wit-ts-mode-gate-field-completion ()
  "Inside a gate's parens the accepted field is offered."
  (skip-unless (treesit-ready-p 'wit t))
  (should (equal (wit-ts-mode-tests--capf-candidates "interface i {\n  @since(")
                 '("version")))
  (should (equal (wit-ts-mode-tests--capf-candidates
                  "interface i {\n  @deprecated(")
                 '("version")))
  (should (equal (wit-ts-mode-tests--capf-candidates
                  "interface i {\n  @unstable(")
                 '("feature")))
  ;; An unknown gate offers no field.
  (should-not (wit-ts-mode-tests--capf-candidates "interface i {\n  @bogus(")))

(ert-deftest wit-ts-mode-gate-context-does-not-leak-keywords ()
  "Gate contexts offer only gates/fields, never the keyword list."
  (skip-unless (treesit-ready-p 'wit t))
  (should-not (member "interface"
                      (wit-ts-mode-tests--capf-candidates "interface i {\n  @")))
  (should-not (member "type"
                      (wit-ts-mode-tests--capf-candidates
                       "interface i {\n  @since("))))

(ert-deftest wit-ts-mode-gate-on-nested-items-parses-clean ()
  "Feature gates on nested items parse without ERROR/MISSING nodes.
Since tree-sitter-wit commit cdf0726 a gate may precede a record
field, variant case, enum case, flags field, or resource method
\(and constructor).  Each such form must parse cleanly."
  (skip-unless (treesit-ready-p 'wit t))
  (dolist (body '("record r {\n    @since(version = 0.2.0)\n    id: u64,\n\
    @deprecated(version = 0.3.0)\n    name: string,\n  }"
                  "variant v {\n    @since(version = 0.2.0)\n    none,\n\
    @unstable(feature = x)\n    some(u32),\n  }"
                  "enum e {\n    @since(version = 0.2.0)\n    hot,\n    cold,\n  }"
                  "flags f {\n    @since(version = 0.2.0)\n    get,\n    post,\n  }"
                  "resource b {\n    @since(version = 0.2.0)\n    constructor(x: u32);\n\
    @since(version = 0.3.0)\n    merge: func();\n  }"))
    (with-temp-buffer
      (insert "package a:b;\ninterface i {\n  " body "\n}\n")
      (wit-ts-mode)
      (let ((root (treesit-buffer-root-node)))
        (should-not (treesit-query-capture root '((ERROR) @e) nil nil t))
        (should-not (treesit-search-subtree
                     root (lambda (n) (treesit-node-check n 'missing)) nil t))))))

(ert-deftest wit-ts-mode-gate-on-nested-items-diagnostics-clean ()
  "A valid file with gates on nested items yields no diagnostics."
  (skip-unless (treesit-ready-p 'wit t))
  (should-not
   (wit-ts-mode-tests--diagnostic-texts
    (concat "package a:b;\ninterface i {\n"
            "  record r {\n"
            "    @since(version = 0.2.0)\n    id: u64,\n"
            "    @deprecated(version = 0.3.0)\n    name: string,\n"
            "  }\n}\n"))))

(ert-deftest wit-ts-mode-gate-on-nested-item-fontifies ()
  "A gate before a nested item is fontified: keyword and `feature' id."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert "package a:b;\ninterface i {\n  record r {\n"
            "    @unstable(feature = experimental)\n    id: u64,\n  }\n}\n")
    (wit-ts-mode)
    (font-lock-ensure)
    ;; The gate keyword after `@'.
    (should (eq (wit-ts-mode-tests--face-at "unstable")
                'font-lock-builtin-face))
    ;; The `@unstable(feature = ...)' feature id.
    (should (eq (wit-ts-mode-tests--face-at "experimental")
                'font-lock-string-face))))

;;; use names list (`use PATH.{ ... }')

(ert-deftest wit-ts-mode-use-names-list-context-detection ()
  "`use PATH.{' is detected as a names list; other braces are not."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (wit-ts-mode)
    (insert "interface i {\n  use types.{")
    (should (wit-ts-mode--in-use-names-list-p))
    (should (equal (wit-ts-mode--current-use-path) "types")))
  (with-temp-buffer
    (wit-ts-mode)
    ;; A record body brace is not a use names list.
    (insert "interface i {\n  record r { ")
    (should-not (wit-ts-mode--in-use-names-list-p))))

(ert-deftest wit-ts-mode-split-use-path ()
  "`wit-ts-mode--split-use-path' separates package id from interface."
  (should (equal (wit-ts-mode--split-use-path "wasi:clocks/wall-clock@0.2.10")
                 '("wasi:clocks" . "wall-clock")))
  (should (equal (wit-ts-mode--split-use-path "wasi:clocks/wall-clock")
                 '("wasi:clocks" . "wall-clock")))
  (should (equal (wit-ts-mode--split-use-path "types")
                 '(nil . "types"))))

(ert-deftest wit-ts-mode-member-candidates-foreign-types-only ()
  "Members of a foreign interface are offered; its functions are not."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\ninterface i {\n  use example:dep/dep-iface@0.1.0.{")
    (should (wit-ts-mode--in-use-names-list-p))
    (let ((cands (all-completions "" (nth 2 (wit-ts-mode-completion-at-point)))))
      ;; `widget' is a record (a type); `gadget' is a func and must not appear.
      (should (member "widget" cands))
      (should-not (member "gadget" cands)))))

(ert-deftest wit-ts-mode-member-candidates-sibling-interface ()
  "A sibling file's interface members resolve for an unqualified `use'."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\ninterface i {\n  use sibling-iface.{")
    (let ((cands (all-completions "" (nth 2 (wit-ts-mode-completion-at-point)))))
      (should (member "timestamp" cands)))))

(ert-deftest wit-ts-mode-member-candidates-exclude-already-listed ()
  "Members already present in the brace list are not offered again."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    ;; Local interface `app' has no types; use a buffer-local interface with
    ;; two types so the exclusion is observable.
    (insert "\ninterface pair {\n  type a = u32;\n  type b = u32;\n}\n")
    (insert "interface i {\n  use pair.{a, ")
    (let ((cands (all-completions "" (nth 2 (wit-ts-mode-completion-at-point)))))
      (should (member "b" cands))
      (should-not (member "a" cands)))))

(ert-deftest wit-ts-mode-member-candidates-nil-for-unknown-interface ()
  "An unresolvable `use' path yields no member candidates."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\ninterface i {\n  use nonesuch.{")
    (should (wit-ts-mode--in-use-names-list-p))
    (should-not (wit-ts-mode--member-candidates))))

;;; Cross-reference (xref)

(defun wit-ts-mode-tests--xref-summaries (identifier)
  "Return the summary strings of xref items defining IDENTIFIER."
  (mapcar #'xref-item-summary
          (wit-ts-mode--xref-find-definitions identifier)))

(ert-deftest wit-ts-mode-xref-backend-registered ()
  "`wit-ts-mode' installs its xref backend."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (wit-ts-mode)
    (should (eq (xref-find-backend) 'wit-ts-mode))))

(ert-deftest wit-ts-mode-xref-identifier-at-point ()
  "The identifier at point is a symbol, or a tagged use_path."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert "package a:b;\ninterface i {\n  record widget { x: u32 }\n"
            "  make: func() -> widget;\n}\n")
    (wit-ts-mode)
    (goto-char (point-min))
    (search-forward "-> wid")
    (let ((id (wit-ts-mode--identifier-at-point)))
      (should (equal id "widget"))
      (should-not (get-text-property 0 'wit-ts-mode--xref-path id))))
  (with-temp-buffer
    (insert "package a:b;\nworld w {\n  import wasi:http/handler@1.0.0;\n}\n")
    (wit-ts-mode)
    (goto-char (point-min))
    (search-forward "wasi:ht")
    (let ((id (wit-ts-mode--identifier-at-point)))
      (should (equal id "wasi:http/handler@1.0.0"))
      (should (get-text-property 0 'wit-ts-mode--xref-path id)))))

(ert-deftest wit-ts-mode-xref-local-definition ()
  "A bare name resolves to its definition in the current buffer."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert "package a:b;\ninterface i {\n  record widget { x: u32 }\n"
            "  make: func() -> widget;\n}\n")
    (wit-ts-mode)
    (should (equal (wit-ts-mode-tests--xref-summaries "widget")
                   '("record widget")))))

(ert-deftest wit-ts-mode-xref-use-path-to-foreign-interface ()
  "A foreign use_path resolves to the interface in the dep file."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let* ((id (propertize "example:dep/dep-iface@0.1.0"
                           'wit-ts-mode--xref-path t))
           (defs (wit-ts-mode--xref-find-definitions id)))
      (should (equal (mapcar #'xref-item-summary defs)
                     '("interface dep-iface")))
      ;; The location points into the dependency file.
      (should (string-match-p
               "dep\\.wit\\'"
               (xref-location-group (xref-item-location (car defs))))))))

(ert-deftest wit-ts-mode-xref-use-path-to-sibling-interface ()
  "A bare use_path resolves to an interface in a sibling file."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((id (propertize "sibling-iface" 'wit-ts-mode--xref-path t)))
      (should (equal (wit-ts-mode-tests--xref-summaries id)
                     '("interface sibling-iface"))))))

(ert-deftest wit-ts-mode-xref-member-in-names-list ()
  "Inside a `use PATH.{ member }' list, point on a member jumps to it."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\nworld w {\n  use sibling-iface.{timestamp}\n}\n")
    (goto-char (point-max))
    (search-backward "timestamp")
    (let ((id (wit-ts-mode--identifier-at-point)))
      (should (equal id "timestamp"))
      (should (equal (wit-ts-mode-tests--xref-summaries id)
                     '("type timestamp"))))))

(ert-deftest wit-ts-mode-xref-unknown-identifier ()
  "An unknown identifier resolves to no definitions."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (should-not (wit-ts-mode--xref-find-definitions "no-such-name"))))

;;; Eldoc

(defun wit-ts-mode-tests--eldoc-at (content marker)
  "Return the Eldoc string for CONTENT with point just after MARKER.
MARKER is searched from the buffer start; point is left at its end
\(inside the target identifier).  Returns nil when the Eldoc
function defers."
  (with-temp-buffer
    (insert content)
    (wit-ts-mode)
    (goto-char (point-min))
    (search-forward marker)
    (let (captured)
      (wit-ts-mode--eldoc-function (lambda (doc &rest _) (setq captured doc)))
      (and captured (substring-no-properties captured)))))

(ert-deftest wit-ts-mode-node-signature-formats-each-kind ()
  "`wit-ts-mode--node-signature' renders each definition kind."
  (skip-unless (treesit-ready-p 'wit t))
  (dolist (case '(("interface i { f: func(a: u32) -> string; }" . "f: func(a: u32) -> string")
                  ("interface i { type n = u64; }" . "type n = u64")
                  ("interface i { record p { x: u32, y: u32 } }" . "record p { x: u32, y: u32 }")
                  ("interface i { variant v { a, b(u32) } }" . "variant v { a, b(u32) }")
                  ("interface i { enum e { on, off } }" . "enum e { on, off }")
                  ("interface i { flags g { r, w } }" . "flags g { r, w }")))
    (with-temp-buffer
      (insert (car case))
      (wit-ts-mode)
      (let* ((root (treesit-buffer-root-node))
             ;; The first member definition inside the interface body.
             (def (treesit-search-subtree
                   root wit-ts-mode--defun-node-regexp))
             ;; Skip the interface_item itself; take its first body child def.
             (member (treesit-search-subtree
                      (car (treesit-filter-child
                            def (lambda (c) (equal (treesit-node-type c) "body"))))
                      wit-ts-mode--defun-node-regexp))
             (kind (pcase (treesit-node-type member)
                     ("func_item" 'func) ("type_item" 'type)
                     ("record_item" 'record) ("variant_items" 'variant)
                     ("enum_items" 'enum) ("flags_items" 'flags))))
        (should (equal (wit-ts-mode--node-signature member kind) (cdr case)))))))

(ert-deftest wit-ts-mode-node-signature-summarises-large-body ()
  "A body longer than the inline limit is rendered as a member summary."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert "interface i { record big { aaaaaaaa: u32, bbbbbbbb: u32,"
            " cccccccc: u32, dddddddd: u32 } }")
    (wit-ts-mode)
    (let ((rec (treesit-search-subtree (treesit-buffer-root-node) "record_item")))
      (should (equal (wit-ts-mode--node-signature rec 'record)
                     "record big { aaaaaaaa, bbbbbbbb, cccccccc, dddddddd }")))))

(ert-deftest wit-ts-mode-eldoc-on-definition ()
  "Eldoc shows the signature when point is on a definition name."
  (skip-unless (treesit-ready-p 'wit t))
  (let ((src (concat "package a:b;\ninterface calc {\n  type num = f64;\n"
                     "  record point { x: num, y: num }\n"
                     "  add: func(a: num, b: num) -> num;\n}\n")))
    (should (equal (wit-ts-mode-tests--eldoc-at src "ad")
                   "add: func(a: num, b: num) -> num"))
    (should (equal (wit-ts-mode-tests--eldoc-at src "type nu")
                   "type num = f64"))
    (should (equal (wit-ts-mode-tests--eldoc-at src "record poi")
                   "record point { x: num, y: num }"))))

(ert-deftest wit-ts-mode-eldoc-on-reference ()
  "Eldoc resolves a type reference in a signature to its definition."
  (skip-unless (treesit-ready-p 'wit t))
  (let ((src (concat "package a:b;\ninterface calc {\n  type num = f64;\n"
                     "  record point { x: num, y: num }\n"
                     "  distance: func(p: point) -> num;\n}\n")))
    ;; Reference to the `point' record in a parameter type.
    (should (equal (wit-ts-mode-tests--eldoc-at src "distance: func(p: poi")
                   "record point { x: num, y: num }"))
    ;; Reference to the `num' type alias in the return type.
    (should (equal (wit-ts-mode-tests--eldoc-at src "-> nu")
                   "type num = f64"))))

(ert-deftest wit-ts-mode-eldoc-defers-when-undefined ()
  "Eldoc returns nil (defers) for a symbol with no local definition."
  (skip-unless (treesit-ready-p 'wit t))
  (should-not (wit-ts-mode-tests--eldoc-at
               "interface i {\n  f: func() -> unknown-type;\n}\n"
               "unknown-typ")))

(defun wit-ts-mode-tests--eldoc-here ()
  "Return the Eldoc string at point in the current buffer, or nil."
  (let (captured)
    (wit-ts-mode--eldoc-function (lambda (doc &rest _) (setq captured doc)))
    (and captured (substring-no-properties captured))))

(ert-deftest wit-ts-mode-eldoc-resolves-sibling-bare-name ()
  "A bare name defined in a sibling file (same package) resolves."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    ;; `sibling-iface' lives in sibling.wit under the same package.
    (insert "\nworld w {\n  export sibling-iface;\n}\n")
    (goto-char (point-max))
    (search-backward "sibling-iface")
    (goto-char (1+ (point)))
    (should (equal (wit-ts-mode-tests--eldoc-here)
                   "interface sibling-iface { timestamp, ping }"))))

(ert-deftest wit-ts-mode-eldoc-resolves-foreign-interface ()
  "A qualified use path resolves to a foreign interface under deps/."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\nworld w {\n  import example:dep/dep-iface@0.1.0;\n}\n")
    (goto-char (point-max))
    (search-backward "dep-iface")
    (goto-char (1+ (point)))
    (should (equal (wit-ts-mode-tests--eldoc-here)
                   "interface dep-iface { widget, gadget }"))))

(ert-deftest wit-ts-mode-eldoc-resolves-foreign-world-in-include ()
  "An include path resolves to a foreign world under deps/."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\nworld w {\n  include example:dep/dep-world@0.1.0;\n}\n")
    (goto-char (point-max))
    (search-backward "dep-world")
    (goto-char (1+ (point)))
    (should (equal (wit-ts-mode-tests--eldoc-here) "world dep-world"))))

;;; Read-only dependency files

(ert-deftest wit-ts-mode-deps-file-is-read-only ()
  "A file under DIR/deps/ is detected as a dependency and visited read-only."
  (wit-ts-mode-tests--with-project-file "proj/wit/deps/dep/dep.wit"
    (should (wit-ts-mode--in-deps-directory-p))
    (should buffer-read-only)))

(ert-deftest wit-ts-mode-root-file-is-writable ()
  "A file outside DIR/deps/ is not a dependency and stays writable."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (should-not (wit-ts-mode--in-deps-directory-p))
    (should-not buffer-read-only)))

(ert-deftest wit-ts-mode-deps-read-only-can-be-disabled ()
  "With `wit-ts-mode-deps-read-only' nil, dependency files stay writable."
  (let ((wit-ts-mode-deps-read-only nil))
    (wit-ts-mode-tests--with-project-file "proj/wit/deps/dep/dep.wit"
      (should (wit-ts-mode--in-deps-directory-p))
      (should-not buffer-read-only))))

;;; Semantic reference checking

(defun wit-ts-mode-tests--reference-texts (&optional extra)
  "Return reference-check diagnostic messages for proj/wit/root.wit.
EXTRA, if given, is appended to the buffer before checking."
  (when extra (goto-char (point-max)) (insert extra))
  (mapcar #'flymake-diagnostic-text
          (wit-ts-mode--reference-diagnostics
           (wit-ts-mode--parser) (current-buffer))))

(ert-deftest wit-ts-mode-reference-unknown-package ()
  "A reference to a package absent from the project is flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  "\nworld w {\n  import totally:bogus/thing;\n}\n")))
      (should (seq-some (lambda (m) (string-match-p "Unknown package `totally:bogus'" m))
                        texts)))))

(ert-deftest wit-ts-mode-reference-unknown-interface-in-package ()
  "A known package but undefined interface is flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  "\nworld w {\n  import example:dep/no-iface@0.1.0;\n}\n")))
      (should (seq-some
               (lambda (m)
                 (string-match-p
                  "Interface `no-iface' is not defined in package `example:dep'" m))
               texts)))))

(ert-deftest wit-ts-mode-reference-unknown-local-interface ()
  "A bare reference to a non-existent local interface is flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  "\nworld w {\n  export no-such-local;\n}\n")))
      (should (seq-some
               (lambda (m)
                 (string-match-p "Interface `no-such-local' is not defined" m))
               texts)))))

(ert-deftest wit-ts-mode-reference-valid-refs-clean ()
  "Valid qualified and local references add no new warnings."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((before (length (wit-ts-mode-tests--reference-texts)))
          (after (length (wit-ts-mode-tests--reference-texts
                          (concat "\ninterface q {\n"
                                  "  use example:dep/dep-iface@0.1.0.{widget};\n}\n"
                                  "world w {\n  export sibling-iface;\n}\n")))))
      ;; The added references resolve, so the warning count is unchanged.
      (should (= before after)))))

(ert-deftest wit-ts-mode-reference-undefined-member ()
  "A `use' names-list member not defined in the interface is flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  (concat "\ninterface q {\n"
                          "  use example:dep/dep-iface@0.1.0.{widget, bogus};\n}\n"))))
      (should (seq-some
               (lambda (m)
                 (string-match-p "`bogus' is not defined in interface `dep-iface'" m))
               texts))
      ;; The valid member `widget' is not flagged.
      (should-not (seq-some (lambda (m) (string-match-p "`widget'" m)) texts)))))

(ert-deftest wit-ts-mode-reference-include-of-world-clean ()
  "`include' of a world defined in a dependency package is not flagged.
Regression: `include ns:pkg/world' must resolve against the
package's worlds, not its interfaces (a world is not an interface)."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((before (length (wit-ts-mode-tests--reference-texts)))
          (after (length (wit-ts-mode-tests--reference-texts
                          "\nworld w {\n  include example:dep/dep-world@0.1.0;\n}\n"))))
      (should (= before after)))))

(ert-deftest wit-ts-mode-reference-include-of-interface-flagged ()
  "`include' of an interface (not a world) is flagged as a world reference."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  "\nworld w {\n  include example:dep/dep-iface@0.1.0;\n}\n")))
      (should (seq-some
               (lambda (m)
                 (string-match-p
                  "World `dep-iface' is not defined in package `example:dep'" m))
               texts)))))

(ert-deftest wit-ts-mode-reference-import-of-world-flagged ()
  "`import' of a world (not an interface) is flagged as an interface reference."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  "\nworld w {\n  import example:dep/dep-world@0.1.0;\n}\n")))
      (should (seq-some
               (lambda (m)
                 (string-match-p
                  "Interface `dep-world' is not defined in package `example:dep'" m))
               texts)))))

(ert-deftest wit-ts-mode-reference-unknown-param-type ()
  "A function parameter whose type is undefined is flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  (concat "\ninterface q {\n"
                          "  frob: func(n: u32, w: no-such-type);\n}\n"))))
      (should (seq-some
               (lambda (m) (string-match-p "Unknown type `no-such-type'" m))
               texts))
      ;; The builtin `u32' parameter is not flagged.
      (should-not (seq-some (lambda (m) (string-match-p "`u32'" m)) texts)))))

(ert-deftest wit-ts-mode-reference-known-func-types-clean ()
  "Builtin, locally-defined, and `use'-imported func types are not flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((before (length (wit-ts-mode-tests--reference-texts)))
          (after (length (wit-ts-mode-tests--reference-texts
                          (concat "\ninterface q {\n"
                                  "  use example:dep/dep-iface@0.1.0.{widget};\n"
                                  "  record local-rec { a: u32 }\n"
                                  "  type alias = u64;\n"
                                  ;; builtin, local record, local alias, and a
                                  ;; `use'-imported name -- all resolve.
                                  "  frob: func(a: string, b: local-rec,\n"
                                  "             c: alias, d: widget)"
                                  " -> local-rec;\n}\n")))))
      (should (= before after)))))

(ert-deftest wit-ts-mode-reference-unknown-return-type ()
  "A function return type that is undefined is flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  (concat "\ninterface q {\n"
                          "  sub: func() -> unknown;\n}\n"))))
      (should (seq-some
               (lambda (m) (string-match-p "Unknown type `unknown'" m))
               texts)))))

(ert-deftest wit-ts-mode-reference-return-type-in-result-flagged ()
  "Unknown types inside a `result<ok, err>' return are flagged; known ones not."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  (concat "\ninterface q {\n"
                          "  record ok-rec { a: u32 }\n"
                          "  go: func() -> result<ok-rec, oops>;\n}\n"))))
      (should (seq-some (lambda (m) (string-match-p "Unknown type `oops'" m))
                        texts))
      ;; The declared `ok-rec' return payload resolves.
      (should-not (seq-some (lambda (m) (string-match-p "`ok-rec'" m)) texts)))))

(ert-deftest wit-ts-mode-reference-nested-and-handle-types ()
  "Unknown types nested in generics or a `borrow' handle are flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  (concat "\ninterface q {\n"
                          "  resource res {}\n"
                          "  a: func(xs: list<mystery>);\n"
                          "  b: func(r: borrow<res>, s: borrow<ghost>);\n}\n"))))
      (should (seq-some (lambda (m) (string-match-p "Unknown type `mystery'" m))
                        texts))
      (should (seq-some (lambda (m) (string-match-p "Unknown type `ghost'" m))
                        texts))
      ;; The declared resource `res' resolves.
      (should-not (seq-some (lambda (m) (string-match-p "`res'" m)) texts)))))

(ert-deftest wit-ts-mode-reference-unknown-type-alias-target ()
  "A `type' alias whose target type is undefined is flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  "\ninterface q {\n  type foo = unknown;\n}\n")))
      (should (seq-some (lambda (m) (string-match-p "Unknown type `unknown'" m))
                        texts)))))

(ert-deftest wit-ts-mode-reference-unknown-record-field-type ()
  "A record field whose type is undefined is flagged; a builtin one is not."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  (concat "\ninterface q {\n"
                          "  record foo { i: unknown, j: u32 }\n}\n"))))
      (should (seq-some (lambda (m) (string-match-p "Unknown type `unknown'" m))
                        texts))
      (should-not (seq-some (lambda (m) (string-match-p "`u32'" m)) texts)))))

(ert-deftest wit-ts-mode-reference-unknown-variant-payload-type ()
  "A variant case payload of an undefined type is flagged."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((texts (wit-ts-mode-tests--reference-texts
                  (concat "\ninterface q {\n"
                          "  variant v { a(mystery), b(u32), c }\n}\n"))))
      (should (seq-some (lambda (m) (string-match-p "Unknown type `mystery'" m))
                        texts)))))

(ert-deftest wit-ts-mode-reference-type-forward-reference-clean ()
  "A field referring to a type defined later in the buffer resolves."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((before (length (wit-ts-mode-tests--reference-texts)))
          (after (length (wit-ts-mode-tests--reference-texts
                          (concat "\ninterface q {\n"
                                  ;; `point' is used before its definition;
                                  ;; scope is whole-buffer, so it resolves.
                                  "  record line { from: point, to: point }\n"
                                  "  record point { x: u32, y: u32 }\n}\n")))))
      (should (= before after)))))

(ert-deftest wit-ts-mode-reference-type-checked-outside-project ()
  "Type-reference checking runs even outside a `wit-deps' project."
  (skip-unless (treesit-ready-p 'wit t))
  (with-temp-buffer
    (insert "package a:b;\ninterface i {\n"
            "  type t = nope;\n  f: func(x: alsobad);\n}\n")
    (wit-ts-mode)
    ;; No project index here, but the in-buffer type check still fires,
    ;; covering both a `type' target and a function parameter.
    (let ((texts (mapcar #'flymake-diagnostic-text
                         (wit-ts-mode--reference-diagnostics
                          (wit-ts-mode--parser) (current-buffer)))))
      (should (seq-some (lambda (m) (string-match-p "Unknown type `nope'" m))
                        texts))
      (should (seq-some (lambda (m) (string-match-p "Unknown type `alsobad'" m))
                        texts)))))

(ert-deftest wit-ts-mode-reference-check-disabled ()
  "With `wit-ts-mode-check-references' nil, the backend adds no warnings."
  (skip-unless (treesit-ready-p 'wit t))
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (goto-char (point-max))
    (insert "\nworld w {\n  import totally:bogus/thing;\n}\n")
    (let* ((wit-ts-mode-check-references nil)
           (out nil))
      (wit-ts-mode-flymake (lambda (diags) (setq out diags)))
      (should-not (seq-some
                   (lambda (d) (eq (flymake-diagnostic-type d) :warning))
                   out)))))

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

(ert-deftest wit-ts-mode-default-deps-tool-keys-on-manifest ()
  "`wit-ts-mode--default-deps-tool' picks `wit-deps' iff a `deps.toml' exists."
  (let ((dir (make-temp-file "wit-ts-tool-" t)))
    (unwind-protect
        (progn
          ;; No manifest yet: falls back to `wkg'.
          (should (eq (wit-ts-mode--default-deps-tool dir) 'wkg))
          ;; With a `deps.toml' present: `wit-deps'.
          (with-temp-file (expand-file-name "deps.toml" dir) (insert ""))
          (should (eq (wit-ts-mode--default-deps-tool dir) 'wit-deps)))
      (delete-directory dir t))))

(ert-deftest wit-ts-mode-deps-run-uses-wit-deps-for-manifest-project ()
  "With a `deps.toml', sync/update drive `wit-deps' in the project root."
  (skip-unless (treesit-ready-p 'wit t))
  ;; The `proj/wit' fixture ships a `deps.toml', so the default tool
  ;; function selects `wit-deps'.
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

(ert-deftest wit-ts-mode-deps-run-uses-wkg-when-selected ()
  "When `wit-ts-deps-tool-function' returns `wkg', sync/update drive `wkg'."
  (skip-unless (treesit-ready-p 'wit t))
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((wit-ts-deps-tool-function (lambda (&rest _) 'wkg))
          captured-command captured-dir)
      (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) "wkg"))
                ((symbol-function 'make-process)
                 (lambda (&rest args)
                   (setq captured-command (plist-get args :command)
                         captured-dir default-directory)
                   nil)))
        (wit-ts-deps-sync)
        (should (equal captured-command '("wkg" "fetch")))
        (should (equal (file-name-nondirectory
                        (directory-file-name captured-dir))
                       "proj"))
        (wit-ts-deps-update)
        (should (equal captured-command '("wkg" "update")))))))

(ert-deftest wit-ts-mode-deps-run-errors-on-unknown-tool ()
  "A `wit-ts-deps-tool-function' returning an unknown symbol errors clearly."
  (skip-unless (treesit-ready-p 'wit t))
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((wit-ts-deps-tool-function (lambda (&rest _) 'bogus)))
      (should-error (wit-ts-deps-sync) :type 'user-error))))

;;; Binding / component generation

(defmacro wit-ts-mode-tests--with-generate (input &rest body)
  "Run BODY with the generate tools stubbed and `read-string' returning INPUT.
Binds `captured-command', `captured-dir', `prompt-count',
`captured-prompt', and `captured-initial' for BODY to inspect, and
starts each test with an empty args cache.  `executable-find'
reports every program as present, so the tool selected by
`wit-ts-deps-tool-function' is what runs."
  (declare (indent 1) (debug (form body)))
  `(let ((captured-command nil) (captured-dir nil) (prompt-count 0)
         (captured-prompt nil) (captured-initial nil)
         (wit-ts-mode--generate-args (make-hash-table :test 'equal)))
     (cl-letf (((symbol-function 'executable-find)
                (lambda (name &rest _) name))
               ((symbol-function 'display-buffer) #'ignore)
               ((symbol-function 'make-process)
                (lambda (&rest args)
                  (setq captured-command (plist-get args :command)
                        captured-dir default-directory)
                  'fake-proc))
               ((symbol-function 'read-string)
                (lambda (prompt &optional initial &rest _)
                  (setq prompt-count (1+ prompt-count)
                        captured-prompt prompt
                        captured-initial initial)
                  ;; Mimic the minibuffer: with no edit, the initial value
                  ;; is what gets returned.
                  (or ,input initial))))
       ,@body)))

(ert-deftest wit-ts-mode-generate-runs-and-remembers ()
  "`wit-ts-generate' prompts once, runs from the root, then reuses args."
  ;; The `proj/wit' fixture has a `deps.toml', so the default tool
  ;; function selects `wit-bindgen'.
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (wit-ts-mode-tests--with-generate "rust --out-dir gen wit"
      (wit-ts-generate)
      (should (equal captured-command
                     '("wit-bindgen" "rust" "--out-dir" "gen" "wit")))
      (should (equal (file-name-nondirectory (directory-file-name captured-dir))
                     "proj"))
      (should (= prompt-count 1))
      ;; Second call reuses the remembered args without prompting.
      (setq captured-command nil)
      (wit-ts-generate)
      (should (= prompt-count 1))
      (should (equal captured-command
                     '("wit-bindgen" "rust" "--out-dir" "gen" "wit"))))))

(ert-deftest wit-ts-mode-generate-uses-cargo-component-for-wkg ()
  "For a `wkg' project, `wit-ts-generate' runs `cargo-component build'."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (let ((wit-ts-deps-tool-function (lambda (&rest _) 'wkg)))
      (wit-ts-mode-tests--with-generate nil  ; accept the pre-filled template
        (wit-ts-generate)
        (should (equal captured-command '("cargo-component" "build")))
        (should (string-match-p "cargo-component" captured-prompt))
        (should (equal captured-initial "build"))
        (should (equal (file-name-nondirectory
                        (directory-file-name captured-dir))
                       "proj"))))))

(ert-deftest wit-ts-mode-generate-prefix-reconfigures ()
  "A prefix argument makes `wit-ts-generate' prompt again."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (wit-ts-mode-tests--with-generate "c --out-dir out wit"
      (wit-ts-generate)
      (should (= prompt-count 1))
      (wit-ts-generate t)              ; prefix -> re-prompt
      (should (= prompt-count 2)))))

(ert-deftest wit-ts-mode-generate-shows-command ()
  "The exact command line appears in the tool's output buffer."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (wit-ts-mode-tests--with-generate "rust wit"
      (wit-ts-generate)
      (with-current-buffer "*wit-bindgen*"
        (should (string-match-p "wit-bindgen rust wit"
                                (buffer-substring-no-properties
                                 (point-min) (point-max))))))))

(ert-deftest wit-ts-mode-generate-errors-without-executable ()
  "`wit-ts-generate' signals a clear error when the CLI is absent."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    (cl-letf (((symbol-function 'executable-find) (lambda (&rest _) nil)))
      (should-error (wit-ts-generate) :type 'user-error))))

(ert-deftest wit-ts-mode-generate-prompt-guides-and-prefills ()
  "The prompt explains the argument form and pre-fills a WIT-dir template."
  (wit-ts-mode-tests--with-project-file "proj/wit/root.wit"
    ;; INPUT nil -> the stub returns the pre-filled initial value.
    (wit-ts-mode-tests--with-generate nil
      (wit-ts-generate)
      ;; The prompt names the expected form and lists a language.
      (should (string-match-p "LANGUAGE" captured-prompt))
      (should (string-match-p "WIT-PATH" captured-prompt))
      (should (string-match-p "rust" captured-prompt))
      ;; The template pre-fill ends with the project's WIT directory.
      (should (string-match-p "\\bwit\\'" captured-initial))
      ;; With no edit, that template is what runs.
      (should (equal (car captured-command) "wit-bindgen"))
      (should (member "wit" captured-command)))))

(provide 'wit-ts-mode-tests)

;;; wit-ts-mode-tests.el ends here
