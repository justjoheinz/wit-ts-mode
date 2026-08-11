# wit-ts-mode

[![CI](https://github.com/justjoheinz/wit-ts-mode/actions/workflows/ci.yml/badge.svg)](https://github.com/justjoheinz/wit-ts-mode/actions/workflows/ci.yml)

A tree-sitter–based Emacs major mode for [WIT][wit] (WebAssembly Interface
Types) files, the interface-definition language used by the WebAssembly
Component Model.

It is built on Emacs's built-in tree-sitter support (`treesit`, Emacs 30.1+)
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
- **Navigation** — tree-sitter structural motion: defun movement (`C-M-a` /
  `C-M-e` / `C-M-h`), `forward-sexp` over identifiers and whole constructs,
  `forward-sentence` across members, and `up-list` / `down-list` on bracketed
  groups.
- **Which-function** — `which-function-mode` shows the enclosing declaration
  (e.g. `foo.errno`, `random.get-random-bytes`) in the mode line.
- **Eldoc** — the signature of the definition (or reference) at point shows in
  the echo area: a function's parameters and result, a type alias's target, a
  record/variant/enum/flags/resource/interface summary. Resolves symbols in
  the current buffer and — for `wit-deps`-managed projects — in sibling files
  and resolved dependencies.
- **Folding** — `hideshow` support for the brace blocks (interfaces, worlds,
  records, resources, variants, …) and block comments.
- **Outline** — a tree-sitter–driven `outline-minor-mode` heading hierarchy
  (package → world/interface → members) for structural navigation.
- **Syntax checking** — a Flymake backend that surfaces tree-sitter parse
  errors (unexpected input and missing tokens such as an unclosed brace).
- **Completion** — a `completion-at-point` function offering WIT keywords,
  builtin types, and identifiers defined in the current buffer, plus — for
  `wit-deps`-managed projects — identifiers from sibling files and resolved
  dependencies (`M-x wit-ts-deps-sync` refreshes them).

## Requirements

- Emacs 30.1 or newer, built with tree-sitter support
  (`(treesit-available-p)` returns `t`). Emacs 30.1 is required for the
  outline and structural-navigation features (`treesit-thing-settings` and
  `treesit-outline-predicate` are new in 30.1).
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
  :mode "\\.wit\\'"
  :config
  ;; Optional: enable folding and outline automatically.
  (add-hook! wit-ts-mode #'hs-minor-mode #'outline-minor-mode))
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

### Navigation

Motion commands operate on the parse tree, so they respect WIT structure:

| Key       | Command               | Moves by                                  |
| --------- | --------------------- | ----------------------------------------- |
| `C-M-a`   | `beginning-of-defun`  | to the start of the enclosing declaration |
| `C-M-e`   | `end-of-defun`        | to the end of the enclosing declaration   |
| `C-M-f`   | `forward-sexp`        | over an identifier or a whole construct   |
| `C-M-u`   | `backward-up-list`    | out of a `{ … }` / `< … >` / `( … )` group |
| `C-M-d`   | `down-list`           | into the next bracketed group             |
| `M-e`     | `forward-sentence`    | to the next member (field, case, item)    |

`which-function-mode` shows the enclosing declaration in the mode line,
including nesting — e.g. `foo.errno` for the `errno` enum inside interface
`foo`, or `random.get-random-bytes` for a function inside interface `random`.
Turn it on with `M-x which-function-mode`, or from `wit-ts-mode-hook`.

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

### Syntax checking (`flymake-mode`)

The mode registers a Flymake backend, so `M-x flymake-mode` highlights parse
errors as you type. Two kinds are reported, each with a descriptive message:

- **unexpected input** — offending text the grammar can't place, quoted in
  the message (e.g. `Syntax error: unexpected `type = u32;'`);
- **expected token** — something required is absent; the message names it
  (e.g. `Syntax error: expected semicolon `;'` or `expected closing brace
  `}'` for an unterminated block).

Beyond parse errors, the backend also flags **unresolved references** as
warnings (toggle with `wit-ts-mode-check-references`):

- **unknown types** — any type reference that is neither a builtin, a type
  defined in the buffer, nor a `use`-imported name, wherever it appears: a
  `type` alias target, a record field, a variant payload, a function
  parameter or return type, an element of `list`/`option`/`result`/`tuple`,
  a `borrow`/`own` handle, and so on (e.g. `Unknown type `widget'`). This is
  a whole-buffer check, so it works even outside a project.
- **unresolved interface paths and members** — in a
  [`wit-deps`][wit-deps]-managed project, an `import`/`export`/`use` path to a
  missing package or interface, and members of a `use PATH.{ … }` list not
  defined in that interface (see below).

Jump between them with `M-x flymake-goto-next-error` /
`flymake-goto-prev-error`, or list them with `M-x
flymake-show-buffer-diagnostics`.

To turn it on for every WIT buffer:

```elisp
(add-hook 'wit-ts-mode-hook #'flymake-mode)
```

`wit-ts-mode` derives from `prog-mode`, so anything hooked onto
`prog-mode-hook` applies — but note that Doom only puts `flymake-mode` there
when the `:checkers syntax` module carries the `+flymake` flag. Its default
checker is Flycheck, which does not display Flymake backends, so under a
default Doom configuration these diagnostics stay hidden until you enable
`flymake-mode` yourself (the two can coexist per buffer).

For a one-off look at *where* a file diverges from the grammar without any
extra setup, `M-x treesit-explore-mode` shows the live parse tree with
`ERROR` / `MISSING` nodes marked.

### Completion

The mode adds a `completion-at-point` function, so `M-x completion-at-point`
(often bound to `C-M-i` / `TAB`) completes:

- **keywords** — `interface`, `world`, `record`, `func`, `resource`, …;
- **builtin types** — `u8`…`u64`, `string`, `list`, `option`, `result`, …;
- **buffer definitions** — the names of interfaces, worlds, records,
  variants, enums, flags, resources, type aliases, and functions defined in
  the current file;
- **cross-file definitions** — when the file belongs to a
  [`wit-deps`][wit-deps]-managed project, the same kinds of definitions from
  every other `.wit` file in that tree: sibling package files and resolved
  dependencies under `wit/deps/` (see below).

Completion is suppressed inside comments and string literals. Candidates are
gathered from the parse tree, so newly typed definitions become available as
soon as they parse. Any completion UI that reads
`completion-at-point-functions` — Corfu, Company, or the built-in
`completion-at-point` — picks these up automatically; in Doom the configured
front-end (Corfu or Company) just works.

### Cross-file symbols and dependencies

There is no WIT language server, so `wit-ts-mode` resolves cross-file symbols
itself. A WIT project keeps its sources in a `wit/` directory with resolved
dependency sources under `wit/deps/`; [`wit-deps`][wit-deps] projects also have
a `wit/deps.toml` manifest. When the current file lives in such a tree,
completion parses the other `.wit` files there (with the same tree-sitter
grammar) and offers their definitions too.

To fetch or refresh the dependencies, run one of:

```
M-x wit-ts-deps-sync     ; populate deps/ from the lock file
M-x wit-ts-deps-update   ; pull latest, rewrite the lock file
```

`wit-ts-deps-sync` populates `wit/deps/` from the manifest while honouring the
existing lock file, so pinned versions do not change. `wit-ts-deps-update`
pulls the latest sources for dynamic references (such as a tracked branch) and
rewrites the lock file.

Which tool backs those commands is decided per project by
`wit-ts-deps-tool-function`. The default finds the `wit/` directory and picks
[`wit-deps`][wit-deps] when it contains a `deps.toml` (run bare for sync,
`wit-deps update` for update), otherwise [`wkg`][wkg] (wasm-pkg-tools:
`wkg fetch` for sync, `wkg update` for update). Override the function to force
one tool or key the choice on some other marker; the executables are
`wit-ts-deps-executable` (default `wit-deps`) and `wit-ts-wkg-executable`
(default `wkg`).

The chosen tool runs in the project root, streaming output to a buffer named
for it; on success the resolved sources become available to completion. The
mode never runs a tool implicitly — no network access happens unless you ask
for it — and it does not author `deps.toml` for you; supply your own manifest.
The WIT directory name defaults to `wit` but is configurable via
`wit-ts-deps-directory`.

Off-buffer files are parsed on demand and cached by modification time, so
completion stays cheap even with a large `wit/deps/` tree; both commands
clear that cache on success.

[wit-deps]: https://github.com/bytecodealliance/wit-deps
[wkg]: https://github.com/bytecodealliance/wasm-pkg-tools

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

An ERT suite lives in `test/`, with fixtures under `test/resources/`. It
covers font-lock faces, indentation, imenu, navigation and which-function,
Flymake diagnostics, and completion. Every test skips itself (rather than
failing) when the grammar is unavailable, so it is safe to run anywhere.

Common tasks are wrapped in a `Makefile`:

```sh
make grammar   # install the WIT tree-sitter grammar (needs a C compiler)
make test      # run the ERT suite
make compile   # byte-compile with warnings as errors
make checkdoc  # run checkdoc
make lint      # run package-lint
make all       # compile + checkdoc + test
```

CI runs `compile`, `checkdoc`, `lint`, and `test` on every push across a
matrix of Emacs versions (see `.github/workflows/ci.yml`).

## License

Apache License 2.0. See the [`LICENSE`](LICENSE) file for the full text.

[wit]: https://component-model.bytecodealliance.org/design/wit.html
[grammar]: https://github.com/bytecodealliance/tree-sitter-wit
