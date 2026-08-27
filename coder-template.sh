terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

variable "computor_extension_channel" {
  type        = string
  default     = "stable"
  description = "stable or a preview identifier"
}

variable "computor_vsix_url" {
  type        = string
  default     = ""
  description = "Short-lived VSIX URL for a preview channel"
}

variable "computor_vsix_sha256" {
  type        = string
  default     = ""
  description = "SHA-256 digest required for preview VSIX installation"
}

variable "computor_vsix_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Optional bearer token for a private preview artifact"
}

variable "computor_backend_url" {
  type        = string
  default     = ""
  description = "Backend URL associated with the selected extension channel"
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # 1. Home vorbereiten
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # 2. Code-Server manuell starten
    EXTENSIONS_DIR="$HOME/.local/share/code-server/extensions"
    mkdir -p "$EXTENSIONS_DIR"
    if [ -d /opt/code-server/extensions ] && [ -z "$(find "$EXTENSIONS_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]; then
      cp -a /opt/code-server/extensions/. "$EXTENSIONS_DIR/" 2>/dev/null || true
    fi

    # A preview VSIX is fetched into the workspace-owned directory.  The
    # checksum is mandatory whenever a URL is supplied so a stale or swapped
    # artifact cannot silently replace the extension.
    if [ -n "${COMPUTOR_VSIX_URL:-}" ]; then
      if [ -z "${COMPUTOR_VSIX_SHA256:-}" ]; then
        echo "COMPUTOR_VSIX_SHA256 is required for preview channel ${COMPUTOR_EXTENSION_CHANNEL:-preview}" >&2
        exit 1
      fi
      VSIX_TMP="$(mktemp --suffix=.vsix)"
      trap 'rm -f "$VSIX_TMP"' EXIT
      if [ -n "${COMPUTOR_VSIX_TOKEN:-}" ]; then
        curl -fsSL --retry 3 -H "Authorization: Bearer ${COMPUTOR_VSIX_TOKEN}" "$COMPUTOR_VSIX_URL" -o "$VSIX_TMP"
      else
        curl -fsSL --retry 3 "$COMPUTOR_VSIX_URL" -o "$VSIX_TMP"
      fi
      printf '%s  %s\\n' "$COMPUTOR_VSIX_SHA256" "$VSIX_TMP" | sha256sum -c -
      code-server --extensions-dir "$EXTENSIONS_DIR" --install-extension "$VSIX_TMP" --force
      rm -f "$VSIX_TMP"
      trap - EXIT
    fi

    code-server --auth none --port 13337 --extensions-dir "$EXTENSIONS_DIR" >/tmp/code-server.log 2>&1 &

  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
    COMPUTOR_EXTENSION_CHANNEL = var.computor_extension_channel
    COMPUTOR_VSIX_URL          = var.computor_vsix_url
    COMPUTOR_VSIX_SHA256       = var.computor_vsix_sha256
    COMPUTOR_VSIX_TOKEN        = var.computor_vsix_token
    COMPUTOR_BACKEND_URL       = var.computor_backend_url
  }

  # ... Metadata Blöcke (CPU, RAM etc.) können hier bleiben ...
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
}

# VS Code Web Module
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  order    = 1

  # KEINE 'extensions' Liste hier, da sie im Image sind.
  # KEINE 'args' hier (das war der Fehler).
}

# JetBrains Gateway Module
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.1"
  agent_id   = coder_agent.main.id
  agent_name = "main"
  folder     = "/home/coder"
}

# Persistentes Volume
resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

# Image bauen
resource "docker_image" "workspace_image" {
  # TRICK: Wir hängen den Hash des Dockerfiles an den Namen.
  # Sobald du im Dockerfile auch nur ein Leerzeichen änderst, ändert sich der Name
  # und Terraform zwingt Docker, das Image neu zu bauen.
  name = "coder-image-${data.coder_workspace.me.id}-${filesha256("Dockerfile")}"

  build {
    context    = "${path.module}"
    dockerfile = "Dockerfile"
  }
  keep_locally = true
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.workspace_image.name
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name

  # Der Fix für die Verbindung ("Unhealthy" Agent verhindern)
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]

  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}
