PREFIX ?= $(HOME)/.local

.PHONY: install uninstall plugins test check

# Link czw into $(PREFIX)/bin, so updating this checkout updates the command.
install:
	mkdir -p $(PREFIX)/bin
	ln -sf $(CURDIR)/bin/czw $(PREFIX)/bin/czw
	@echo "installed: $(PREFIX)/bin/czw -> $(CURDIR)/bin/czw"

# The status bar: zjstatus, pinned, checked against the checksums below.
ZJSTATUS_VERSION := v0.25.0
ZJSTATUS_SHA256 := 282ceab219e56e1908c9fac33907241fe6c3e1ef7d85faab3e5f438cef87b8fe
PLUGINS := $(or $(XDG_DATA_HOME),$(HOME)/.local/share)/czw/plugins

plugins:
	mkdir -p $(PLUGINS)
	curl -fsSL -o $(PLUGINS)/zjstatus.wasm.part https://github.com/dj95/zjstatus/releases/download/$(ZJSTATUS_VERSION)/zjstatus.wasm
	echo "$(ZJSTATUS_SHA256)  $(PLUGINS)/zjstatus.wasm.part" | sha256sum -c --quiet
	mv $(PLUGINS)/zjstatus.wasm.part $(PLUGINS)/zjstatus.wasm
	@echo "zjstatus $(ZJSTATUS_VERSION) installed; czw open uses it from now on"

uninstall:
	rm -f $(PREFIX)/bin/czw

# Static checks, then the tests (the end-to-end one needs zellij).
check:
	bash -n bin/czw share/resurrect-hook.sh tests/test.sh
	python3 -m py_compile lib/layout.py lib/statusline.py
	@if command -v shellcheck >/dev/null; then shellcheck bin/czw share/resurrect-hook.sh tests/test.sh; else echo "shellcheck not installed: skipped"; fi

test: check
	./tests/test.sh
