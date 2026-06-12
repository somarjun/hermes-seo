#!/usr/bin/env bash
set -euo pipefail

# Hermes SEO Installer
# Installs skills to ~/.hermes/skills/ for Hermes Agent
# Docs: https://hermes-agent.nousresearch.com/docs/user-guide/features/skills

main() {
    HERMES_SKILLS="${HOME}/.hermes/skills"
    SKILL_DIR="${HERMES_SKILLS}/seo"
    BUNDLES_DIR="${HOME}/.hermes/skill-bundles"
    REPO_URL="https://github.com/somarjun/hermes-seo"
    REPO_TAG="${HERMES_SEO_TAG:-main}"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    SOURCE_DIR="${HERMES_SEO_SOURCE:-${SCRIPT_DIR}}"

    echo "════════════════════════════════════════"
    echo "║   Hermes SEO - Installer             ║"
    echo "║   Hermes Agent SEO Skill Suite       ║"
    echo "════════════════════════════════════════"
    echo ""

    command -v python3 >/dev/null 2>&1 || { echo "✗ Python 3 is required but not installed."; exit 1; }

    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    PYTHON_OK=$(python3 -c 'import sys; print(1 if sys.version_info >= (3, 10) else 0)')
    if [ "${PYTHON_OK}" = "0" ]; then
        echo "✗ Python 3.10+ is required but ${PYTHON_VERSION} was found."
        exit 1
    fi
    echo "✓ Python ${PYTHON_VERSION} detected"

    if command -v hermes >/dev/null 2>&1; then
        echo "✓ Hermes Agent CLI detected"
    else
        echo "⚠  Hermes CLI not found. Install: curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash"
    fi

    mkdir -p "${HERMES_SKILLS}" "${SKILL_DIR}" "${BUNDLES_DIR}"

    TEMP_DIR=""
    if [ -d "${SOURCE_DIR}/skills" ]; then
        echo "→ Installing from local source: ${SOURCE_DIR}"
        WORK_DIR="${SOURCE_DIR}"
    else
        command -v git >/dev/null 2>&1 || { echo "✗ Git is required for remote install."; exit 1; }
        TEMP_DIR=$(mktemp -d)
        trap "rm -rf ${TEMP_DIR}" EXIT
        echo "↓ Downloading Hermes SEO (${REPO_TAG})..."
        git clone --depth 1 --branch "${REPO_TAG}" "${REPO_URL}" "${TEMP_DIR}/hermes-seo"
        WORK_DIR="${TEMP_DIR}/hermes-seo"
    fi

    echo "→ Installing skill files..."
    cp -r "${WORK_DIR}/skills/seo/"* "${SKILL_DIR}/"

    for skill_dir in "${WORK_DIR}/skills"/*/; do
        skill_name=$(basename "${skill_dir}")
        target="${HERMES_SKILLS}/${skill_name}"
        mkdir -p "${target}"
        cp -r "${skill_dir}"* "${target}/"
    done

    if [ -d "${WORK_DIR}/schema" ]; then
        mkdir -p "${SKILL_DIR}/schema"
        cp -r "${WORK_DIR}/schema/"* "${SKILL_DIR}/schema/"
    fi

    if [ -d "${WORK_DIR}/pdf" ]; then
        mkdir -p "${SKILL_DIR}/pdf"
        cp -r "${WORK_DIR}/pdf/"* "${SKILL_DIR}/pdf/"
    fi

    if [ -d "${WORK_DIR}/scripts" ]; then
        mkdir -p "${SKILL_DIR}/scripts"
        cp -r "${WORK_DIR}/scripts/"* "${SKILL_DIR}/scripts/"
        rm -f "${SKILL_DIR}/scripts/port_to_hermes.py" "${SKILL_DIR}/scripts/fix_hermes_port.py" 2>/dev/null || true
    fi

    if [ -d "${WORK_DIR}/hooks" ]; then
        mkdir -p "${SKILL_DIR}/hooks"
        cp -r "${WORK_DIR}/hooks/"* "${SKILL_DIR}/hooks/"
        chmod +x "${SKILL_DIR}/hooks/"*.sh 2>/dev/null || true
        chmod +x "${SKILL_DIR}/hooks/"*.py 2>/dev/null || true
    fi

    if [ -d "${WORK_DIR}/extensions" ]; then
        echo "→ Installing extensions..."
        for ext_dir in "${WORK_DIR}/extensions"/*/; do
            [ -d "${ext_dir}" ] || continue
            ext_name=$(basename "${ext_dir}")
            if [ -d "${ext_dir}skills" ]; then
                for ext_skill in "${ext_dir}skills"/*/; do
                    [ -d "${ext_skill}" ] || continue
                    ext_skill_name=$(basename "${ext_skill}")
                    target="${HERMES_SKILLS}/${ext_skill_name}"
                    mkdir -p "${target}"
                    cp -r "${ext_skill}"* "${target}/"
                done
            fi
            if [ -d "${ext_dir}agents" ]; then
                mkdir -p "${SKILL_DIR}/references/delegates"
                cp -r "${ext_dir}agents/"*.md "${SKILL_DIR}/references/delegates/" 2>/dev/null || true
            fi
            if [ -d "${ext_dir}references" ]; then
                mkdir -p "${SKILL_DIR}/extensions/${ext_name}/references"
                cp -r "${ext_dir}references/"* "${SKILL_DIR}/extensions/${ext_name}/references/"
            fi
            if [ -d "${ext_dir}scripts" ]; then
                mkdir -p "${SKILL_DIR}/extensions/${ext_name}/scripts"
                cp -r "${ext_dir}scripts/"* "${SKILL_DIR}/extensions/${ext_name}/scripts/"
            fi
        done
    fi

    if [ -d "${WORK_DIR}/skill-bundles" ]; then
        echo "→ Installing skill bundles..."
        cp "${WORK_DIR}/skill-bundles/"*.yaml "${BUNDLES_DIR}/" 2>/dev/null || true
    fi

    cp "${WORK_DIR}/requirements.txt" "${SKILL_DIR}/requirements.txt" 2>/dev/null || true

    echo "→ Installing Python dependencies..."
    VENV_DIR="${SKILL_DIR}/.venv"
    if python3 -m venv "${VENV_DIR}" 2>/dev/null; then
        "${VENV_DIR}/bin/pip" install --quiet -r "${WORK_DIR}/requirements.txt" 2>/dev/null && \
            echo "  ✓ Installed in venv at ${VENV_DIR}" || \
            echo "  ⚠  Venv pip install failed. Run: ${VENV_DIR}/bin/pip install -r ${SKILL_DIR}/requirements.txt"
    else
        pip install --quiet --user -r "${WORK_DIR}/requirements.txt" 2>/dev/null || \
        echo "  ⚠  Could not auto-install. Run: pip install --user -r ${SKILL_DIR}/requirements.txt"
    fi

    echo "→ Installing Playwright browsers (optional, for visual analysis)..."
    if [ -f "${VENV_DIR}/bin/playwright" ]; then
        "${VENV_DIR}/bin/python" -m playwright install chromium 2>/dev/null || \
        echo "  ⚠  Playwright install failed. Visual analysis will use web_extract fallback."
    else
        python3 -m playwright install chromium 2>/dev/null || \
        echo "  ⚠  Playwright install failed. Visual analysis will use web_extract fallback."
    fi

    echo ""
    echo "✓ Hermes SEO installed successfully!"
    echo ""
    echo "Skills:  ${HERMES_SKILLS}/seo-*"
    echo "Bundles: ${BUNDLES_DIR}/"
    echo ""
    echo "Usage:"
    echo "  hermes chat"
    echo "  /seo audit https://example.com"
    echo "  /seo-audit https://example.com    # full audit bundle"
    echo ""
    echo "Optional: raise parallel audit workers in ~/.hermes/config.yaml:"
    echo "  delegation:"
    echo "    max_concurrent_children: 15"
    echo ""
    echo "To uninstall: bash ${WORK_DIR}/uninstall.sh"
}

main "$@"
