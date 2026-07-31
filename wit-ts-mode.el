;;; wit-ts-mode.el --- Major mode for WIT files  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Markus Klink

;; Author: Markus Klink <justjoheinz@gmail.com>
;; Assisted-by: claude:claude-opus-4-8
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

(require 'cl-lib)
(require 'treesit)
(require 'hideshow)
(require 'flymake)
(require 'outline)
(require 'seq)
(require 'xref)

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

(defcustom wit-ts-deps-executable "wit-deps"
  "Program used to resolve WIT dependencies.
Invoked by `wit-ts-deps-sync' to populate the dependency directory.
Looked up with `executable-find' on the variable `exec-path', so a
bare program name or an absolute path both work."
  :type 'string
  :group 'wit-ts)

(defcustom wit-ts-deps-directory "wit"
  "Name of the directory `wit-deps' manages, relative to the project.
Its manifest lives at DIR/deps.toml and resolved dependencies at
DIR/deps/.  `wit' is the `wit-deps' default but is configurable,
so `wit-ts-mode' does not hardcode it."
  :type 'string
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

(defconst wit-ts-mode--gates
  '("since" "unstable" "deprecated")
  "WIT feature-gate attribute names offered after `@'.
See the WIT spec's feature-gate grammar: `@since(version = ...)',
`@unstable(feature = ...)', `@deprecated(version = ...)'.")

(defconst wit-ts-mode--gate-fields
  '(("since"      . "version")
    ("deprecated" . "version")
    ("unstable"   . "feature"))
  "Alist mapping a WIT feature gate to the field name it takes.
`@since'/`@deprecated' take `version = <semver>'; `@unstable'
takes `feature = <id>' (per the WIT feature-gate grammar).")

(defconst wit-ts-mode--kind-property 'wit-ts-mode--kind
  "Text property naming the WIT kind of a completion candidate.
The value is a symbol such as `interface', `world', `record',
`enum', `flags', `variant', `resource', `type', `func',
`package', `keyword' or `builtin'.")

(defconst wit-ts-mode--kind-annotations
  '((interface . " interface")
    (world     . " world")
    (record    . " record")
    (enum      . " enum")
    (flags     . " flags")
    (variant   . " variant")
    (resource  . " resource")
    (type      . " type")
    (func      . " func")
    (package   . " package")
    (keyword   . " keyword")
    (builtin   . " builtin type")
    (gate      . " feature gate")
    (field     . " gate field"))
  "Alist mapping a candidate's WIT kind to its completion annotation.
The annotation is the text shown after a candidate in the
completion UI (e.g. the `*Completions*' buffer).")

(defconst wit-ts-mode--kind-company-kinds
  '((interface . interface)
    (world     . module)
    (record    . struct)
    (enum      . enum)
    (flags     . enum)
    (variant   . enum)
    (resource  . class)
    (type      . type-parameter)
    (func      . function)
    (package   . module)
    (keyword   . keyword)
    (builtin   . type-parameter)
    (gate      . keyword)
    (field     . property))
  "Alist mapping a candidate's WIT kind to a Company/Corfu `kind' symbol.
These symbols select the icon shown by frontends that support the
`company-kind' completion property (e.g. Corfu, Company).")

(defun wit-ts-mode--kinded (name kind)
  "Return NAME as a completion candidate carrying its WIT KIND.
KIND is stored in the `wit-ts-mode--kind-property' text property;
it is ignored by `equal' and completion matching but read back by
the completion annotation and `company-kind' functions."
  (propertize name wit-ts-mode--kind-property kind))

(defun wit-ts-mode--candidate-kind (candidate)
  "Return the WIT kind symbol of completion CANDIDATE, or nil."
  (and (> (length candidate) 0)
       (get-text-property 0 wit-ts-mode--kind-property candidate)))

(defconst wit-ts-mode--completion-defs-query
  ;; Each capture is named after the WIT kind it matches, so a single
  ;; `treesit-query-capture' yields both the name and its kind.
  '((interface_item name: (id) @interface)
    (world_item name: (id) @world)
    (record_item name: (id) @record)
    (variant_items name: (id) @variant)
    (enum_items name: (id) @enum)
    (flags_items name: (id) @flags)
    (resource_item name: (id) @resource)
    (type_item alias: (id) @type)
    (func_item name: (id) @func))
  "Tree-sitter query capturing names of top-level WIT definitions.
Each capture name is the WIT kind of the matched definition (see
`wit-ts-mode--kinded'), so callers can label candidates by kind.")

(defun wit-ts-mode--kinded-captures (root query)
  "Return kinded candidate strings for QUERY captured under ROOT.
Each capture name in QUERY is taken to be the candidate's WIT kind
\(a symbol); the captured node's text becomes the candidate, tagged
with that kind via `wit-ts-mode--kinded'.  Duplicates are removed."
  (let (seen result)
    (dolist (cap (treesit-query-capture root query nil nil nil))
      (let ((name (treesit-node-text (cdr cap) t)))
        (unless (member name seen)
          (push name seen)
          (push (wit-ts-mode--kinded name (car cap)) result))))
    (nreverse result)))

(defconst wit-ts-mode--completion-packages-query
  '((package_decl (decl_head) @h))
  "Tree-sitter query capturing the `decl_head' of package declarations.
A `decl_head' spells out the package id, e.g. the tokens of
\"package wasi:http@0.2.10;\" (see the WIT grammar's `decl_head',
`_uri_head' and `_uri_tail' rules).")

(defun wit-ts-mode--package-id-from-decl-head (node)
  "Reconstruct a package id from a `decl_head' NODE, or nil.
Per the WIT grammar a `decl_head' is `package' followed by
namespace/name id tokens joined by `:' and `/', then an optional
@version.  Concatenate the id and separator tokens (dropping the
`package' keyword and the version), yielding e.g. \"wasi:http\"."
  (let (parts done)
    (dotimes (i (treesit-node-child-count node))
      (unless done
        (let ((type (treesit-node-type (treesit-node-child node i))))
          (cond
           ((member type '("id" ":" "/"))
            (push (treesit-node-text (treesit-node-child node i) t) parts))
           ((member type '("@" "version"))
            (setq done t))))))
    (when parts
      (apply #'concat (nreverse parts)))))

(defun wit-ts-mode--package-version-from-decl-head (node)
  "Return the @version string of a `decl_head' NODE, or nil.
E.g. \"0.2.10\" for \"package wasi:http@0.2.10;\"."
  (let (version)
    (dotimes (i (treesit-node-child-count node))
      (let ((child (treesit-node-child node i)))
        (when (equal (treesit-node-type child) "version")
          (setq version (treesit-node-text child t)))))
    version))

(defconst wit-ts-mode--completion-interfaces-query
  ;; Capture names double as WIT kinds (see `wit-ts-mode--kinded-captures').
  '((interface_item name: (id) @interface)
    (world_item name: (id) @world))
  "Tree-sitter query capturing interface and world names.
These are the definitions an `import'/`export'/`use' path may
refer to (by bare name within a package, or as ns:pkg/NAME across
packages).")

(defconst wit-ts-mode--completion-members-query
  ;; Capture names double as WIT kinds (see `wit-ts-mode--kinded-captures').
  '((type_item alias: (id) @type)
    (record_item name: (id) @record)
    (variant_items name: (id) @variant)
    (enum_items name: (id) @enum)
    (flags_items name: (id) @flags)
    (resource_item name: (id) @resource))
  "Tree-sitter query capturing an interface's `use'-able members.
Per the WIT spec a `use interface.{ ... }' names list may only
refer to types and resources, never functions, so `func_item' is
deliberately absent here.  Each capture name is the member's WIT
kind.")

(defun wit-ts-mode--interface-members-alist (root)
  "Return an alist mapping each interface name under ROOT to its members.
Each value is the list of type/resource names defined directly in
that interface (see `wit-ts-mode--completion-members-query'), as
kinded candidates -- the identifiers valid in a
`use interface.{ ... }' list."
  (let (alist)
    (dolist (iface (treesit-query-capture root '((interface_item) @i) nil nil t))
      (when-let* ((name-node (treesit-node-child-by-field-name iface "name")))
        (push (cons (treesit-node-text name-node t)
                    (wit-ts-mode--kinded-captures
                     iface wit-ts-mode--completion-members-query))
              alist)))
    alist))

(defun wit-ts-mode--buffer-definitions ()
  "Return the definitions of the current buffer as kinded candidates.
Collected from the tree-sitter parse tree (interfaces, worlds, and
the various type and function definitions), each tagged with its
WIT kind (see `wit-ts-mode--kinded')."
  (when-let* ((parser (wit-ts-mode--parser)))
    (wit-ts-mode--kinded-captures
     (treesit-parser-root-node parser)
     wit-ts-mode--completion-defs-query)))

(defun wit-ts-mode--completion-candidates ()
  "Return the default completion candidates: keywords, builtins, and defs.
These are offered in ordinary (non-import) contexts: WIT keywords,
builtin types, and the definitions of the current buffer.  Each
candidate is tagged with its WIT kind (see `wit-ts-mode--kinded').

Cross-file symbols are deliberately excluded here: names from
other packages are only meaningful in an `import'/`export'/`use'
path, where `wit-ts-mode--path-candidates' supplies them."
  (append (mapcar (lambda (k) (wit-ts-mode--kinded k 'keyword))
                  wit-ts-mode--keywords)
          (mapcar (lambda (b) (wit-ts-mode--kinded b 'builtin))
                  wit-ts-mode--builtin-types)
          (wit-ts-mode--buffer-definitions)))

;;; Cross-file symbols

;; Real WIT projects span several files: sibling files within one package and
;; foreign packages pulled in via `use'/`import'.  There is no WIT language
;; server, so symbols outside the current buffer are otherwise invisible.  The
;; `wit-deps' CLI resolves declared dependencies into DIR/deps/ on disk; once
;; the sources are there we parse them with the same tree-sitter grammar the
;; mode already loads and fold their definitions into completion.

(defun wit-ts-mode--wit-root ()
  "Locate the `wit-deps'-managed directory for the current buffer.
Return a cons (WIT-ROOT . PROJECT-ROOT), where WIT-ROOT is the
directory holding deps.toml and PROJECT-ROOT is the directory in
which `wit-deps' should run (WIT-ROOT's parent).  Return nil when
the buffer is not visiting a file or no manifest is found.

Two layouts are recognised, walking up from the buffer's file:
an ancestor DIR containing `wit-ts-deps-directory'/deps.toml (root
is that subdirectory), or an ancestor that is itself the managed
directory and contains deps.toml directly."
  (when-let* ((file buffer-file-name)
              (start (file-name-directory file)))
    (let (result)
      (locate-dominating-file
       start
       (lambda (dir)
         (let ((nested (expand-file-name
                        (concat (file-name-as-directory wit-ts-deps-directory)
                                "deps.toml")
                        dir)))
           (cond
            ((file-exists-p nested)
             (setq result
                   (cons (file-name-directory nested)
                         (file-name-as-directory (expand-file-name dir))))
             t)
            ((and (file-exists-p (expand-file-name "deps.toml" dir))
                  (equal (file-name-nondirectory
                          (directory-file-name dir))
                         wit-ts-deps-directory))
             (setq result
                   (cons (file-name-as-directory (expand-file-name dir))
                         (file-name-directory
                          (directory-file-name dir))))
             t)
            (t nil)))))
      result)))

(defvar wit-ts-mode--definitions-cache (make-hash-table :test 'equal)
  "Cache of symbols parsed from off-buffer `.wit' files.
Keyed by absolute file name; each value is a cons (MTIME . INFO)
where INFO is the plist returned by `wit-ts-mode--parse-file' (see
there for its keys).  A file is re-parsed only when its
modification time changes.  Cleared by `wit-ts-deps-sync' so
freshly fetched dependencies are picked up.")

(defun wit-ts-mode--parse-file (file)
  "Parse FILE with the `wit' grammar and return a plist of its symbols.
The plist has keys `:package' (the declared package id, or nil),
`:version' (the package @version, or nil), `:interfaces' (a list
of interface and world names) and `:members' (an alist mapping
each interface name to its `use'-able type/resource members).
Result is memoised in `wit-ts-mode--definitions-cache' keyed by
FILE and its mtime.  Return nil if the grammar is unavailable or
FILE cannot be read.

A single WIT package may span several files and only some of them
carry the `package' header (per the WIT spec), so `:package' can
legitimately be nil for a file that still belongs to a package."
  (when (treesit-ready-p 'wit t)
    (let* ((attrs (file-attributes file))
           (mtime (and attrs (file-attribute-modification-time attrs)))
           (cached (gethash file wit-ts-mode--definitions-cache)))
      (if (and cached mtime (equal (car cached) mtime))
          (cdr cached)
        (let ((info
               (ignore-errors
                 (with-temp-buffer
                   (insert-file-contents file)
                   (let* ((parser (treesit-parser-create 'wit))
                          (root (treesit-parser-root-node parser))
                          (head (car (treesit-query-capture
                                      root
                                      wit-ts-mode--completion-packages-query
                                      nil nil t))))
                     (list :package
                           (and head (wit-ts-mode--package-id-from-decl-head
                                      head))
                           :version
                           (and head (wit-ts-mode--package-version-from-decl-head
                                      head))
                           :interfaces
                           (wit-ts-mode--kinded-captures
                            root wit-ts-mode--completion-interfaces-query)
                           :members
                           (wit-ts-mode--interface-members-alist root)))))))
          (when mtime
            (puthash file (cons mtime info) wit-ts-mode--definitions-cache))
          info)))))

(defun wit-ts-mode--buffer-package-id ()
  "Return the package id declared in the current buffer, or nil."
  (when-let* ((parser (wit-ts-mode--parser))
              (head (car (treesit-query-capture
                          (treesit-parser-root-node parser)
                          wit-ts-mode--completion-packages-query nil nil t))))
    (wit-ts-mode--package-id-from-decl-head head)))

(defun wit-ts-mode--buffer-interfaces ()
  "Return the current buffer's interface and world names, kind-tagged."
  (when-let* ((parser (wit-ts-mode--parser)))
    (wit-ts-mode--kinded-captures
     (treesit-parser-root-node parser)
     wit-ts-mode--completion-interfaces-query)))

(defun wit-ts-mode--path-candidates ()
  "Return candidates valid after `import'/`export'/`use' (a use_path).
Per the WIT grammar a use_path is either a bare interface name in
the current package, or a foreign ns:pkg/interface@version path.
Accordingly this returns:

- bare interface names from files sharing the current buffer's
  declared package id (its own interfaces plus sibling files), and
- ns:pkg/interface@version paths for interfaces in every other
  \(foreign) package under the `wit-deps' root.

Return nil when the buffer is not part of a `wit-deps' project."
  (when-let* ((roots (wit-ts-mode--wit-root))
              (wit-root (car roots)))
    (let ((own-pkg (wit-ts-mode--buffer-package-id))
          (self (and buffer-file-name (expand-file-name buffer-file-name)))
          ;; The buffer's own interfaces are always local, and reflect
          ;; unsaved edits the on-disk scan would miss.
          (locals (copy-sequence (wit-ts-mode--buffer-interfaces)))
          foreign)
      (dolist (file (directory-files-recursively wit-root "\\.wit\\'"))
        (unless (equal (expand-file-name file) self)
          (let* ((info (wit-ts-mode--parse-file file))
                 (pkg (plist-get info :package))
                 (version (plist-get info :version))
                 (interfaces (plist-get info :interfaces)))
            (if (and own-pkg pkg (equal pkg own-pkg))
                ;; Same package (spec allows splitting across files): the
                ;; interfaces are referable by bare name.
                (dolist (name interfaces)
                  (push name locals))
              ;; Foreign package: only reachable as ns:pkg/interface@version.
              ;; Preserve each interface's kind on the constructed path.
              (when pkg
                (dolist (name interfaces)
                  (push (wit-ts-mode--kinded
                         (concat pkg "/" name
                                 (and version (concat "@" version)))
                         (wit-ts-mode--candidate-kind name))
                        foreign)))))))
      (delete-dups (nconc (nreverse locals) (nreverse foreign))))))

(defun wit-ts-mode--split-use-path (path)
  "Split a use_path PATH into a cons (PACKAGE-ID . INTERFACE).
For a foreign path like \"wasi:clocks/wall-clock@0.2.10\" this is
\(\"wasi:clocks\" . \"wall-clock\"); for a bare local interface name
like \"types\" it is (nil . \"types\").  Any @version is dropped."
  (let* ((path (car (split-string path "@")))
         (slash (string-search "/" path)))
    (if slash
        (cons (substring path 0 slash) (substring path (1+ slash)))
      (cons nil path))))

(defun wit-ts-mode--interface-members (package interface)
  "Return the `use'-able members of INTERFACE, or nil.
When PACKAGE is nil, INTERFACE is resolved within the current
package: the current buffer first (honouring unsaved edits), then
sibling files sharing the buffer's package id.  When PACKAGE is
non-nil, INTERFACE is resolved in the foreign package with that
id.  Members are the interface's type and resource names."
  (or
   ;; Current buffer (only meaningful for a local, unqualified reference).
   (and (null package)
        (when-let* ((parser (wit-ts-mode--parser)))
          (cdr (assoc interface
                      (wit-ts-mode--interface-members-alist
                       (treesit-parser-root-node parser))))))
   ;; Otherwise scan the project's files for the owning package/interface.
   (when-let* ((roots (wit-ts-mode--wit-root))
               (wit-root (car roots)))
     (let ((own-pkg (wit-ts-mode--buffer-package-id))
           (self (and buffer-file-name (expand-file-name buffer-file-name)))
           result)
       (catch 'found
         (dolist (file (directory-files-recursively wit-root "\\.wit\\'"))
           (unless (equal (expand-file-name file) self)
             (let* ((info (wit-ts-mode--parse-file file))
                    (pkg (plist-get info :package))
                    ;; A file matches when its package equals the requested
                    ;; one, or -- for an unqualified reference -- when it
                    ;; shares the current buffer's package (a sibling file).
                    (match (if package
                               (equal pkg package)
                             (and own-pkg (equal pkg own-pkg))))
                    (members (and match
                                  (cdr (assoc interface
                                              (plist-get info :members))))))
               (when members
                 (setq result members)
                 (throw 'found result))))))
       result))))

(defun wit-ts-mode--member-candidates ()
  "Return member candidates for a `use PATH.{ ... }' names list.
Resolves the interface named by the `use' path preceding point
\(see `wit-ts-mode--current-use-path') and returns its type and
resource members, excluding those already present in the brace
list.  Return nil when the path or interface cannot be resolved."
  (when-let* ((path (wit-ts-mode--current-use-path))
              (split (wit-ts-mode--split-use-path path))
              (members (wit-ts-mode--interface-members (car split)
                                                       (cdr split))))
    (let ((already (wit-ts-mode--use-names-already-listed)))
      (seq-remove (lambda (m) (member m already)) members))))

;;; Dependency synchronisation

(defun wit-ts-mode--deps-run (args label)
  "Run `wit-ts-deps-executable' with ARGS asynchronously for this project.
ARGS is a list of extra command-line arguments (nil for the bare
`lock' behaviour).  LABEL names the operation in progress messages.
The process runs in the project root (the parent of the
`wit-deps'-managed directory), streaming output to the `*wit-deps*'
buffer.  On success the off-buffer definitions cache is cleared so
the next completion re-scans the resolved sources.

Signals a `user-error' if the executable is not found or the
current buffer is not part of a `wit-deps' project (no
DIR/deps.toml)."
  (unless (executable-find wit-ts-deps-executable)
    (user-error "Cannot find `%s' on `exec-path'; set `wit-ts-deps-executable'"
                wit-ts-deps-executable))
  (let ((roots (wit-ts-mode--wit-root)))
    (unless roots
      (user-error "No `%s/deps.toml' found for this buffer"
                  wit-ts-deps-directory))
    (let* ((default-directory (cdr roots))
           (command (cons wit-ts-deps-executable args))
           (buffer (get-buffer-create "*wit-deps*")))
      (with-current-buffer buffer
        (setq buffer-read-only nil)
        (erase-buffer)
        (insert (format "Running %s in %s\n\n"
                        (mapconcat #'identity command " ")
                        default-directory)))
      (make-process
       :name "wit-deps"
       :buffer buffer
       :command command
       :noquery t
       :sentinel
       (lambda (proc _event)
         (when (memq (process-status proc) '(exit signal))
           (if (and (eq (process-status proc) 'exit)
                    (zerop (process-exit-status proc)))
               (progn
                 (clrhash wit-ts-mode--definitions-cache)
                 (message "wit-deps: %s complete" label))
             (message "wit-deps %s failed (exit %s); see *wit-deps*"
                      label (process-exit-status proc)))))))))

;;;###autoload
(defun wit-ts-deps-sync ()
  "Resolve WIT dependencies for the current project with `wit-deps'.
Runs `wit-deps' (equivalent to `wit-deps lock'): it populates the
dependency directory from the manifest, honouring the existing
lock file without changing pinned versions.  To pull newer sources
for dynamic references, use `wit-ts-deps-update' instead.

See `wit-ts-mode--deps-run' for the execution model and the errors
this may signal."
  (interactive)
  (wit-ts-mode--deps-run nil "sync"))

;;;###autoload
(defun wit-ts-deps-update ()
  "Update WIT dependencies for the current project with `wit-deps update'.
Unlike `wit-ts-deps-sync', this pulls the latest sources for
dynamic references (such as a tracked branch) and rewrites the
lock file.

See `wit-ts-mode--deps-run' for the execution model and the errors
this may signal."
  (interactive)
  (wit-ts-mode--deps-run '("update") "update"))

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

(defconst wit-ts-mode--use-path-context-regexp
  (rx (or bos (any ?\; ?{ ?} ?\n))
      (* space)
      (or "import" "export" "use" "include")
      (+ space)
      ;; The use_path itself: a single unbroken run of the characters a
      ;; path may contain -- ids plus the `:'/`/' separators and the `.'s
      ;; of an `@version'.  Whitespace is excluded, so the inline
      ;; `import NAME: extern-type' form (space after `:') breaks the run
      ;; and falls through to default completion, as intended.  A `{' also
      ;; breaks it, ending the path before a `use PATH.{...}' names body.
      (* (any alnum ?_ ?% ?: ?/ ?@ ?- ?.))
      eos)
  "Regexp matching an `import'/`export'/`use'/`include' path up to point.
Matched against the buffer text from the enclosing statement's
start to point; a match means point sits in a use_path position.")

(defun wit-ts-mode--in-use-path-p ()
  "Return non-nil when point is in an `import'/`export'/`use' path.
Detected textually from the text preceding point, which is robust
to the incomplete (ERROR-node) parses produced while typing such a
statement."
  (let ((line-start (line-beginning-position)))
    ;; Scan from the enclosing statement's start.  `import'/`use' bodies do
    ;; not span lines in practice, so bounding the search at the line start
    ;; keeps it cheap; the regexp still anchors on `;'/`{'/`}' within it.
    (string-match-p wit-ts-mode--use-path-context-regexp
                    (buffer-substring-no-properties
                     (max (point-min)
                          (save-excursion
                            (or (re-search-backward "[;{}]" line-start t)
                                (goto-char line-start))
                            (point)))
                     (point)))))

(defun wit-ts-mode--use-names-list-open ()
  "If point is in a `use PATH.{ ... }' names list, return (PATH . OPEN).
PATH is the use_path string preceding the brace and OPEN is the
buffer position just after the opening brace.  Return nil when
point is not within such a list (before its closing brace).

Detected textually, which is robust to the incomplete
\(ERROR-node) parse produced while typing a `use' names list."
  (save-excursion
    ;; The nearest preceding `{'/`}'/`;' must be the opening `{': that
    ;; guarantees no closing brace or statement terminator sits between it
    ;; and point.  A `use' statement stays on one logical line in practice,
    ;; so bound the search at the previous line's start to keep it cheap.
    (let ((bound (max (point-min) (line-beginning-position 0))))
      (when (and (re-search-backward "[{};]" bound t)
                 (eq (char-after) ?\{))
        (let ((open (1+ (point))))
          (skip-chars-backward " \t")
          (when (eq (char-before) ?.)
            (backward-char)
            (let ((path-end (point)))
              (skip-chars-backward "[:alnum:]_%:/@.-")
              (let ((path-start (point)))
                (skip-chars-backward " \t")
                (when (and (< path-start path-end)
                           (looking-back "\\(?:^\\|[^[:alnum:]_%-]\\)use"
                                         (max (point-min) (- (point) 4))))
                  (cons (buffer-substring-no-properties path-start path-end)
                        open))))))))))

(defun wit-ts-mode--current-use-path ()
  "Return the use_path of the `use' names list point is in, or nil."
  (car (wit-ts-mode--use-names-list-open)))

(defun wit-ts-mode--use-names-already-listed ()
  "Return the member names already present in the current `use' names list.
Excludes the item currently being typed at point.  Each `x as y'
alias contributes the imported name x."
  (when-let* ((ctx (wit-ts-mode--use-names-list-open)))
    (let* ((text (buffer-substring-no-properties (cdr ctx) (point)))
           (pieces (split-string text "," t "[ \t\n]+"))
           ;; Unless the list ends at a comma, the final piece is the
           ;; in-progress item -- not yet \"already listed\".
           (complete (if (string-match-p ",[ \t\n]*\\'" text)
                         pieces
                       (butlast pieces))))
      (delq nil
            (mapcar (lambda (piece)
                      (car (split-string (string-trim piece) "[ \t]+")))
                    complete)))))

(defun wit-ts-mode--use-name-bounds ()
  "Return the (START . END) bounds of the member name being typed at point."
  (let (start end)
    (save-excursion (skip-chars-backward "[:alnum:]_-") (setq start (point)))
    (save-excursion (skip-chars-forward "[:alnum:]_-") (setq end (point)))
    (cons start end)))

(defconst wit-ts-mode--gate-name-regexp
  (rx "@" (group (* (any alnum ?_ ?-))) eos)
  "Regexp matching a feature-gate attribute name typed after `@'.
Group 1 is the (possibly empty) gate name up to point, e.g. the
`sin' of `@sin'.")

(defconst wit-ts-mode--gate-field-regexp
  (rx "@" (group (+ (any alnum ?_ ?-)))       ; the gate name
      "(" (* (not (any ?\) ?\n)))             ; inside the parens, up to point
      eos)
  "Regexp matching an in-progress feature-gate field, e.g. `@since(ver'.
Group 1 is the gate name; a match means point is inside the gate's
parentheses (before the closing `)').")

(defun wit-ts-mode--gate-context ()
  "Return the feature-gate completion context at point, or nil.
The result is (KIND . GATE): KIND is `gate' when point is on the
attribute name just after `@' (GATE is then nil), or `field' when
point is inside a gate's parentheses (GATE is the gate name, e.g.
\"since\").  Detected textually, since a partial gate parses as an
ERROR node."
  (let ((line-head (buffer-substring-no-properties
                    (line-beginning-position) (point))))
    (cond
     ((string-match wit-ts-mode--gate-field-regexp line-head)
      (cons 'field (match-string 1 line-head)))
     ((string-match wit-ts-mode--gate-name-regexp line-head)
      (cons 'gate nil)))))

(defun wit-ts-mode--gate-candidates (context)
  "Return feature-gate candidates for CONTEXT (from `wit-ts-mode--gate-context').
For a `gate' context, the three gate names; for a `field' context,
the field the named gate accepts (`version' or `feature'), or nil
when the gate is unknown."
  (pcase context
    (`(gate . ,_)
     (mapcar (lambda (g) (wit-ts-mode--kinded g 'gate)) wit-ts-mode--gates))
    (`(field . ,gate)
     (when-let* ((field (cdr (assoc gate wit-ts-mode--gate-fields))))
       (list (wit-ts-mode--kinded field 'field))))))

(defun wit-ts-mode-completion-at-point ()
  "Completion-at-point function for `wit-ts-mode'.
Context-sensitive: after `@' it completes feature-gate attributes
\(`since'/`unstable'/`deprecated') and their fields.  In a
`use PATH.{ ... }' names list, completes the target interface's
type and resource members (see `wit-ts-mode--member-candidates').
In an `import'/`export'/`use' path, completes local interface
names and foreign package paths (see `wit-ts-mode--path-candidates').
Otherwise completes WIT keywords, builtin types, and identifiers
defined in the current buffer.  Suitable for
`completion-at-point-functions'."
  (let ((node (treesit-node-at (point))))
    ;; Do not complete inside comments or string literals.
    (unless (wit-ts-mode--in-comment-or-string-p node)
      (let* ((gate-context (wit-ts-mode--gate-context))
             (names-context (and (not gate-context)
                                 (wit-ts-mode--in-use-names-list-p)))
             ;; A names list is inside `{ ... }', so the path regexp (which
             ;; stops at `{') never matches there; check it only otherwise.
             (path-context (and (not gate-context) (not names-context)
                                (wit-ts-mode--in-use-path-p)))
             ;; `:'/`/' are part of a use_path, so widen past the default
             ;; `symbol' bounds there; member and gate names are ordinary ids.
             (bounds (cond (path-context (wit-ts-mode--use-path-bounds))
                           (names-context (wit-ts-mode--use-name-bounds))
                           (t (bounds-of-thing-at-point 'symbol))))
             (start (if bounds (car bounds) (point)))
             (end (if bounds (cdr bounds) (point))))
        (list start end
              (wit-ts-mode--completion-table
               (lambda ()
                 (cond (gate-context (wit-ts-mode--gate-candidates gate-context))
                       (names-context (wit-ts-mode--member-candidates))
                       (path-context (wit-ts-mode--path-candidates))
                       (t (wit-ts-mode--completion-candidates)))))
              :exclusive 'no
              ;; Surface each candidate's WIT kind: as trailing text in the
              ;; `*Completions*' buffer, and as an icon in Corfu/Company.
              :annotation-function #'wit-ts-mode--completion-annotation
              :company-kind #'wit-ts-mode--candidate-company-kind)))))

(defun wit-ts-mode--completion-annotation (candidate)
  "Return the annotation string for completion CANDIDATE, or nil.
Reads the candidate's WIT kind (see `wit-ts-mode--kinded') and
maps it through `wit-ts-mode--kind-annotations'."
  (cdr (assq (wit-ts-mode--candidate-kind candidate)
             wit-ts-mode--kind-annotations)))

(defun wit-ts-mode--candidate-company-kind (candidate)
  "Return the Company/Corfu `kind' symbol for CANDIDATE, or nil.
Reads the candidate's WIT kind (see `wit-ts-mode--kinded') and
maps it through `wit-ts-mode--kind-company-kinds'."
  (cdr (assq (wit-ts-mode--candidate-kind candidate)
             wit-ts-mode--kind-company-kinds)))

(defun wit-ts-mode--in-use-names-list-p ()
  "Return non-nil when point is in a `use PATH.{ ... }' names list."
  (and (wit-ts-mode--use-names-list-open) t))

(defun wit-ts-mode--completion-table (candidate-fn)
  "Return a completion table over the strings produced by CANDIDATE-FN.
Candidates are sorted alphabetically, and the table advertises a
`display-sort-function' of `identity' so that frontends preserve
that order instead of imposing their own."
  (lambda (string predicate action)
    (if (eq action 'metadata)
        '(metadata (display-sort-function . identity)
                   (cycle-sort-function . identity))
      (complete-with-action
       action
       (sort (copy-sequence (funcall candidate-fn)) #'string<)
       string predicate))))

(defun wit-ts-mode--use-path-bounds ()
  "Return the (START . END) bounds of the use_path token around point.
A use_path may contain `:', `/' and `@' in addition to the
characters of an ordinary symbol, so this widens past those."
  (save-excursion
    (let ((end (point))
          (start (point)))
      (skip-chars-backward "[:alnum:]_%:/@.-")
      (setq start (point))
      (goto-char end)
      (skip-chars-forward "[:alnum:]_%:/@.-")
      (cons start (max start (point))))))

;;; Cross-reference (xref)

;; Jump-to-definition reuses the completion resolver's model: a definition is
;; found either in the current buffer or in another `.wit' file under the
;; `wit-deps' root (siblings and resolved dependencies under DIR/deps/).  The
;; completion index stores only names, so xref re-parses to recover positions.

(defconst wit-ts-mode--xref-path-property 'wit-ts-mode--xref-path
  "Text property flagging an xref identifier as a use_path.
When set, `wit-ts-mode--xref-find-definitions' resolves the
identifier as an `import'/`export'/`use' path (an interface)
rather than a bare definition name.")

(defun wit-ts-mode--identifier-at-point ()
  "Return the WIT identifier around point, or nil.
In an `import'/`export'/`use' path (or its names list) the whole
path is returned, tagged with `wit-ts-mode--xref-path-property' so
it is resolved as an interface reference.  Otherwise the symbol at
point is returned."
  (cond
   ;; A `use PATH.{ ... }' names list: a member name under point jumps to
   ;; that member (a bare type/resource name); otherwise the path names the
   ;; interface to jump to.
   ((wit-ts-mode--in-use-names-list-p)
    (or (thing-at-point 'symbol t)
        (when-let* ((path (wit-ts-mode--current-use-path)))
          (propertize path wit-ts-mode--xref-path-property t))))
   ;; An import/export/use path position.
   ((wit-ts-mode--in-use-path-p)
    (let ((bounds (wit-ts-mode--use-path-bounds)))
      (when (< (car bounds) (cdr bounds))
        (propertize (buffer-substring-no-properties (car bounds) (cdr bounds))
                    wit-ts-mode--xref-path-property t))))
   (t
    (thing-at-point 'symbol t))))

(defun wit-ts-mode--definitions-in-node (root query)
  "Return definitions captured by QUERY under ROOT as position records.
Each record is a plist (:name NAME :kind KIND :node NODE); NODE is
the captured name node, from which callers derive a location."
  (mapcar (lambda (cap)
            (list :name (treesit-node-text (cdr cap) t)
                  :kind (car cap)
                  :node (cdr cap)))
          (treesit-query-capture root query nil nil nil)))

(defun wit-ts-mode--xref-make-item (name kind file node)
  "Build an `xref-item' for NAME of KIND at NODE's position in FILE.
FILE nil means the current buffer.  A summary line prefixes the
kind so the *xref* buffer reads, e.g., \"interface handler\"."
  (let* ((start (treesit-node-start node))
         (line (line-number-at-pos start))
         (column (save-excursion (goto-char start) (current-column)))
         (summary (format "%s %s" (or kind "def") name))
         (location (if file
                       (xref-make-file-location file line column)
                     (xref-make-buffer-location (current-buffer) start))))
    (xref-make summary location)))

(defun wit-ts-mode--xref-defs-in-file (file names)
  "Return xref items for definitions named in NAMES found in FILE.
FILE is parsed in a temporary buffer; NAMES is a list of strings.
Positions are resolved against a widened view of that buffer so
`line-number-at-pos' and `current-column' are accurate."
  (when (treesit-ready-p 'wit t)
    (ignore-errors
      (with-temp-buffer
        (insert-file-contents file)
        (let* ((parser (treesit-parser-create 'wit))
               (root (treesit-parser-root-node parser))
               items)
          (dolist (def (wit-ts-mode--definitions-in-node
                        root wit-ts-mode--completion-defs-query))
            (when (member (plist-get def :name) names)
              (push (wit-ts-mode--xref-make-item
                     (plist-get def :name) (plist-get def :kind)
                     file (plist-get def :node))
                    items)))
          (nreverse items))))))

(defun wit-ts-mode--xref-buffer-defs (names)
  "Return xref items for definitions named in NAMES in the current buffer."
  (when-let* ((parser (wit-ts-mode--parser)))
    (let (items)
      (dolist (def (wit-ts-mode--definitions-in-node
                    (treesit-parser-root-node parser)
                    wit-ts-mode--completion-defs-query))
        (when (member (plist-get def :name) names)
          (push (wit-ts-mode--xref-make-item
                 (plist-get def :name) (plist-get def :kind)
                 nil (plist-get def :node))
                items)))
      (nreverse items))))

(defun wit-ts-mode--xref-path-target (path)
  "Return the interface NAME a use_path PATH refers to, ignoring package.
The definition of `wasi:clocks/wall-clock@0.2.10' is the interface
`wall-clock'; a bare `types' resolves to the interface `types'.
A trailing `.' (the separator before a `.{ ... }' names body) is
stripped first, so `types.' resolves to `types' too."
  (cdr (wit-ts-mode--split-use-path
        (string-remove-suffix "." path))))

(defun wit-ts-mode--xref-find-definitions (identifier)
  "Return a list of xref items defining IDENTIFIER.
IDENTIFIER is what `wit-ts-mode--identifier-at-point' returned: a
use_path (tagged with `wit-ts-mode--xref-path-property', resolved
to its interface name) or a bare definition name.  Searches the
current buffer first, then the other `.wit' files under the
`wit-deps' root."
  (when (and identifier (> (length identifier) 0))
    (let* ((path-p (get-text-property 0 wit-ts-mode--xref-path-property
                                      identifier))
           (name (if path-p
                     (wit-ts-mode--xref-path-target identifier)
                   (substring-no-properties identifier)))
           (names (list name))
           (self (and buffer-file-name (expand-file-name buffer-file-name)))
           (items (wit-ts-mode--xref-buffer-defs names)))
      (when-let* ((roots (wit-ts-mode--wit-root))
                  (wit-root (car roots)))
        (dolist (file (directory-files-recursively wit-root "\\.wit\\'"))
          (unless (equal (expand-file-name file) self)
            (setq items
                  (nconc items (wit-ts-mode--xref-defs-in-file file names))))))
      items)))

;; The backend is a function returning a symbol; its methods dispatch on it.
(defun wit-ts-mode--xref-backend ()
  "Return the xref backend symbol for `wit-ts-mode'."
  'wit-ts-mode)

(cl-defmethod xref-backend-identifier-at-point ((_backend (eql wit-ts-mode)))
  "Return the WIT identifier at point for the `wit-ts-mode' xref backend."
  (wit-ts-mode--identifier-at-point))

(cl-defmethod xref-backend-definitions ((_backend (eql wit-ts-mode)) identifier)
  "Return xref items defining IDENTIFIER for the `wit-ts-mode' backend."
  (wit-ts-mode--xref-find-definitions identifier))

(cl-defmethod xref-backend-identifier-completion-table
  ((_backend (eql wit-ts-mode)))
  "Return the buffer's definition names for `wit-ts-mode' xref completion."
  (mapcar (lambda (def) (plist-get def :name))
          (when-let* ((parser (wit-ts-mode--parser)))
            (wit-ts-mode--definitions-in-node
             (treesit-parser-root-node parser)
             wit-ts-mode--completion-defs-query))))

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
              "func_item" "type_item" "record_item"
              "variant_items" "enum_items" "flags_items" "resource_item"
              "import_item" "export_item" "toplevel_use_item")
      eos)
  "Regexp of node types treated as outline headings in `wit-ts-mode'.
All top-level and member declarations are headings, including
single-line ones such as `type t = u32;'.  A single-line item is
a childless (leaf) heading; this is required so that outline can
bound the *preceding* multi-line block correctly.  Marking only
multi-line nodes would make a fold like `flags { ... }' swallow
every declaration after it, up to the next multi-line heading.")

;; `wit-ts-mode' uses a custom `outline-search-function' rather than the
;; built-in `treesit-outline-predicate'.  The built-in anchors headings by
;; testing whether a heading node covers the beginning or end of the line,
;; but WIT declarations are indented and single-line items end exactly at
;; end-of-line, so neither position falls inside the node's half-open span.
;; The result is that single-line items (`type t = u32;') are reported as
;; headings for display yet fail `outline-on-heading-p', so folding operates
;; on the wrong subtree (collapsing them hides the line above, and
;; collapsing a block swallows the items after it).  Anchoring on the node's
;; own start line instead fixes both.

(defun wit-ts-mode--outline-heading-on-line-p ()
  "Return non-nil if an outline heading node begins on the current line."
  (save-excursion
    (let* ((bol (line-beginning-position))
           (eol (line-end-position))
           (node (treesit-node-at
                  (save-excursion (back-to-indentation) (point)))))
      (while (and node
                  (>= (treesit-node-start node) bol)
                  (not (string-match-p wit-ts-mode--outline-node-regexp
                                       (treesit-node-type node))))
        (setq node (treesit-node-parent node)))
      (and node
           (string-match-p wit-ts-mode--outline-node-regexp
                           (treesit-node-type node))
           (<= bol (treesit-node-start node))
           (< (treesit-node-start node) eol)))))

(defun wit-ts-mode--outline-level ()
  "Return the outline nesting level of the heading on the current line.
Derived from the depth of the heading node in the syntax tree so
that members nest one level below their enclosing world or
interface."
  (let ((node (treesit-node-at
               (save-excursion (back-to-indentation) (point))))
        (level 1))
    ;; Ascend to the heading node itself.
    (while (and node
                (not (string-match-p wit-ts-mode--outline-node-regexp
                                     (treesit-node-type node))))
      (setq node (treesit-node-parent node)))
    ;; Count enclosing heading nodes above it.
    (when node
      (let ((parent (treesit-node-parent node)))
        (while parent
          (when (string-match-p wit-ts-mode--outline-node-regexp
                                (treesit-node-type parent))
            (setq level (1+ level)))
          (setq parent (treesit-node-parent parent)))))
    level))

(defun wit-ts-mode--outline-search (&optional bound move backward looking-at)
  "Search for the next WIT outline heading via the syntax tree.
For BOUND, MOVE, BACKWARD, and LOOKING-AT see `outline-search-function'."
  (if looking-at
      (wit-ts-mode--outline-heading-on-line-p)
    (let ((step (if backward -1 1))
          (found nil))
      (save-excursion
        (catch 'done
          (while (if backward (not (bobp)) (not (eobp)))
            (forward-line step)
            (when (and bound (if backward (< (point) bound) (> (point) bound)))
              (throw 'done nil))
            (when (wit-ts-mode--outline-heading-on-line-p)
              (setq found (line-beginning-position))
              (throw 'done t)))))
      (if found
          (progn (goto-char found)
                 (set-match-data (list (point) (line-end-position)))
                 t)
        (when move
          (goto-char (or bound (if backward (point-min) (point-max)))))
        nil))))

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

(defun wit-ts-mode--bare-use-in-body-p (node)
  "Return non-nil if ERROR NODE is a bare `use PATH;' in an interface/world.
That is the shape produced when a `use' inside an interface or
world body omits the mandatory `.{ ... }' names list: the grammar
accepts a bare `use PATH;' only at file top level, so within a
body it becomes an ERROR wrapping a lone `use_path'."
  (let ((children (treesit-node-children node t)))
    (and (equal (treesit-node-type (treesit-node-parent node)) "body")
         (= (length children) 1)
         (equal (treesit-node-type (car children)) "use_path"))))

(defun wit-ts-mode--error-leading-keyword (node)
  "Return the leading `import'/`export'/`include'/`use' keyword of NODE's text.
Return nil when NODE's text does not begin with one of them.  Used
to recognise malformed world items, whose keyword survives in the
ERROR node's text even when the rest fails to parse."
  (let ((text (treesit-node-text node t)))
    (when (string-match "\\`\\(import\\|export\\|include\\|use\\)\\_>" text)
      (match-string 1 text))))

(defun wit-ts-mode--error-message (node)
  "Return a Flymake message describing ERROR NODE.
Recognises the common malformed `use'/`import'/`export' shapes and
explains them; otherwise quotes the offending text (or falls back
to a generic message when it is empty)."
  (let* ((parent-type (treesit-node-type (treesit-node-parent node)))
         (keyword (wit-ts-mode--error-leading-keyword node))
         (text (treesit-node-text node t)))
    (cond
     ((wit-ts-mode--bare-use-in-body-p node)
      (let ((path (treesit-node-text (car (treesit-node-children node t)) t)))
        (format "`use' inside an interface or world needs a `.{...}' names \
list, e.g. `%s.{name}'; a bare `use %s;' is only valid at file top level"
                path path)))
     ;; `import'/`export'/`include' at file top level: they are world items.
     ((and (equal parent-type "source_file")
           (member keyword '("import" "export" "include")))
      (format "`%s' is only valid inside a `world' block" keyword))
     ;; Inline `import NAME:' / `export NAME:' with no type after the colon.
     ((and (equal parent-type "body")
           (member keyword '("import" "export"))
           (string-match-p ":[ \t\n]*\\'" text))
      (format "`%s' name must be followed by a type: a `func(...)', an \
`interface {...}', or an interface path" keyword))
     ;; `import: ...' / `export: ...' with the name missing before the colon.
     ((member parent-type '("import_item" "export_item"))
      (let ((kw (if (equal parent-type "export_item") "export" "import")))
        (format "`%s' needs a name before `:', e.g. `%s my-name: func()'"
                kw kw)))
     ((string-empty-p (wit-ts-mode--snippet node))
      "Syntax error: unexpected input")
     (t
      (format "Syntax error: unexpected `%s'" (wit-ts-mode--snippet node))))))

(defun wit-ts-mode--flymake-diag (source node message)
  "Make a Flymake error diagnostic for NODE in SOURCE with MESSAGE.
Zero-width nodes are widened by one character so there is
something to underline."
  (let* ((beg (treesit-node-start node))
         (end (max (treesit-node-end node) (1+ beg))))
    (flymake-make-diagnostic source beg end :error message)))

(defun wit-ts-mode--empty-use-names-positions (root)
  "Return the set of buffer positions of empty `use' names lists under ROOT.
An empty `.{ }' list parses as a `use_names_item' holding only a
missing `id'.  The synthetic missing node has no reachable parent,
so this walks top-down (where navigation works) and records each
empty item's start position for the diagnostics pass to recognise.
The result is a hash table used as a set."
  (let ((positions (make-hash-table :test 'eql)))
    (dolist (item (treesit-query-capture root '((use_names_item) @i) nil nil t))
      (when (string-empty-p (string-trim (treesit-node-text item t)))
        (puthash (treesit-node-start item) t positions)))
    positions))

(defun wit-ts-mode--flymake-diagnostics (parser source)
  "Return Flymake diagnostics for parse errors in PARSER.
Anchor them in the SOURCE buffer.  Missing nodes report the token
the grammar expected (a missing node's type is that token, e.g.
`}' or `;'); `ERROR' nodes quote the offending input.  The
traversal visits anonymous nodes too, since a missing token is
often an anonymous node.  A missing `id' at the position of an
empty `use' names list gets a tailored message instead."
  (let* ((root (treesit-parser-root-node parser))
         (empty-uses (wit-ts-mode--empty-use-names-positions root))
         diags)
    (treesit-search-subtree
     root
     (lambda (node)
       (cond
        ((treesit-node-check node 'missing)
         (push (wit-ts-mode--flymake-diag
                source node
                (if (and (equal (treesit-node-type node) "id")
                         (gethash (treesit-node-start node) empty-uses))
                    "Empty `use' names list: list at least one type, \
e.g. `use path.{errno}'"
                  (wit-ts-mode--missing-message node)))
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
  "Major mode for editing WIT (WebAssembly Interface Type) files.

WIT describes the interfaces of WebAssembly components.  This mode
is powered by the tree-sitter `wit' grammar, which is installed on
first use (see `wit-ts-mode-grammar-url').

Features:

- Syntax highlighting, indentation, and `electric-indent-mode'.
- Structural navigation: `forward-sexp', `beginning-of-defun', and
  `which-function-mode' operate on WIT declarations, and Imenu
  \(\\[imenu]) indexes worlds, interfaces, types, and functions.
- Folding: brace blocks fold with `hs-minor-mode', and the
  declaration hierarchy folds with `outline-minor-mode'.
- Diagnostics: turn on `flymake-mode' to see parse errors, with
  tailored messages for common `use'/`import'/`export' mistakes.
- Completion at point (\\[completion-at-point]) is context-aware:
  in an `import'/`export'/`use' path it offers local interfaces
  and foreign package paths; in a `use PATH.{...}' names list it
  offers the target interface's types and resources; elsewhere it
  offers keywords, builtin types, and buffer definitions.

Dependencies:

Cross-file and cross-package completion resolves symbols from the
sources that `wit-deps' fetches under the project's dependency
directory (see `wit-ts-deps-directory').  Manage them with:

\\[wit-ts-deps-sync]
    Resolve dependencies from the manifest, honouring the lock
    file (like `wit-deps lock').
\\[wit-ts-deps-update]
    Pull newer sources for dynamic references and rewrite the lock
    file (like `wit-deps update').

Both run the `wit-ts-deps-executable' program asynchronously.

\\{wit-ts-mode-map}"
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
  ;; tree-sitter-driven outline covers the declaration hierarchy, via a
  ;; custom search function (see `wit-ts-mode--outline-search').
  (setq-local outline-search-function #'wit-ts-mode--outline-search)
  (setq-local outline-level #'wit-ts-mode--outline-level)

  ;; Syntax checking: report tree-sitter parse errors through Flymake.
  ;; Enable `flymake-mode' to see them.
  (add-hook 'flymake-diagnostic-functions #'wit-ts-mode-flymake nil t)

  ;; Completion: keywords, builtin types, and buffer-local definitions.
  (add-hook 'completion-at-point-functions
            #'wit-ts-mode-completion-at-point nil t)

  ;; Cross-reference: jump to definitions with `xref-find-definitions'
  ;; (\\[xref-find-definitions]), across the buffer and project files.
  (add-hook 'xref-backend-functions #'wit-ts-mode--xref-backend nil t)

  (treesit-major-mode-setup))

;;;###autoload
(when (fboundp 'treesit-ready-p)
  (add-to-list 'auto-mode-alist '("\\.wit\\'" . wit-ts-mode)))

(provide 'wit-ts-mode)

;;; wit-ts-mode.el ends here
