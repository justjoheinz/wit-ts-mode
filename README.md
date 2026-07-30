# wit-ts-mode

A tree-sitter–based Emacs major mode for [WIT][wit] (WebAssembly Interface
Types) files, the interface-definition language used by the WebAssembly
Component Model.

It is built on Emacs's built-in tree-sitter support (`treesit`, Emacs 29.1+)
and the [`tree-sitter-wit`][grammar] grammar. Highlighting is a faithful
translation of that project's `queries/highlights.scm`; folding mirrors
`queries/folds.scm`.

## Features

- **Syntax highlighting** — every capture from the grammar's `highlights.scm`,
  mapped onto standard Emacs faces (keywords, types, built-in types,
  functions, record/variant/enum members, feature-gate attributes, doc
  comments, and so on).
- **Indentation** — tree-sitter–driven, configurable via
  `wit-ts-mode-indent-offset` (default 4). Uses spaces, per WIT convention.
- **Imenu** — worlds, interfaces, types (records, variants, enums, flags,
  resources, and type aliases), and functions.
- **Navigation** — `treesit`-based defun movement (`C-M-a` / `C-M-e`,
  `C-M-h`, etc.).
- **Folding** — `hideshow` support for the brace blocks (interfaces, worlds,
  records, resources, variants, …) and block comments.
- **Outline** — a tree-sitter–driven `outline-minor-mode` heading hierarchy
  (package → world/interface → members) for structural navigation.

## Requirements

- Emacs 29.1 or newer, built with tree-sitter support
  (`(treesit-available-p)` returns `t`).
- The `wit` tree-sitter grammar installed and loadable
  (`(treesit-ready-p 'wit)` returns `t`).

## Installing the grammar

Loading the mode registers the grammar's source, so the first time you open a
`.wit` file `wit-ts-mode` offers to install the grammar for you. This compiles
the grammar from source, so **a C compiler must be on your `PATH`**.

To install it ahead of time instead:

```
M-x treesit-install-language-grammar RET wit RET
```

If your grammar library lives outside the default search path (for example,
Doom Emacs places it under `~/.config/emacs/.local/cache/tree-sitter/`, which
`treesit` already searches), point Emacs at it explicitly:

```elisp
(add-to-list 'treesit-extra-load-path "/path/to/your/tree-sitter/")
```

## Installing the mode

### With `use-package` and `:vc` (Emacs 30+)

```elisp
(use-package wit-ts-mode
  :vc (:url "https://github.com/justjoheinz/wit-ts-mode")
  :mode "\\.wit\\'")
```

### With `straight.el` / `elpaca`

```elisp
(use-package wit-ts-mode
  :straight (:host github :repo "justjoheinz/wit-ts-mode")
  :mode "\\.wit\\'")
```

### Doom Emacs

In `~/.config/doom/packages.el`:

```elisp
(package! wit-ts-mode
  :recipe (:host github :repo "justjoheinz/wit-ts-mode"))
```

In `~/.config/doom/config.el`:

```elisp
(use-package! wit-ts-mode
  :mode "\\.wit\\'")
```

Run `doom sync` afterwards.

### Manually

Put `wit-ts-mode.el` on your `load-path` and `(require 'wit-ts-mode)`.

Loading the mode registers the grammar source and associates `.wit` files
with `wit-ts-mode`. The first time you open a WIT file, the mode offers to
install the tree-sitter grammar if it is missing (a C compiler is required).

## Configuration

| Variable                    | Default | Meaning                              |
| --------------------------- | ------- | ------------------------------------ |
| `wit-ts-mode-indent-offset` | `4`     | Spaces per indentation step.         |

Turn folding and/or outline on automatically:

```elisp
(add-hook 'wit-ts-mode-hook #'hs-minor-mode)
(add-hook 'wit-ts-mode-hook #'outline-minor-mode)
```

### Folding keys (`hs-minor-mode`)

| Key             | Action                 |
| --------------- | ---------------------- |
| `C-c @ C-c`     | Toggle block at point  |
| `C-c @ C-h`     | Hide block             |
| `C-c @ C-s`     | Show block             |
| `C-c @ C-M-h`   | Hide all blocks        |
| `C-c @ C-M-s`   | Show all blocks        |

### Outline (`outline-minor-mode`)

`TAB` / `S-TAB` cycle a heading's visibility; `C-c @ C-q` shows only
top-level headings. Headings are the package declaration and each
world/interface plus their members — derived from the parse tree, not
regexps.

## Highlighting notes

The mode translates `highlights.scm` capture-for-capture. A few captures
reference grammar nodes that don't appear in the bundled examples
(`unstable_gate`, `external_id`, `map`, `future`, `stream`, `async`); their
rules are present and will activate on files that use those features.

The grammar's `injections.scm` only marks comments for a nested "comment"
sub-parser, which has no Emacs equivalent, so there is nothing to translate
there.

## Testing

The `examples/` directory holds the sample `.wit` files from the grammar
repository. Open any of them to exercise highlighting, indentation, imenu,
folding, and outline. All five parse with zero errors and round-trip through
`indent-region` unchanged (at their native indent width).

## License

Apache License 2.0. See the [`LICENSE`](LICENSE) file for the full text.

[wit]: https://component-model.bytecodealliance.org/design/wit.html
[grammar]: https://github.com/bytecodealliance/tree-sitter-wit
