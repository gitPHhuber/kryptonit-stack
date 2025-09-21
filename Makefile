GALAXY=ansible-galaxy install -r requirements.yml
RUN=ansible-playbook site.yml

all: deps vault run

deps:
	$(GALAXY)

vault:
	@echo "Encrypting group_vars/secrets.vault.yml (you'll set a password)"
	ansible-vault encrypt --encrypt-vault-id default group_vars/secrets.vault.yml || true

run:
	$(RUN)

.PHONY: all deps run vault
