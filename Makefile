# Convenience targets. Everything also runs directly; see README.md.
LUA ?= lua

.PHONY: check lint test build install clean

check: lint test build

lint:
	luacheck .

test:
	$(LUA) tests/run.lua

build:
	python3 tools/build.py

install: build
	python3 tools/install.py

clean:
	rm -rf dist
