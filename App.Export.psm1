#Requires -Version 5.1
# App.Export.psm1 — Streaming exports from run artifacts. No API calls. No full in-memory load.
Set-StrictMode -Version Latest

function ConvertTo-FlatRow {
    <#
    .SYNOPSIS
        Converts a raw conversation record (from Core data JSONL) into a flat export row.
        Includes participant rollups, hold/transfer counts, MOS, and optional attributes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Conversation,

        [switch]$IncludeAttributes
    )

    $conv = $Conversation

    # Duration
    $durationMs        = [long]0
    $durationFormatted = ''
    if ($conv.conversationStart -and $conv.conversationEnd) {
        try {
            $dtS        = [datetime]::Parse([string]$conv.conversationStart, [System.Globalization.CultureInfo]::InvariantCulture)
            $dtE        = [datetime]::Parse([string]$conv.conversationEnd,   [System.Globalization.CultureInfo]::InvariantCulture)
            $span       = $dtE - $dtS
            $durationMs = [long]$span.TotalMilliseconds
            $durationFormatted = '{0:D2}:{1:D2}:{2:D2}' -f [int]$span.Hours, [int]$span.Minutes, [int]$span.Seconds
        }
        catch {}
    }

    # Participant analysis
    $direction     = ''
    $divisionIds   = [System.Collections.Generic.List[string]]::new()
    $queueNames    = [System.Collections.Generic.List[string]]::new()
    $flowNames     = [System.Collections.Generic.List[string]]::new()
    $mediaTypes    = [System.Collections.Generic.List[string]]::new()
    $agentCount    = 0
    $customerCount = 0
    $acdCount      = 0
    $discType      = ''
    $holdCount     = 0
    $holdTotalMs   = [long]0
    $holdMaxMs     = [long]0
    $transferCount = 0
    $mosValues     = [System.Collections.Generic.List[double]]::new()
    $partCount     = 0

    if ($conv.participants) {
        $partCount = @($conv.participants).Count

        foreach ($p in @($conv.participants)) {
            switch ([string]$p.purpose) {
                'agent'    { $agentCount++ }
                'customer' { $customerCount++ }
                'acd'      { $acdCount++ }
            }

            if ($p.divisionIds) {
                foreach ($d in @($p.divisionIds)) {
                    if ($d -and -not $divisionIds.Contains([string]$d)) { $divisionIds.Add([string]$d) }
                }
            }

            if (-not $p.sessions) { continue }

            foreach ($session in @($p.sessions)) {
                if ($session.mediaType) {
                    $mt = [string]$session.mediaType
                    if (-not $mediaTypes.Contains($mt)) { $mediaTypes.Add($mt) }
                }
                if ($session.queueName) {
                    $qn = [string]$session.queueName
                    if (-not $queueNames.Contains($qn)) { $queueNames.Add($qn) }
                }
                if ($session.flowName) {
                    $fn = [string]$session.flowName
                    if (-not $flowNames.Contains($fn)) { $flowNames.Add($fn) }
                }
                if ($p.purpose -eq 'customer' -and $session.direction -and -not $direction) {
                    $direction = [string]$session.direction
                }
                if ($session.mos) {
                    try { $mosValues.Add([double]$session.mos) } catch {}
                }

                if (-not $session.segments) { continue }

                foreach ($seg in @($session.segments)) {
                    if ($seg.disconnectType -and -not $discType) {
                        $discType = [string]$seg.disconnectType
                    }
                    if ([string]$seg.segmentType -eq 'hold') {
                        $holdCount++
                        if ($seg.segmentStart -and $seg.segmentEnd) {
                            try {
                                $hs  = [datetime]::Parse([string]$seg.segmentStart, [System.Globalization.CultureInfo]::InvariantCulture)
                                $he  = [datetime]::Parse([string]$seg.segmentEnd,   [System.Globalization.CultureInfo]::InvariantCulture)
                                $hms = [long]($he - $hs).TotalMilliseconds
                                $holdTotalMs += $hms
                                if ($hms -gt $holdMaxMs) { $holdMaxMs = $hms }
                            }
                            catch {}
                        }
                    }
                    if ([string]$seg.segmentType -eq 'transfer') { $transferCount++ }
                }
            }
        }
    }

    $mosAvg = if ($mosValues.Count -gt 0) { [Math]::Round(($mosValues | Measure-Object -Average).Average, 2) } else { $null }
    $mosMin = if ($mosValues.Count -gt 0) { [Math]::Round(($mosValues | Measure-Object -Minimum).Minimum, 2) } else { $null }

    $row = [ordered]@{
        ConversationId   = [string]$conv.conversationId
        StartTime        = [string]$conv.conversationStart
        EndTime          = [string]$conv.conversationEnd
        DurationMs       = $durationMs
        Duration         = $durationFormatted
        Direction        = $direction
        DivisionIds      = ($divisionIds -join '; ')
        Queues           = ($queueNames -join '; ')
        Flows            = ($flowNames -join '; ')
        MediaTypes       = ($mediaTypes -join '; ')
        ParticipantCount = $partCount
        AgentCount       = $agentCount
        CustomerCount    = $customerCount
        DisconnectType   = $discType
        HoldCount        = $holdCount
        HoldTotalMs      = $holdTotalMs
        HoldMaxMs        = $holdMaxMs
        TransferCount    = $transferCount
        MosAverage       = if ($null -ne $mosAvg) { $mosAvg } else { '' }
        MosMin           = if ($null -ne $mosMin) { $mosMin } else { '' }
    }

    if ($IncludeAttributes -and $conv.attributes) {
        foreach ($key in $conv.attributes.PSObject.Properties.Name) {
            $row["attr_$($key)"] = [string]$conv.attributes.$key
        }
    }

    return [pscustomobject]$row
}

function Get-CsvHeaderLine {
    param([pscustomobject]$Row)
    return ($Row.PSObject.Properties.Name | ForEach-Object { "`"$($_)`"" }) -join ','
}

function Get-CsvValueLine {
    param([pscustomobject]$Row)
    $values = $Row.PSObject.Properties.Value | ForEach-Object {
        $v = if ($null -eq $_) { '' } else { [string]$_ }
        "`"$($v.Replace('"', '""'))`""
    }
    return ($values -join ',')
}

function Export-PageToCsv {
    <#
    .SYNOPSIS
        Exports the current page of records to a CSV file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Records,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [switch]$IncludeAttributes
    )

    $rows = @($Records | ForEach-Object { ConvertTo-FlatRow -Conversation $_ -IncludeAttributes:$IncludeAttributes })

    if ($rows.Count -eq 0) {
        Write-Warning "No records to export."
        return 0
    }

    $writer = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.Encoding]::UTF8)
    try {
        $writer.WriteLine((Get-CsvHeaderLine -Row $rows[0]))
        foreach ($row in $rows) {
            $writer.WriteLine((Get-CsvValueLine -Row $row))
        }
    }
    finally {
        $writer.Dispose()
    }

    return $rows.Count
}

function Export-RunToCsv {
    <#
    .SYNOPSIS
        Streams all records from a run's data JSONL files to a CSV.
        Never loads the full dataset into memory — O(1) peak memory per record.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunFolder,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [switch]$IncludeAttributes,
        [scriptblock]$OnProgress
    )

    $dataDir = [System.IO.Path]::Combine($RunFolder, 'data')
    if (-not (Test-Path -Path $dataDir)) {
        throw "No data directory at '$($dataDir)'"
    }

    $dataFiles     = [System.IO.Directory]::GetFiles($dataDir, '*.jsonl') | Sort-Object
    $headerWritten = $false
    $count         = 0
    $writer        = [System.IO.StreamWriter]::new($OutputPath, $false, [System.Text.Encoding]::UTF8)

    try {
        foreach ($dataFile in $dataFiles) {
            $reader = [System.IO.StreamReader]::new($dataFile, [System.Text.Encoding]::UTF8)
            try {
                while ($true) {
                    $line = $reader.ReadLine()
                    if ($null -eq $line) { break }
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }

                    try {
                        $rec = $line | ConvertFrom-Json
                        $row = ConvertTo-FlatRow -Conversation $rec -IncludeAttributes:$IncludeAttributes

                        if (-not $headerWritten) {
                            $writer.WriteLine((Get-CsvHeaderLine -Row $row))
                            $headerWritten = $true
                        }

                        $writer.WriteLine((Get-CsvValueLine -Row $row))
                        $count++

                        if ($OnProgress -and ($count % 500 -eq 0)) {
                            & $OnProgress $count
                        }
                    }
                    catch {}
                }
            }
            finally {
                $reader.Dispose()
            }
        }
    }
    finally {
        $writer.Dispose()
    }

    return $count
}

function Export-ConversationToJson {
    <#
    .SYNOPSIS
        Writes a single conversation record as pretty-printed JSON to disk.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Conversation,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $json = $Conversation | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.Encoding]::UTF8)
}

function Get-ConversationDisplayRow {
    <#
    .SYNOPSIS
        Returns a lightweight display row for DataGrid binding (DataTable row values).
        Fields match the DataGrid column bindings in MainWindow.xaml.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Conversation
    )

    $flat = ConvertTo-FlatRow -Conversation $Conversation

    # Format duration as mm:ss or hh:mm:ss
    $durFmt = $flat.Duration
    if (-not $durFmt -and $flat.DurationMs -gt 0) {
        $span   = [TimeSpan]::FromMilliseconds($flat.DurationMs)
        $durFmt = if ($span.Hours -gt 0) {
            '{0:D2}:{1:D2}:{2:D2}' -f $span.Hours, $span.Minutes, $span.Seconds
        }
        else {
            '{0:D2}:{1:D2}' -f $span.Minutes, $span.Seconds
        }
    }

    # Shorten timestamps for display
    $startDisp = if ($flat.StartTime) { try { [datetime]::Parse($flat.StartTime).ToString('yyyy-MM-dd HH:mm:ss') } catch { $flat.StartTime } } else { '' }
    $endDisp   = if ($flat.EndTime)   { try { [datetime]::Parse($flat.EndTime).ToString('HH:mm:ss') } catch { $flat.EndTime } } else { '' }

    return [pscustomobject]@{
        ConversationId   = $flat.ConversationId
        StartTime        = $startDisp
        EndTime          = $endDisp
        Duration         = $durFmt
        Direction        = $flat.Direction
        Queue            = $flat.Queues
        MediaTypes       = $flat.MediaTypes
        Participants     = $flat.ParticipantCount
        DisconnectType   = $flat.DisconnectType
        MOS              = $flat.MosAverage
        _Raw             = $Conversation   # Keep reference for drilldown
    }
}

Export-ModuleMember -Function ConvertTo-FlatRow, Export-PageToCsv, Export-RunToCsv, Export-ConversationToJson, Get-ConversationDisplayRow
