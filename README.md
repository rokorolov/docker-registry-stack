# Docker Registry

**Escape Docker Hub rate limits — self-hosted registry + pull-through cache on your own VPS.**

[![License](https://img.shields.io/badge/license-BSD-blue.svg)](LICENSE.md)
[![Release](https://img.shields.io/github/v/release/rokorolov/docker-registry-stack)](https://github.com/rokorolov/docker-registry-stack/releases/latest)

Self-hosted private Docker registry with a Docker Hub pull-through cache, Nginx reverse proxy, TLS via Let's Encrypt, and Ansible provisioning.

## Contents

- [Who This Is For](#who-this-is-for)
- [Key Benefits](#key-benefits)
- [Self-hosted vs. GitHub Container Registry](#self-hosted-vs-github-container-registry)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Using the Registries](#using-the-registries)
- [Security Notes](#security-notes)
- [Day-2 Operations](#day-2-operations)
- [Local Development](#local-development)
- [Project Structure](#project-structure)
- [Roadmap](#roadmap)

## Who This Is For

If you are a solo developer, indie hacker, or part of a small engineering team without a dedicated DevOps engineer, this project is built for you. Specifically, it is a great fit if you:

- already pay for a VPS and want to get more out of it,
- are hitting Docker Hub rate limits in CI and tired of working around them,
- need a private place to store proprietary images without paying for a managed registry,
- or want production-ready infrastructure without spending days reading documentation.

You do not need to be an Ansible expert, a networking specialist, or a security engineer. The provisioning is fully automated, the security defaults are already correct, and the only tool you need on your local machine is Docker.

## Key Benefits

**No more Docker Hub rate limits.**
Docker Hub throttles unauthenticated pulls to 100 per six hours, and free accounts to 200. For a team running parallel CI jobs, that ceiling is hit fast. The built-in pull-through cache makes the rate limit invisible — every `docker pull` goes through your own registry after the first hit, and your entire team benefits automatically with no per-developer configuration.

**One tool. No clutter on your machine.**
The entire provisioning toolchain — Ansible, Galaxy collections, SSH utilities — runs inside a Docker container. You do not install anything on your laptop or CI runner beyond Docker itself. No version conflicts, no "works on my machine," no residual packages after you are done.

**A full registry in under 30 minutes.**
From a freshly created VPS with DNS records pointing at it, provisioning is complete — TLS certificates issued, firewall configured, both registries running — in a single session. No manual SSH steps, no copy-pasting commands from a wiki page.

**Your images never leave your server.**
Build artifacts from proprietary software contain your source code. Pushing to a third-party registry means trusting that registry with your IP. With this setup, images live on infrastructure you control, in a jurisdiction you choose.

**Security that does not require a checklist.**
TLS 1.2/1.3 only, HSTS with a two-year max-age, OCSP stapling, bcrypt-hashed credentials, and a default-deny firewall are all configured by the provisioning playbooks — not as optional hardening steps, but as the starting point. There is nothing to forget to enable.

**Re-run anything, safely.**
All provisioning playbooks are idempotent. Re-running `make server` after a config change, a failed step, or a team member's first setup applies only what changed and leaves everything else untouched. No state to track, no teardown required.

---

> *"I built this because I kept hitting Docker Hub rate limits in CI and did not want to pay for a managed registry I could run myself on a VPS I was already paying for. It has been running in production for years with zero maintenance beyond the occasional `make upgrade`. I use it on every project."*
>
> — Romans Korolovs, author

---

## Self-hosted vs. GitHub Container Registry

GitHub Container Registry (GHCR) is the most common alternative for teams already on GitHub. The honest answer is that GHCR is the right choice for some teams — and this project is the right choice for others.

**Choose this project when:**

| Situation | Why self-hosted wins |
|---|---|
| Docker Hub rate limits are hitting your CI | GHCR stores your images but **cannot proxy Docker Hub**. The pull-through cache is the only clean fix. |
| You are already paying for a VPS | The registry runs on infrastructure you pay for regardless — marginal cost is zero. |
| High pull volume in CI | GHCR charges for data out. Pulling a 1 GB image across 50 CI runs/day is ~1.5 TB/month. On your own VPS that is $0. |
| Non-GitHub CI (GitLab, Jenkins, Buildkite) | No `GITHUB_TOKEN` shortcut — GHCR credential management becomes manual. |
| Data locality requirements | Images stay on your server, in your jurisdiction. Note: auth is single-tier `htpasswd` — no per-user RBAC or audit logging. |

**Choose GHCR when:**

| Situation | Why GHCR wins |
|---|---|
| Private image storage only, no rate limit problem | Simpler, zero-maintenance, no server to run. |
| Your CI is GitHub Actions | Authentication via `GITHUB_TOKEN` is automatic — no credential management. |
| Low ops tolerance | No disk to monitor, no garbage collection, no server to patch or recover. |
| Open source project | GHCR is free for public repositories with no storage or egress limits. |

The pull-through cache is the single capability GHCR cannot replicate. If that is not your pain point, weigh the operational cost of running your own server honestly before committing to it.

## Architecture

```
Internet
   │
   ▼
Nginx (80/443)
   │  TLS termination, HTTP→HTTPS redirect
   │
   ├── registry.example.com ──────────────▶ Registry (5000)
   │   Basic auth (htpasswd)                 Private image storage
   │
   └── cache-registry.example.com ────────▶ Cache Registry (5000)
                                              Docker Hub pull-through cache
```

Two independent registry containers run behind a single Nginx instance. The **private registry** stores your own images and requires authentication. The **cache registry** is a transparent pull-through proxy for Docker Hub — configure it as a registry mirror in your Docker daemon to avoid rate limits and speed up pulls. Nginx configs and SSL certificates are managed by Ansible and mounted into the container from the host — they are not part of the deployed application files.

## Prerequisites

### Server requirements

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 1 vCPU | 1 vCPU |
| RAM | 512 MB | 1 GB |
| Disk free on `/` | 5 GB | 20 GB |
| Disk (registry data) | depends on image count | plan for growth |
| Network | 1 public IP, ports 80 and 443 open | — |

The production stack (Nginx + two registry containers) is lightweight — under 250 MB RSS at idle. The only variable is disk space for stored images, which can range from a few MB to several GB per image. A standard 1 vCPU / 1 GB RAM VPS with 40 GB total disk is a comfortable starting point for a small team.

### Supported operating systems

| Layer | Supported OS |
|---|---|
| Remote server | Ubuntu 22.04 LTS (Jammy) / 24.04 LTS (Noble) — Debian 11 (Bullseye) / 12 (Bookworm) (any APT-based distro should work) |
| Control node (provisioning + deploy) | Linux, macOS |
| Local development (Docker only) | Linux, macOS, Windows |

### Required tools

| Tool | Purpose |
|---|---|
| Docker + Docker Compose plugin | Local development, production runtime, and provisioning toolbox |
| GNU Make | Makefile convenience targets (`make deploy`, `make up`, etc.) — pre-installed on macOS; install with `apt install make` on Debian/Ubuntu |
| SSH client (`ssh`, `scp`) | Deployment |
| SSH access to the server | Provisioning and deployment |
| Two DNS records pointed at the server | TLS certificate issuance (one per registry) |

Ansible, `apache2-utils`, and all other provisioning dependencies are bundled in the toolbox Docker image — nothing else needs to be installed locally.

## Getting Started

> All commands in this section run from the `provisioning/` directory — `cd provisioning` once before starting.
>
> Steps **2** (Bootstrap SSH key) and **7** (Authorize deploy user) are optional — skip them if your VPS provider installed your SSH key at server creation time.

### 0. Build the provisioning toolbox

All provisioning commands run inside a Docker container that bundles Ansible, Galaxy collections, and all other dependencies. Build the image once before running any of the steps below:

```bash
cd provisioning && make build
```

All subsequent provisioning commands use the `./provision` wrapper, which runs `make` inside the container with the correct volume mounts and SSH agent forwarding:

```bash
cd provisioning
./provision make <target>
```

### 1. Configure inventory

```bash
cp provisioning/hosts.yml.dist provisioning/hosts.yml
```

Edit `provisioning/hosts.yml` and fill in your values:

| Variable | Description |
|---|---|
| `ansible_host` | Server IP address |
| `ansible_port` | SSH port (default: `22`) |
| `registry_domain` | Domain for the private registry (e.g. `registry.example.com`) |
| `cache_registry_domain` | Domain for the cache registry (e.g. `cache-registry.example.com`) |
| `certbot_admin_email` | Email address for Let's Encrypt expiry notifications |

Both domains must resolve to the server before running the certbot step.

### 2. Bootstrap root SSH key access

> **Skip this step if your VPS provider already installed your SSH key at creation time** — most providers offer this during the server setup wizard. Only needed when your server was provisioned with password-only root access.

Connects to the server once using the root password and installs your local public key into `/root/.ssh/authorized_keys`. After this step, all subsequent commands use key-based authentication — the password is no longer needed.

```bash
cd provisioning && ./provision make bootstrap
```

You will be prompted for the root password interactively. The playbook detects your key type automatically, checking for `id_ed25519`, `id_ecdsa`, and `id_rsa` in that order.

### 3. Generate registry credentials

The production `htpasswd` file is gitignored and must be created locally before deployment. Use bcrypt (`-B`) — Nginx's `auth_basic` module accepts MD5 and SHA as well, but both are cryptographically weak and trivially crackable offline.

```bash
# Create a new file with the first user
htpasswd -Bc htpasswd <username>

# Add additional users to an existing file
htpasswd -B htpasswd <username>
```

If `htpasswd` is not installed, use the Docker equivalent:

```bash
docker run --rm httpd:2.4 htpasswd -nbB <username> <password> >> htpasswd
```

Keep `htpasswd` out of version control — it is already listed in `.gitignore`.

### 4. Run preflight checks

Validates that all required inventory variables are set, SSH connectivity works, the server has sufficient disk space, and both DNS records resolve to the server. Run this before any other provisioning step — it catches the most common configuration mistakes upfront.

```bash
cd provisioning && ./provision make preflight
```

### 5. Upgrade the server

Update all system packages before installing anything. This ensures a clean security baseline and avoids Docker being installed on top of stale package lists. If a kernel upgrade was applied, the playbook reboots the server automatically and waits for it to come back up.

```bash
cd provisioning && ./provision make upgrade
```

### 6. Provision the server

Installs Docker Engine, creates the `deploy` system user, and renders Nginx config templates to `/etc/docker-registry/nginx/` on the server.

```bash
cd provisioning && ./provision make server
```

This requires root SSH access. The playbook also configures UFW with a default-deny incoming policy, allowing only SSH (on the port configured in `hosts.yml`), HTTP (80), and HTTPS (443). After this step you can lock down the `root` account.

### 7. Authorize your SSH key for deployments

Copies your public key to the `deploy` user's `authorized_keys`. The playbook automatically detects your key type, checking for `id_ed25519`, `id_ecdsa`, and `id_rsa` in that order.

```bash
cd provisioning && ./provision make authorize
```

### 8. Issue SSL certificates

The playbook uses the webroot method. If port 80 is not yet occupied by any service, it temporarily starts an Apache container to serve the ACME challenge.

```bash
cd provisioning && ./provision make certbot
```

Both `registry_domain` and `cache_registry_domain` receive their own certificate.

### 9. Deploy

Run from the project root. Transfers the compose file and `htpasswd` to the server atomically, then starts the stack.

```bash
make deploy HOST=<server-ip> PORT=<ssh-port> HTPASSWD_FILE=./htpasswd
```

The compose file is staged as `compose.yml.new` on the server and renamed to `compose.yml` only after a successful transfer, preventing a broken state if the transfer is interrupted.

After deployment the registries are available at:

| Service | URL |
|---|---|
| Private registry | `https://registry.example.com` |
| Cache registry | `https://cache-registry.example.com` |

## Using the registries

### Authenticate and push images

```bash
docker login registry.example.com
```

To verify the registry works end-to-end, use `hello-world` — it is the smallest available image (~13 KB) and purpose-built for testing Docker infrastructure:

```bash
docker pull hello-world
docker tag hello-world registry.example.com/hello-world
docker push registry.example.com/hello-world

# Confirm it is stored
curl -u <username>:<password> https://registry.example.com/v2/_catalog

# Remove the local copy, then pull back from the registry to confirm the round-trip
docker rmi registry.example.com/hello-world
docker pull registry.example.com/hello-world
```

Once verified, push your own images the same way:

```bash
docker tag myimage:latest registry.example.com/myimage:latest
docker push registry.example.com/myimage:latest
docker pull registry.example.com/myimage:latest
```

### Configure the cache registry as a Docker Hub mirror

Add the following to `/etc/docker/daemon.json` on each Docker host that should pull through the cache, then restart Docker:

```json
{
    "registry-mirrors": ["https://cache-registry.example.com"]
}
```

```bash
sudo systemctl restart docker
```

After this, `docker pull nginx:alpine` will transparently proxy through the cache registry on the first pull and serve from cache on subsequent pulls. Authentication is not required for the cache registry.

### Configure the cache registry for private Docker Hub images

By default the cache registry proxies public Docker Hub images anonymously. To also cache private images or to raise the authenticated rate-limit tier, set Docker Hub credentials in `~/registry/.env` on the server — never in the compose file:

```bash
# ~/registry/.env on the server
REGISTRY_PROXY_USERNAME=<dockerhub-username>
REGISTRY_PROXY_PASSWORD=<dockerhub-password-or-pat>
```

The compose file already reads these via `${REGISTRY_PROXY_USERNAME:-}` and `${REGISTRY_PROXY_PASSWORD:-}`. Redeploy to restart the container with the new environment:

```bash
make deploy HOST=<server-ip> PORT=<ssh-port> HTPASSWD_FILE=./htpasswd
```

### List stored images

```bash
# Via the API (will prompt for password)
curl -u <username> https://registry.example.com/v2/_catalog

# Non-interactive form
curl -u <username>:<password> https://registry.example.com/v2/_catalog

# List tags for a specific image
curl -u <username>:<password> https://registry.example.com/v2/myimage/tags/list
```

## Security notes

- **Firewall:** UFW is configured by the provisioning playbook with a default-deny incoming policy. Only SSH, HTTP, and HTTPS are open. All other ports are blocked.
- **Authentication:** Only the private registry (`registry_domain`) requires credentials. The cache registry is intentionally unauthenticated — it is protected by the firewall and should only be reachable from trusted hosts.
- **TLS:** Both registries use TLS 1.2/1.3 only. HSTS with a two-year max-age is enforced. OCSP stapling is enabled.
- **htpasswd:** Use bcrypt (`-B` flag). Nginx's `auth_basic` module technically accepts MD5 and SHA formats, but both are cryptographically weak and can be cracked offline in seconds — bcrypt is the only safe choice.
- **Old Docker clients:** Nginx blocks Docker clients older than 1.6 (`user_agent` filter in the Nginx config) — they use an incompatible registry protocol.
- **Credentials file:** `htpasswd` and `provisioning/hosts.yml` are listed in `.gitignore`. Never commit either file.
- **HTTP secret:** Registry v3 logs a startup warning if no HTTP secret is set. On a single-node deployment this is harmless — the secret only matters when multiple registry instances share a load-balancer (session stickiness for uploads). To suppress the warning, add `REGISTRY_HTTP_SECRET=<random-string>` to `~/registry/.env` on the server.
- **SSH host key checking:** The provisioning toolbox runs Ansible inside a Docker container where `~/.ssh` is mounted read-only and owned by the host user. SSH refuses config files it does not own, so `ansible.cfg` sets `host_key_checking = False` and `-F /dev/null` to skip the SSH config file entirely. This means provisioning commands do not verify the server's host key against a known-hosts file. The risk is low for a server you own and provisioned yourself, but be aware that a compromised DNS or network MITM would not be detected. Provision over a trusted network.

## Day-2 operations

### Check server status

Shows live state of all containers, disk usage, firewall rules, TLS certificate expiry, and external API reachability — without changing anything on the server. Run this before any Day-2 operation to confirm the server is healthy.

```bash
cd provisioning && ./provision make status
```

### View container logs

Shows the last 200 lines of logs from both the private registry and the cache registry.

```bash
cd provisioning && ./provision make logs

# Show more lines
cd provisioning && ./provision make logs LINES=500
```

### Change the SSH port

Changing the default SSH port from 22 reduces exposure to automated scanning bots and eliminates most brute-force noise in auth logs. It is not a substitute for key-based authentication and a firewall, but it is a low-cost hardening step.

```bash
cd provisioning && ./provision make change-ssh-port PORT=2222
```

The playbook handles the full sequence safely: opens the new port in UFW first (if UFW is active), updates `/etc/ssh/sshd_config`, validates the new config with `sshd -t` before restarting, removes the old UFW rule, restarts sshd, then verifies the new port is reachable. `ansible_port` in `hosts.yml` is updated automatically — all subsequent commands use the new port without any manual changes.

> If the connection is interrupted after sshd restarts and the playbook cannot confirm the new port is reachable, use your VPS provider's out-of-band console to verify the service is running, then re-run the command.

### Upgrade system packages

```bash
cd provisioning && ./provision make upgrade
```

### Renew SSL certificates

Certbot renewal runs automatically via cron on the server. To trigger a manual renewal:

```bash
cd provisioning && ./provision make certbot
```

### Update Nginx configuration

Nginx configs are managed by Ansible. After editing `registry_domain`, `cache_registry_domain`, or the templates in `provisioning/roles/docker-registry/templates/`, re-provision to push the change:

```bash
cd provisioning && ./provision make server
```

Then restart Nginx on the server to reload the new config:

```bash
ssh deploy@<server-ip> -p <port> 'cd registry && docker compose exec nginx nginx -s reload'
```

### Delete images and run garbage collection

The API can delete image manifests, but the underlying layer blobs remain on disk until garbage collection is run. Deleting is a two-step process.

**Step 1 — delete the manifest via the API:**

```bash
# Get the digest for the tag (accepts both OCI and Docker manifest formats)
DIGEST=$(curl -sI -u <username>:<password> \
    -H "Accept: application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json" \
    https://registry.example.com/v2/myimage/manifests/latest \
    | grep -i docker-content-digest | awk '{print $2}' | tr -d $'\r')

# Delete the manifest
curl -X DELETE -u <username>:<password> \
    https://registry.example.com/v2/myimage/manifests/${DIGEST}
```

**Step 2 — run garbage collection:**

```bash
cd provisioning && ./provision make gc
```

Runs GC on both the private registry and the cache registry without stopping the containers. Pause any CI pipelines that push images before running to avoid a race condition.

### Back up registry data

Only the private registry volume needs backing up — the cache re-populates automatically from Docker Hub on the next pull.

See [`docs/backup-plan.md`](docs/backup-plan.md) for the full implementation plan, including a ready-to-use backup script, an Ansible role for provisioning secrets and a cron job, and a step-by-step restore procedure.

### Add or rotate registry credentials

Regenerate the `htpasswd` file locally, then redeploy:

```bash
htpasswd -Bc htpasswd <username>
make deploy HOST=<server-ip> PORT=<ssh-port> HTPASSWD_FILE=./htpasswd
```

The running Nginx process picks up the updated file immediately — no reload required, because Nginx reads `htpasswd` on each request.

### Update Docker image versions

Images are pinned to `major.minor.patch` (nginx also includes the Alpine OS version) so updates are always explicit and reproducible. To upgrade, find the new tag on Docker Hub, update both `compose.yml` and `compose-production.yml`, then redeploy:

```bash
make deploy HOST=<server-ip> PORT=<ssh-port> HTPASSWD_FILE=./htpasswd
```

| Image | Tag strategy | Rationale |
|---|---|---|
| `nginx` | `1.30.3-alpine3.23` | Stable branch (`1.30.x`). Pin the Alpine OS version to prevent a silent base-image change. |
| `registry` | `3.1.1` | Registry v3 is the current actively-maintained series; v2 received its last update in February 2025. |

### Update Ansible Galaxy roles

Bump the version in `provisioning/requirements.yml`, rebuild the toolbox image, then re-run server provisioning:

```bash
cd provisioning && make build && ./provision make server
```

### Manage firewall rules

UFW is configured during provisioning. To inspect or modify rules on the server:

```bash
ssh root@<server-ip> -p <ssh-port> 'ufw status numbered'
```

To allow an additional port:

```bash
ssh root@<server-ip> -p <ssh-port> 'ufw allow <port>/tcp'
```

To remove a rule by number:

```bash
ssh root@<server-ip> -p <ssh-port> 'ufw delete <rule-number>'
```

## Local development

The development stack exposes the private registry on port `5000` and the cache registry on port `5001`. It uses a pre-configured `htpasswd` file and plain HTTP — no TLS.

```bash
make init   # Pull images and start all services
make up     # Start services
make down   # Stop services
```

| Service | URL |
|---|---|
| Private registry | `http://localhost:5000` |
| Cache registry | `http://localhost:5001` |

Dev credentials are defined in `docker/development/nginx/auth/htpasswd`. Docker automatically allows plain HTTP for loopback addresses (`127.0.0.1`), so no `--insecure-registry` flag is needed.

Test that the registry is reachable (replace `<password>` with the value from the htpasswd file):

```bash
curl -u registry:<password> http://localhost:5000/v2/_catalog
```

## Project structure

```
.
├── compose.yml                        # Development stack (ports 5000/5001)
├── compose-production.yml             # Production stack (ports 80/443)
├── Makefile                           # Local dev and deploy commands
├── docker/
│   └── development/nginx/
│       ├── auth/htpasswd              # Dev credentials (not for production)
│       └── conf.d/                    # Dev Nginx configs (no TLS)
└── provisioning/
    ├── Dockerfile                     # Provisioning toolbox image
    ├── provision                      # Wrapper script — runs make inside the toolbox container
    ├── ansible.cfg                    # Ansible configuration
    ├── Makefile                       # Provisioning commands
    ├── requirements.yml               # Ansible Galaxy roles and collections
    ├── hosts.yml.dist                 # Inventory template — copy to hosts.yml
    ├── preflight.yml                  # Pre-provisioning validation playbook
    ├── bootstrap.yml                  # One-time root SSH key setup (password → key auth)
    ├── change-ssh-port.yml            # Change SSH port and update hosts.yml
    ├── server.yml                     # Main provisioning playbook
    ├── certbot.yml                    # SSL certificate playbook
    ├── authorize.yml                  # SSH key authorization playbook
    ├── upgrade.yml                    # System upgrade playbook
    ├── status.yml                     # Live server status (containers, disk, firewall, TLS, API)
    ├── logs.yml                       # Tail container logs from both registries
    ├── gc.yml                         # Garbage collection for private and cache registries
    └── roles/
        ├── ufw/                       # Configures UFW firewall rules
        ├── docker/                    # Installs Docker Engine
        ├── create-deploy-user/        # Creates the deploy system user
        └── docker-registry/           # Deploys Nginx config templates
            └── templates/
                ├── registry.conf.j2
                └── cache-registry.conf.j2
```

## Roadmap

### Object storage backend

The registry supports S3-compatible storage natively. The planned change moves image data off the server disk to Cloudflare R2 (free egress, generous free tier) or AWS S3, making the server stateless — pure compute with no persistent data.

The key operational benefit: if the server dies, provision a fresh VPS, point the new registry at the same bucket, and recovery is complete in ~15 minutes. No data is lost because the data was never on the server. Disk space monitoring and garbage collection become non-issues.

Planned implementation:
- Ansible role to provision the R2 bucket and credentials
- Registry and cache-registry configured to use the S3 storage driver
- Secrets managed via inventory variables, not hardcoded in compose files
