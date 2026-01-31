#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="${MANIFEST:-$ROOT/workspace.yaml}"
GITIGNORE="$ROOT/.gitignore"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need git
need yq

repos_b64() { yq -r '.repos[] | tojson | @base64' "$MANIFEST"; }
field() { echo "$1" | base64 --decode | yq -r "$2"; }

ensure_ignored() {
  mkdir -p "$ROOT"
  touch "$GITIGNORE"

  local path="$1"

  # Add "path/" to .gitignore if not present
  if ! grep -qxF "$path/" "$GITIGNORE"; then
    echo "$path/" >> "$GITIGNORE"
    echo "[workspace] added to .gitignore: $path/"
  fi
}

cmd="${1:-}"
shift || true

case "$cmd" in
  clone)
    for r in $(repos_b64); do
      name="$(field "$r" '.name')"
      url="$(field "$r" '.url')"
      branch="$(field "$r" '.branch')"
      path="$(field "$r" '.path')"

      ensure_ignored "$path"

      if [ -d "$ROOT/$path/.git" ]; then
        echo "[skip] $name already cloned at $path"
        continue
      fi

      echo "[clone] $name -> $path"
      git clone --branch "$branch" "$url" "$ROOT/$path"
    done
    ;;

  pull)
    for r in $(repos_b64); do
      name="$(field "$r" '.name')"
      path="$(field "$r" '.path')"

      if [ ! -d "$ROOT/$path/.git" ]; then
        echo "[missing] $name not cloned (run: ws clone)"
        continue
      fi

      echo "[pull] $name"
      (cd "$ROOT/$path" && git fetch origin && git pull --ff-only)
    done
    ;;

  update-main)
    for r in $(repos_b64); do
      name="$(field "$r" '.name')"
      path="$(field "$r" '.path')"
      branch="$(field "$r" '.branch')"

      if [ ! -d "$ROOT/$path/.git" ]; then
        echo "[missing] $name not cloned (run: ws clone)"
        continue
      fi

      echo "[update] $name ($branch)"
      (
        cd "$ROOT/$path"
        git fetch origin
        git checkout "$branch" >/dev/null 2>&1 || git checkout -b "$branch" "origin/$branch"
        git pull --ff-only
      )
    done
    ;;

  status)
    for r in $(repos_b64); do
      name="$(field "$r" '.name')"
      path="$(field "$r" '.path')"

      echo "== $name =="
      if [ ! -d "$ROOT/$path/.git" ]; then
        echo "(not cloned)"
      else
        (cd "$ROOT/$path" && git status --porcelain=v1 -b)
      fi
      echo
    done
    ;;

  add)
    # Usage: ws add repo3 git@github.com:org/repo3.git main
    name="${1:?name required}"
    url="${2:?url required}"
    branch="${3:-main}"
    path="${4:-$name}"

    # Append repo entry to workspace.yaml
    yq -i ".repos += [{\"name\":\"$name\",\"url\":\"$url\",\"branch\":\"$branch\",\"path\":\"$path\"}]" "$MANIFEST"
    ensure_ignored "$path"
    echo "[workspace] added to manifest: $name ($path)"
    echo "Next: ./scripts/ws clone"
    ;;

  *)
    cat <<EOF
Usage: ./ws.sh <command>

Commands:
  clone         Clone all repos from workspace.yaml into workspace/
  pull          Fast-forward pull all cloned repos
  update-main   Fetch + fast-forward each repo's configured branch
  status        Show branch + dirty status for each repo
  add           Add a repo to workspace.yaml and .gitignore

Examples:
  ./ws clone
  ./ws status
  ./ws add repo3 git@github.com:org/repo3.git main
EOF
    exit 1
    ;;
esac