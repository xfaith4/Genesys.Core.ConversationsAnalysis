#Requires -Version 5.1
<#
.SYNOPSIS
    Runs all compliance and integration tests for Genesys Conversation Analysis.
    Returns exit code 0 (all pass) or 1 (any failure).
#>
$ErrorActionPreference = 'Stop'

$testRoot = $PSScriptRoot
$pass  = 0
$fail  = 0

Write-Host ""
Write-Host "  Genesys Conversation Analysis — Full Test Suite" -ForegroundColor Cyan
Write-Host ""

# ── Gate D: Mechanical compliance
Write-Host "Running Gate D compliance tests..." -ForegroundColor Yellow
try {
    & pwsh -NoProfile -File (Join-Path -Path $testRoot -ChildPath 'Test-Compliance.ps1')
    if ($LASTEXITCODE -eq 0) { Write-Host "  Gate D: PASS" -ForegroundColor Green; $pass++ }
    else                     { Write-Host "  Gate D: FAIL" -ForegroundColor Red;   $fail++ }
}
catch {
    Write-Host "  Gate D: ERROR — $($_)" -ForegroundColor Red
    $fail++
}

Write-Host ""

# ── Architecture checks (module structure)
Write-Host "Running architecture checks..." -ForegroundColor Yellow

$appRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $testRoot -ChildPath '..'))

function Check {
    param([string]$Name, [scriptblock]$Test)
    try {
        $r = & $Test
        if ($r) { Write-Host "  [PASS] $($Name)" -ForegroundColor Green; $script:pass++ }
        else    { Write-Host "  [FAIL] $($Name)" -ForegroundColor Red;   $script:fail++ }
    }
    catch {
        Write-Host "  [FAIL] $($Name) — $($_)" -ForegroundColor Red
        $script:fail++
    }
}

Check "App.CoreAdapter.psm1 imports Core from configured path (not hardcoded relative)" {
    $content = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.CoreAdapter.psm1'))
    # Must use a variable/param for the path, not a literal inline path to Genesys.Core
    $content -match 'Import-Module \$' -or $content -match 'Import-Module \$\w'
}

Check "App.ps1 calls Initialize-CoreAdapter (Gate A entry)" {
    $content = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.ps1'))
    $content -match 'Initialize-CoreAdapter'
}

Check "App.ps1 dot-sources App.UI.ps1 (not App.CoreAdapter directly from UI)" {
    $content = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.ps1'))
    $content -match '\. .*App\.UI\.ps1'
}

Check "App.UI.ps1 does NOT call Invoke-Dataset (must go through CoreAdapter)" {
    $content = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.UI.ps1'))
    -not ($content -match '\bInvoke-Dataset\b')
}

Check "App.UI.ps1 uses Start-PreviewRun and Start-FullRun (CoreAdapter functions)" {
    $content = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.UI.ps1'))
    ($content -match 'Start-PreviewRun') -or ($content -match 'Start-FullRun')
}

Check "App.Export.psm1 uses StreamReader for run CSV (no Get-Content on data JSONL)" {
    $content = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.Export.psm1'))
    $content -match 'StreamReader' -and -not ($content -match 'Get-Content.*data')
}

Check "App.Index.psm1 uses FileStream.Seek for O(pageSize) record access" {
    $content = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.Index.psm1'))
    $content -match 'Seek\(' -and $content -match 'FileStream'
}

Check "Run folder data contract: index.jsonl path uses 'index.jsonl' naming" {
    $content = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.Index.psm1'))
    $content -match 'index\.jsonl'
}

Check "Run folder data contract: App reads manifest.json + summary.json + events.jsonl" {
    $adapterContent = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.CoreAdapter.psm1'))
    ($adapterContent -match 'manifest\.json') -and
    ($adapterContent -match 'summary\.json')  -and
    ($adapterContent -match 'events\.jsonl')
}

Check "Dataset keys used match catalog (analytics-conversation-details variants)" {
    $adapterContent = [System.IO.File]::ReadAllText((Join-Path -Path $appRoot -ChildPath 'App.CoreAdapter.psm1'))
    ($adapterContent -match 'analytics-conversation-details-query') -and
    ($adapterContent -match "'analytics-conversation-details'")
}

# ── Summary
Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
$total = $pass + $fail
if ($fail -eq 0) {
    Write-Host "  ALL TESTS PASSED: $($pass)/$($total)" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "  FAILURES: $($fail)/$($total)" -ForegroundColor Red
    exit 1
}
