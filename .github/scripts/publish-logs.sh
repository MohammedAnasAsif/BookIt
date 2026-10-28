#!/usr/bin/env bash
# Copies CI log files to the `ci-logs` branch so they can be read without
# access to the Actions log storage. Usage: publish-logs.sh <name> <files...>
set -u
name="$1"; shift
tmp="$(mktemp -d)"
for f in "$@"; do [ -f "$f" ] && cp "$f" "$tmp/" ; done
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
for attempt in 1 2 3 4 5 6; do
  work="$(mktemp -d)"
  if git clone -q --depth 1 --branch ci-logs "$(git remote get-url origin)" "$work" 2>/dev/null; then :; else
    git clone -q --depth 1 "$(git remote get-url origin)" "$work" && (cd "$work" && git checkout -q --orphan ci-logs && git rm -rf -q .)
  fi
  mkdir -p "$work/logs/$name" && cp "$tmp"/* "$work/logs/$name/" 2>/dev/null || true
  (cd "$work" && git add -A logs && git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" commit -qm "logs $name" && git push -q origin ci-logs) && exit 0
  sleep $((attempt * 4))
done
echo "could not publish logs"
