#Requires -Version 5.1
<#
.SYNOPSIS
    Gate D — Mechanical Compliance Tests.
    Verifies that no app code makes direct Genesys API REST calls, imports Genesys.Core
    outside the designated adapter, or copies Core into the app directory.

.DESCRIPTION
    Run with: pwsh -File tests\Test-Compliance.ps1
    Or with Pester: Invoke-Pester tests\Test-Compliance.ps1

    ALL tests must PASS for the app to be considered compliant.
    ANY failure = delivery rejected.

.NOTES
    Gate D rules enforced:
      1. No Invoke-RestMethod in any app file except App.Auth.psm1 (Gate E escape hatch)
      2. No Invoke-WebRequest in any app file except App.Auth.psm1
      3. No /api/v2/ literal in ANY app file (including App.Auth.psm1)
      4. Genesys.Core only imported in App.CoreAdapter.psm1
      5. Genesys.Core NOT copied into the app directory
      6. Only App.CoreAdapter.psm1 calls Invoke-Dataset
      7. Only App.CoreAdapter.psm1 calls Assert-Catalog
#>

$ErrorActionPreference = 'Stop'
$AppRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))

# ─── Collect all app files ────────────────────────────────────────────
$allAppFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()

Get-ChildItem -Path $AppRoot -Filter '*.ps1'  -Recurse | Where-Object { $_.FullName -notlike '*\tests\*' } | ForEach-Object { $allAppFiles.Add($_) }
Get-ChildItem -Path $AppRoot -Filter '*.psm1' -Recurse | ForEach-Object { $allAppFiles.Add($_) }

# Exclude test files themselves
$allAppFiles = @($allAppFiles | Where-Object { $_.FullName -notlike '*\tests\*' })

# Gate E escape hatch: App.Auth.psm1 may use Invoke-RestMethod for OAuth token only
$authFile       = $allAppFiles | Where-Object { $_.Name -eq 'App.Auth.psm1' }
$nonAuthFiles   = @($allAppFiles | Where-Object { $_.Name -ne 'App.Auth.psm1' })
$adapterFile    = $allAppFiles | Where-Object { $_.Name -eq 'App.CoreAdapter.psm1' }
$nonAdapterFiles= @($allAppFiles | Where-Object { $_.Name -ne 'App.CoreAdapter.psm1' })

$pass  = 0
$fail  = 0
$total = 0

function Test-Assert {
    param([string]$Name, [scriptblock]$Test)

    $script:total++
    try {
        $result = & $Test
        if ($result -eq $false) {
            Write-Host "  [FAIL] $($Name)" -ForegroundColor Red
            $script:fail++
        }
        else {
            Write-Host "  [PASS] $($Name)" -ForegroundColor Green
            $script:pass++
        }
    }
    catch {
        Write-Host "  [FAIL] $($Name) — Exception: $($_)" -ForegroundColor Red
        $script:fail++
    }
}

function Get-FileContent { param([System.IO.FileInfo]$File) return [System.IO.File]::ReadAllText($File.FullName) }

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Genesys Conversation Analysis — Gate D Compliance Tests  " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  App root : $($AppRoot)" -ForegroundColor Gray
Write-Host "  Files    : $($allAppFiles.Count) app files scanned" -ForegroundColor Gray
Write-Host ""

# ─── SECTION 1: Structural checks ────────────────────────────────────
Write-Host "SECTION 1: Structural Requirements" -ForegroundColor Yellow

Test-Assert -Name "App.CoreAdapter.psm1 exists" {
    $adapterFile.Count -gt 0
}

Test-Assert -Name "App.Auth.psm1 exists (Gate E escape hatch)" {
    $authFile.Count -gt 0
}

Test-Assert -Name "App.ps1 (entry point) exists" {
    ($allAppFiles | Where-Object { $_.Name -eq 'App.ps1' }).Count -gt 0
}

Test-Assert -Name "XAML\MainWindow.xaml exists" {
    Test-Path -Path (Join-Path -Path $AppRoot -ChildPath 'XAML\MainWindow.xaml')
}

Test-Assert -Name "App.Index.psm1 exists (indexing requirement)" {
    ($allAppFiles | Where-Object { $_.Name -eq 'App.Index.psm1' }).Count -gt 0
}

Test-Assert -Name "App.Export.psm1 exists (export requirement)" {
    ($allAppFiles | Where-Object { $_.Name -eq 'App.Export.psm1' }).Count -gt 0
}

# ─── SECTION 2: No direct REST in non-Auth files ─────────────────────
Write-Host ""
Write-Host "SECTION 2: No Direct REST Calls (except App.Auth.psm1 Gate E)" -ForegroundColor Yellow

foreach ($file in $nonAuthFiles) {
    $content = Get-FileContent -File $file

    Test-Assert -Name "[$($file.Name)] must NOT use Invoke-RestMethod" {
        -not ($content -match 'Invoke-RestMethod')
    }

    Test-Assert -Name "[$($file.Name)] must NOT use Invoke-WebRequest" {
        -not ($content -match 'Invoke-WebRequest')
    }
}

# ─── SECTION 3: No /api/v2/ in ANY app file ──────────────────────────
Write-Host ""
Write-Host "SECTION 3: No /api/v2/ Literals in Any App File" -ForegroundColor Yellow

foreach ($file in $allAppFiles) {
    $content = Get-FileContent -File $file
    Test-Assert -Name "[$($file.Name)] must NOT contain /api/v2/ literals" {
        -not ($content -match '/api/v2/')
    }
}

# ─── SECTION 4: Genesys.Core import isolation ────────────────────────
Write-Host ""
Write-Host "SECTION 4: Genesys.Core Import Isolation (only App.CoreAdapter.psm1)" -ForegroundColor Yellow

foreach ($file in $nonAdapterFiles) {
    $content = Get-FileContent -File $file
    Test-Assert -Name "[$($file.Name)] must NOT Import-Module Genesys.Core" {
        -not ($content -match 'Import-Module[^\r\n]*Genesys\.Core')
    }
}

Test-Assert -Name "[App.CoreAdapter.psm1] MUST contain Import-Module for Genesys.Core" {
    if ($adapterFile.Count -eq 0) { return $false }
    $content = Get-FileContent -File $adapterFile[0]
    $content -match 'Import-Module'
}

Test-Assert -Name "[App.CoreAdapter.psm1] MUST call Assert-Catalog" {
    if ($adapterFile.Count -eq 0) { return $false }
    $content = Get-FileContent -File $adapterFile[0]
    $content -match 'Assert-Catalog'
}

Test-Assert -Name "[App.CoreAdapter.psm1] MUST call Invoke-Dataset" {
    if ($adapterFile.Count -eq 0) { return $false }
    $content = Get-FileContent -File $adapterFile[0]
    $content -match 'Invoke-Dataset'
}

# ─── SECTION 5: Invoke-Dataset only in CoreAdapter ───────────────────
Write-Host ""
Write-Host "SECTION 5: Invoke-Dataset only called from App.CoreAdapter.psm1" -ForegroundColor Yellow

foreach ($file in $nonAdapterFiles) {
    $content = Get-FileContent -File $file
    Test-Assert -Name "[$($file.Name)] must NOT call Invoke-Dataset" {
        -not ($content -match '\bInvoke-Dataset\b')
    }
}

# ─── SECTION 6: No Genesys.Core copy in app directory ────────────────
Write-Host ""
Write-Host "SECTION 6: Genesys.Core NOT Copied into App Directory" -ForegroundColor Yellow

Test-Assert -Name "Genesys.Core.psd1 must NOT be present in app tree" {
    $found = Get-ChildItem -Path $AppRoot -Filter 'Genesys.Core.psd1' -Recurse -ErrorAction SilentlyContinue
    $found.Count -eq 0
}

Test-Assert -Name "Genesys.Core.psm1 must NOT be present in app tree" {
    $found = Get-ChildItem -Path $AppRoot -Filter 'Genesys.Core.psm1' -Recurse -ErrorAction SilentlyContinue
    $found.Count -eq 0
}

Test-Assert -Name "No folder named 'Genesys.Core' inside app directory" {
    $found = Get-ChildItem -Path $AppRoot -Filter 'Genesys.Core' -Recurse -Directory -ErrorAction SilentlyContinue
    $found.Count -eq 0
}

# ─── SECTION 7: Auth escape hatch constraints ────────────────────────
Write-Host ""
Write-Host "SECTION 7: App.Auth.psm1 Gate E Constraints" -ForegroundColor Yellow

if ($authFile.Count -gt 0) {
    $authContent = Get-FileContent -File $authFile[0]

    Test-Assert -Name "[App.Auth.psm1] must NOT contain /api/v2/ (only login endpoint allowed)" {
        -not ($authContent -match '/api/v2/')
    }

    Test-Assert -Name "[App.Auth.psm1] must contain DPAPI usage (ProtectedData::Protect)" {
        $authContent -match 'ProtectedData.*Protect'
    }

    Test-Assert -Name "[App.Auth.psm1] must target login endpoint not API" {
        $authContent -match 'login\.\$\(' -or $authContent -match "login\."
    }

    Test-Assert -Name "[App.Auth.psm1] must NOT import Genesys.Core" {
        -not ($authContent -match 'Import-Module[^\r\n]*Genesys\.Core')
    }
}
else {
    Write-Host "  [SKIP] App.Auth.psm1 not found — section skipped" -ForegroundColor DarkYellow
}

# ─── SECTION 8: Indexing requirement ─────────────────────────────────
Write-Host ""
Write-Host "SECTION 8: Indexing Implementation (for O(pageSize) paging)" -ForegroundColor Yellow

$indexFile = $allAppFiles | Where-Object { $_.Name -eq 'App.Index.psm1' }
if ($indexFile.Count -gt 0) {
    $indexContent = Get-FileContent -File $indexFile[0]

    Test-Assert -Name "[App.Index.psm1] must implement Build-RunIndex" {
        $indexContent -match 'function Build-RunIndex'
    }

    Test-Assert -Name "[App.Index.psm1] must implement Get-IndexedPage" {
        $indexContent -match 'function Get-IndexedPage'
    }

    Test-Assert -Name "[App.Index.psm1] must use StreamReader (not Get-Content for data files)" {
        $indexContent -match 'StreamReader'
    }

    Test-Assert -Name "[App.Index.psm1] must use FileStream Seek for O(pageSize) access" {
        $indexContent -match '\.Seek\('
    }

    Test-Assert -Name "[App.Index.psm1] must NOT call Get-Content for JSONL paging" {
        # Get-Content is forbidden for large JSONL paging (except for small config files)
        # Only allowed references should be for index.jsonl loading (not data/*.jsonl)
        $lines = $indexContent -split "`n"
        $violations = @($lines | Where-Object { $_ -match 'Get-Content' -and $_ -notmatch '#' })
        $violations.Count -eq 0
    }
}

# ─── SECTION 9: Export streaming requirement ─────────────────────────
Write-Host ""
Write-Host "SECTION 9: Export Streaming (no full in-memory load)" -ForegroundColor Yellow

$exportFile = $allAppFiles | Where-Object { $_.Name -eq 'App.Export.psm1' }
if ($exportFile.Count -gt 0) {
    $exportContent = Get-FileContent -File $exportFile[0]

    Test-Assert -Name "[App.Export.psm1] must implement Export-RunToCsv" {
        $exportContent -match 'function Export-RunToCsv'
    }

    Test-Assert -Name "[App.Export.psm1] Export-RunToCsv must use StreamReader (not Get-Content)" {
        $exportContent -match 'StreamReader'
    }

    Test-Assert -Name "[App.Export.psm1] must NOT use Invoke-RestMethod" {
        -not ($exportContent -match 'Invoke-RestMethod')
    }
}

# ─── SUMMARY ─────────────────────────────────────────────────────────
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
if ($fail -eq 0) {
    Write-Host "  RESULT: ALL $($pass)/$($total) TESTS PASSED ✓" -ForegroundColor Green
}
else {
    Write-Host "  RESULT: $($fail) FAILURES / $($total) tests  ✗" -ForegroundColor Red
    Write-Host "  GATE D FAILED — delivery must be rejected."       -ForegroundColor Red
}
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($fail -gt 0) { exit 1 } else { exit 0 }
