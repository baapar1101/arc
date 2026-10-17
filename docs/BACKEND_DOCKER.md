# Backend-only Docker deployment

This deployment runs Hesabix API, PostgreSQL, Redis, and the backend workers. It does not install Flutter, Nginx, or the web client.

## Install

Requirements: Docker Engine with the Docker Compose v2 plugin, Git, and an internet connection. Run the installer as root on the server:

```bash
git clone --depth 1 https://source.hesabix.ir/hesabix/arc.git /tmp/hesabix-backend-installer
sudo bash /tmp/hesabix-backend-installer/docker/install-backend.sh
```

For an unattended install, the installer accepts these environment variables:

```bash
sudo REPO_URL=https://source.hesabix.ir/hesabix/arc.git BRANCH=main API_PORT=8000 bash docker/install-backend.sh
```

The installer creates `/opt/hesabix-backend/.env` with unique secrets, then builds the API image and starts the services. It imports the repository's initial database dump only when PostgreSQL has no tables. If a partially populated database is detected, installation stops without dropping or replacing its contents.

## Connect a client

Allow inbound TCP on the configured API port in the server firewall and cloud network rules. A client can use:

```text
http://SERVER_IP:8000
```

The health endpoint is `http://SERVER_IP:8000/api/v1/health`. The API container also serves the application's WebSocket endpoints on the same port. PostgreSQL and Redis are not published to the host network.

This direct-IP setup uses HTTP. For access over untrusted networks, put a TLS reverse proxy in front of the API and use its HTTPS address in the client.

## Update and manage

The backend-only management command is:

```bash
sudo hesabix-backend update
```

It fetches and checks out the configured repository branch, rebuilds the API image, runs the current database bootstrap check, and replaces the API and worker containers. Database migrations run before the API starts. The PostgreSQL data, uploaded files, voice data, and `/opt/hesabix-backend/.env` live outside the source checkout and are not replaced by this update.

Other commands:

```bash
sudo hesabix-backend status
sudo hesabix-backend logs api
sudo hesabix-backend restart
sudo hesabix-backend stop
sudo hesabix-backend start
sudo hesabix-backend backup
```

Database backups are written to `/opt/hesabix-backend/backups`. Keep a separate copy of backups for disaster recovery. Do not use `docker compose down -v`; removing volumes deletes the database and locally uploaded files.

To change the published port, edit `API_PORT` in `/opt/hesabix-backend/.env`, then run `sudo hesabix-backend update`.

## Deploy on ParsPack PaaS

The VPS Compose file above builds the API locally and bind-mounts the database seed, so it is not accepted by ParsPack PaaS. Use `docker-compose.parspack.yml` there: it references prebuilt images only and uses named volumes for persistent data.

Before uploading the Compose file, publish the API and seeded PostgreSQL images to a container registry ParsPack can access. The seeded database image contains the repository's initial database dump; keep it in a private registry unless you have verified that the seed is safe for public distribution. From the repository root, after logging in to that registry, run:

```bash
IMAGE_NAMESPACE=source.hesabix.ir/hesabix IMAGE_TAG=0.1.0 \
DEBIAN_MIRROR=https://mirrors.tuna.tsinghua.edu.cn \
PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
  bash docker/paas/build-and-push.sh
```

The script defaults to upstream Debian and PyPI indexes; the mirror settings above are useful in networks where those endpoints are not reachable. The published `0.1.0` images are `source.hesabix.ir/hesabix/hesabix-backend:0.1.0` and `source.hesabix.ir/hesabix/hesabix-postgres-seeded:0.1.0`.

Copy the printed `API_IMAGE` and `DATABASE_IMAGE` values into the `.env` uploaded to ParsPack along with `docker-compose.parspack.yml`. Start with `docker/paas/.env.example`, replace every placeholder with fresh secrets, and do not commit the filled `.env` file. These packages are private; configure ParsPack with a Forgejo token that can pull packages.

In the ParsPack application setup, make only `api` public and route it to container port `8000`. Keep `db` and `redis` internal. Assign persistent disks to `/var/lib/postgresql/data`, `/tmp/hesabix_files`, and `/var/lib/hesabix/voice-data`; assign `/data` to Redis if Redis persistence is desired. The seed import runs only when PostgreSQL first initializes an empty data volume. Subsequent image deployments keep the database and uploaded files in their persistent volumes. Never delete those volumes during an update.

To update in PaaS, build and publish new version tags, then update `API_IMAGE` (and `DATABASE_IMAGE` only when changing the seed/base database image) in the PaaS environment and redeploy. The `hesabix-backend update` command applies to the VPS installation, not to PaaS.

ParsPack documents that `build:` and bind mounts are unsupported, but its public guide does not specify all Compose dependency/health-check behavior or registry-auth details. Confirm private-registry access and service startup ordering in the PaaS panel before using this for production.
