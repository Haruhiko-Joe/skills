#!/usr/bin/env bash
# Copy each delegation skill into the two hosts that call it (never into the host it delegates to).
# Rerun after editing a skill to refresh the copies.
# Usage: ./install-delegation.sh [--force]
#   --force  replace an existing skill directory of the same name
set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
force=0
for arg in "$@"; do
  case "$arg" in
    --force) force=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

install_skill() { # <skill> <host dir>
  local skill=$1 dir=$2 target="$2/$1"
  mkdir -p "$dir"
  if [ -e "$target" ] || [ -L "$target" ]; then
    if [ "$force" = 0 ]; then echo "skip     $target exists (rerun with --force to replace)"; return; fi
    rm -rf "$target"
  fi
  cp -R "$src/$skill" "$target"
  echo "copy     $target"
}

claude_dir=~/.claude/skills agy_dir=~/.gemini/config/skills codex_dir=~/.codex/skills

install_skill agy-delegation    "$claude_dir"
install_skill codex-delegation  "$claude_dir"
install_skill claude-delegation "$agy_dir"
install_skill codex-delegation  "$agy_dir"
install_skill claude-delegation "$codex_dir"
install_skill agy-delegation    "$codex_dir"

# A host must not see a skill that delegates to itself. Codex also reads ~/.agents/skills.
for target in "$claude_dir/claude-delegation" "$agy_dir/agy-delegation" \
              "$codex_dir/codex-delegation" ~/.agents/skills/codex-delegation; do
  if [ -e "$target" ]; then echo "warning  $target lets that host delegate to itself; remove it"; fi
done
