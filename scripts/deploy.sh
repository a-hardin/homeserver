#!/bin/sh
# Pull-based deploy: apply origin/master if it has commits that haven't been deployed yet.
# Safe to run by hand. On the server it runs from cron every 5 minutes:
#   */5 * * * * flock -n /tmp/homeserver-deploy.lock /var/www/homeserver/scripts/deploy.sh 2>&1 | logger -t homeserver-deploy
# Logs: journalctl -t homeserver-deploy
set -eu
cd "$(dirname "$0")/.."

# Last commit that deployed cleanly. A failed deploy leaves it unchanged, so the next run retries.
marker=.git/deployed-rev

git fetch --quiet origin master
target=$(git rev-parse origin/master)
if [ -f "$marker" ] && [ "$(cat "$marker")" = "$target" ]; then
    exit 0
fi

echo "==> deploying $(git rev-parse --short "$target")"

# --ff-only refuses to deploy if someone edited files directly on the server
git merge --ff-only origin/master

# Checks out the static site commits pinned in this repo, not the latest of each site
git submodule update --init --recursive

# Validate against the real .env before touching any container
docker compose config -q

# Only recreates containers whose config changed. Does not pull newer images or rebuild.
docker compose up -d

docker exec nginx nginx -t
docker exec nginx nginx -s reload

echo "$target" > "$marker"
echo "==> deployed $(git rev-parse --short "$target")"
