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
  wt="$(mktemp -d)/wt"
  if git fetch -q origin +refs/heads/ci-logs:refs/remotes/origin/ci-logs 2>/dev/null; then
    git worktree add -q -B ci-logs-publish "$wt" origin/ci-logs
  else
    git worktree add -q --detach "$wt" && (cd "$wt" && git checkout -q --orphan ci-logs-publish && git rm -rf -q .)
  fi
  mkdir -p "$wt/logs/$name" && cp "$tmp"/* "$wt/logs/$name/" 2>/dev/null || true
  if (cd "$wt" && git add -A logs && git commit -qm "logs $name" && git push -q origin HEAD:refs/heads/ci-logs); then
    git worktree remove --force "$wt"; exit 0
  fi
  git worktree remove --force "$wt" || true
  sleep $((attempt * 4))
done
echo "could not publish logs"
