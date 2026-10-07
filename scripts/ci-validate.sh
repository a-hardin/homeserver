#!/bin/sh
# Validate docker-compose.yaml without the real .env files.
# Runs in CI (GitHub Actions) and locally: ./scripts/ci-validate.sh
# The nginx config is checked by the deploy job (nginx -t on the server, before reload).
set -eu
cd "$(dirname "$0")/.."

# title-exam's env_file is gitignored and compose refuses to parse without it
stub=system/title-exam/.env
if [ ! -e "$stub" ]; then
    mkdir -p "$(dirname "$stub")"
    : > "$stub"
    trap 'rm -f "$stub"' EXIT
fi

echo "==> docker compose config"
# .example.env stands in for the real .env (which is gitignored)
docker compose --env-file .example.env config -q

echo "OK"
