FROM postgres:17

# The initial data dump is baked into this one-time initialization image because
# ParsPack PaaS does not support bind mounts or Compose build instructions.
COPY backup/hesabix_seed_*.dump /docker-entrypoint-initdb.d/hesabix-seed.dump
COPY docker/paas/10-import-hesabix-seed.sh /docker-entrypoint-initdb.d/10-import-hesabix-seed.sh
RUN chmod 0555 /docker-entrypoint-initdb.d/10-import-hesabix-seed.sh
