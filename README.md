# Modded Minecraft Server on AWS (Terraform)

Infrastructure-as-code for a **modded Minecraft server** running on AWS EC2,
reachable by any player on the internet. The server runs the well-maintained
[`itzg/minecraft-server`](https://github.com/itzg/docker-minecraft-server)
Docker image, which supports **Forge, NeoForge, Fabric, Quilt, Paper and
Vanilla**, plus automatic mod downloading.

## Architecture

```
                 Internet
                    │  (TCP 25565)
                    ▼
        ┌───────────────────────┐
        │  Elastic IP (stable)  │
        └───────────┬───────────┘
                    ▼
   VPC 10.20.0.0/16 ── public subnet ── Internet Gateway
                    │
        ┌───────────▼────────────┐
        │  EC2 (Amazon Linux 2023)│
        │  Docker + compose       │
        │  itzg/minecraft-server  │
        └───────────┬────────────┘
                    │  /opt/minecraft/data
        ┌───────────▼────────────┐
        │  EBS gp3 data volume    │  ← world + mods persist here
        │  (survives instance     │
        │   replacement/resizing) │
        └─────────────────────────┘
```

What Terraform creates:

- A dedicated **VPC** with a public subnet, internet gateway and route table.
- A **security group** opening the Minecraft port (`25565/tcp`) to the internet
  and (optionally) SSH to a CIDR you specify.
- An **EC2 instance** (Amazon Linux 2023) that installs Docker and launches the
  Minecraft container via a systemd-managed `docker compose` service.
- A separate **EBS data volume** for the world and mods, so you can resize or
  replace the instance without losing your world. It is protected with
  `prevent_destroy`.
- An **Elastic IP** so the connection address never changes.
- An **IAM role** enabling **SSM Session Manager**, so you can get a shell on
  the box without opening SSH or managing keys.

## Prerequisites

- An AWS account and credentials configured locally
  (`aws configure`, or environment variables / SSO).
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.
- (Optional) the AWS CLI if you want to use SSM Session Manager.

## Usage

```bash
cd terraform

# 1. Configure your deployment
cp terraform.tfvars.example terraform.tfvars
#   then edit terraform.tfvars (region, instance size, mod loader, mods, ...)

# 2. Initialize and review
terraform init
terraform plan

# 3. Deploy
terraform apply
```

When the apply finishes, Terraform prints the connection address:

```
connection_address = "203.0.113.10:25565"
```

> First boot takes a few minutes: the instance installs Docker, pulls the image,
> downloads the mod loader + mods, and generates the world. Watch progress with
> the `ssm_connect_command` output, then run the command from `logs_hint`.

In Minecraft: **Multiplayer → Add Server → Server Address** = the
`connection_address` value. If you used the default port `25565`, players can
just enter the IP.

## Configuring mods

### Option A — manual URLs (default)

Set the loader, version and a list of direct mod download URLs in
`terraform.tfvars`:

```hcl
mod_loader        = "FORGE"
minecraft_version = "1.20.1"
mod_urls = [
  "https://.../jei-1.20.1-forge.jar",
  "https://.../create-1.20.1-forge.jar",
]
```

The mods must match the chosen loader and Minecraft version. After changing
these values, run `terraform apply` — the server re-syncs the mod list via SSM
(without replacing the instance).

### Option B — CurseForge modpack sync (recommended for players)

Keep the server in sync with a **CurseForge modpack project** so players can
install the same pack from the CurseForge app.

**Setup:**

1. Create a modpack at [curseforge.com/minecraft/modpacks](https://www.curseforge.com/minecraft/modpacks).
2. In the **CurseForge app**, create a profile with your mods (Forge 1.20.1),
   then **Create Custom Profile → Export** and upload the zip to your project.
3. Find the **numeric project ID** in the Authors Console (or from the API).
4. Configure Terraform:

```hcl
curseforge_modpack_project_id = 123456   # your modpack project ID
# curseforge_modpack_file_id  = 0        # 0 = latest release for 1.20.1 Forge

# Mods not on CurseForge (e.g. Modrinth-only) — appended after the pack list:
mod_urls_extra = [
  "https://cdn.modrinth.com/data/.../some-mod.jar",
]
```

5. Export your API key and apply:

```bash
export CURSEFORGE_API_KEY="your-token"   # https://console.curseforge.com/
cd terraform && terraform apply
```

On each apply, Terraform reads the modpack `manifest.json` via the CurseForge
API, resolves download URLs for every mod, writes them to SSM, and pushes them
to the running server.

Preview the resolved sync after apply:

```bash
terraform output curseforge_modpack_sync
```

**Workflow when you update the modpack on CurseForge:**

1. Export a new version from the CurseForge app and upload it.
2. Run `terraform apply` (or pin `curseforge_modpack_file_id` to a specific file).
3. The server picks up the new mod list automatically.

You can also drop `.jar` files directly into `/opt/minecraft/data/mods` on the
instance (via SSM/SSH) and restart the container:

```bash
cd /opt/minecraft && docker compose restart
```

## Server administration

From the repo root, `make` wraps common operations:

```bash
make start      # start the EC2 instance
make stop       # stop the instance (saves compute cost)
make status     # running / stopped
make address    # connection address
make connect    # shell via SSM
make logs       # recent server logs
make mods       # re-sync mod list to running server
```

Connect a shell to the instance:

```bash
aws ssm start-session --target <instance-id> --region <region>
```

Useful commands once connected:

```bash
sudo tail -f /var/log/minecraft-setup.log     # provisioning log
cd /opt/minecraft
sudo docker compose logs -f                   # live server log
sudo docker compose restart                   # restart the server
sudo docker exec -i minecraft rcon-cli        # run server console commands
```

## Costs

You pay for the EC2 instance (largest cost), the EBS volumes, and the Elastic
IP while the instance is running. To stop charges for compute without losing
your world, you can stop the instance:

```bash
aws ec2 stop-instances --instance-ids <instance-id> --region <region>
```

`terraform destroy` removes everything **except** the data volume, which is
protected by `prevent_destroy`. To delete it too, remove that lifecycle block
or detach and delete the volume manually.

## Troubleshooting

### `Error: timeout while waiting for plugin to start` (Apple Silicon Mac)

**Most common cause: an x86_64 Terraform running under Rosetta.** On Apple
Silicon, if you installed the Intel build of Terraform (e.g. via an Intel
Homebrew at `/usr/local`), it downloads the x86_64 provider and runs it under
Rosetta. macOS security scanning (XProtect/Jamf/EDR) scans the large (~700 MB)
provider binary on every launch, and the Rosetta overhead pushes each launch
past Terraform's fixed 60 s plugin-start timeout.

**Fix: use the native `arm64` build.** Check what you have:

```bash
terraform version          # should say: on darwin_arm64
file "$(which terraform)"  # should say: Mach-O 64-bit executable arm64
```

If it says `darwin_amd64` / `x86_64`, install the native build:

```bash
brew uninstall terraform   # remove the Intel build, if installed via brew
# install native arm64 (1.x):
curl -fsSL -o /tmp/tf.zip \
  https://releases.hashicorp.com/terraform/1.15.6/terraform_1.15.6_darwin_arm64.zip
unzip -o /tmp/tf.zip -d /tmp && sudo install -m 0755 /tmp/terraform /usr/local/bin/terraform
hash -r
# re-init so the native arm64 provider is downloaded:
cd terraform && rm -rf .terraform .terraform.lock.hcl && terraform init
```

(Alternatively, install the native arm64 Homebrew at `/opt/homebrew` and use it.)

## Security notes

- SSH is **disabled by default** (`allowed_ssh_cidrs = []`); management is done
  through SSM Session Manager. If you enable SSH, restrict `allowed_ssh_cidrs`
  to your own IP rather than `0.0.0.0/0`.
- The Minecraft port must be open to your players; restrict
  `allowed_minecraft_cidrs` if you only want specific networks to connect.
- The instance requires IMDSv2 (`http_tokens = "required"`).
