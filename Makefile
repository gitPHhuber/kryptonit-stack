ANSIBLE ?= ansible-playbook
ANSIBLE_COLLECTIONS_PATH ?= ./collections:~/.ansible/collections:/usr/share/ansible/collections
export ANSIBLE_COLLECTIONS_PATH
INVENTORY ?= inventory/local.ini
PLAYBOOK ?= site.yml

.PHONY: deps lint run vault images-cache bootstrap-tools

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

run:
	$(ANSIBLE) -i "$(INVENTORY)" "$(PLAYBOOK)"

vault:
	ansible-vault edit group_vars/dev/vault.yml

images-cache:
	$(ANSIBLE) -i localhost, -c local playbooks/images-cache.yml
