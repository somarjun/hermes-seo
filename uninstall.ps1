#!/usr/bin/env pwsh
# hermes-seo manual-install uninstaller (Windows)
#
# Removes the orchestrator skill (~/.hermes/skills/seo), all sub-skills
# (~/.hermes/skills/seo-*), and all sub-agents (~/.hermes/skills/seo/references/delegates/seo-*.md).
#
# Uses glob enumeration rather than a hardcoded list so future skill
# additions are cleaned up automatically without releasing a new
# uninstaller.
#
# Plugin-install users should use Hermes Agent's own command instead:
#   /plugin uninstall hermes-seo@agricidaniel-seo
#   /plugin marketplace remove somarjun/hermes-seo

$ErrorActionPreference = "Stop"

function Write-Color($Color, $Text) {
    Write-Host $Text -ForegroundColor $Color
}

function Main {
    $SkillDir = Join-Path $env:USERPROFILE ".claude" "skills"
    $AgentDir = Join-Path $env:USERPROFILE ".claude" "agents"

    Write-Color Cyan "=== Uninstalling hermes-seo ==="
    Write-Host ""

    $removedSkills = 0
    $removedAgents = 0

    # Remove orchestrator if present
    $orchestratorPath = Join-Path $SkillDir "seo"
    if (Test-Path $orchestratorPath -PathType Container) {
        Remove-Item -Recurse -Force $orchestratorPath
        Write-Color Green "  Removed: $orchestratorPath"
        $removedSkills++
    }

    # Remove every seo-* sub-skill directory
    if (Test-Path $SkillDir -PathType Container) {
        Get-ChildItem -Path $SkillDir -Directory -Filter "seo-*" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Recurse -Force $_.FullName
            Write-Color Green "  Removed: $($_.FullName)"
            $script:removedSkills++
        }
    }

    # Remove every seo-*.md agent file
    if (Test-Path $AgentDir -PathType Container) {
        Get-ChildItem -Path $AgentDir -File -Filter "seo-*.md" -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Force $_.FullName
            Write-Color Green "  Removed: $($_.FullName)"
            $script:removedAgents++
        }
    }

    Write-Host ""
    if ($removedSkills -eq 0 -and $removedAgents -eq 0) {
        Write-Color Yellow "Nothing to remove. Hermes SEO does not appear to be installed."
        Write-Color Yellow "If you installed via /plugin install, run /plugin uninstall instead."
        return
    }

    Write-Color Cyan "=== hermes-seo uninstalled ($removedSkills skill dirs, $removedAgents agent files) ==="
    Write-Host ""
    Write-Color Yellow "Restart Hermes Agent to complete removal."
}

Main
