;;; wit-ts-mode.el --- Major mode for WIT files  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Markus Klink

;; Author: Markus Klink <justjoheinz@gmail.com>
;; URL: https://github.com/justjoheinz/wit-ts-mode
;; Keywords: languages wasm wit
;; Version: 0.1.0
;; Package-Requires: ((emacs "30.1"))
;; SPDX-License-Identifier: Apache-2.0

;; Licensed under the Apache License, Version 2.0 (the "License"); you may
;; not use this file except in compliance with the License.  See the LICENSE
;; file in this directory for the full text.

;;; Commentary:

;; A major mode for editing WIT (WebAssembly Interface Types) files, built on
;; the built-in tree-sitter support (`treesit', Emacs 30.1+).
;;
;; It uses the `wit' tree-sitter grammar from
;; https://github.com/bytecodealliance/tree-sitter-wit and mirrors the
;; highlighting captures from that project's queries/highlights.scm.
;;
;; Installation:
;;
;;   Loading this file registers the grammar's upstream source in
;;   `treesit-language-source-alist' and associates `.wit' files with
;;   `wit-ts-mode'.  The first time you open a WIT file, if the grammar is
;;   not yet installed the mode offers to install it for you (this requires
;;   a C compiler).  You can also install it ahead of time with:
;;
;;     M-x treesit-install-language-grammar RET wit RET
;;
;;   Then simply open a `.wit' file, or `M-x wit-ts-mode'.

;;; Code:

(require 'treesit)
(require 'hideshow)
(require 'flymake)
(require 'seq)

(declare-function treesit-parser-create "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-node-child "treesit.c")
(declare-function treesit-node-child-by-field-name "treesit.c")
(declare-function treesit-node-start "treesit.c")
(declare-function treesit-node-end "treesit.c")
(declare-function treesit-node-check "treesit.c")
(declare-function treesit-search-subtree "treesit.c")
(declare-function treesit-parser-root-node "treesit.c")
(declare-function treesit-parser-list "treesit.c")
(declare-function treesit-parser-language "treesit.c")
(declare-function treesit-node-at "treesit.c")
(declare-function treesit-node-parent "treesit.c")
(declare-function treesit-node-text "treesit.c")
(declare-function treesit-query-capture "treesit.c")

(defun wit-ts-mode--parser ()
  "Return the buffer's `wit' tree-sitter parser, or nil.
Filters `treesit-parser-list' by language in Emacs Lisp rather
than passing a language argument, which is unsupported before
Emacs 30."
  (seq-find (lambda (parser)
              (eq (treesit-parser-language parser) 'wit))
            (treesit-parser-list)))

;;; Grammar

(defvar wit-ts-mode-grammar-url
  "https://github.com/bytecodealliance/tree-sitter-wit"
  "URL of the tree-sitter grammar used by `wit-ts-mode'.")

(defun wit-ts-mode--register-grammar-source ()
  "Register the WIT grammar in `treesit-language-source-alist'.
Done lazily (only when the mode is used) so that merely loading
this file does not mutate that global variable."
  (unless (assq 'wit treesit-language-source-alist)
    (add-to-list 'treesit-language-source-alist
                 `(wit ,wit-ts-mode-grammar-url))))

(defun wit-ts-mode--ensure-grammar ()
  "Ensure the WIT tree-sitter grammar is available.
If it is not installed, offer to install it interactively.  Signal
an error if it remains unavailable."
  (wit-ts-mode--register-grammar-source)
  (unless (treesit-ready-p 'wit t)
    (if (and (not noninteractive)
             (fboundp 'treesit-install-language-grammar)
             (y-or-n-p "The WIT tree-sitter grammar is not installed.  \
Install it now? "))
        (treesit-install-language-grammar 'wit)
      (error "The WIT tree-sitter grammar (`wit') is not installed; \
run `M-x treesit-install-language-grammar RET wit RET'")))
  (unless (treesit-ready-p 'wit)
    (error "The WIT tree-sitter grammar (`wit') could not be loaded")))

;;; Customization

(defgroup wit-ts nil
  "Major mode for editing WIT files with tree-sitter."
  :group 'languages
  :prefix "wit-ts-")

(defcustom wit-ts-mode-indent-offset 4
  "Number of spaces for each indentation step in `wit-ts-mode'."
  :type 'natnum
  :safe #'natnump
  :group 'wit-ts)

;;; Indentation

(defvar wit-ts-mode--indent-rules
  `((wit
     ((parent-is "source_file") column-0 0)
     ((node-is "}") parent-bol 0)
     ((node-is ")") parent-bol 0)
     ((node-is ">") parent-bol 0)
     ((parent-is "body") parent-bol wit-ts-mode-indent-offset)
     ((parent-is "func_type") parent-bol wit-ts-mode-indent-offset)
     ((parent-is "tuple") parent-bol wit-ts-mode-indent-offset)
     ((parent-is "record_item") parent-bol wit-ts-mode-indent-offset)
     ((parent-is "flags_items") parent-bol wit-ts-mode-indent-offset)
     ((parent-is "variant_items") parent-bol wit-ts-mode-indent-offset)
     ((parent-is "enum_items") parent-bol wit-ts-mode-indent-offset)
     ((parent-is "resource_item") parent-bol wit-ts-mode-indent-offset)
     (catch-all parent-bol wit-ts-mode-indent-offset)))
  "Tree-sitter indentation rules for `wit-ts-mode'.")

;;; Font-lock

(defvar wit-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'wit
   :feature 'comment
   '([(line_comment) (block_comment)] @font-lock-comment-face
     (line_comment (doc_comment)) @font-lock-doc-face
     (block_comment (doc_comment)) @font-lock-doc-face)

   :language 'wit
   :feature 'string
   '((version) @font-lock-string-face
     (unstable_gate feature: (id) @font-lock-string-face)
     (external_id
      "@" @font-lock-preprocessor-face
      "external-id" @font-lock-preprocessor-face
      id: (string_literal) @font-lock-string-face))

   :language 'wit
   :feature 'keyword
   '("func" @font-lock-keyword-face
     ["type" "interface" "world" "package" "resource"
      "record" "enum" "flags" "variant"] @font-lock-keyword-face
     "static" @font-lock-keyword-face
     "async" @font-lock-keyword-face
     ["include" "import" "export" "as" "with"] @font-lock-keyword-face
     (toplevel_use_item "use" @font-lock-keyword-face)
     (use_item "use" @font-lock-keyword-face))

   :language 'wit
   :feature 'attribute
   ;; Feature gates with a leading `@', e.g. `@since', `@unstable',
   ;; `@deprecated'.  `:anchor' is the s-expression form of the query
   ;; anchor `.'.
   '((_ :anchor "@" @font-lock-preprocessor-face
        :anchor ["since" "unstable" "deprecated"] @font-lock-builtin-face))

   :language 'wit
   :feature 'type
   '((ty (id) @font-lock-type-face)
     (handle (id) @font-lock-type-face)
     (type_item alias: (id) @font-lock-type-face)
     (record_item name: (id) @font-lock-type-face)
     (flags_items name: (id) @font-lock-type-face)
     (variant_items name: (id) @font-lock-type-face)
     (enum_items name: (id) @font-lock-type-face)
     (resource_item name: (id) @font-lock-type-face)
     ["u8" "u16" "u32" "u64" "s8" "s16" "s32" "s64"
      "f32" "f64" "char" "bool" "string"] @font-lock-type-face
     ["tuple" "list" "option" "result" "map"
      "borrow" "future" "stream"] @font-lock-type-face)

   :language 'wit
   :feature 'definition
   '((decl_head (id) @font-lock-function-name-face)
     (world_item name: (id) @font-lock-function-name-face)
     (interface_item name: (id) @font-lock-function-name-face)
     (import_item name: (id) @font-lock-function-name-face
                  (extern_type (body)))
     (import_item name: (id) @font-lock-function-name-face
                  (extern_type (func_type)))
     (export_item name: (id) @font-lock-function-name-face
                  (extern_type (body)))
     (export_item name: (id) @font-lock-function-name-face
                  (extern_type (func_type)))
     (func_item name: (id) @font-lock-function-name-face)
     (resource_method (id) @font-lock-function-name-face)
     (resource_method "constructor" @font-lock-function-name-face)
     (toplevel_use_item alias: (id) @font-lock-function-name-face)
     (use_path (id) @font-lock-function-name-face)
     (alias_item (id) @font-lock-function-name-face)
     (use_names_item (id) @font-lock-function-name-face))

   :language 'wit
   :feature 'property
   '((named_type name: (id) @font-lock-variable-name-face)
     (record_field name: (id) @font-lock-property-name-face)
     (flags_field) @font-lock-property-name-face
     "_" @font-lock-variable-name-face)

   :language 'wit
   :feature 'constant
   '((uint) @font-lock-constant-face
     (variant_case name: (id) @font-lock-constant-face)
     (enum_case) @font-lock-constant-face)

   :language 'wit
   :feature 'operator
   '("=" @font-lock-operator-face)

   :language 'wit
   :feature 'bracket
   '(["{" "}" "(" ")" ">" "<"] @font-lock-bracket-face)

   :language 'wit
   :feature 'delimiter
   '([";" ":" "," "." "->"] @font-lock-delimiter-face
     (use_path ["@" "/"] @font-lock-delimiter-face)
     (decl_head ["@" "/"] @font-lock-delimiter-face)))
  "Tree-sitter font-lock settings for `wit-ts-mode'.")

;;; Imenu

(defun wit-ts-mode--defun-name (node)
  "Return the name of NODE for imenu / `treesit-defun-name'.
Most WIT declarations store their name in the `name' field; a
`type_item' alias stores it in the `alias' field instead."
  (let ((name (or (treesit-node-child-by-field-name node "name")
                  (treesit-node-child-by-field-name node "alias"))))
    (when name
      (treesit-node-text name t))))

;;; Completion

(defconst wit-ts-mode--keywords
  '("type" "interface" "world" "package" "resource" "record" "enum"
    "flags" "variant" "func" "static" "async" "constructor"
    "include" "import" "export" "use" "as" "with")
  "WIT keywords offered for completion.")

(defconst wit-ts-mode--builtin-types
  '("u8" "u16" "u32" "u64" "s8" "s16" "s32" "s64" "f32" "f64"
    "char" "bool" "string"
    "tuple" "list" "option" "result" "map" "borrow" "future" "stream")
  "WIT builtin and predefined type constructors offered for completion.")

(defconst wit-ts-mode--completion-defs-query
  '((interface_item name: (id) @n)
    (world_item name: (id) @n)
    (record_item name: (id) @n)
    (variant_items name: (id) @n)
    (enum_items name: (id) @n)
    (flags_items name: (id) @n)
    (resource_item name: (id) @n)
    (type_item alias: (id) @n)
    (func_item name: (id) @n))
  "Tree-sitter query capturing names of top-level WIT definitions.")

(defun wit-ts-mode--buffer-definitions ()
  "Return a list of identifier names defined in the current buffer.
Collected from the tree-sitter parse tree (interfaces, worlds, and
the various type and function definitions)."
  (when-let* ((parser (wit-ts-mode--parser)))
    (delete-dups
     (mapcar (lambda (node) (treesit-node-text node t))
             (treesit-query-capture
              (treesit-parser-root-node parser)
              wit-ts-mode--completion-defs-query nil nil t)))))

(defun wit-ts-mode--completion-candidates ()
  "Return all completion candidates: keywords, builtins, definitions."
  (append wit-ts-mode--keywords
          wit-ts-mode--builtin-types
          (wit-ts-mode--buffer-definitions)))

(defun wit-ts-mode--in-comment-or-string-p (node)
  "Return non-nil if NODE is, or is inside, a comment or string."
  (let ((types '("line_comment" "block_comment" "doc_comment"
                 "string_literal"))
        (cur node)
        found)
    (while (and cur (not found))
      (when (member (treesit-node-type cur) types)
        (setq found t))
      (setq cur (treesit-node-parent cur)))
    found))

(defun wit-ts-mode-completion-at-point ()
  "Completion-at-point function for `wit-ts-mode'.
Completes WIT keywords, builtin types, and identifiers defined in
the current buffer.  Suitable for `completion-at-point-functions'."
  (let ((node (treesit-node-at (point))))
    ;; Do not complete inside comments or string literals.
    (unless (wit-ts-mode--in-comment-or-string-p node)
      (let* ((bounds (bounds-of-thing-at-point 'symbol))
             (start (if bounds (car bounds) (point)))
             (end (if bounds (cdr bounds) (point))))
        (list start end
              (completion-table-dynamic
               (lambda (_prefix) (wit-ts-mode--completion-candidates)))
              :exclusive 'no)))))

;;; Folding

;; Translation of queries/folds.scm.  The grammar folds on `(body)' nodes
;; (the braced blocks of worlds, interfaces, records, resources, variants,
;; ...) and on block comments.  hideshow drives this from its per-mode
;; entry in `hs-special-modes-alist'.  That variable is obsolete as of
;; Emacs 31.1 but still honoured (and is the only cross-version way to
;; configure block *and* comment folding, since `hs-minor-mode' otherwise
;; overwrites the buffer-local parameters), so the warning is suppressed.
(defvar wit-ts-mode--hideshow-spec
  '(wit-ts-mode "{" "}" "/[*/]" nil nil)
  "Entry describing WIT block folds for hideshow.")

(with-suppressed-warnings ((obsolete hs-special-modes-alist))
  (unless (assq 'wit-ts-mode hs-special-modes-alist)
    (add-to-list 'hs-special-modes-alist wit-ts-mode--hideshow-spec)))

;;; Outline

(defvar wit-ts-mode--outline-node-regexp
  (rx bos (or "world_item" "interface_item"
              "func_item" "record_item"
              "variant_items" "enum_items" "flags_items" "resource_item")
      eos)
  "Regexp of node types that may act as outline headings in `wit-ts-mode'.
A node is only treated as a heading when it also spans multiple
lines; see `wit-ts-mode--outline-predicate'.")

(defun wit-ts-mode--outline-predicate (node)
  "Return non-nil if NODE should be an outline heading.
Only multi-line declarations qualify, so single-line items (such
as `type t = u32;' or a one-line function) do not get a fold
marker with nothing to hide."
  (and (string-match-p wit-ts-mode--outline-node-regexp
                       (treesit-node-type node))
       (> (line-number-at-pos (treesit-node-end node))
          (line-number-at-pos (treesit-node-start node)))))

;;; Navigation

(defvar wit-ts-mode--defun-node-regexp
  (rx bos (or "world_item" "interface_item" "func_item"
              "record_item" "variant_items" "enum_items"
              "flags_items" "resource_item" "type_item")
      eos)
  "Regexp of node types treated as defuns in `wit-ts-mode'.")

(defvar wit-ts-mode--thing-settings
  `((wit
     ;; Top-level declarations, for `beginning-of-defun' etc.
     (defun ,wit-ts-mode--defun-node-regexp)
     ;; A sexp is any node that is not a bare delimiter, so `forward-sexp'
     ;; and friends step over identifiers and whole constructs rather than
     ;; individual punctuation.
     (sexp (not ,(rx bos (or "{" "}" "(" ")" "<" ">"
                             "," ";" ":" "." "=" "->" "@" "/")
                     eos)))
     ;; Bracketed groups, for `forward-list' / `up-list' / `down-list'.
     (list ,(rx bos (or "body" "func_type" "tuple" "tuple_list"
                        "list" "option" "result")
                eos))
     ;; A single declaration or member, for `forward-sentence'.
     (sentence ,(rx bos (or "type_item" "record_field" "variant_case"
                            "enum_case" "flags_field" "func_item"
                            "use_item" "import_item" "export_item")
                    eos))
     ;; Comments and strings behave as free text.
     (text ,(rx bos (or "line_comment" "block_comment" "string_literal")
                eos))))
  "Tree-sitter thing definitions for `wit-ts-mode' navigation.")

;;; Syntax checking (Flymake)

(defvar-local wit-ts-mode--flymake-parser nil
  "Tree-sitter parser used by the Flymake backend, if any.")

(defconst wit-ts-mode--token-descriptions
  '(("}" . "closing brace `}'")
    ("{" . "opening brace `{'")
    (")" . "closing parenthesis `)'")
    ("(" . "opening parenthesis `('")
    (">" . "closing angle bracket `>'")
    ("<" . "opening angle bracket `<'")
    (";" . "semicolon `;'")
    ("," . "comma `,'")
    (":" . "colon `:'")
    ("=" . "`='")
    ("->" . "arrow `->'"))
  "Human-readable descriptions for tokens that may be reported missing.")

(defun wit-ts-mode--describe-token (type)
  "Return a human-readable description of tree-sitter node TYPE."
  (or (cdr (assoc type wit-ts-mode--token-descriptions))
      (format "`%s'" type)))

(defun wit-ts-mode--snippet (node)
  "Return a short single-line snippet of NODE's text for a message."
  (let* ((text (treesit-node-text node t))
         ;; Collapse whitespace/newlines so the message stays one line.
         (flat (string-trim (replace-regexp-in-string "[ \t\n]+" " " text))))
    (if (> (length flat) 30)
        (concat (substring flat 0 30) "…")
      flat)))

(defun wit-ts-mode--missing-message (node)
  "Return a Flymake message describing missing-token NODE."
  (format "Syntax error: expected %s"
          (wit-ts-mode--describe-token (treesit-node-type node))))

(defun wit-ts-mode--error-message (node)
  "Return a Flymake message describing ERROR NODE.
When the offending text is short, quote it; otherwise fall back to
a generic message."
  (let ((snippet (wit-ts-mode--snippet node)))
    (if (string-empty-p snippet)
        "Syntax error: unexpected input"
      (format "Syntax error: unexpected `%s'" snippet))))

(defun wit-ts-mode--flymake-diag (source node message)
  "Make a Flymake error diagnostic for NODE in SOURCE with MESSAGE.
Zero-width nodes are widened by one character so there is
something to underline."
  (let* ((beg (treesit-node-start node))
         (end (max (treesit-node-end node) (1+ beg))))
    (flymake-make-diagnostic source beg end :error message)))

(defun wit-ts-mode--flymake-diagnostics (parser source)
  "Return Flymake diagnostics for parse errors in PARSER.
Anchor them in the SOURCE buffer.  Missing nodes report the token
the grammar expected (a missing node's type is that token, e.g.
`}' or `;'); `ERROR' nodes quote the offending input.  The
traversal visits anonymous nodes too, since a missing token is
often an anonymous node."
  (let (diags)
    (treesit-search-subtree
     (treesit-parser-root-node parser)
     (lambda (node)
       (cond
        ((treesit-node-check node 'missing)
         (push (wit-ts-mode--flymake-diag
                source node (wit-ts-mode--missing-message node))
               diags))
        ((equal (treesit-node-type node) "ERROR")
         (push (wit-ts-mode--flymake-diag
                source node (wit-ts-mode--error-message node))
               diags)))
       ;; Return nil so the walk visits every node.
       nil)
     nil
     ;; ALL: include anonymous nodes so missing tokens are seen.
     t)
    (nreverse diags)))

(defun wit-ts-mode-flymake (report-fn &rest _args)
  "A Flymake backend reporting WIT tree-sitter parse errors.
REPORT-FN is called with the diagnostics, per the Flymake backend
protocol.  Intended for `flymake-diagnostic-functions'."
  (if-let* ((parser (or wit-ts-mode--flymake-parser
                        (wit-ts-mode--parser))))
      (funcall report-fn
               (wit-ts-mode--flymake-diagnostics parser (current-buffer)))
    (funcall report-fn nil)))

;;; Mode definition

;;;###autoload
(define-derived-mode wit-ts-mode prog-mode "WIT"
  "Major mode for editing WIT files, powered by tree-sitter."
  :group 'wit-ts
  (wit-ts-mode--ensure-grammar)

  (setq wit-ts-mode--flymake-parser (treesit-parser-create 'wit))

  ;; Comments.
  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip (rx "/" (+ "/") (* (syntax whitespace))))

  ;; Indentation.  WIT files conventionally indent with spaces.
  (setq-local indent-tabs-mode nil)
  (setq-local treesit-simple-indent-rules wit-ts-mode--indent-rules)
  (setq-local electric-indent-chars
              (append "{}()<>" electric-indent-chars))

  ;; Font-lock.
  (setq-local treesit-font-lock-settings wit-ts-mode--font-lock-settings)
  (setq-local treesit-font-lock-feature-list
              '((comment definition)
                (keyword string type)
                (attribute constant property)
                (operator bracket delimiter)))

  ;; Navigation & imenu.
  (setq-local treesit-defun-type-regexp wit-ts-mode--defun-node-regexp)
  (setq-local treesit-defun-name-function #'wit-ts-mode--defun-name)
  ;; Structural motion: `forward-sexp', `forward-sentence', `up-list',
  ;; `beginning-of-defun', and (via `treesit-major-mode-setup')
  ;; `which-function-mode' all read these thing definitions.
  (setq-local treesit-thing-settings wit-ts-mode--thing-settings)
  (setq-local treesit-simple-imenu-settings
              `(("World" "\\`world_item\\'" nil nil)
                ("Interface" "\\`interface_item\\'" nil nil)
                ("Type" ,(rx bos (or "record_item" "variant_items" "enum_items"
                                     "flags_items" "resource_item" "type_item")
                             eos)
                 nil nil)
                ("Function" "\\`func_item\\'" nil nil)))

  ;; Folding: hideshow reads the `hs-special-modes-alist' entry above; a
  ;; tree-sitter-driven outline covers the declaration hierarchy.
  (setq-local treesit-outline-predicate #'wit-ts-mode--outline-predicate)

  ;; Syntax checking: report tree-sitter parse errors through Flymake.
  ;; Enable `flymake-mode' to see them.
  (add-hook 'flymake-diagnostic-functions #'wit-ts-mode-flymake nil t)

  ;; Completion: keywords, builtin types, and buffer-local definitions.
  (add-hook 'completion-at-point-functions
            #'wit-ts-mode-completion-at-point nil t)

  (treesit-major-mode-setup))

;;;###autoload
(when (fboundp 'treesit-ready-p)
  (add-to-list 'auto-mode-alist '("\\.wit\\'" . wit-ts-mode)))

(provide 'wit-ts-mode)

;;; wit-ts-mode.el ends here
