# =========================
# 1) Builder: clone & package VSIX
# =========================
FROM node:25-bookworm@sha256:78839ac448c23517f8eab2e8f7943d9b4f73979eb7f8bed2c73dbf72ff869e7b AS vsix-builder

ARG EXTENSION_REPO_URL=https://github.com/computor-org/computor-vscode.git
ARG EXTENSION_REPO_REF=main

WORKDIR /build

# git installieren
RUN apt-get update && apt-get install -y git \
    && rm -rf /var/lib/apt/lists/*

# Repo clonen
RUN git clone --depth 1 --branch ${EXTENSION_REPO_REF} ${EXTENSION_REPO_URL} extension

WORKDIR /build/extension

# Bauen & Packen
# Hinweis: npm ci ist strikter als npm install. Falls es fehlschlägt, nimm 'npm install'.
RUN npm ci \
    && npm run compile --if-present \
    && npm run build --if-present \
    && npm install -g @vscode/vsce@3.9.2 \
    # --no-dependencies nur nutzen, wenn dependencies gebundelt werden (meistens ok)
    && vsce package --out /tmp/extension.vsix

# =========================
# 2) Runtime: code-server
# =========================
FROM ghcr.io/coder/code-server@sha256:1c9ad972a78450f430155144110da4c02d3627c72a598e9197e2781fb9f92e28

USER root

# System Updates & Python Setup
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Extensions Ordner vorbereiten
RUN mkdir -p /opt/code-server/extensions \
    && chown -R coder:coder /opt/code-server

# Deine Pip-Konfiguration (PERFEKT!)
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# VSIX kopieren
# OPTIMIERUNG: Direkt mit den richtigen Rechten kopieren (--chown)
COPY --from=vsix-builder --chown=coder:coder /tmp/extension.vsix /opt/code-server/extension.vsix

USER coder

# Extensions installieren
# OPTIMIERUNG: Am Ende die .vsix Datei löschen, um Platz zu sparen
RUN code-server --extensions-dir /opt/code-server/extensions --install-extension /opt/code-server/extension.vsix --force \
    && code-server --extensions-dir /opt/code-server/extensions --install-extension ms-python.python --force \
    && code-server --extensions-dir /opt/code-server/extensions --install-extension ms-toolsai.jupyter --force \
    && rm /opt/code-server/extension.vsix
