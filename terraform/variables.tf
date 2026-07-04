###############################################################################
# General
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy the Minecraft server into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix applied to all created resources."
  type        = string
  default     = "minecraft"
}

###############################################################################
# Networking / access
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "minecraft_port" {
  description = "TCP port the Minecraft server listens on."
  type        = number
  default     = 25565
}

variable "allowed_minecraft_cidrs" {
  description = "CIDR blocks allowed to connect to the Minecraft port. Default is the whole internet."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH into the instance. Set to your IP (e.g. 1.2.3.4/32). Empty list disables SSH ingress."
  type        = list(string)
  default     = []
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair for SSH access. Leave empty to launch without an SSH key."
  type        = string
  default     = ""
}

###############################################################################
# Compute / storage
###############################################################################

variable "instance_type" {
  description = "EC2 instance type. Modded servers are memory-hungry; t3.large = 8GB, t3.xlarge = 16GB."
  type        = string
  default     = "t3.large"
}

variable "data_volume_size_gb" {
  description = "Size of the persistent EBS data volume that stores the world and mods."
  type        = number
  default     = 30
}

variable "root_volume_size_gb" {
  description = "Size of the instance root volume (OS + Docker images)."
  type        = number
  default     = 16
}

###############################################################################
# Minecraft server configuration (passed to the itzg/minecraft-server image)
###############################################################################

variable "mod_loader" {
  description = "Mod loader / server type. One of: FORGE, NEOFORGE, FABRIC, QUILT, PAPER, VANILLA."
  type        = string
  default     = "FORGE"

  validation {
    condition     = contains(["FORGE", "NEOFORGE", "FABRIC", "QUILT", "PAPER", "VANILLA"], var.mod_loader)
    error_message = "mod_loader must be one of: FORGE, NEOFORGE, FABRIC, QUILT, PAPER, VANILLA."
  }
}

variable "minecraft_version" {
  description = "Minecraft version to run (e.g. 1.20.1). Use LATEST for the newest release."
  type        = string
  default     = "1.20.1"
}

variable "server_memory" {
  description = "JVM heap size for the server (e.g. 6G). Leave headroom below the instance's total RAM."
  type        = string
  default     = "6G"
}

variable "mod_urls" {
  description = "List of direct download URLs for mod .jar files. Used when curseforge_modpack_project_id is 0. When CurseForge sync is enabled, use mod_urls_extra instead for additional jars."
  type        = list(string)
  default     = []
}

variable "mod_urls_extra" {
  description = "Extra mod .jar URLs appended after the CurseForge modpack list (for Modrinth-only mods or jars not in the pack)."
  type        = list(string)
  default     = []
}

variable "curseforge_modpack_project_id" {
  description = "CurseForge project ID of your modpack. When set (>0), mod URLs are resolved from the pack manifest via the CurseForge API instead of mod_urls."
  type        = number
  default     = 0
}

variable "curseforge_modpack_file_id" {
  description = "Specific CurseForge modpack file ID to pin. 0 = use the latest release matching minecraft_version and mod_loader."
  type        = number
  default     = 0
}

variable "curseforge_api_key" {
  description = "CurseForge API key. Prefer exporting CURSEFORGE_API_KEY instead of putting the key in tfvars."
  type        = string
  default     = ""
  sensitive   = true
}

variable "seed" {
  description = "World seed. Empty string lets Minecraft pick a random seed."
  type        = string
  default     = ""
}

variable "motd" {
  description = "Message of the day shown in the server list."
  type        = string
  default     = "A modded Minecraft server, powered by Terraform"
}

variable "difficulty" {
  description = "World difficulty: peaceful, easy, normal, hard."
  type        = string
  default     = "normal"
}

variable "max_players" {
  description = "Maximum number of concurrent players."
  type        = number
  default     = 20
}

variable "ops" {
  description = "Comma-separated list of player usernames granted operator (admin) status."
  type        = string
  default     = ""
}

variable "server_image_tag" {
  description = "Tag of the itzg/minecraft-server Docker image to run."
  type        = string
  default     = "java21"
}

variable "idle_shutdown_minutes" {
  description = "Stop the EC2 instance after this many minutes with no players online, to save compute cost. Restart it with `make start`. Set to 0 to disable."
  type        = number
  default     = 0
}
