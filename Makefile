ANSIBLE ?= ansible-playbook

INVENTORY ?=


PLAYBOOK ?= site.yml

.PHONY: deps lint run vault

deps:
	ansible-galaxy collection install --timeout 60 -r requirements.yml

lint:
	yamllint .
	ansible-lint --offline

run:
	@if [ -n "$(INVENTORY)" ]; then \
		$(ANSIBLE) -i "$(INVENTORY)" $(PLAYBOOK); \
	else \
		$(ANSIBLE) $(PLAYBOOK); \
	fi

vault:
	ansible-vault edit group_vars/dev/vault.yml
