# Docker Registry

**Escape Docker Hub rate limits - self-hosted registry + pull-through cache on your own VPS.**

[![License](https://img.shields.io/badge/license-BSD-blue.svg)](LICENSE.md)
[![Release](https://img.shields.io/github/v/tag/rokorolov/docker-registry-stack)](https://github.com/rokorolov/docker-registry-stack/releases/latest)

Self-hosted private Docker registry with a Docker Hub pull-through cache, Caddy reverse proxy with automatic TLS via Let's Encrypt, and Ansible provisioning.

## Contents

- [Who This Is For](#who-this-is-for)
- [Key Benefits](#key-benefits)
- [Self-hosted vs. GitHub Container Registry](#self-hosted-vs-github-container-registry)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Using the Registries](#using-the-registries)
- [Security Notes](#security-notes)
- [Custom SSH Port](#custom-ssh-port)
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
Docker Hub throttles unauthenticated pulls to 100 per six hours, and free accounts to 200. For a team running parallel CI jobs, that ceiling is hit fast. The built-in pull-through cache makes the rate limit invisible - every `docker pull` goes through your own registry after the first hit, and your entire team benefits automatically with no per-developer configuration.

**One tool. No clutter on your machine.**
The entire provisioning toolchain - Ansible, Galaxy collections, SSH utilities - runs inside a Docker container. You do not install anything on your laptop or CI runner beyond Docker itself. No version conflicts, no "works on my machine," no residual packages after you are done.

**A full registry in under 30 minutes.**
From a freshly created VPS with DNS records pointing at it, provisioning is complete - TLS certificates issued, firewall configured, both registries running - in a single session. No manual SSH steps, no copy-pasting commands from a wiki page.

**Your images never leave your server.**
Build artifacts from proprietary software contain your source code. Pushing to a third-party registry means trusting that registry with your IP. With this setup, images live on infrastructure you control, in a jurisdiction you choose.

**Security that does not require a checklist.**
TLS 1.2/1.3 only, HSTS with a two-year max-age, bcrypt-hashed credentials, and a default-deny firewall are all configured by the provisioning playbooks - not as optional hardening steps, but as the starting point. There is nothing to forget to enable.

**Re-run anything, safely.**
All provisioning playbooks are idempotent. Re-running `make server` after a config change, a failed step, or a team member's first setup applies only what changed and leaves everything else untouched. No state to track, no teardown required.

---

> *"I built this because I kept hitting Docker Hub rate limits in CI and did not want to pay for a managed registry I could run myself on a VPS I was already paying for. It has been running in production for years with zero maintenance beyond the occasional `make upgrade`. I use it on every project."*
>
> - Romans Korolovs, author

---

## Self-hosted vs. GitHub Container Registry

GitHub Container Registry (GHCR) is the most common alternative for teams already on GitHub. The honest answer is that GHCR is the right choice for some teams - and this project is the right choice for others.

**Choose this project when:**

| Situation | Why self-hosted wins |
|---|---|
| Docker Hub rate limits are hitting your CI | GHCR stores your images but **cannot proxy Docker Hub**. The pull-through cache is the only clean fix. |
| You are already paying for a VPS | The registry runs on infrastructure you pay for regardless - marginal cost is zero. |
| High pull volume in CI | GHCR charges for data out. Pulling a 1 GB image across 50 CI runs/day is ~1.5 TB/month. On your own VPS that is $0. |
| Non-GitHub CI (GitLab, Jenkins, Buildkite) | No `GITHUB_TOKEN` shortcut - GHCR credential management becomes manual. |
| Data locality requirements | Images stay on your server, in your jurisdiction. Note: auth is single-tier `htpasswd` - no per-user RBAC or audit logging. |

**Choose GHCR when:**

| Situation | Why GHCR wins |
|---|---|
| Private image storage only, no rate limit problem | Simpler, zero-maintenance, no server to run. |
| Your CI is GitHub Actions | Authentication via `GITHUB_TOKEN` is automatic - no credential management. |
| Low ops tolerance | No disk to monitor, no garbage collection, no server to patch or recover. |
| Open source project | GHCR is free for public repositories with no storage or egress limits. |

The pull-through cache is the single capability GHCR cannot replicate. If that is not your pain point, weigh the operational cost of running your own server honestly before committing to it.

## Architecture

```
Internet
   │
   ▼
Caddy (80/443)
   │  Automatic TLS, HTTP→HTTPS redirect
   │
   ├── registry.example.com ──────────────▶ Registry (5000)
   │   Basic auth (htpasswd)                 Private image storage
   │
   └── cache-registry.example.com ────────▶ Cache Registry (5000)
                                              Docker Hub pull-through cache
```

Two independent registry containers run behind a single Caddy instance. The **private registry** stores your own images and requires authentication. The **cache registry** is a transparent pull-through proxy for Docker Hub - configure it as a registry mirror in your Docker daemon to avoid rate limits and speed up pulls. The Caddyfile is rendered by Ansible and mounted into the container from the host - it is not part of the deployed application files. Caddy obtains and renews TLS certificates itself and stores them in the `caddy_data` volume.

## Prerequisites

### Server requirements

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 1 vCPU | 1 vCPU |
| RAM | 512 MB | 1 GB |
| Disk free on `/` | 5 GB | 20 GB |
| Disk (registry data) | depends on image count | plan for growth |
| Network | 1 public IP, ports 80 and 443 open | - |

Provisioning targets a **fresh server**.

The production stack (Caddy + two registry containers) is lightweight - under 250 MB RSS at idle. The only variable is disk space for stored images, which can range from a few MB to several GB per image. A standard 1 vCPU / 1 GB RAM VPS with 40 GB total disk is a comfortable starting point for a small team.

### Supported operating systems

| Layer | Supported OS |
|---|---|
| Remote server | Ubuntu 22.04 LTS (Jammy) / 24.04 LTS (Noble) / 26.04 LTS (Resolute) - Debian 11 (Bullseye) / 12 (Bookworm) (any APT-based distro should work) |
| Control node (provisioning + deploy) | Linux, macOS |
| Local development (Docker only) | Linux, macOS, Windows |

### Required tools

| Tool | Purpose |
|---|---|
| Docker + Docker Compose plugin | Local development, production runtime, and provisioning toolbox |
| GNU Make | Makefile convenience targets (`make deploy`, `make up`, etc.) - pre-installed on macOS; install with `apt install make` on Debian/Ubuntu |
| SSH client (`ssh`, `scp`) | Deployment |
| SSH access to the server | Provisioning and deployment |
| Two DNS records pointed at the server | TLS certificate issuance (one per registry) |

Ansible, the Galaxy collections, and all other provisioning dependencies are bundled in the toolbox Docker image - nothing else needs to be installed locally.

## Getting Started

> Run every command from the project root. Provisioning commands start with `cd provisioning &&` - return to the project root (`cd ..`) before the next step.
>
> Steps **2** (Install your SSH key) and **7** (Authorize deploy user) are optional - skip them if your VPS provider installed your SSH key at server creation time.

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
| `ansible_port` | SSH port (default: `22`). If your server uses a non-default SSH port, set it here - every provisioning command connects on this port and the firewall allows it. |
| `registry_domain` | Domain for the private registry (e.g. `registry.example.com`) |
| `cache_registry_domain` | Domain for the cache registry (e.g. `cache-registry.example.com`) |
| `acme_email` | Email address for Let's Encrypt account and expiry notifications |
| `ssh_hardening` | Disable SSH password logins (default: `true`). Set to `false` if you need password logins - see [Security notes](#security-notes) |

Both domains must resolve to the server before the first deploy - Caddy requests certificates when it starts.

### 2. Install your SSH key on the server

> **Skip this step if your VPS provider already installed your SSH key at creation time** - most providers offer this during the server setup wizard. Only needed when your server was provisioned with password-only root access.

Run on your machine, not in the toolbox. `ssh-copy-id` ships with OpenSSH, asks for the root password once, and appends your public key to `/root/.ssh/authorized_keys`:

```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub -p <ssh-port> root@<server-ip>
```

Use the public key you normally log in with (`id_ed25519.pub`, `id_ecdsa.pub`, or `id_rsa.pub`). After this step, all provisioning commands use key-based authentication - the password is no longer needed, and step 6 disables SSH password logins entirely (unless you set `ssh_hardening: false`).

> **Want a non-default SSH port?** Change it now, before step 6 enables the firewall - see [Custom SSH port](#custom-ssh-port).

### 3. Generate registry credentials

Run from the project root, so the file sits where the step 8 example (`HTPASSWD_FILE=./htpasswd`) expects it.

The production `htpasswd` file must be created locally before deployment. Use bcrypt (`-B`) - other `htpasswd` formats such as MD5 and SHA are cryptographically weak, trivially crackable offline, and not accepted by Caddy.

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

Keep `htpasswd` out of version control - `.gitignore` ignores any file named `htpasswd`, wherever you create it.

### 4. Run preflight checks

Validates that all required inventory variables are set, SSH connectivity works, the server has sufficient disk space, and both DNS records resolve to the server. Run this before any other provisioning step - it catches the most common configuration mistakes upfront.

```bash
cd provisioning && ./provision make preflight
```

### 5. Upgrade the server

Update all system packages before installing anything. This ensures a clean security baseline and avoids Docker being installed on top of stale package lists. If a kernel upgrade was applied, the playbook reboots the server automatically and waits for it to come back up.

```bash
cd provisioning && ./provision make upgrade
```

### 6. Provision the server

Installs Docker Engine, creates the `deploy` system user, and renders the Caddyfile to `/etc/docker-registry/caddy/` on the server.

```bash
cd provisioning && ./provision make server
```

This requires root SSH access with your key. The playbook also disables SSH password logins unless `ssh_hardening` is `false` (see [Security notes](#security-notes)) and configures UFW with a default-deny incoming policy, allowing only SSH (on the port configured in `hosts.yml`), HTTP (80), and HTTPS (443, TCP and UDP for HTTP/3).

### 7. Authorize your SSH key for deployments

Copies your public key to the `deploy` user's `authorized_keys`. The playbook automatically detects your key type, checking for `id_ed25519`, `id_ecdsa`, and `id_rsa` in that order.

```bash
cd provisioning && ./provision make authorize
```

### 8. Deploy

Run from the project root. Transfers the compose file and `htpasswd` to the server atomically, then starts the stack. On first start Caddy obtains a certificate for both `registry_domain` and `cache_registry_domain`, which takes a few seconds.

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

To verify the registry works end-to-end, use `hello-world` - it is the smallest available image (~13 KB) and purpose-built for testing Docker infrastructure:

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

By default the cache registry proxies public Docker Hub images anonymously. To also cache private images or to raise the authenticated rate-limit tier, set Docker Hub credentials in `~/registry/.env` on the server - never in the compose file:

> **Warning:** the cache registry is public. Once credentials are set, every private Docker Hub image that account can access becomes pullable by anyone through your cache. Use an account (or a read-only access token) that can only see images you are comfortable exposing.

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

- **SSH:** `make server` writes `/etc/ssh/sshd_config.d/01-hardening.conf`, which disables password and keyboard-interactive logins and limits `root` to key-based login (`PermitRootLogin prohibit-password` - provisioning still connects as `root` with your key). The file sorts before cloud-init's `50-cloud-init.conf`, because sshd uses the first value it reads for these options, and the playbook fails if the effective settings do not match. Check them on the server with `sshd -T | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) '`. If you lose your SSH key, use your VPS provider's web console - password login over SSH no longer works. To keep password logins enabled, set `ssh_hardening: false` in `hosts.yml`; `make server` then removes `01-hardening.conf` again, so the setting can be switched either way at any time.
- **Security updates:** `make server` enables `unattended-upgrades`, which installs OS security updates daily. It uses the distribution's default origins, so packages from the Docker repository are never upgraded automatically, and it never reboots - use `make upgrade REBOOT=true` when a reboot is needed.
- **Firewall:** UFW is configured by the provisioning playbook with a default-deny incoming policy. Only SSH, HTTP, and HTTPS are open. All other ports are blocked.
- **Authentication:** Only the private registry (`registry_domain`) requires credentials. The cache registry is intentionally public and unauthenticated - anyone who can reach port 443 can pull through it. This is safe for public Docker Hub images, but see the warning below about Docker Hub credentials.
- **TLS:** Both registries use TLS 1.2/1.3 only. HSTS with a two-year max-age is enforced. Certificates are issued and renewed automatically by Caddy.
- **htpasswd:** Use bcrypt (`-B` flag). The Caddyfile is configured for bcrypt hashes; `make deploy` converts the `htpasswd` file to Caddy's format on the server.
- **Credentials file:** `htpasswd` and `provisioning/hosts.yml` are listed in `.gitignore`. Never commit either file.
- **HTTP secret:** Registry v3 logs a startup warning if no HTTP secret is set. On a single-node deployment this is harmless - the secret only matters when multiple registry instances share a load-balancer (session stickiness for uploads). To suppress the warning, add `REGISTRY_HTTP_SECRET=<random-string>` to `~/registry/.env` on the server.
- **SSH host key checking:** The provisioning toolbox runs Ansible inside a Docker container where `~/.ssh` is mounted read-only and owned by the host user. SSH refuses config files it does not own, so `ansible.cfg` sets `host_key_checking = False` and `-F /dev/null` to skip the SSH config file entirely. This means provisioning commands do not verify the server's host key against a known-hosts file. The risk is low for a server you own and provisioned yourself, but be aware that a compromised DNS or network MITM would not be detected. Provision over a trusted network.

## Custom SSH port

Moving SSH off port 22 cuts down automated scanning and brute-force noise in the auth logs. It is not a substitute for key-based authentication and a firewall.

Pick the path that matches your server:

- [Fresh server](#fresh-server) - before `make server` has run (recommended: the firewall is not active yet)
- [Already provisioned server](#already-provisioned-server) - UFW is active, so open the new port first
- [At server creation with cloud-init](#at-server-creation-with-cloud-init) - set the port before you ever log in

### Fresh server

Change the port **before** `make server`. UFW is still inactive at that point, so a mistake cannot lock you out at the firewall, and `make server` then enables UFW with only the new port allowed - port 22 is never opened.

1. Log in on the current port and **keep this session open** until step 3 succeeds:

   ```bash
   ssh -p 22 root@<server-ip>
   ```

   On the server, set the new port in a drop-in file, check it, and restart SSH:

   ```bash
   echo "Port 2222" > /etc/ssh/sshd_config.d/10-port.conf
   sshd -t
   sshd -T | grep '^port '
   systemctl daemon-reload
   if systemctl is-active --quiet ssh.socket; then
       systemctl restart ssh.socket
   else
       systemctl restart ssh
   fi
   ```

   Before restarting, check the output: `sshd -t` must print nothing, and `sshd -T | grep '^port '` must print only `port 2222` - see [Why a drop-in file](#why-a-drop-in-file) if it also shows `port 22`. Ubuntu 24.04 and later start SSH through `ssh.socket`; Debian and older Ubuntu use the `ssh` service - the `if` handles both.

2. If your VPS provider has a cloud firewall (Hetzner, AWS, DigitalOcean, and others), allow the new TCP port there. This is the most common reason a new port appears unreachable.

3. From a **new** terminal, confirm the new port works:

   ```bash
   ssh -p 2222 root@<server-ip>
   ```

   If it fails, fix it from the session you kept open, or from your provider's web console.

4. Set `ansible_port: 2222` in `provisioning/hosts.yml`, then continue with the normal steps - `./provision make preflight` confirms Ansible connects on the new port.

### Already provisioned server

UFW is active, so follow the [Fresh server](#fresh-server) steps with two additions: allow the new port before restarting SSH in step 1, and remove the old rule only after step 3 succeeds.

```bash
ufw allow 2222/tcp          # before the restart in step 1
ufw delete allow 22/tcp     # after step 3 succeeds
```

### At server creation with cloud-init

Most providers accept cloud-init user data when you create a server. This sets the port before you ever log in; then continue with step 2 of [Fresh server](#fresh-server):

```yaml
#cloud-config
write_files:
  - path: /etc/ssh/sshd_config.d/10-port.conf
    content: "Port 2222\n"
runcmd:
  - [systemctl, daemon-reload]
  - [sh, -c, "systemctl restart ssh.socket 2>/dev/null || systemctl restart ssh"]
```

### Why a drop-in file

The commands above write `/etc/ssh/sshd_config.d/10-port.conf` instead of editing `/etc/ssh/sshd_config`:

- **Package upgrades stay clean.** Files in `sshd_config.d/` are never touched by upgrades, while an edited main config triggers conffile prompts on `openssh-server` upgrades.
- **`Port` values are combined, not overridden.** Unlike most settings, sshd listens on every `Port` from every config file. If the main config still has an uncommented `Port 22` line, SSH listens on both ports. Fresh installs ship it commented out (`#Port 22`); otherwise comment it out first.
- **Single-value settings work the other way.** For options such as `PasswordAuthentication`, the first value read wins, and `sshd_config.d/` is read before the rest of the main config - so an edit to the main config can be silently overridden by a drop-in like cloud-init's `50-cloud-init.conf`. This is why `make server` names its hardening file `01-hardening.conf` (see [Security notes](#security-notes)).

## Day-2 operations

### Check server status

Shows live state of all containers, disk usage, firewall rules, TLS certificate expiry, and external API reachability - without changing anything on the server. Run this before any Day-2 operation to confirm the server is healthy.

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

### Upgrade system packages

Security updates install automatically every day (see [Security notes](#security-notes)). For a full upgrade of all packages:

```bash
cd provisioning && ./provision make upgrade
```

If the upgrade needs a reboot (for example a new kernel), the command says so but does not reboot. Reboot when convenient - the registry is unavailable for about a minute:

```bash
cd provisioning && ./provision make upgrade REBOOT=true
```

### TLS certificates

Caddy renews certificates automatically, roughly 30 days before expiry, with no cron job or reload step. Check the remaining validity with `./provision make status`. Certificates live in the `registry_caddy_data` volume - never delete it, or Caddy has to request new certificates and may hit Let's Encrypt rate limits.

### Update Caddy configuration

The Caddyfile is managed by Ansible. After editing `registry_domain`, `cache_registry_domain`, `acme_email`, or `provisioning/roles/docker-registry/templates/Caddyfile.j2`, re-provision to push the change:

```bash
cd provisioning && ./provision make server
```

Caddy reloads the new config automatically - no restart needed.

### Delete images and run garbage collection

The API can delete image manifests, but the underlying layer blobs remain on disk until garbage collection is run. Deleting is a two-step process.

**Step 1 - delete the manifest via the API:**

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

**Step 2 - run garbage collection:**

```bash
cd provisioning && ./provision make gc
```

Garbage collection is stop-the-world: a layer pushed during the sweep could be deleted. `make gc` therefore restarts the private registry in read-only mode, runs the collection, and restarts it in read-write mode afterwards - even if the collection fails. Pulls keep working throughout, apart from a few seconds during each restart; pushes are refused with HTTP 405 until it finishes.

The cache registry is not garbage collected: it removes cached content on its own once `REGISTRY_PROXY_TTL` (168h) expires.

### Back up registry data

Only the private registry volume needs backing up - the cache re-populates automatically from Docker Hub on the next pull. Optionally also back up `registry_caddy_data` so a server rebuild reuses the existing TLS certificates instead of requesting new ones.

See [`docs/backup-plan.md`](docs/backup-plan.md) for the full implementation plan, including a ready-to-use backup script, an Ansible role for provisioning secrets and a cron job, and a step-by-step restore procedure.

### Add or rotate registry credentials

Regenerate the `htpasswd` file locally, then redeploy:

```bash
htpasswd -Bc htpasswd <username>
make deploy HOST=<server-ip> PORT=<ssh-port> HTPASSWD_FILE=./htpasswd
```

`make deploy` reloads Caddy after updating the credentials, so the change takes effect immediately.

### Update Docker image versions

Images are pinned to `major.minor.patch` so updates are always explicit and reproducible. To upgrade, find the new tag on Docker Hub, update both `compose.yml` and `compose-production.yml`, then redeploy:

```bash
make deploy HOST=<server-ip> PORT=<ssh-port> HTPASSWD_FILE=./htpasswd
```

| Image | Tag strategy | Rationale |
|---|---|---|
| `caddy` | `2.11.6-alpine` | Caddy 2 stable series. |
| `registry` | `3.1.2` | Registry v3 is the current actively-maintained series; v2 received its last update in February 2025. |

### Update Ansible Galaxy collections

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

The development stack exposes the private registry on port `5000` and the cache registry on port `5001`. It uses Caddy with a pre-configured users file and plain HTTP - no TLS.

```bash
make init   # Pull images and start all services
make up     # Start services
make down   # Stop services
```

| Service | URL |
|---|---|
| Private registry | `http://localhost:5000` |
| Cache registry | `http://localhost:5001` |

Dev credentials are defined in `docker/development/caddy/users` (Caddy format: `username bcrypt-hash`). Docker automatically allows plain HTTP for loopback addresses (`127.0.0.1`), so no `--insecure-registry` flag is needed.

Test that the registry is reachable (replace `<password>` with the dev password):

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
│   └── development/caddy/
│       ├── Caddyfile                  # Dev Caddy config (no TLS)
│       └── users                      # Dev credentials (not for production)
└── provisioning/
    ├── Dockerfile                     # Provisioning toolbox image
    ├── provision                      # Wrapper script - runs make inside the toolbox container
    ├── ansible.cfg                    # Ansible configuration
    ├── Makefile                       # Provisioning commands
    ├── requirements.yml               # Ansible Galaxy roles and collections
    ├── hosts.yml.dist                 # Inventory template - copy to hosts.yml
    ├── preflight.yml                  # Pre-provisioning validation playbook
    ├── server.yml                     # Main provisioning playbook
    ├── authorize.yml                  # SSH key authorization playbook
    ├── upgrade.yml                    # System upgrade playbook
    ├── status.yml                     # Live server status (containers, disk, firewall, TLS, API)
    ├── logs.yml                       # Tail container logs from both registries
    ├── gc.yml                         # Garbage collection for private and cache registries
    └── roles/
        ├── ssh-hardening/             # Disables SSH password logins
        ├── security-updates/          # Daily unattended OS security updates
        ├── ufw/                       # Configures UFW firewall rules
        ├── docker/                    # Installs Docker Engine
        ├── create-deploy-user/        # Creates the deploy system user
        └── docker-registry/           # Deploys the Caddyfile
            └── templates/
                └── Caddyfile.j2
```

## Roadmap

Planned improvements, listed in the order they are expected to land.

### Monitoring and alerting

Today the only health check is running `make status` by hand - a full disk or a stopped registry is first noticed when CI jobs fail. The plan adds two complementary layers, both on free tiers:

- **External checks** (UptimeRobot or Better Stack) probe both registries from the internet every few minutes: `https://<registry_domain>/v2/` must return 401, `https://<cache_registry_domain>/v2/` must return 200, and certificate expiry is tracked for both domains. This catches DNS, firewall, TLS, and reachability problems.
- **Heartbeat from the server** (Healthchecks.io). An Ansible role installs a small script that cron runs every 5 minutes. It checks that disk usage on `/` is below 85% and that all three containers report `healthy`, then pings a check URL - or pings its `/fail` endpoint with the reason. If the server goes down, the pings stop and Healthchecks.io raises the alert after the grace period.
- `make gc` reports to the same check, so failed garbage collection runs are noticed too.

Planned implementation:
- Ansible role for the heartbeat script and cron job, with the ping URL as an inventory variable
- README setup guide for the external checks

### Encrypted inventory

`provisioning/hosts.yml`, `htpasswd`, and server secrets currently exist only on the operator's machine. Losing that machine means reconstructing them, and switching servers overwrites the only inventory. Because this repository is public, the real inventory must never be committed here either.

Planned implementation:
- Real inventory, secrets, and `htpasswd` kept in a separate private repository, encrypted with `ansible-vault` (already included in the toolbox image - no new tools)
- `INVENTORY ?= hosts.yml` in the provisioning Makefile, so the inventory can live outside this repository and several servers can be managed side by side
- Vault password supplied by a password-manager script via `--vault-password-file`; `./provision` already forwards `ANSIBLE_*` variables into the container
- `make deploy` decrypts `htpasswd` to a temporary file for the upload

### Object storage backend

The registry supports S3-compatible storage natively. The planned change moves image data off the server disk to Cloudflare R2 (free egress, generous free tier) or AWS S3, making the server stateless - pure compute with no persistent data.

The key operational benefit: if the server dies, provision a fresh VPS, point the new registry at the same bucket, and recovery is complete in ~15 minutes. No data is lost because the data was never on the server. Disk space monitoring for the private registry becomes a non-issue. Garbage collection is still needed to free bucket storage, but no longer risks filling the server disk.

Image layer downloads are redirected to presigned bucket URLs by default, so pulls are served directly by R2 rather than through the VPS - server bandwidth stops being a bottleneck.

Object storage protects against a failed disk or server, not against deletion: a garbage collection bug or leaked credentials could still empty the bucket. A nightly copy to a second provider (for example Backblaze B2) covers that case and replaces the stop-and-sync approach in [`docs/backup-plan.md`](docs/backup-plan.md) with a bucket-to-bucket copy that needs no downtime.

Planned implementation:
- R2 bucket and a bucket-scoped access token created once in the Cloudflare dashboard (documented step - keeps a broad Cloudflare API token out of the inventory)
- Private registry configured to use the S3 storage driver; the cache registry stays on local disk, since its content can always be re-fetched from Docker Hub
- Provider-neutral inventory variables (`registry_s3_*`, never `r2_*`), so switching between R2, AWS S3, Backblaze B2, Hetzner, or MinIO is a configuration change plus an `rclone sync` of the bucket - no code changes
- An explicit `registry_s3_type` variable, either `aws` or `s3-compatible`, instead of inferring the provider from an empty endpoint. `s3-compatible` adds `regionendpoint` and `forcepathstyle: true` (required by registry v3 for non-AWS endpoints); `aws` sets neither. Two values rather than one per provider, because every non-AWS service needs identical driver settings
- Preflight and role assertions that reject invalid combinations: an unknown type, `s3-compatible` without `registry_s3_endpoint`, or `aws` with a leftover endpoint
- Credentials stored as inventory variables and rendered by Ansible into a root-only env file loaded by the registry container - never hardcoded in compose files
- Migration of existing images with `rclone sync` (the on-disk layout and the bucket layout are identical)
- Nightly bucket copy to a second provider
