ANSIBLE ?= ansible-playbook
PYTHON_USER_SITE := $(shell python3 -c "import site; print(site.getusersitepackages())")
ANSIBLE_COLLECTIONS_PATH ?= ./collections:~/.ansible/collections:/usr/share/ansible/collections:$(PYTHON_USER_SITE)/ansible_collections
export ANSIBLE_COLLECTIONS_PATH
INVENTORY ?= inventory/local.ini
PLAYBOOK ?= playbooks/stack-up.yml

.PHONY: deps lint run vault fetch-images load-images stack-up

bootstrap-tools:
	@command -v python3 >/dev/null 2>&1 || { echo "python3 is required" >&2; exit 1; }
	@command -v pip3 >/dev/null 2>&1 || python3 -m ensurepip --upgrade
	@command -v ansible-galaxy >/dev/null 2>&1 || python3 -m pip install --user --upgrade 'ansible>=10.3'
	@command -v ansible-lint >/dev/null 2>&1 || python3 -m pip install --user --upgrade 'ansible-lint>=24.10'
	@command -v yamllint >/dev/null 2>&1 || python3 -m pip install --user --upgrade 'yamllint>=1.35'

deps: bootstrap-tools
	ansible-galaxy collection install --timeout 60 -r requirements.yml -p collections

lint: bootstrap-tools
	yamllint .
	ansible-lint --offline

run: stack-up

vault:
	ansible-vault edit group_vars/dev/vault.yml

fetch-images:
	$(ANSIBLE) -i localhost, -c local playbooks/images-fetch.yml

load-images:
	$(ANSIBLE) -i "$(INVENTORY)" playbooks/images-load.yml

stack-up:
	$(ANSIBLE) -i "$(INVENTORY)" "$(PLAYBOOK)"
