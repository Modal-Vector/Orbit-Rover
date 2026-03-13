FROM debian:bookworm-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    jq \
    python3 \
    python3-yaml \
    cron \
    inotify-tools \
    curl \
    git \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js (for claude-code)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Install Go (for opencode)
ARG GO_VERSION=1.23.6
RUN ARCH=$(dpkg --print-architecture) && \
    curl -sL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:/usr/local/go-bin:${PATH}"
ENV GOPATH="/usr/local/go-pkg"
ENV GOBIN="/usr/local/go-bin"

# Install opencode (into shared path so non-root user can access it)
RUN mkdir -p /usr/local/go-bin /usr/local/go-pkg && \
    go install github.com/opencode-ai/opencode@latest

# Install yq (latest stable)
ARG YQ_VERSION=v4.44.6
RUN ARCH=$(dpkg --print-architecture) && \
    curl -sL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" \
      -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq

# Install gum for TUI dashboard
ARG GUM_VERSION=0.14.5
RUN ARCH=$(dpkg --print-architecture) && \
    curl -sL "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_linux_${ARCH}.deb" \
      -o /tmp/gum.deb && \
    dpkg -i /tmp/gum.deb && \
    rm /tmp/gum.deb

# Copy Orbit Rover into the image
COPY . /opt/orbit-rover

# Make the orbit CLI available on PATH
RUN chmod +x /opt/orbit-rover/orbit && \
    ln -s /opt/orbit-rover/orbit /usr/local/bin/orbit

# Create non-root user (claude-code requires non-root invocation)
RUN useradd -m -s /bin/bash orbit

# Default workspace for user projects
RUN mkdir -p /workspace && chown orbit:orbit /workspace
WORKDIR /workspace

# Verify installation (still as root, before switching user)
RUN orbit doctor

# Run as non-root user
USER orbit

ENTRYPOINT ["orbit"]
CMD ["--help"]
