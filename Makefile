.PHONY: bootstrap deps lint syntax check run clean

# настройки
VENV := .venv
PY := python3
BIN := $(VENV)/bin
ANSIBLE_PLAYBOOK := $(BIN)/ansible-playbook
GALAXY := $(BIN)/ansible-galaxy
PIP := $(BIN)/pip
YAMLLINT := $(BIN)/yamllint
ANSIBLE_LINT := $(BIN)/ansible-lint

INVENTORY := ansible/inventory.ini
PLAYBOOK := ansible/site.yml
REQ := $(if $(wildcard ansible/requirements.yml),ansible/requirements.yml,requirements.yml)

# дополнительные параметры для ansible-playbook, например --tags, --limit и т.п.
PLAYBOOK_OPTS ?=

bootstrap:
	@which $(PY) >/dev/null 2>&1 || (echo "python3 не найден" && exit 1)
	@test -d $(VENV) || $(PY) -m venv $(VENV)
	@$(PIP) install --upgrade pip
	@$(PIP) install "ansible>=9" ansible-lint yamllint

deps: bootstrap
	@$(GALAXY) install -r $(REQ)

lint: bootstrap
	@$(YAMLLINT) .
	@$(ANSIBLE_LINT) -p

syntax: deps
	@$(ANSIBLE_PLAYBOOK) $(PLAYBOOK_OPTS) -i $(INVENTORY) --syntax-check $(PLAYBOOK)

check: deps
	@ANSIBLE_STDOUT_CALLBACK=yaml $(ANSIBLE_PLAYBOOK) $(PLAYBOOK_OPTS) -i $(INVENTORY) --check $(PLAYBOOK)

run: deps
	@ANSIBLE_STDOUT_CALLBACK=yaml $(ANSIBLE_PLAYBOOK) $(PLAYBOOK_OPTS) -i $(INVENTORY) $(PLAYBOOK)

clean:
	@rm -rf $(VENV) .cache __pycache__ .ansible_tmp
