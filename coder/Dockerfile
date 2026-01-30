# =========================
# Stage 1: Build VSIX extension
# =========================
FROM node:20-bookworm AS vsix-builder

ARG EXTENSION_REPO_URL=https://github.com/computor-org/computor-vscode.git
ARG EXTENSION_REPO_REF=main

WORKDIR /build

# Install git
RUN apt-get update && apt-get install -y git \
    && rm -rf /var/lib/apt/lists/*

# Clone extension repository
RUN git clone --depth 1 --branch ${EXTENSION_REPO_REF} ${EXTENSION_REPO_URL} extension

WORKDIR /build/extension

# Build and package extension
RUN npm ci \
    && npm run compile --if-present \
    && npm run build --if-present \
    && npm install -g @vscode/vsce \
    && vsce package --out /tmp/extension.vsix

# =========================
# Stage 2: Runtime image with code-server
# =========================
FROM ghcr.io/coder/code-server:latest

USER root

# Install Python and common development tools
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Prepare extensions directory
RUN mkdir -p /opt/code-server/extensions \
    && chown -R coder:coder /opt/code-server

# Allow pip to install packages system-wide
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Copy VSIX from builder stage
COPY --from=vsix-builder --chown=coder:coder /tmp/extension.vsix /opt/code-server/extension.vsix

USER coder

# Install extensions and clean up VSIX
RUN code-server --extensions-dir /opt/code-server/extensions --install-extension /opt/code-server/extension.vsix --force \
    && code-server --extensions-dir /opt/code-server/extensions --install-extension ms-python.python --force \
    && code-server --extensions-dir /opt/code-server/extensions --install-extension ms-toolsai.jupyter --force \
    && rm /opt/code-server/extension.vsix
