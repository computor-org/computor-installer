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
    # Wir nutzen port 13337 (Standard für Coder) und den speziellen Extension-Ordner aus dem Image
    code-server --auth none --port 13337 --extensions-dir /opt/code-server/extensions >/tmp/code-server.log 2>&1 &

  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
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
