FROM golang:1.25-bookworm

# Install Node.js 24.x and pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y nodejs && \
    corepack enable && \
    corepack prepare pnpm@latest --activate

# Install development and debug tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    jq \
    make \
    gcc \
    g++ \
    ca-certificates \
    mailcap \
    procps \
    lsof \
    net-tools \
    vim \
    && rm -rf /var/lib/apt/lists/*

# Install Go development tools
RUN go install github.com/go-delve/delve/cmd/dlv@latest && \
    go install golang.org/x/tools/gopls@latest && \
    go install github.com/go-task/task/v3/cmd/task@latest

WORKDIR /app

# Pre-install Go dependencies
COPY go.mod go.sum ./
RUN go mod download

# Pre-install frontend dependencies
COPY frontend/package.json frontend/pnpm-lock.yaml ./frontend/
RUN cd frontend && pnpm install --frozen-lockfile

# Create runtime directories
RUN mkdir -p /config /database /srv

ENTRYPOINT ["sleep", "infinity"]
