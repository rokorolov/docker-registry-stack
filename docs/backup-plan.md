# Registry Backup Implementation Plan

Automated daily backup of the private registry volume to S3-compatible storage.

---

## What to back up

Only the private registry volume needs backing up:

| Volume | Back up | Reason |
|---|---|---|
| `registry_registry` | Yes | Stores your own pushed images — irreplaceable |
| `registry_cache-registry` | No | Docker Hub pull-through cache — re-populates automatically on next pull |
| `registry_caddy_data` | Optional | Caddy's TLS certificates and ACME account — avoids re-issuance (and Let's Encrypt rate limits) after a server rebuild |

---

## Architecture

```
Production server (cron job, 3am daily)
    1. Stop registry container       ← ensures consistency, no mid-write layers
    2. aws s3 sync volume → S3       ← incremental, only changed blobs uploaded
    3. Start registry container
    4. Delete backups older than 30 days from S3
```

The registry is unavailable for ~30 seconds during backup. Acceptable for a personal/small
team registry. If zero-downtime backup is ever required, use `--read-only` mode instead of
stopping the container.

---

## New files to create

### 1. `docker/production/registry-backup/backup.sh`

Backup script:
- `set -o errexit` + `set -o pipefail`
- Reads secrets from `_FILE` variables (same Docker secrets pattern)
- Validates all required variables with `${VAR:?}`
- Stops registry → syncs to S3 → starts registry → prunes old backups
- Logs each step to stdout (captured by cron to syslog)

```bash
#!/bin/bash

set -o errexit
set -o pipefail

if [ -f "$AWS_ACCESS_KEY_ID_FILE" ]; then
  AWS_ACCESS_KEY_ID="$(cat "$AWS_ACCESS_KEY_ID_FILE")"
fi

if [ -f "$AWS_SECRET_ACCESS_KEY_FILE" ]; then
  AWS_SECRET_ACCESS_KEY="$(cat "$AWS_SECRET_ACCESS_KEY_FILE")"
fi

export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:?}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:?}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:?}"

REGISTRY_VOLUME="${REGISTRY_VOLUME:-/var/lib/docker/volumes/registry_registry/_data}"
S3_PATH="s3://${S3_BUCKET:?}/registry"

echo "Stopping registry..."
docker compose -f "${COMPOSE_FILE:?}" stop registry

echo "Syncing to S3..."
aws --endpoint-url="${S3_ENDPOINT:?}" s3 sync "$REGISTRY_VOLUME" "$S3_PATH" --delete

echo "Starting registry..."
docker compose -f "${COMPOSE_FILE:?}" start registry

echo "Pruning backups older than ${RETENTION_DAYS:-30} days..."
aws --endpoint-url="${S3_ENDPOINT}" s3 ls "${S3_PATH}/" \
    | awk '{print $4}' \
    | sort \
    | head -n "-${RETENTION_DAYS:-30}" \
    | xargs -r -I{} aws --endpoint-url="${S3_ENDPOINT}" s3 rm "${S3_PATH}/{}"

echo "Backup complete."
```

---

## Changes to existing files

### 2. `provisioning/hosts.yml.dist`

Add backup variables to the `all.vars` section so operators know what to configure:

```yaml
all:
    vars:
        registry_domain: registry.example.com
        cache_registry_domain: cache-registry.example.com
        acme_email: admin@example.com
        # Backup
        backup_aws_access_key_id: ""
        backup_aws_secret_access_key: ""
        backup_aws_default_region: ""
        backup_s3_endpoint: ""
        backup_s3_bucket: ""
```

### 3. New Ansible role: `provisioning/roles/registry-backup/tasks/main.yml`

Provisions secrets as protected files and installs the cron job:

```yaml
---
-   name: Configure registry backup
    become: true
    block:
        -   name: Create backup secrets directory
            ansible.builtin.file:
                path: /etc/docker-registry/secrets
                state: directory
                owner: root
                group: root
                mode: '0700'

        -   name: Write AWS access key ID
            ansible.builtin.copy:
                content: "{{ backup_aws_access_key_id }}"
                dest: /etc/docker-registry/secrets/aws_access_key_id
                owner: root
                group: root
                mode: '0400'

        -   name: Write AWS secret access key
            ansible.builtin.copy:
                content: "{{ backup_aws_secret_access_key }}"
                dest: /etc/docker-registry/secrets/aws_secret_access_key
                owner: root
                group: root
                mode: '0400'

        -   name: Copy backup script
            ansible.builtin.copy:
                src: ../../../docker/production/registry-backup/backup.sh
                dest: /usr/local/bin/registry-backup
                owner: root
                group: root
                mode: '0700'

        -   name: Install backup cron job
            ansible.builtin.cron:
                name: registry-backup
                job: >
                    AWS_ACCESS_KEY_ID_FILE=/etc/docker-registry/secrets/aws_access_key_id
                    AWS_SECRET_ACCESS_KEY_FILE=/etc/docker-registry/secrets/aws_secret_access_key
                    AWS_DEFAULT_REGION="{{ backup_aws_default_region }}"
                    S3_ENDPOINT="{{ backup_s3_endpoint }}"
                    S3_BUCKET="{{ backup_s3_bucket }}"
                    COMPOSE_FILE=/home/deploy/registry/compose.yml
                    /usr/local/bin/registry-backup 2>&1 | logger -t registry-backup
                minute: "0"
                hour: "3"
```

### 4. `provisioning/server.yml`

Add the new role:

```yaml
roles:
    - ufw
    - docker
    - create-deploy-user
    - docker-registry
    - registry-backup       ← add this
```

### 5. `provisioning/roles/docker-registry/tasks/main.yml`

Add assert validation for the new required backup variables:

```yaml
-   name: Validate required variables
    assert:
        that:
            - registry_domain is defined and registry_domain | length > 0
            - cache_registry_domain is defined and cache_registry_domain | length > 0
            - backup_aws_access_key_id is defined and backup_aws_access_key_id | length > 0
            - backup_aws_secret_access_key is defined and backup_aws_secret_access_key | length > 0
            - backup_s3_bucket is defined and backup_s3_bucket | length > 0
            - backup_s3_endpoint is defined and backup_s3_endpoint | length > 0
```

---

## Restore procedure

```bash
# 1. Stop the registry
ssh deploy@<server-ip> -p <port> 'cd registry && docker compose stop registry'

# 2. Sync from S3 back to the volume
ssh deploy@<server-ip> -p <port> \
    'AWS_ACCESS_KEY_ID=$(cat /etc/docker-registry/secrets/aws_access_key_id) \
     AWS_SECRET_ACCESS_KEY=$(cat /etc/docker-registry/secrets/aws_secret_access_key) \
     aws --endpoint-url=<s3-endpoint> s3 sync \
         s3://<bucket>/registry \
         /var/lib/docker/volumes/registry_registry/_data'

# 3. Start the registry
ssh deploy@<server-ip> -p <port> 'cd registry && docker compose start registry'
```

---

## README updates required

- Add a "Backup" section under Day-2 operations describing the automated cron job.
- Add restore instructions.
- Update the "Configure inventory" table with the new backup variables.
- Update the project structure tree with the new role and script.
