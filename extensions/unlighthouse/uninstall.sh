#!/usr/bin/env bash
set -euo pipefail
SKILL_DIR="${HOME}/.hermes/skills/seo-unlighthouse"
[ -d "${SKILL_DIR}" ] && rm -rf "${SKILL_DIR}" && echo "✓ Removed ${SKILL_DIR}"
echo "Done. (Nothing to remove from settings.json — Unlighthouse has no keys.)"
