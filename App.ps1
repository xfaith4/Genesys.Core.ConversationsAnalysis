#Requires -Version 5.1
<#
.SYNOPSIS
    Genesys Conversation Analysis — WPF desktop application.
    Core-first: all extraction delegates to Genesys.Core via App.CoreAdapter.psm1.

.DESCRIPTION
    Entry point. Loads WPF assemblies, imports app modules (NOT Genesys.Core directly),
    calls Initialize-CoreAdapter for Gate A validation, loads XAML, dot-sources App.UI.ps1.

.NOTES
    All Genesys API calls are delegated to Genesys.Core. MUST NOT import Core except via CoreAdapter.
    Paths: configured in %LOCALAPPDATA%\GenesysConversationAnalysis\config.json
           overrideable via env vars GENESYS_CORE_MODULE, GENESYS_CORE_CATALOG, GENESYS_CORE_SCHEMA
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppRoot = $PSScriptRoot

# ─── WPF and Windows assemblies ──────────────────────────────────────
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
# Microsoft.Win32.SaveFileDialog is part of PresentationFramework (already loaded above)

# ─── Import application modules ──────────────────────────────────────
# NOTE: Genesys.Core is NOT imported here. Only CoreAdapter may import it.
Import-Module (Join-Path -Path $script:AppRoot -ChildPath 'App.Config.psm1')    -Force -ErrorAction Stop
Import-Module (Join-Path -Path $script:AppRoot -ChildPath 'App.Auth.psm1')      -Force -ErrorAction Stop
Import-Module (Join-Path -Path $script:AppRoot -ChildPath 'App.Index.psm1')     -Force -DisableNameChecking -ErrorAction Stop
Import-Module (Join-Path -Path $script:AppRoot -ChildPath 'App.Export.psm1')    -Force -ErrorAction Stop
Import-Module (Join-Path -Path $script:AppRoot -ChildPath 'App.CoreAdapter.psm1') -Force -ErrorAction Stop

# ─── Resolve Core paths (config → env override → defaults) ───────────
$script:Config = Get-AppConfig

$corePath    = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE  } else { $script:Config.CoreModulePath }
$catalogPath = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { $script:Config.CatalogPath    }
$schemaPath  = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA  } else { $script:Config.SchemaPath     }

# ─── Gate A: Initialize CoreAdapter (imports Genesys.Core + Assert-Catalog) ─
try {
    Initialize-CoreAdapter `
        -CoreModulePath $corePath `
        -CatalogPath    $catalogPath `
        -SchemaPath     $schemaPath
}
catch {
    # Show WPF error dialog even if window isn't open yet
    [System.Windows.MessageBox]::Show(
        "Failed to initialize Genesys.Core (Gate A):`n`n$($_)`n`nPaths:`n  Core   : $($corePath)`n  Catalog: $($catalogPath)`n  Schema : $($schemaPath)",
        'Startup Error — Core Validation Failed',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    exit 1
}

# ─── Load XAML ───────────────────────────────────────────────────────
$xamlPath = Join-Path -Path $script:AppRoot -ChildPath 'XAML\MainWindow.xaml'

if (-not (Test-Path -Path $xamlPath)) {
    [System.Windows.MessageBox]::Show(
        "XAML file not found: $($xamlPath)",
        'Startup Error',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    exit 1
}

try {
    [xml]$xaml = [System.IO.File]::ReadAllText($xamlPath)

    # Remove x:Class if present (not used in interpreted PS WPF)
    if ($xaml.Window.Attributes['x:Class']) {
        $xaml.Window.RemoveAttribute('x:Class')
    }

    $reader = [System.Xml.XmlNodeReader]::new($xaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
}
catch {
    [System.Windows.MessageBox]::Show(
        "Failed to load XAML:`n$($_)",
        'Startup Error — UI Load Failed',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    exit 1
}

# ─── Wire up App.UI.ps1 (event handlers, state, grid logic) ──────────
# Dot-sourced so it runs in this scope and has access to $window and all modules.
try {
    . (Join-Path -Path $script:AppRoot -ChildPath 'App.UI.ps1')
}
catch {
    [System.Windows.MessageBox]::Show(
        "Failed to initialize UI:`n$($_)",
        'Startup Error — UI Init Failed',
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error
    )
    exit 1
}

# ─── Show window ─────────────────────────────────────────────────────
$window.Add_Closed({
    # Cleanup background jobs on window close
    if ($script:State.RefreshTimer) { $script:State.RefreshTimer.Stop() }
    try { Stop-BackgroundRun } catch {}
    # Persist last used dates
    try {
        $ctrl = $script:Controls
        $cfg  = Get-AppConfig
        if ($ctrl.DtpStart.SelectedDate) { $cfg | Add-Member -NotePropertyName 'LastStartDate' -NotePropertyValue $ctrl.DtpStart.SelectedDate.Value.ToString('yyyy-MM-dd') -Force }
        if ($ctrl.DtpEnd.SelectedDate)   { $cfg | Add-Member -NotePropertyName 'LastEndDate'   -NotePropertyValue $ctrl.DtpEnd.SelectedDate.Value.ToString('yyyy-MM-dd')   -Force }
        Save-AppConfig -Config $cfg
    }
    catch {}
})

[void]$window.ShowDialog()
