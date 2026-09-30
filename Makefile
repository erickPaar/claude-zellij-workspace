PREFIX ?= $(HOME)/.local

.PHONY: install uninstall test check

# Link czw into $(PREFIX)/bin, so updating this checkout updates the command.
install:
	mkdir -p $(PREFIX)/bin
	ln -sf $(CURDIR)/bin/czw $(PREFIX)/bin/czw
	@echo "installed: $(PREFIX)/bin/czw -> $(CURDIR)/bin/czw"

uninstall:
	rm -f $(PREFIX)/bin/czw

# Static checks, then the tests (the end-to-end one needs zellij).
check:
	bash -n bin/czw share/resurrect-hook.sh tests/test.sh
	python3 -m py_compile lib/layout.py
	@if command -v shellcheck >/dev/null; then shellcheck bin/czw share/resurrect-hook.sh tests/test.sh; else echo "shellcheck not installed: skipped"; fi

test: check
	./tests/test.sh
