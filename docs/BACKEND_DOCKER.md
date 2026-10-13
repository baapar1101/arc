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
