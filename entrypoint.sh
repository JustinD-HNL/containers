#!/bin/bash
set -euo pipefail

# Default values
BUILDKITE_AGENT_TOKEN="${BUILDKITE_AGENT_TOKEN:-}"
BUILDKITE_AGENT_NAME="${BUILDKITE_AGENT_NAME:-buildkite-agent-$(hostname)}"
BUILDKITE_AGENT_TAGS="${BUILDKITE_AGENT_TAGS:-queue=default,os=linux,docker=true}"
BUILDKITE_AGENT_PRIORITY="${BUILDKITE_AGENT_PRIORITY:-}"
BUILDKITE_BUILD_PATH="${BUILDKITE_BUILD_PATH:-/buildkite/builds}"

echo "🚀 Starting Buildkite Agent..."
echo "Agent Name: $BUILDKITE_AGENT_NAME"
echo "Agent Tags: $BUILDKITE_AGENT_TAGS"
echo "Build Path: $BUILDKITE_BUILD_PATH"

# Validate required environment variables
if [ -z "$BUILDKITE_AGENT_TOKEN" ]; then
    echo "❌ ERROR: BUILDKITE_AGENT_TOKEN environment variable is required"
    echo "Please set it when running the container:"
    echo "  docker run -e BUILDKITE_AGENT_TOKEN=your_token_here ..."
    exit 1
fi

# Create build directory if it doesn't exist
mkdir -p "$BUILDKITE_BUILD_PATH"

# Export environment variables for substitution
export BUILDKITE_AGENT_TOKEN
export BUILDKITE_AGENT_NAME
export BUILDKITE_AGENT_TAGS
export BUILDKITE_AGENT_PRIORITY
export BUILDKITE_BUILD_PATH

# Substitute environment variables in config file
envsubst < /etc/buildkite-agent/buildkite-agent.cfg > /tmp/buildkite-agent.cfg
mv /tmp/buildkite-agent.cfg /etc/buildkite-agent/buildkite-agent.cfg

# Check if Docker daemon is accessible (for Docker-in-Docker scenarios)
if command -v docker &> /dev/null; then
    if ! docker info &> /dev/null; then
        echo "⚠️  WARNING: Docker daemon is not accessible. Make sure to:"
        echo "   - Run with --privileged flag, OR"
        echo "   - Mount Docker socket: -v /var/run/docker.sock:/var/run/docker.sock"
        echo "   - Or run in Docker-in-Docker mode"
    else
        echo "✅ Docker daemon is accessible"
    fi
fi

# Check Git configuration
if ! git config --global user.email &> /dev/null; then
    echo "📝 Setting default Git configuration..."
    git config --global user.email "buildkite-agent@localhost"
    git config --global user.name "Buildkite Agent"
    git config --global init.defaultBranch "main"
fi

# Ensure proper permissions on build directory
if [ -w "$BUILDKITE_BUILD_PATH" ]; then
    echo "✅ Build directory is writable"
else
    echo "❌ WARNING: Build directory is not writable: $BUILDKITE_BUILD_PATH"
fi

# Display Buildkite agent version
echo "📋 Buildkite Agent Version:"
buildkite-agent --version

# Start SSH agent if SSH keys are mounted
if [ -d "/home/buildkite-agent/.ssh" ] && [ "$(ls -A /home/buildkite-agent/.ssh 2>/dev/null)" ]; then
    echo "🔐 Starting SSH agent..."
    eval "$(ssh-agent -s)"
    for key in /home/buildkite-agent/.ssh/id_*; do
        if [ -f "$key" ] && [ ! "${key##*.}" = "pub" ]; then
            ssh-add "$key" 2>/dev/null || true
        fi
    done
fi

echo "🎯 Configuration complete. Starting Buildkite Agent..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Execute the command passed to the container
exec "$@"