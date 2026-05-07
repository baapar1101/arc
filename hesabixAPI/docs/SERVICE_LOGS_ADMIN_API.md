# Service logs admin API (`/api/v1/admin/system-services`)

The UI path **Profile → System settings → Service logs** calls these endpoints. They run `journalctl` and `systemctl` on the **same host** as the API process.

## When it works

- Linux with **systemd**.
- `journalctl` and `systemctl` are on `PATH` for the API process.
- Journald on that host actually contains logs for the allowed units (`hesabix-api`, `hesabix-rq-worker`, `hesabix-notification-moderation`).

## When it returns 503

- API runs on **Windows** or macOS (no host journald for those units).
- API runs in a **container** without access to the host journal.
- `journalctl` fails (permission, missing unit on that host, etc.). The API may include a short preview under `error.details.journalctl_preview` for debugging.

## Optional sudo fallback for journalctl

If the API user cannot read journald directly, you can allow a tightly-scoped non-interactive sudo fallback.

1) Set:

```bash
HESABIX_ALLOW_SUDO_JOURNALCTL=1
```

2) Add a restricted sudoers rule for the API runtime user (example):

```sudoers
hesabix ALL=(root) NOPASSWD: /usr/bin/journalctl
```

The API uses `sudo -n journalctl ...` only when direct `journalctl` fails with a permission-style error (or when the env is enabled explicitly).

## Docker: give the API container host journal access

Mount the host journal socket (preferred on most distros):

```yaml
services:
  hesabix-api:
    volumes:
      - /run/systemd/journal/socket:/run/systemd/journal/socket
```

If your distro layout differs, alternatives people use include read-only mounts of journal data paths (e.g. `/var/log/journal`); keep host and image journald versions compatible and prefer the **socket** pattern when available.

The user inside the container should be allowed to read the journal (often: add the runtime user to group `systemd-journal` on the **host** numeric GID mapped into the container, or run with a user that already has journal access—policy depends on your image).

## Restart (`POST .../restart`)

`systemctl restart` usually requires elevated privileges. Typical patterns:

- Run the API service on the host under systemd with a **sudoers** rule allowing only `systemctl restart` for the allowlisted units, or
- Use a small **root** sidecar / helper that only exposes restart, or
- Avoid restart from the panel in container-only setups and restart via your orchestrator.

## Security

These routes are protected by the **`system_settings`** app permission. They can leak operational detail and can disrupt services; restrict who has that permission and harden the host as above.

## See also

- Worker deployment and moderation service (includes the same REST examples): [`NOTIFICATION_MODERATION_WORKER_DEPLOYMENT.md`](./NOTIFICATION_MODERATION_WORKER_DEPLOYMENT.md)
- RQ worker systemd and `journalctl` usage: [`PHASE4_BACKGROUND_JOBS.md`](./PHASE4_BACKGROUND_JOBS.md)
