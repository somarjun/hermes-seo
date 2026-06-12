#!/usr/bin/env bash
set -euo pipefail

# Hermes SEO uninstaller (Unix / macOS / Linux)
# Removes orchestrator skill (~/.hermes/skills/seo), sub-skills (~/.hermes/skills/seo-*),
# and skill bundles installed by hermes-seo.

HERMES_SKILLS="${HOME}/.hermes/skills"
BUNDLES_DIR="${HOME}/.hermes/skill-bundles"

echo "→ Uninstalling Hermes SEO..."

removed_skills=0
removed_bundles=0

if [ -d "${HERMES_SKILLS}/seo" ]; then
    rm -rf "${HERMES_SKILLS}/seo"
    removed_skills=$((removed_skills + 1))
fi

for skill_dir in "${HERMES_SKILLS}"/seo-*; do
    [ -d "${skill_dir}" ] || continue
    rm -rf "${skill_dir}"
    removed_skills=$((removed_skills + 1))
done

for bundle in seo-audit.yaml seo-full.yaml; do
    if [ -f "${BUNDLES_DIR}/${bundle}" ]; then
        rm -f "${BUNDLES_DIR}/${bundle}"
        removed_bundles=$((removed_bundles + 1))
    fi
done

if [ "${removed_skills}" -eq 0 ] && [ "${removed_bundles}" -eq 0 ]; then
    echo "  Nothing to remove. Hermes SEO does not appear to be installed."
    exit 0
fi

echo "✓ Hermes SEO uninstalled (${removed_skills} skill dirs, ${removed_bundles} bundles)."
echo "  Restart Hermes Agent to complete removal."
