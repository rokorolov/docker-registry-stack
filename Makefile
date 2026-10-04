.DEFAULT_GOAL := help

.PHONY: help init up down docker-up docker-down docker-down-clear docker-pull docker-build deploy

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Local development:"
	@echo "  init                                                   Pull, build and start all services"
	@echo "  up                                                     Start all services"
	@echo "  down                                                   Stop all services"
	@echo ""
	@echo "Production:"
	@echo "  deploy HOST=<ip> PORT=<port> HTPASSWD_FILE=<path>     Deploy to remote server"

init: docker-down-clear docker-pull docker-build docker-up

up: docker-up
down: docker-down

docker-up:
	docker compose up -d

docker-down:
	docker compose down --remove-orphans

docker-down-clear:
	docker compose down -v --remove-orphans

docker-pull:
	docker compose pull

docker-build:
	docker compose build

deploy:
ifndef HOST
	$(error HOST is not set. Usage: make deploy HOST=<ip> PORT=<port> HTPASSWD_FILE=<path>)
endif
ifndef PORT
	$(error PORT is not set. Usage: make deploy HOST=<ip> PORT=<port> HTPASSWD_FILE=<path>)
endif
ifndef HTPASSWD_FILE
	$(error HTPASSWD_FILE is not set. Usage: make deploy HOST=<ip> PORT=<port> HTPASSWD_FILE=<path>)
endif
	@echo "Starting deployment to $(HOST):$(PORT)..."
	@set -e; \
	echo "Transferring files..."; \
	ssh deploy@$(HOST) -p $(PORT) 'mkdir -p registry'; \
	scp -P $(PORT) compose-production.yml deploy@$(HOST):registry/compose.yml.new; \
	scp -P $(PORT) $(HTPASSWD_FILE) deploy@$(HOST):registry/htpasswd; \
	echo "Deploying services..."; \
	ssh deploy@$(HOST) -p $(PORT) 'set -e; cd registry && { \
		docker compose -p registry -f compose.yml.new pull; \
		mv -f compose.yml.new compose.yml; \
		sed "s/:/ /" htpasswd > users; \
		docker compose -p registry up -d --remove-orphans; \
		docker compose -p registry exec -T caddy caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile; \
	}'; \
	echo "Deployment completed successfully"
