#!/bin/bash
# Build script for Buildkite Agent Docker container

set -euo pipefail

# Configuration
IMAGE_NAME="buildkite-agent"
IMAGE_TAG="latest"
DOCKERFILE="Dockerfile"
BUILD_CONTEXT="."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show help
show_help() {
    cat << EOF
Buildkite Agent Docker Container Build Script

Usage: $0 [OPTIONS] COMMAND

Commands:
    build       Build the Docker image
    run         Run a container with the image
    stop        Stop running containers
    clean       Clean up containers and images
    push        Push image to registry
    logs        Show container logs
    shell       Open shell in running container

Options:
    -t, --tag TAG           Set image tag (default: latest)
    -n, --name NAME         Set container name (default: buildkite-agent)
    -k, --token TOKEN       Set Buildkite agent token
    --agent-name NAME       Set agent name
    --agent-tags TAGS       Set agent tags
    --no-cache              Build without cache
    --privileged            Run container in privileged mode
    --dry-run               Show commands without executing
    -h, --help              Show this help

Examples:
    $0 build
    $0 build --no-cache
    $0 run --token "your-buildkite-token"
    $0 run --token "token" --agent-name "my-agent" --agent-tags "queue=deploy,os=linux"
    $0 logs
    $0 clean

Environment Variables:
    BUILDKITE_AGENT_TOKEN   Agent token (required for run command)
    DOCKER_REGISTRY         Docker registry URL for push command
    IMAGE_PREFIX            Prefix for image name
EOF
}

# Parse command line arguments
COMMAND=""
NO_CACHE=""
DRY_RUN=""
PRIVILEGED=""
CONTAINER_NAME="buildkite-agent"
BUILDKITE_AGENT_TOKEN="${BUILDKITE_AGENT_TOKEN:-}"
AGENT_NAME=""
AGENT_TAGS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -n|--name)
            CONTAINER_NAME="$2"
            shift 2
            ;;
        -k|--token)
            BUILDKITE_AGENT_TOKEN="$2"
            shift 2
            ;;
        --agent-name)
            AGENT_NAME="$2"
            shift 2
            ;;
        --agent-tags)
            AGENT_TAGS="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        --privileged)
            PRIVILEGED="--privileged"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        build|run|stop|clean|push|logs|shell)
            COMMAND="$1"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Set full image name
if [ -n "${IMAGE_PREFIX:-}" ]; then
    FULL_IMAGE_NAME="${IMAGE_PREFIX}/${IMAGE_NAME}:${IMAGE_TAG}"
else
    FULL_IMAGE_NAME="${IMAGE_NAME}:${IMAGE_TAG}"
fi

# Function to execute command (with dry-run support)
execute() {
    if [ "$DRY_RUN" = "true" ]; then
        echo "[DRY-RUN] $*"
    else
        "$@"
    fi
}

# Build function
build_image() {
    print_status "Building Buildkite Agent Docker image..."
    print_status "Image: $FULL_IMAGE_NAME"
    
    # Create hooks directory structure if it doesn't exist
    mkdir -p hooks
    
    # Make hook scripts executable
    find hooks -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find hooks -type f ! -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    
    # Build the image
    BUILD_CMD="docker build $NO_CACHE -t $FULL_IMAGE_NAME -f $DOCKERFILE $BUILD_CONTEXT"
    print_status "Build command: $BUILD_CMD"
    
    if execute $BUILD_CMD; then
        print_success "Image built successfully: $FULL_IMAGE_NAME"
        
        # Show image info
        if [ "$DRY_RUN" != "true" ]; then
            docker images "$FULL_IMAGE_NAME"
        fi
    else
        print_error "Failed to build image"
        exit 1
    fi
}

# Run function
run_container() {
    print_status "Running Buildkite Agent container..."
    
    # Validate required token
    if [ -z "$BUILDKITE_AGENT_TOKEN" ]; then
        print_error "BUILDKITE_AGENT_TOKEN is required"
        print_status "Set it with: -k TOKEN or export BUILDKITE_AGENT_TOKEN=your_token"
        exit 1
    fi
    
    # Stop existing container if running
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        print_warning "Stopping existing container: $CONTAINER_NAME"
        execute docker stop "$CONTAINER_NAME"
        execute docker rm "$CONTAINER_NAME"
    fi
    
    # Prepare environment variables
    ENV_VARS="-e BUILDKITE_AGENT_TOKEN=$BUILDKITE_AGENT_TOKEN"
    
    if [ -n "$AGENT_NAME" ]; then
        ENV_VARS="$ENV_VARS -e BUILDKITE_AGENT_NAME=$AGENT_NAME"
    fi
    
    if [ -n "$AGENT_TAGS" ]; then
        ENV_VARS="$ENV_VARS -e BUILDKITE_AGENT_TAGS=$AGENT_TAGS"
    fi
    
    # Prepare Docker command
    RUN_CMD="docker run -d \
        --name $CONTAINER_NAME \
        --restart unless-stopped \
        $PRIVILEGED \
        $ENV_VARS \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v buildkite-builds:/buildkite/builds \
        $FULL_IMAGE_NAME"
    
    print_status "Run command: $RUN_CMD"
    
    if execute $RUN_CMD; then
        print_success "Container started successfully: $CONTAINER_NAME"
        if [ "$DRY_RUN" != "true" ]; then
            sleep 2
            docker logs --tail 20 "$CONTAINER_NAME"
        fi
    else
        print_error "Failed to start container"
        exit 1
    fi
}

# Stop function
stop_container() {
    print_status "Stopping Buildkite Agent container..."
    
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        execute docker stop "$CONTAINER_NAME"
        execute docker rm "$CONTAINER_NAME"
        print_success "Container stopped and removed: $CONTAINER_NAME"
    else
        print_warning "No running container found with name: $CONTAINER_NAME"
    fi
}

# Clean function
clean_up() {
    print_status "Cleaning up Buildkite Agent resources..."
    
    # Stop and remove containers
    if docker ps -aq -f name="buildkite-agent" | grep -q .; then
        print_status "Removing Buildkite Agent containers..."
        execute docker stop $(docker ps -aq -f name="buildkite-agent") 2>/dev/null || true
        execute docker rm $(docker ps -aq -f name="buildkite-agent") 2>/dev/null || true
    fi
    
    # Remove images
    if docker images -q "$IMAGE_NAME" | grep -q .; then
        print_status "Removing Buildkite Agent images..."
        execute docker rmi $(docker images -q "$IMAGE_NAME") 2>/dev/null || true
    fi
    
    # Remove volumes (with confirmation)
    if docker volume ls -q -f name="buildkite" | grep -q .; then
        read -p "Remove Buildkite volumes? This will delete build data. (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            execute docker volume rm $(docker volume ls -q -f name="buildkite") 2>/dev/null || true
            print_success "Volumes removed"
        fi
    fi
    
    print_success "Cleanup completed"
}

# Push function
push_image() {
    if [ -z "${DOCKER_REGISTRY:-}" ]; then
        print_error "DOCKER_REGISTRY environment variable is required for push"
        exit 1
    fi
    
    REGISTRY_IMAGE="${DOCKER_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    print_status "Tagging image for registry..."
    execute docker tag "$FULL_IMAGE_NAME" "$REGISTRY_IMAGE"
    
    print_status "Pushing image to registry: $REGISTRY_IMAGE"
    execute docker push "$REGISTRY_IMAGE"
    
    print_success "Image pushed successfully"
}

# Logs function
show_logs() {
    print_status "Showing logs for container: $CONTAINER_NAME"
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        docker logs -f "$CONTAINER_NAME"
    else
        print_error "No running container found with name: $CONTAINER_NAME"
        exit 1
    fi
}

# Shell function
open_shell() {
    print_status "Opening shell in container: $CONTAINER_NAME"
    if docker ps -q -f name="$CONTAINER_NAME" | grep -q .; then
        docker exec -it "$CONTAINER_NAME" /bin/bash
    else
        print_error "No running container found with name: $CONTAINER_NAME"
        exit 1
    fi
}

# Main execution
case "$COMMAND" in
    build)
        build_image
        ;;
    run)
        run_container
        ;;
    stop)
        stop_container
        ;;
    clean)
        clean_up
        ;;
    push)
        push_image
        ;;
    logs)
        show_logs
        ;;
    shell)
        open_shell
        ;;
    "")
        print_error "No command specified"
        show_help
        exit 1
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_help
        exit 1
        ;;
esac