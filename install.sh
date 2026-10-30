#!/usr/bin/env bash
# Install skills from KHOA-SKILL-MCP into current project.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Kurtt806/KHOA-SKILL-MCP/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --all   # also install to .claude + .agents
set -euo pipefail

REPO="https://github.com/Kurtt806/KHOA-SKILL-MCP.git"
TMPDIR="${TMPDIR:-/tmp}/khoa-skills-$$"

cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required" >&2
  exit 1
fi

git clone --depth 1 "$REPO" "$TMPDIR" >/dev/null 2>&1

install_to() {
  mkdir -p "$1"
  cp -r "$TMPDIR/devops" "$1/devops"
  echo "installed -> $1/devops"
}

install_to ".opencode/skills"

if [ "${1:-}" = "--all" ]; then
  install_to ".claude/skills"
  install_to ".agents/skills"
fi

echo "done. verify: head -5 .opencode/skills/devops/SKILL.md"
