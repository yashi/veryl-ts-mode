EMACS ?= emacs
GRAMMAR_DIR ?=
GRAMMAR_SRC ?=
BUILD_DIR ?= build
GRAMMAR_LIBRARY ?= libtree-sitter-veryl.so

.PHONY: check compile test test-package grammar clean

check: test test-package

compile:
	$(EMACS) -Q --batch -L . \
		--eval '(setq byte-compile-error-on-warn t)' \
		-f batch-byte-compile veryl-ts-mode.el

test: compile
	VERYL_TS_MODE_GRAMMAR_DIR="$(GRAMMAR_DIR)" \
		$(EMACS) -Q --batch -L . -L test \
		-l veryl-ts-mode-test -f ert-run-tests-batch-and-exit

test-package:
	$(EMACS) -Q --batch -l test/veryl-ts-mode-package-test.el \
		-f ert-run-tests-batch-and-exit

grammar:
	test -n "$(GRAMMAR_SRC)"
	mkdir -p "$(BUILD_DIR)"
	$(CC) $(CPPFLAGS) $(CFLAGS) -O2 -fPIC -shared \
		-I "$(GRAMMAR_SRC)/src" "$(GRAMMAR_SRC)/src/parser.c" \
		$(LDFLAGS) -o "$(BUILD_DIR)/$(GRAMMAR_LIBRARY)"

clean:
	$(RM) veryl-ts-mode.elc
