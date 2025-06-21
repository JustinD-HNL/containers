# Buildkite Agent Docker Container Makefile

# Configuration
IMAGE_NAME := buildkite-agent
IMAGE_TAG := latest
CONTAINER_NAME := buildkite-agent
FULL_IMAGE_NAME := $(IMAGE_NAME):$(IMAGE_TAG)

# Include environment variables from .env if it exists
-include .env
export

.PHONY: help build run stop clean logs shell test push setup

# Default target
help: ## Show this help message
	@echo "Buildkite Agent Docker Container"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Copy environment template and make scripts executable
	@echo "🔧 Setting up project..."
	@cp -n .env.template .env || true
	@chmod +x build.sh
	@chmod +x entrypoint.sh
	@find hooks -type f -exec chmod +x {} \; 2>/dev/null || true
	@echo "✅ Setup complete! Edit .env with your configuration."

build: ## Build the Docker image
	@echo "🏗️ Building Docker image: $(FULL_IMAGE_NAME)"
	@docker build -t $(FULL_IMAGE_NAME) .
	@echo "✅ Build complete!"

build-no-cache: ## Build the Docker image without cache
	@echo "🏗️ Building Docker image without cache: $(FULL_IMAGE_NAME)"
	@docker build --no-cache -t $(FULL_IMAGE_NAME) .
	@echo "✅ Build complete!"

run: ## Run the container (requires BUILDKITE_AGENT_TOKEN)
	@if [ -z "$(BUILDKITE_AGENT_TOKEN)" ]; then \
		echo "❌ ERROR: BUILDKITE_AGENT_TOKEN is required"; \
		echo "Set it in .env file or export BUILDKITE_AGENT_TOKEN=your_token"; \
		exit 1; \
	fi
	@echo "🚀 Starting Buildkite Agent container..."
	@docker run -d \
		--name $(CONTAINER_NAME) \
		--restart unless-stopped \
		-e BUILDKITE_AGENT_TOKEN="$(BUILDKITE_AGENT_TOKEN)" \
		$(if $(BUILDKITE_AGENT_NAME),-e BUILDKITE_AGENT_NAME="$(BUILDKITE_AGENT_NAME)") \
		$(if $(BUILDKITE_AGENT_TAGS),-e BUILDKITE_AGENT_TAGS="$(BUILDKITE_AGENT_TAGS)") \
		$(if $(BUILDKITE_AGENT_PRIORITY),-e BUILDKITE_AGENT_PRIORITY="$(BUILDKITE_AGENT_PRIORITY)") \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v buildkite-builds:/buildkite/builds \
		$(FULL_IMAGE_NAME)
	@echo "✅ Container started: $(CONTAINER_NAME)"
	@sleep 2
	@$(MAKE) logs-tail

run-privileged: ## Run the container in privileged mode
	@if [ -z "$(BUILDKITE_AGENT_TOKEN)" ]; then \
		echo "❌ ERROR: BUILDKITE_AGENT_TOKEN is required"; \
		exit 1; \
	fi
	@echo "🚀 Starting Buildkite Agent container (privileged mode)..."
	@docker run -d \
		--name $(CONTAINER_NAME) \
		--restart unless-stopped \
		--privileged \
		-e BUILDKITE_AGENT_TOKEN="$(BUILDKITE_AGENT_TOKEN)" \
		$(if $(BUILDKITE_AGENT_NAME),-e BUILDKITE_AGENT_NAME="$(BUILDKITE_AGENT_NAME)") \
		$(if $(BUILDKITE_AGENT_TAGS),-e BUILDKITE_AGENT_TAGS="$(BUILDKITE_AGENT_TAGS)") \
		-v buildkite-builds:/buildkite/builds \
		$(FULL_IMAGE_NAME)
	@echo "✅ Container started: $(CONTAINER_NAME)"

stop: ## Stop and remove the container
	@echo "🛑 Stopping container: $(CONTAINER_NAME)"
	@docker stop $(CONTAINER_NAME) 2>/dev/null || true
	@docker rm $(CONTAINER_NAME) 2>/dev/null || true
	@echo "✅ Container stopped and removed"

restart: stop run ## Restart the container

logs: ## Show container logs
	@docker logs $(CONTAINER_NAME)

logs-tail: ## Follow container logs
	@docker logs --tail 20 -f $(CONTAINER_NAME)

shell: ## Open shell in running container
	@echo "🐚 Opening shell in container: $(CONTAINER_NAME)"
	@docker exec -it $(CONTAINER_NAME) /bin/bash

status: ## Show container status
	@echo "📊 Container Status:"
	@docker ps -f name=$(CONTAINER_NAME) --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "📈 Resource Usage:"
	@docker stats $(CONTAINER_NAME) --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" 2>/dev/null || echo "Container not running"

health: ## Check container health
	@echo "🏥 Health Check:"
	@docker inspect --format='{{.State.Health.Status}}' $(CONTAINER_NAME) 2>/dev/null || echo "No health check or container not found"

test: ## Run basic tests on the container
	@echo "🧪 Running basic tests..."
	@echo "Testing Docker access..."
	@docker exec $(CONTAINER_NAME) docker --version
	@echo "Testing Git..."
	@docker exec $(CONTAINER_NAME) git --version
	@echo "Testing Buildkite Agent..."
	@docker exec $(CONTAINER_NAME) buildkite-agent --version
	@echo "Testing file permissions..."
	@docker exec $(CONTAINER_NAME) ls -la /buildkite/builds
	@echo "✅ All tests passed!"

clean: ## Clean up containers, images, and volumes
	@echo "🧹 Cleaning up..."
	@echo "Stopping and removing containers..."
	@docker ps -aq -f name="buildkite-agent" | xargs -r docker stop
	@docker ps -aq -f name="buildkite-agent" | xargs -r docker rm
	@echo "Removing images..."
	@docker images -q $(IMAGE_NAME) | xargs -r docker rmi
	@echo "Removing volumes (with confirmation)..."
	@docker volume ls -q -f name="buildkite" | while read vol; do \
		read -p "Remove volume $$vol? (y/N): " confirm; \
		if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
			docker volume rm $$vol; \
		fi; \
	done
	@echo "✅ Cleanup complete!"

clean-force: ## Force clean up everything without confirmation
	@echo "🧹 Force cleaning up..."
	@docker ps -aq -f name="buildkite-agent" | xargs -r docker stop 2>/dev/null || true
	@docker ps -aq -f name="buildkite-agent" | xargs -r docker rm 2>/dev/null || true
	@docker images -q $(IMAGE_NAME) | xargs -r docker rmi 2>/dev/null || true
	@docker volume ls -q -f name="buildkite" | xargs -r docker volume rm 2>/dev/null || true
	@echo "✅ Force cleanup complete!"

push: ## Push image to registry (requires DOCKER_REGISTRY)
	@if [ -z "$(DOCKER_REGISTRY)" ]; then \
		echo "❌ ERROR: DOCKER_REGISTRY is required"; \
		echo "Set it in .env file or export DOCKER_REGISTRY=your_registry"; \
		exit 1; \
	fi
	@echo "📤 Pushing to registry: $(DOCKER_REGISTRY)"
	@docker tag $(FULL_IMAGE_NAME) $(DOCKER_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
	@docker push $(DOCKER_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)
	@echo "✅ Push complete!"

compose-up: ## Start services with Docker Compose
	@echo "🚀 Starting with Docker Compose..."
	@docker-compose up -d
	@echo "✅ Services started!"

compose-down: ## Stop services with Docker Compose
	@echo "🛑 Stopping Docker Compose services..."
	@docker-compose down
	@echo "✅ Services stopped!"

compose-logs: ## Show Docker Compose logs
	@docker-compose logs -f

info: ## Show project information
	@echo "📋 Buildkite Agent Docker Container"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "Image Name:      $(FULL_IMAGE_NAME)"
	@echo "Container Name:  $(CONTAINER_NAME)"
	@echo ""
	@echo "Environment:"
	@echo "  Token:         $(if $(BUILDKITE_AGENT_TOKEN),✅ Set,❌ Not set)"
	@echo "  Agent Name:    $(BUILDKITE_AGENT_NAME)"
	@echo "  Agent Tags:    $(BUILDKITE_AGENT_TAGS)"
	@echo ""
	@echo "Quick Start:"
	@echo "  1. make setup"
	@echo "  2. Edit .env with your BUILDKITE_AGENT_TOKEN"
	@echo "  3. make build"
	@echo "  4. make run"
	@echo ""
	@echo "For help: make help"

# Development targets
dev-build: ## Build for development with cache disabled
	$(MAKE) build-no-cache IMAGE_TAG=dev

dev-run: ## Run development container
	$(MAKE) run IMAGE_TAG=dev CONTAINER_NAME=buildkite-agent-dev

dev-clean: ## Clean development containers
	@docker stop buildkite-agent-dev 2>/dev/null || true
	@docker rm buildkite-agent-dev 2>/dev/null || true
	@docker rmi $(IMAGE_NAME):dev 2>/dev/null || true