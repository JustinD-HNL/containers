FROM ubuntu:24.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV BUILDKITE_AGENT_TOKEN=""
ENV BUILDKITE_AGENT_NAME=""
ENV BUILDKITE_AGENT_TAGS=""
ENV BUILDKITE_AGENT_PRIORITY=""
ENV BUILDKITE_BUILD_PATH="/buildkite/builds"

# Create buildkite user and group
RUN groupadd -g 1000 buildkite-agent && \
    useradd -u 1000 -g 1000 -m -s /bin/bash buildkite-agent

# Update system and install dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y \
        curl \
        wget \
        git \
        unzip \
        ca-certificates \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common \
        build-essential \
        jq \
        sudo \
        openssh-client && \
    rm -rf /var/lib/apt/lists/*

# Install Docker CE
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Add buildkite-agent user to docker group
RUN usermod -aG docker buildkite-agent

# Install Buildkite Agent
RUN curl -fsSL https://keys.openpgp.org/vks/v1/by-fingerprint/32A37959C2FA5C3C99EFBC32A79206696452D198 | gpg --dearmor -o /usr/share/keyrings/buildkite-agent-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/buildkite-agent-archive-keyring.gpg] https://apt.buildkite.com/buildkite-agent stable main" | tee /etc/apt/sources.list.d/buildkite-agent.list && \
    apt-get update && \
    apt-get install -y buildkite-agent && \
    rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /buildkite/builds /buildkite/hooks /buildkite/plugins && \
    chown -R buildkite-agent:buildkite-agent /buildkite

# Copy configuration and scripts
COPY buildkite-agent.cfg /etc/buildkite-agent/buildkite-agent.cfg
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY hooks/ /buildkite/hooks/

# Make scripts executable
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chmod +x /buildkite/hooks/* || true

# Set proper permissions
RUN chown buildkite-agent:buildkite-agent /etc/buildkite-agent/buildkite-agent.cfg

# Create sudo rule for buildkite-agent (needed for some CI operations)
RUN echo "buildkite-agent ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/buildkite-agent

# Switch to buildkite-agent user
USER buildkite-agent
WORKDIR /buildkite

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep -f "buildkite-agent start" || exit 1

# Expose any ports if needed (typically not required for agents)
# EXPOSE 3000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["buildkite-agent", "start"]