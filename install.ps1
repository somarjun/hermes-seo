# Hermes SEO Installer for Windows
# PowerShell installation script

$ErrorActionPreference = "Stop"

function Link-SharedResources {
    param(
        [Parameter(Mandatory = $true)][string]$SkillsRoot,
        [Parameter(Mandatory = $true)][string]$SeoRoot
    )
    $items = @('scripts', 'schema', 'pdf', 'hooks')
    Get-ChildItem -Directory $SkillsRoot -Filter 'seo-*' | ForEach-Object {
        foreach ($item in $items) {
            $source = Join-Path $SeoRoot $item
            if (-not (Test-Path $source)) { continue }
            $target = Join-Path $_.FullName $item
            if (Test-Path $target) { Remove-Item -Force -Recurse $target }
            New-Item -ItemType SymbolicLink -Path $target -Target $source -Force | Out-Null
        }
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "|   Hermes SEO - Installer             |" -ForegroundColor Cyan
Write-Host "|   Hermes Agent SEO Skill              |" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

function Resolve-Python {
    $pythonCmd = Get-Command -Name python -ErrorAction SilentlyContinue
    if ($null -ne $pythonCmd) {
        return @{ Exe = 'python'; Args = @() }
    }

    $pyCmd = Get-Command -Name py -ErrorAction SilentlyContinue
    if ($null -ne $pyCmd) {
        return @{ Exe = 'py'; Args = @('-3') }
    }

    return $null
}

function Invoke-External {
    param(
        [Parameter(Mandatory = $true)][string]$Exe,
        [Parameter(Mandatory = $true)][string[]]$Args,
        [switch]$Quiet
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $hasNativePreference = $null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)
    if ($hasNativePreference) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    }

    try {
        $ErrorActionPreference = 'Continue'
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $false
        }

        $output = & $Exe @Args 2>&1 | ForEach-Object { $_.ToString() }
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($hasNativePreference) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
    }

    if (-not $Quiet -and $null -ne $output -and $output.Count -gt 0) {
        $output | ForEach-Object { Write-Host $_ }
    }

    return @{ ExitCode = $exitCode; Output = $output }
}

# Check prerequisites
$python = Resolve-Python
if ($null -eq $python) {
    Write-Host "[x] Python is required but was not found (tried 'python' and 'py')." -ForegroundColor Red
    exit 1
}

try {
    $pythonVersion = & $python.Exe @($python.Args + @('--version')) 2>&1
    Write-Host "[+] $pythonVersion detected" -ForegroundColor Green
} catch {
    Write-Host "[x] Python is installed but could not be executed." -ForegroundColor Red
    exit 1
}

try {
    git --version | Out-Null
    Write-Host "[+] Git detected" -ForegroundColor Green
} catch {
    Write-Host "[x] Git is required but not installed." -ForegroundColor Red
    exit 1
}

# Set paths
$HermesSkills = Join-Path $env:USERPROFILE ".hermes" "skills"
$SkillDir = Join-Path $HermesSkills "seo"
$BundlesDir = Join-Path $env:USERPROFILE ".hermes" "skill-bundles"
$DelegatesDir = Join-Path $SkillDir "references" "delegates"
$RepoUrl = "https://github.com/somarjun/hermes-seo"
$RepoTag = if ($env:HERMES_SEO_TAG) { $env:HERMES_SEO_TAG } else { 'main' }
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SourceDir = if ($env:HERMES_SEO_SOURCE) { $env:HERMES_SEO_SOURCE } else { $ScriptDir }

# Create directories
New-Item -ItemType Directory -Force -Path $HermesSkills, $SkillDir, $BundlesDir, $DelegatesDir | Out-Null

$TempDir = $null
$keepTemp = ($env:HERMES_SEO_KEEP_TEMP -eq '1')

try {
    if (Test-Path (Join-Path $SourceDir 'skills')) {
        Write-Host "=> Installing from local source: $SourceDir" -ForegroundColor Yellow
        $WorkDir = $SourceDir
    } else {
        $TempDir = Join-Path $env:TEMP "hermes-seo-install"
        if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir }
        Write-Host ">> Downloading Hermes SEO ($RepoTag)..." -ForegroundColor Yellow
        $clone = Invoke-External -Exe 'git' -Args @('clone','--depth','1','--branch',$RepoTag,$RepoUrl,$TempDir) -Quiet
        if ($clone.ExitCode -ne 0) {
            throw "git clone failed. Output:`n$($clone.Output -join "`n")"
        }
        $WorkDir = Join-Path $TempDir 'hermes-seo'
        if (-not (Test-Path $WorkDir)) { $WorkDir = $TempDir }
    }

    # Copy skill files
    Write-Host "=> Installing skill files..." -ForegroundColor Yellow
    $skillSource = Join-Path $WorkDir 'skills\seo'
    if (-not (Test-Path $skillSource)) {
        throw "Could not find skill source folder in repo clone."
    }
    Copy-Item -Recurse -Force (Join-Path $skillSource '*') $SkillDir

    # Copy sub-skills
    $SkillsPath = Join-Path $WorkDir 'skills'
    if (Test-Path $SkillsPath) {
        Get-ChildItem -Directory $SkillsPath | ForEach-Object {
            $target = Join-Path $HermesSkills $_.Name
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            Copy-Item -Recurse -Force "$($_.FullName)\*" $target
        }
    }

    # Copy schema templates
    $SchemaPath = Join-Path $WorkDir 'schema'
    if (Test-Path $SchemaPath) {
        $SkillSchema = "$SkillDir\schema"
        New-Item -ItemType Directory -Force -Path $SkillSchema | Out-Null
        Copy-Item -Recurse -Force "$SchemaPath\*" $SkillSchema
    }

    # Copy reference docs
    $PdfPath = Join-Path $WorkDir 'pdf'
    if (Test-Path $PdfPath) {
        $SkillPdf = "$SkillDir\pdf"
        New-Item -ItemType Directory -Force -Path $SkillPdf | Out-Null
        Copy-Item -Recurse -Force "$PdfPath\*" $SkillPdf
    }

    # Copy shared scripts
    $ScriptsPath = Join-Path $WorkDir 'scripts'
    if (Test-Path $ScriptsPath) {
        $SkillScripts = Join-Path $SkillDir 'scripts'
        New-Item -ItemType Directory -Force -Path $SkillScripts | Out-Null
        Copy-Item -Recurse -Force (Join-Path $ScriptsPath '*') $SkillScripts
        Remove-Item -Force (Join-Path $SkillScripts 'port_to_hermes.py'), (Join-Path $SkillScripts 'fix_hermes_port.py') -ErrorAction SilentlyContinue
    }

    # Copy hooks
    $HooksPath = Join-Path $WorkDir 'hooks'
    if (Test-Path $HooksPath) {
        $SkillHooks = Join-Path $SkillDir 'hooks'
        New-Item -ItemType Directory -Force -Path $SkillHooks | Out-Null
        Copy-Item -Recurse -Force (Join-Path $HooksPath '*') $SkillHooks
    }

    # Copy skill bundles
    $BundlesPath = Join-Path $WorkDir 'skill-bundles'
    if (Test-Path $BundlesPath) {
        Copy-Item -Force (Join-Path $BundlesPath '*.yaml') $BundlesDir -ErrorAction SilentlyContinue
    }

    Write-Host "=> Linking shared resources into sub-skills..." -ForegroundColor Yellow
    Link-SharedResources -SkillsRoot $HermesSkills -SeoRoot $SkillDir

    # Copy extensions (optional add-ons)
    $ExtensionsPath = Join-Path $WorkDir 'extensions'
    if (Test-Path $ExtensionsPath) {
        Write-Host "=> Installing extensions..." -ForegroundColor Yellow
        Get-ChildItem -Directory $ExtensionsPath | ForEach-Object {
            $extName = $_.Name
            $extDir = $_.FullName
            $extSkills = Join-Path $extDir 'skills'
            if (Test-Path $extSkills) {
                Get-ChildItem -Directory $extSkills | ForEach-Object {
                    $target = Join-Path $HermesSkills $_.Name
                    New-Item -ItemType Directory -Force -Path $target | Out-Null
                    Copy-Item -Recurse -Force (Join-Path $_.FullName '*') $target
                }
            }
            $extAgents = Join-Path $extDir 'agents'
            if (Test-Path $extAgents) {
                Copy-Item -Force (Join-Path $extAgents '*.md') $DelegatesDir -ErrorAction SilentlyContinue
            }
            $extRefs = Join-Path $extDir 'references'
            if (Test-Path $extRefs) {
                $refTarget = Join-Path $SkillDir "extensions\$extName\references"
                New-Item -ItemType Directory -Force -Path $refTarget | Out-Null
                Copy-Item -Recurse -Force (Join-Path $extRefs '*') $refTarget
            }
            $extScripts = Join-Path $extDir 'scripts'
            if (Test-Path $extScripts) {
                $scriptTarget = Join-Path $SkillDir "extensions\$extName\scripts"
                New-Item -ItemType Directory -Force -Path $scriptTarget | Out-Null
                Copy-Item -Recurse -Force (Join-Path $extScripts '*') $scriptTarget
            }
        }
    }

    # Copy requirements.txt to skill dir for retry
    $reqFile = Join-Path $WorkDir 'requirements.txt'
    $installedReqFile = Join-Path $SkillDir 'requirements.txt'
    if (Test-Path $reqFile) {
        Copy-Item -Force $reqFile $installedReqFile
    }

    # Install Python dependencies
    Write-Host "=> Installing Python dependencies..." -ForegroundColor Yellow
    if (Test-Path $reqFile) {
        try {
            $pip = Invoke-External -Exe $python.Exe -Args @($python.Args + @('-m','pip','install','-q','-r',$reqFile)) -Quiet
            if ($pip.ExitCode -ne 0) {
                throw ($pip.Output -join "`n")
            }
        } catch {
            Write-Host "  [!]  Could not auto-install Python packages." -ForegroundColor Yellow
            Write-Host "  Try: $($python.Exe) $($python.Args -join ' ') -m pip install -r `"$installedReqFile`"" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [!]  No requirements.txt found; skipping Python dependency install." -ForegroundColor Yellow
    }

    # Optional: Install Playwright browsers
    Write-Host "=> Installing Playwright browsers (optional, for visual analysis)..." -ForegroundColor Yellow
    try {
        $pw = Invoke-External -Exe $python.Exe -Args @($python.Args + @('-m','playwright','install','chromium')) -Quiet
        if ($pw.ExitCode -ne 0) {
            throw ($pw.Output -join "`n")
        }
    } catch {
        Write-Host "  [!]  Playwright install failed. Visual analysis will use WebFetch fallback." -ForegroundColor Yellow
    }
} catch {
    Write-Host ""
    Write-Host "[x] Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($keepTemp -and (Test-Path $TempDir)) {
        Write-Host "Temp dir kept at: $TempDir" -ForegroundColor Yellow
    }
    throw
} finally {
    if (-not $keepTemp -and (Test-Path $TempDir)) {
        Remove-Item -Recurse -Force $TempDir
    }
}

Write-Host ""
Write-Host "[+] Hermes SEO installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Usage:" -ForegroundColor Cyan
Write-Host "  1. Start Hermes Agent:  hermes chat"
Write-Host "  2. Run commands:       /seo audit https://example.com"
Write-Host "  3. Or use bundle:      /seo-audit https://example.com"
Write-Host ""
Write-Host "Python deps location: $installedReqFile" -ForegroundColor Gray
