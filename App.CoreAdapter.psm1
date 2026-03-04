#Requires -Version 5.1
# App.CoreAdapter.psm1 — THE ONLY FILE PERMITTED TO IMPORT GENESYS.CORE
#
# ARCHITECTURE BOUNDARY (non-negotiable):
#   - Only this module may call: Import-Module Genesys.Core, Assert-Catalog, Invoke-Dataset
#   - All other modules/scripts MUST NOT import or reference Genesys.Core directly
#   - No direct Genesys API calls. No REST methods outside Auth. No web requests.
#
Set-StrictMode -Version Latest

$script:CoreModulePath = $null
$script:CatalogPath    = $null
$script:SchemaPath     = $null
$script:IsInitialized  = $false

function Initialize-CoreAdapter {
    <#
    .SYNOPSIS
        Imports Genesys.Core by reference and validates the catalog (Gate A).
        Must be called once at application startup before any extraction.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CoreModulePath,

        [Parameter(Mandatory = $true)]
        [string]$CatalogPath,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    if (-not (Test-Path -Path $CoreModulePath)) {
        throw "Genesys.Core module not found at: $($CoreModulePath)"
    }
    if (-not (Test-Path -Path $CatalogPath)) {
        throw "Catalog not found at: $($CatalogPath)"
    }
    if (-not (Test-Path -Path $SchemaPath)) {
        throw "Schema not found at: $($SchemaPath)"
    }

    # Import Genesys.Core by reference (not copied into app dir)
    Import-Module $CoreModulePath -Force -Global -ErrorAction Stop

    # Gate A: Validate catalog against schema at startup — fail fast if invalid
    Assert-Catalog -CatalogPath $CatalogPath -SchemaPath $SchemaPath -ErrorAction Stop | Out-Null

    $script:CoreModulePath = $CoreModulePath
    $script:CatalogPath    = $CatalogPath
    $script:SchemaPath     = $SchemaPath
    $script:IsInitialized  = $true

    Write-Verbose "CoreAdapter: Genesys.Core loaded. Catalog validated at '$($CatalogPath)'."
}

function Assert-CoreInitialized {
    if (-not $script:IsInitialized) {
        throw "CoreAdapter not initialized. Call Initialize-CoreAdapter first."
    }
}

function Test-CoreInitialized {
    return $script:IsInitialized
}

function Start-PreviewRun {
    <#
    .SYNOPSIS
        Gate B (Preview Mode): Invokes Invoke-Dataset with analytics-conversation-details-query.
        Small page, fast feedback, synchronous POST query.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DatasetParameters,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot,

        [hashtable]$Headers
    )

    Assert-CoreInitialized

    $invokeParams = @{
        Dataset           = 'analytics-conversation-details-query'
        CatalogPath       = $script:CatalogPath
        OutputRoot        = $OutputRoot
        DatasetParameters = $DatasetParameters
    }
    if ($Headers) { $invokeParams['Headers'] = $Headers }

    return Invoke-Dataset @invokeParams
}

function Start-FullRun {
    <#
    .SYNOPSIS
        Gate B (Full Run Mode): Invokes Invoke-Dataset with analytics-conversation-details.
        Job-based, scalable, streams to disk. No in-memory accumulation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$DatasetParameters,

        [Parameter(Mandatory = $true)]
        [string]$OutputRoot,

        [hashtable]$Headers
    )

    Assert-CoreInitialized

    $invokeParams = @{
        Dataset           = 'analytics-conversation-details'
        CatalogPath       = $script:CatalogPath
        OutputRoot        = $OutputRoot
        DatasetParameters = $DatasetParameters
    }
    if ($Headers) { $invokeParams['Headers'] = $Headers }

    return Invoke-Dataset @invokeParams
}

function Get-RunManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunFolder)

    $path = [System.IO.Path]::Combine($RunFolder, 'manifest.json')
    if (-not (Test-Path -Path $path)) { return $null }
    try { return (Get-Content -Path $path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Get-RunSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunFolder)

    $path = [System.IO.Path]::Combine($RunFolder, 'summary.json')
    if (-not (Test-Path -Path $path)) { return $null }
    try { return (Get-Content -Path $path -Raw | ConvertFrom-Json) } catch { return $null }
}

function Get-RunEvents {
    <#
    .SYNOPSIS
        Tails the last N events from events.jsonl in a run folder.
        Uses StreamReader to avoid Get-Content on potentially large files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$RunFolder,

        [int]$Last = 100
    )

    $path = [System.IO.Path]::Combine($RunFolder, 'events.jsonl')
    if (-not (Test-Path -Path $path)) { return @() }

    $lines  = [System.Collections.Generic.List[string]]::new()
    $fs     = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)

    try {
        while ($true) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if (-not [string]::IsNullOrWhiteSpace($line)) { $lines.Add($line) }
        }
    }
    finally {
        $reader.Dispose()
        $fs.Dispose()
    }

    $events = @($lines | Select-Object -Last $Last | ForEach-Object {
        try { $_ | ConvertFrom-Json } catch { $null }
    } | Where-Object { $null -ne $_ })

    return $events
}

function Get-RunStatus {
    <#
    .SYNOPSIS
        Derives a simple status string from summary.json and events.jsonl presence.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunFolder)

    $summary = Get-RunSummary -RunFolder $RunFolder
    if ($null -eq $summary) {
        # Check if events exist — run may be in progress
        $eventsPath = [System.IO.Path]::Combine($RunFolder, 'events.jsonl')
        if (Test-Path -Path $eventsPath) { return 'Running' }
        return 'Unknown'
    }

    $status = [string]$summary.status
    switch ($status) {
        'complete' { return 'Complete' }
        'failed'   { return 'Failed'   }
        'running'  { return 'Running'  }
        default    { return if ($status) { $status } else { 'Unknown' } }
    }
}

function Get-RecentRunFolders {
    <#
    .SYNOPSIS
        Discovers recent run folders under OutputRoot by walking dataset/runId subdirs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputRoot,

        [int]$Limit = 20
    )

    if (-not (Test-Path -Path $OutputRoot)) { return @() }

    $runs = [System.Collections.Generic.List[object]]::new()

    $datasetDirs = [System.IO.Directory]::GetDirectories($OutputRoot)
    foreach ($datasetDir in $datasetDirs) {
        $runDirs = [System.IO.Directory]::GetDirectories($datasetDir) | Sort-Object -Descending
        foreach ($runDir in ($runDirs | Select-Object -First 5)) {
            $manifestPath = [System.IO.Path]::Combine($runDir, 'manifest.json')
            if (-not (Test-Path -Path $manifestPath)) { continue }

            try {
                $manifest  = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
                $summary   = Get-RunSummary -RunFolder $runDir
                $itemCount = if ($summary -and $summary.counts) { [string]$summary.counts.itemCount } else { '?' }
                $status    = Get-RunStatus -RunFolder $runDir

                $runs.Add([pscustomobject]@{
                    RunFolder  = $runDir
                    DatasetKey = [string]$manifest.datasetKey
                    RunId      = [string]$manifest.runId
                    ItemCount  = $itemCount
                    Status     = $status
                    ModifiedAt = [System.IO.Directory]::GetLastWriteTimeUtc($runDir)
                })
            }
            catch {}
        }
    }

    return @($runs | Sort-Object -Property ModifiedAt -Descending | Select-Object -First $Limit)
}

function Get-DiagnosticsText {
    <#
    .SYNOPSIS
        Returns a formatted diagnostics string for "Copy Diagnostics" button.
    #>
    [CmdletBinding()]
    param(
        [string]$RunFolder,
        [hashtable]$DatasetParameters,
        [string]$DatasetKey,
        [int]$LastEventCount = 50
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("=== Genesys Conversation Analysis Diagnostics ===")
    [void]$sb.AppendLine("Timestamp  : $([datetime]::UtcNow.ToString('o'))")
    [void]$sb.AppendLine("Dataset Key: $($DatasetKey)")
    [void]$sb.AppendLine("Run Folder : $($RunFolder)")

    if ($DatasetParameters) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("--- Dataset Parameters ---")
        foreach ($key in $DatasetParameters.Keys) {
            [void]$sb.AppendLine("  $($key) = $($DatasetParameters[$key])")
        }
    }

    if ($RunFolder -and (Test-Path -Path $RunFolder)) {
        $summary = Get-RunSummary -RunFolder $RunFolder
        if ($summary) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("--- Summary ---")
            [void]$sb.AppendLine(($summary | ConvertTo-Json -Depth 5 -Compress))
        }

        $events = Get-RunEvents -RunFolder $RunFolder -Last $LastEventCount
        if ($events.Count -gt 0) {
            [void]$sb.AppendLine("")
            [void]$sb.AppendLine("--- Last $($LastEventCount) Events ---")
            foreach ($evt in $events) {
                $ts    = if ($evt.ts)      { [string]$evt.ts }      else { '' }
                $level = if ($evt.level)   { [string]$evt.level }   else { '' }
                $event = if ($evt.event)   { [string]$evt.event }   else { [string]$evt.eventType }
                $msg   = if ($evt.message) { [string]$evt.message } else { ($evt.payload | ConvertTo-Json -Compress) }
                [void]$sb.AppendLine("[$($ts)] [$($level)] $($event) $($msg)")
            }
        }
    }

    return $sb.ToString()
}

Export-ModuleMember -Function Initialize-CoreAdapter, Test-CoreInitialized, Start-PreviewRun, Start-FullRun, Get-RunManifest, Get-RunSummary, Get-RunEvents, Get-RunStatus, Get-RecentRunFolders, Get-DiagnosticsText
