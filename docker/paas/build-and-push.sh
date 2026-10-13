#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker Engine and the Docker Buildx plugin are required." >&2
  exit 1
fi

: "${IMAGE_NAMESPACE:?Set IMAGE_NAMESPACE, e.g. docker.io/myaccount}"
: "${IMAGE_TAG:?Set IMAGE_TAG, e.g. 0.1.0}"
DEBIAN_MIRROR="${DEBIAN_MIRROR:-https://deb.debian.org}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.org/simple}"

api_image="${IMAGE_NAMESPACE%/}/hesabix-backend:${IMAGE_TAG}"
database_image="${IMAGE_NAMESPACE%/}/hesabix-postgres-seeded:${IMAGE_TAG}"

docker buildx build --platform linux/amd64 --push \
  --build-arg "DEBIAN_MIRROR=$DEBIAN_MIRROR" \
  --build-arg "PIP_INDEX_URL=$PIP_INDEX_URL" \
  --file docker/backend/Dockerfile \
  --tag "$api_image" .

docker buildx build --platform linux/amd64 --push \
  --file docker/paas/postgres.Dockerfile \
  --tag "$database_image" .

cat <<EOF
Published images:
  API_IMAGE=$api_image
  DATABASE_IMAGE=$database_image

Use these exact values in docker-compose.parspack.yml / the PaaS .env settings.
EOF
