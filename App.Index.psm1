#Requires -Version 5.1
# App.Index.psm1 — Run index builder and O(pageSize) paging engine.
# Builds index.jsonl in run folder on first open; subsequent pages seek by byte offset.
Set-StrictMode -Version Latest

# Per-session cache: RunFolder -> index entry array
$script:IndexCache = [hashtable]::Synchronized(@{})

function Get-RelativePathCompat {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$BasePath,
        [Parameter(Mandatory=$true)][string]$TargetPath
    )

    try {
        return [System.IO.Path]::GetRelativePath($BasePath, $TargetPath)
    }
    catch {
        $base = [System.IO.Path]::GetFullPath($BasePath)
        $target = [System.IO.Path]::GetFullPath($TargetPath)

        if (-not $base.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $base += [System.IO.Path]::DirectorySeparatorChar
        }

        $baseUri = [System.Uri]::new($base)
        $targetUri = [System.Uri]::new($target)
        $rel = $baseUri.MakeRelativeUri($targetUri).ToString()
        return [System.Uri]::UnescapeDataString($rel).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    }
}

function Get-JsonlFileLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)

    $newlineLength = 1
    $bomLength = 0
    $fs = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        if ($fs.Length -ge 3) {
            $sig = New-Object byte[] 3
            [void]$fs.Read($sig, 0, 3)
            if ($sig[0] -eq 0xEF -and $sig[1] -eq 0xBB -and $sig[2] -eq 0xBF) {
                $bomLength = 3
            }
        }

        $fs.Seek(0, [System.IO.SeekOrigin]::Begin) | Out-Null
        while ($fs.Position -lt $fs.Length) {
            $b = $fs.ReadByte()
            if ($b -eq 10) {
                if ($fs.Position -ge 2) {
                    $fs.Seek(-2, [System.IO.SeekOrigin]::Current) | Out-Null
                    $prev = $fs.ReadByte()
                    if ($prev -eq 13) { $newlineLength = 2 }
                }
                break
            }
        }
    }
    finally {
        $fs.Dispose()
    }

    return [pscustomobject]@{
        NewlineLength = $newlineLength
        BomLength = $bomLength
    }
}

function Get-RunIndexPath {
    param([Parameter(Mandatory=$true)][string]$RunFolder)
    return [System.IO.Path]::Combine($RunFolder, 'index.jsonl')
}

function Build-RunIndex {
    <#
    .SYNOPSIS
        Scans data/*.jsonl files in a run folder and writes index.jsonl.
        Each index entry records the byte offset of a conversation record for O(1) seek.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunFolder,

        [switch]$Force
    )

    $indexPath = Get-RunIndexPath -RunFolder $RunFolder

    if ((Test-Path -Path $indexPath) -and -not $Force) {
        return $indexPath
    }

    $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
    if (-not (Test-Path -Path $dataDir)) {
        throw "No data directory found at '$($dataDir)'"
    }

    $tmpPath = $indexPath + '.tmp'
    $writer  = [System.IO.StreamWriter]::new($tmpPath, $false, [System.Text.Encoding]::UTF8)
    $idx     = 0

    try {
        $dataFiles = [System.IO.Directory]::GetFiles($dataDir, '*.jsonl') | Sort-Object

        foreach ($dataFile in $dataFiles) {
            $relPath = Get-RelativePathCompat -BasePath $RunFolder -TargetPath $dataFile

            $layout = Get-JsonlFileLayout -Path $dataFile
            $offset = [long]$layout.BomLength
            $fs     = [System.IO.FileStream]::new($dataFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8, $true, 65536)

            try {
                while ($true) {
                    $lineStart = $offset
                    $line      = $reader.ReadLine()
                    if ($null -eq $line) { break }
                    $offset   += [System.Text.Encoding]::UTF8.GetByteCount($line) + $layout.NewlineLength
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }

                    try {
                        $rec    = $line | ConvertFrom-Json
                        $convId = [string]$rec.conversationId
                        if ([string]::IsNullOrWhiteSpace($convId)) { continue }

                        # Extract minimal summary fields for index
                        $startTime  = ''
                        $endTime    = ''
                        $durationMs = [long]0
                        $direction  = ''
                        $queueName  = ''
                        $mediaType  = ''
                        $partCount  = 0
                        $discType   = ''
                        $hasMos     = $false
                        $hasHold    = $false

                        if ($rec.conversationStart) { $startTime = [string]$rec.conversationStart }
                        if ($rec.conversationEnd)   { $endTime   = [string]$rec.conversationEnd }

                        if ($startTime -and $endTime) {
                            try {
                                $dtS = [datetime]::Parse($startTime, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                                $dtE = [datetime]::Parse($endTime,   [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
                                $durationMs = [long]($dtE - $dtS).TotalMilliseconds
                            }
                            catch {}
                        }

                        if ($rec.participants) {
                            $partCount = @($rec.participants).Count

                            foreach ($p in @($rec.participants)) {
                                if (-not $p.sessions) { continue }

                                foreach ($sess in @($p.sessions)) {
                                    if ($sess.mediaType -and -not $mediaType) {
                                        $mediaType = [string]$sess.mediaType
                                    }
                                    if ($sess.queueName -and -not $queueName) {
                                        $queueName = [string]$sess.queueName
                                    }
                                    if ($p.purpose -eq 'customer' -and $sess.direction -and -not $direction) {
                                        $direction = [string]$sess.direction
                                    }
                                    if ($sess.mos)        { $hasMos  = $true }
                                    if (-not $discType -and $sess.segments) {
                                        foreach ($seg in @($sess.segments)) {
                                            if ($seg.disconnectType) { $discType = [string]$seg.disconnectType }
                                            if ($seg.segmentType -eq 'hold') { $hasHold = $true }
                                        }
                                    }
                                }
                            }
                        }

                        $entry = [ordered]@{
                            i    = $idx
                            id   = $convId
                            f    = $relPath
                            o    = [long]$lineStart
                            ms   = $durationMs
                            s    = $startTime
                            e    = $endTime
                            dir  = $direction
                            q    = $queueName
                            mt   = $mediaType
                            pc   = $partCount
                            dc   = $discType
                            mos  = [int][bool]$hasMos
                            hld  = [int][bool]$hasHold
                        }

                        $writer.WriteLine(($entry | ConvertTo-Json -Compress))
                        $idx++
                    }
                    catch {
                        # Skip malformed records
                    }
                }
            }
            finally {
                $reader.Dispose()
                $fs.Dispose()
            }
        }
    }
    finally {
        $writer.Dispose()
    }

    # Atomic rename
    if (Test-Path -Path $indexPath) { Remove-Item -Path $indexPath -Force }
    [System.IO.File]::Move($tmpPath, $indexPath)

    return $indexPath
}

function Load-RunIndex {
    <#
    .SYNOPSIS
        Loads index.jsonl into memory (minimal fields only). Builds it first if missing.
        Caches per run folder for the session lifetime.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunFolder
    )

    if ($script:IndexCache.ContainsKey($RunFolder)) {
        return , $script:IndexCache[$RunFolder]
    }

    $indexPath = Get-RunIndexPath -RunFolder $RunFolder
    if (-not (Test-Path -Path $indexPath)) {
        Build-RunIndex -RunFolder $RunFolder | Out-Null
    }

    $entries = [System.Collections.Generic.List[object]]::new()
    $reader  = [System.IO.StreamReader]::new($indexPath, [System.Text.Encoding]::UTF8)

    try {
        while ($true) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $entries.Add(($line | ConvertFrom-Json)) } catch {}
        }
    }
    finally {
        $reader.Dispose()
    }

    $arr = $entries.ToArray()
    $script:IndexCache[$RunFolder] = $arr
    return , $arr
}

function Clear-IndexCache {
    [CmdletBinding()]
    param([string]$RunFolder = '')

    if ($RunFolder) {
        $script:IndexCache.Remove($RunFolder)
    }
    else {
        $script:IndexCache.Clear()
    }
}

function Get-FilteredIndex {
    <#
    .SYNOPSIS
        Returns a filtered subset of index entries based on search/quick-filters.
    #>
    [CmdletBinding()]
    param(
        [object[]]$Index,
        [string]$SearchText  = '',
        [hashtable]$Filters  = @{}
    )

    $result = $Index

    if (-not [string]::IsNullOrWhiteSpace($SearchText)) {
        $s = $SearchText.ToLowerInvariant()
        $result = @($result | Where-Object {
            ([string]$_.id).ToLowerInvariant().Contains($s) -or
            ([string]$_.q).ToLowerInvariant().Contains($s) -or
            ([string]$_.dir).ToLowerInvariant().Contains($s) -or
            ([string]$_.mt).ToLowerInvariant().Contains($s) -or
            ([string]$_.dc).ToLowerInvariant().Contains($s)
        })
    }

    if ($Filters.ContainsKey('Direction') -and $Filters['Direction']) {
        $dir = $Filters['Direction'].ToLowerInvariant()
        $result = @($result | Where-Object { ([string]$_.dir).ToLowerInvariant() -eq $dir })
    }

    if ($Filters.ContainsKey('MediaType') -and $Filters['MediaType']) {
        $mt = $Filters['MediaType'].ToLowerInvariant()
        $result = @($result | Where-Object { ([string]$_.mt).ToLowerInvariant() -eq $mt })
    }

    if ($Filters.ContainsKey('HasMos') -and $Filters['HasMos']) {
        $result = @($result | Where-Object { $_.mos -eq 1 })
    }

    if ($Filters.ContainsKey('HasHolds') -and $Filters['HasHolds']) {
        $result = @($result | Where-Object { $_.hld -eq 1 })
    }

    if ($Filters.ContainsKey('Disconnected') -and $Filters['Disconnected']) {
        $result = @($result | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.dc) })
    }

    if ($Filters.ContainsKey('Queue') -and $Filters['Queue']) {
        $q = $Filters['Queue'].ToLowerInvariant()
        $result = @($result | Where-Object { ([string]$_.q).ToLowerInvariant().Contains($q) })
    }

    return $result
}

function Get-IndexedPage {
    <#
    .SYNOPSIS
        Returns a page of full conversation records from the run's data files.
        Lookup is O(pageSize) after index is loaded — no full-file rescan per page.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunFolder,

        [int]$PageNumber   = 0,
        [int]$PageSize     = 50,
        [string]$SearchText = '',
        [hashtable]$Filters = @{}
    )

    $index    = Load-RunIndex -RunFolder $RunFolder
    $filtered = Get-FilteredIndex -Index $index -SearchText $SearchText -Filters $Filters

    $totalCount  = $filtered.Count
    $totalPages  = [Math]::Max(1, [Math]::Ceiling($totalCount / $PageSize))
    $clampedPage = [Math]::Max(0, [Math]::Min($PageNumber, $totalPages - 1))
    $skip        = $clampedPage * $PageSize
    $pageEntries = @($filtered | Select-Object -Skip $skip -First $PageSize)

    # Group entries by file for efficient sequential seeking
    $byFile = [ordered]@{}
    foreach ($entry in $pageEntries) {
        $absPath = [System.IO.Path]::GetFullPath(
            [System.IO.Path]::Combine($RunFolder, [string]$entry.f)
        )
        if (-not $byFile.Contains($absPath)) { $byFile[$absPath] = [System.Collections.Generic.List[object]]::new() }
        $byFile[$absPath].Add($entry)
    }

    # Read full records via byte-offset seek — O(pageSize) total
    $recordMap = @{}  # id -> record
    foreach ($filePath in $byFile.Keys) {
        if (-not (Test-Path -Path $filePath)) { continue }

        $fs     = [System.IO.FileStream]::new($filePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)

        try {
            foreach ($entry in @($byFile[$filePath])) {
                $fs.Seek([long]$entry.o, [System.IO.SeekOrigin]::Begin) | Out-Null
                $reader.DiscardBufferedData()
                $line = $reader.ReadLine()
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    try {
                        $rec = $line | ConvertFrom-Json
                        $recordMap[[string]$entry.id] = $rec
                    }
                    catch {}
                }
            }
        }
        finally {
            $reader.Dispose()
            $fs.Dispose()
        }
    }

    # Return records in original index order
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $pageEntries) {
        if ($recordMap.ContainsKey([string]$entry.id)) {
            $records.Add($recordMap[[string]$entry.id])
        }
    }

    return [pscustomobject]@{
        Records     = $records.ToArray()
        PageNumber  = $clampedPage
        PageSize    = $PageSize
        TotalCount  = $totalCount
        TotalPages  = $totalPages
        HasPrev     = ($clampedPage -gt 0)
        HasNext     = ($clampedPage -lt ($totalPages - 1))
    }
}

function Get-ConversationRecord {
    <#
    .SYNOPSIS
        Retrieves a single conversation record by ID from the run's data files.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunFolder,

        [Parameter(Mandatory = $true)]
        [string]$ConversationId
    )

    $index = Load-RunIndex -RunFolder $RunFolder
    $entry = $index | Where-Object { $_.id -eq $ConversationId } | Select-Object -First 1

    if ($null -eq $entry) { return $null }

    $absPath = [System.IO.Path]::GetFullPath(
        [System.IO.Path]::Combine($RunFolder, [string]$entry.f)
    )

    $fs     = [System.IO.FileStream]::new($absPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)

    try {
        $fs.Seek([long]$entry.o, [System.IO.SeekOrigin]::Begin) | Out-Null
        $reader.DiscardBufferedData()
        $line = $reader.ReadLine()
        if ($line) { return ($line | ConvertFrom-Json) }
        return $null
    }
    finally {
        $reader.Dispose()
        $fs.Dispose()
    }
}

function Get-RunTotalCount {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RunFolder)

    $index = Load-RunIndex -RunFolder $RunFolder
    return $index.Count
}

Export-ModuleMember -Function Build-RunIndex, Load-RunIndex, Clear-IndexCache, Get-IndexedPage, Get-ConversationRecord, Get-RunTotalCount, Get-FilteredIndex
