# Convenience targets. Everything also runs directly; see README.md.
LUA ?= lua

.PHONY: check changelog lint test build beta install clean

check: lint test build

# toolbox/changelog.lua is generated from CHANGELOG.md; refresh it before anything reads it.
changelog:
	python3 tools/build.py --changelog

lint: changelog
	luacheck .

test: changelog
	$(LUA) tests/run.lua

build:
	python3 tools/build.py

# A zip for hand-installing beta testers: toolbox/ (with the default sounds) + INSTALL.txt.
beta: lint test
	python3 tools/beta.py

install: build
	python3 tools/install.py

clean:
	rm -rf dist
