# Convenience targets for make users. Everything runs without make too: `python3 tools/check.py`
# (Windows: `py tools/check.py`) is the one command for lint + tests + build; see CONTRIBUTING.md.
PYTHON ?= python3
LUA ?= lua

.PHONY: check container-check changelog lint test build beta install clean

check:
	$(PYTHON) tools/check.py

# The same checks inside the dev container (Docker or Podman; nothing else to install).
container-check:
	$(PYTHON) tools/check.py --container

# toolbox/changelog.lua is generated from CHANGELOG.md; refresh it before anything reads it.
changelog:
	$(PYTHON) tools/build.py --changelog

lint: changelog
	luacheck .

test: changelog
	$(LUA) tests/run.lua

build:
	$(PYTHON) tools/build.py

# A zip for hand-installing beta testers: toolbox/ (with the default sounds) + INSTALL.txt.
beta: check
	$(PYTHON) tools/beta.py

install: build
	$(PYTHON) tools/install.py

clean:
	$(PYTHON) -c "import shutil; shutil.rmtree('dist', ignore_errors=True)"
