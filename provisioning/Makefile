.DEFAULT_GOAL := help

.PHONY: help build bootstrap change-ssh-port preflight status logs gc requirements server authorize certbot upgrade

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "  build                          Build the provisioning toolbox Docker image"
	@echo "  bootstrap                      Add local SSH public key to root authorized_keys (password auth required)"
	@echo "  change-ssh-port PORT=<port>    Change the SSH port and update hosts.yml"
	@echo "  preflight                      Verify inventory variables, SSH connectivity, disk space, and DNS"
	@echo "  status                         Show live server status: containers, disk, firewall, TLS, API health"
	@echo "  logs                           Show last 200 lines of registry logs (override: LINES=500)"
	@echo "  gc                             Run garbage collection to free disk space from deleted images"
	@echo "  requirements                   Install Ansible Galaxy roles and collections (local Ansible only)"
	@echo "  server                         Provision the server (docker, deploy user, nginx config)"
	@echo "  authorize                      Authorize SSH keys for the deploy user"
	@echo "  certbot                        Install Certbot and issue SSL certificates"
	@echo "  upgrade                        Upgrade and clean APT packages on the server"

build:
	docker build -t docker-registry-provision .

bootstrap:
	ansible-playbook bootstrap.yml -i hosts.yml --ask-pass -e "ansible_port=22"

change-ssh-port:
	@test -n "$(PORT)" || (echo "PORT is required. Usage: make change-ssh-port PORT=2222" >&2 && exit 1)
	ansible-playbook change-ssh-port.yml -i hosts.yml -e "new_ssh_port=$(PORT)"

preflight:
	ansible-playbook preflight.yml -i hosts.yml

status:
	ansible-playbook status.yml -i hosts.yml

logs:
	ansible-playbook logs.yml -i hosts.yml $(if $(LINES),-e "lines=$(LINES)",)

gc:
	ansible-playbook gc.yml -i hosts.yml

requirements:
	ansible-galaxy install -r requirements.yml

server: requirements
	ansible-playbook server.yml -i hosts.yml

authorize:
	ansible-playbook authorize.yml -i hosts.yml

certbot: requirements
	ansible-playbook certbot.yml -i hosts.yml

upgrade:
	ansible-playbook upgrade.yml -i hosts.yml
