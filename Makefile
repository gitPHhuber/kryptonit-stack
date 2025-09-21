ANSIBLE ?= ansible-playbook

INVENTORY ?= inventory/local.ini


PLAYBOOK ?= site.yml

.PHONY: deps lint run vault

deps:
	ansible-galaxy collection install --timeout 60 -r requirements.yml

lint:
	yamllint .
	ansible-lint --offline

run:
	$(ANSIBLE) -i $(INVENTORY) $(PLAYBOOK)

vault:
	ansible-vault edit group_vars/dev/vault.yml
