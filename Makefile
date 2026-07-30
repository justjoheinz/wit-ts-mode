# Makefile for wit-ts-mode
#
# Targets:
#   make compile   byte-compile with warnings as errors
#   make checkdoc  run checkdoc on the source
#   make lint      run package-lint (installs it if needed)
#   make test      run the ERT suite
#   make grammar   install the WIT tree-sitter grammar
#   make all       compile + checkdoc + test
#   make clean     remove byte-compiled files

EMACS ?= emacs
SRC   := wit-ts-mode.el
TESTS := test/wit-ts-mode-tests.el

BATCH := $(EMACS) -Q --batch -L .

.PHONY: all compile checkdoc lint test grammar clean

all: compile checkdoc test

compile:
	$(BATCH) --eval '(setq byte-compile-error-on-warn t)' \
		-f batch-byte-compile $(SRC)

checkdoc:
	$(BATCH) --eval '(checkdoc-file "$(SRC)")'

lint:
	$(BATCH) --eval "(progn \
		(require 'package) \
		(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t) \
		(package-initialize) \
		(unless (package-installed-p 'package-lint) \
			(package-refresh-contents) (package-install 'package-lint)) \
		(require 'package-lint))" \
		-f package-lint-batch-and-exit $(SRC)

grammar:
	$(BATCH) --eval "(progn \
		(require 'treesit) \
		(setq treesit-language-source-alist \
			'((wit \"https://github.com/bytecodealliance/tree-sitter-wit\"))) \
		(treesit-install-language-grammar 'wit))"

test:
	$(BATCH) -l $(TESTS) -f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
