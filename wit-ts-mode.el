;;; wit-ts-mode.el --- Major mode for WIT files  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Markus Klink

;; Author: Markus Klink <justjoheinz@gmail.com>
;; URL: https://github.com/justjoheinz/wit-ts-mode
;; Keywords: languages wasm wit
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1"))
;; SPDX-License-Identifier: Apache-2.0

;; Licensed under the Apache License, Version 2.0 (the "License"); you may
;; not use this file except in compliance with the License.  See the LICENSE
;; file in this directory for the full text.

;;; Commentary:

;; A major mode for editing WIT (WebAssembly Interface Types) files, built on
;; the built-in tree-sitter support (`treesit', Emacs 29.1+).
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

(declare-function treesit-parser-create "treesit.c")
(declare-function treesit-node-type "treesit.c")
(declare-function treesit-node-child "treesit.c")
(declare-function treesit-node-child-by-field-name "treesit.c")

;;; Grammar

(defvar wit-ts-mode-grammar-url
  "https://github.com/bytecodealliance/tree-sitter-wit"
  "URL of the tree-sitter grammar used by `wit-ts-mode'.")

;; Register the grammar source so `M-x treesit-install-language-grammar'
;; and the on-demand install in `wit-ts-mode' both know where to find it.
(add-to-list 'treesit-language-source-alist
             `(wit ,wit-ts-mode-grammar-url))

(defun wit-ts-mode--ensure-grammar ()
  "Ensure the WIT tree-sitter grammar is available.
If it is not installed, offer to install it interactively.  Signal
an error if it remains unavailable."
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

;;; Folding

;; Translation of queries/folds.scm.  The grammar folds on `(body)' nodes
;; (the braced blocks of worlds, interfaces, records, resources, variants,
;; ...) and on block comments.  hideshow works on the brace structure
;; directly, so registering the block delimiters reproduces those folds.
(defvar wit-ts-mode--hideshow-spec
  '(wit-ts-mode "{" "}" "/[*/]" nil nil)
  "Entry for `hs-special-modes-alist' describing WIT block folds.")

(unless (assq 'wit-ts-mode hs-special-modes-alist)
  (add-to-list 'hs-special-modes-alist wit-ts-mode--hideshow-spec))

;;; Outline

(defvar wit-ts-mode--outline-node-regexp
  (rx bos (or "package_decl"
              "world_item" "interface_item"
              "func_item" "type_item" "record_item"
              "variant_items" "enum_items" "flags_items" "resource_item"
              "import_item" "export_item" "toplevel_use_item")
      eos)
  "Regexp of node types treated as outline headings in `wit-ts-mode'.")

;;; Mode definition

;;;###autoload
(define-derived-mode wit-ts-mode prog-mode "WIT"
  "Major mode for editing WIT files, powered by tree-sitter."
  :group 'wit-ts
  (wit-ts-mode--ensure-grammar)

  (treesit-parser-create 'wit)

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
  (setq-local treesit-defun-type-regexp
              (rx bos (or "world_item" "interface_item" "func_item"
                          "record_item" "variant_items" "enum_items"
                          "flags_items" "resource_item" "type_item")
                  eos))
  (setq-local treesit-defun-name-function #'wit-ts-mode--defun-name)
  (setq-local treesit-simple-imenu-settings
              `(("World" "\\`world_item\\'" nil nil)
                ("Interface" "\\`interface_item\\'" nil nil)
                ("Type" ,(rx bos (or "record_item" "variant_items" "enum_items"
                                     "flags_items" "resource_item" "type_item")
                             eos)
                 nil nil)
                ("Function" "\\`func_item\\'" nil nil)))

  ;; Folding: hideshow on the brace blocks (queries/folds.scm) via the
  ;; entry registered in `hs-special-modes-alist', and a
  ;; tree-sitter-driven outline over the declaration hierarchy.
  (setq-local treesit-outline-predicate wit-ts-mode--outline-node-regexp)

  (treesit-major-mode-setup))

;;;###autoload
(when (fboundp 'treesit-ready-p)
  (add-to-list 'auto-mode-alist '("\\.wit\\'" . wit-ts-mode)))

(provide 'wit-ts-mode)

;;; wit-ts-mode.el ends here
