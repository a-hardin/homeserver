#!/bin/sh
# Pull-based deploy: apply origin/master if it has commits that haven't been deployed yet.
# Safe to run by hand. On the server it runs every 5 minutes from a systemd timer
# (system/systemd/homeserver-deploy.timer). Logs: journalctl -u homeserver-deploy
set -eu
cd "$(dirname "$0")/.."

marker=.git/deployed-rev    # last commit deployed cleanly; a failed deploy retries
failed=.git/deploy-failed   # last failed commit notified; its retries stay quiet
target=unknown
step=fetch

# POST the result to n8n if DEPLOY_WEBHOOK_URL is set in .env. Retries while n8n restarts.
notify() {
    url=$(sed -n 's/^DEPLOY_WEBHOOK_URL=//p' .env 2>/dev/null || true)
    [ -n "$url" ] || return 0
    subject=$(git log -1 --format=%s "$target" 2>/dev/null | sed 's/\\/\\\\/g; s/"/\\"/g')
    curl -fsS -m 10 --retry 6 --retry-delay 10 --retry-all-errors \
        -H 'Content-Type: application/json' \
        -d "{\"status\":\"$1\",\"commit\":\"$target\",\"message\":\"$subject\",\"step\":\"$step\",\"host\":\"$(hostname)\"}" \
        "$url" >/dev/null || echo "notify failed"
}

on_exit() {
    [ $? -ne 0 ] || return 0
    [ "$(cat "$failed" 2>/dev/null)" != "$target" ] || return 0
    echo "$target" > "$failed"
    notify failure
}
trap on_exit EXIT

git fetch --quiet origin master
target=$(git rev-parse origin/master)
if [ -f "$marker" ] && [ "$(cat "$marker")" = "$target" ]; then
    rm -f "$failed"
    exit 0
fi

echo "==> deploying $(git rev-parse --short "$target")"

# --ff-only refuses to deploy if someone edited files directly on the server
step=pull
git merge --ff-only origin/master

# Checks out the static site commits pinned in this repo, not the latest of each site
step=submodules
git submodule update --init --recursive

# Validate against the real .env before touching any container
step=compose-config
docker compose config -q

# Only recreates containers whose config changed. Does not pull newer images or rebuild.
step=compose-up
docker compose up -d

step=nginx
docker exec nginx nginx -t
docker exec nginx nginx -s reload

echo "$target" > "$marker"
rm -f "$failed"
echo "==> deployed $(git rev-parse --short "$target")"
step=done
notify success