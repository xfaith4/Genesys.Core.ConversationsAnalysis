#Requires -Version 5.1
# App.UI.ps1 — WPF event handlers, background extraction, grid population, drilldown.
# Dot-sourced by App.ps1 after $window is loaded and modules imported.
# MUST NOT import Genesys.Core directly. All Core access is through App.CoreAdapter.psm1.
Set-StrictMode -Version Latest

# ═══════════════════════════════════════════════════════════════════════
# Control References
# ═══════════════════════════════════════════════════════════════════════
$script:Controls = @{
    # Header
    BtnConnect          = $window.FindName('BtnConnect')
    BtnDisconnect       = $window.FindName('BtnDisconnect')
    BtnSettings         = $window.FindName('BtnSettings')
    TxtConnStatus       = $window.FindName('TxtConnStatus')
    EllConnDot          = $window.FindName('EllConnDot')
    BdrConnStatus       = $window.FindName('BdrConnStatus')

    # Left panel
    RbPreview           = $window.FindName('RbPreview')
    RbFullRun           = $window.FindName('RbFullRun')
    TxtRunTypeDesc      = $window.FindName('TxtRunTypeDesc')
    DtpStart            = $window.FindName('DtpStart')
    DtpEnd              = $window.FindName('DtpEnd')
    CboDirection        = $window.FindName('CboDirection')
    CboMediaType        = $window.FindName('CboMediaType')
    TxtQueueFilter      = $window.FindName('TxtQueueFilter')
    CboPreviewPageSize  = $window.FindName('CboPreviewPageSize')
    BtnRun              = $window.FindName('BtnRun')
    BtnCancelRun        = $window.FindName('BtnCancelRun')
    BdrProgress         = $window.FindName('BdrProgress')
    TxtRunProgress      = $window.FindName('TxtRunProgress')
    PbRun               = $window.FindName('PbRun')
    LstRecentRuns       = $window.FindName('LstRecentRuns')
    BtnRefreshRuns      = $window.FindName('BtnRefreshRuns')
    BtnOpenRunFolder    = $window.FindName('BtnOpenRunFolder')

    # Conversations tab
    TxtSearch           = $window.FindName('TxtSearch')
    TbtnInbound         = $window.FindName('TbtnInbound')
    TbtnOutbound        = $window.FindName('TbtnOutbound')
    TbtnVoiceOnly       = $window.FindName('TbtnVoiceOnly')
    TbtnHasMOS          = $window.FindName('TbtnHasMOS')
    TbtnHasHolds        = $window.FindName('TbtnHasHolds')
    TbtnDisconnected    = $window.FindName('TbtnDisconnected')
    BtnClearFilters     = $window.FindName('BtnClearFilters')
    BtnExportPage       = $window.FindName('BtnExportPage')
    BtnExportRun        = $window.FindName('BtnExportRun')
    DgConversations     = $window.FindName('DgConversations')
    BtnPrevPage         = $window.FindName('BtnPrevPage')
    BtnNextPage         = $window.FindName('BtnNextPage')
    TxtPageInfo         = $window.FindName('TxtPageInfo')
    CboPageSize         = $window.FindName('CboPageSize')

    # Context menu
    CmiCopyId           = $window.FindName('CmiCopyId')
    CmiCopyRow          = $window.FindName('CmiCopyRow')
    CmiOpenDrilldown    = $window.FindName('CmiOpenDrilldown')
    CmiExportJson       = $window.FindName('CmiExportJson')

    # Drilldown
    TabDrilldown        = $window.FindName('TabDrilldown')
    BtnBackToList       = $window.FindName('BtnBackToList')
    TxtDrilldownId      = $window.FindName('TxtDrilldownId')
    BtnDrillCopyId      = $window.FindName('BtnDrillCopyId')
    BtnDrillExportJson  = $window.FindName('BtnDrillExportJson')
    TxtSumId            = $window.FindName('TxtSumId')
    TxtSumStart         = $window.FindName('TxtSumStart')
    TxtSumEnd           = $window.FindName('TxtSumEnd')
    TxtSumDur           = $window.FindName('TxtSumDur')
    TxtSumDir           = $window.FindName('TxtSumDir')
    TxtSumParts         = $window.FindName('TxtSumParts')
    TxtSumMedia         = $window.FindName('TxtSumMedia')
    TxtSumDisconn       = $window.FindName('TxtSumDisconn')
    TxtSumQueue         = $window.FindName('TxtSumQueue')
    TxtSumHolds         = $window.FindName('TxtSumHolds')
    TxtSumTransfers     = $window.FindName('TxtSumTransfers')
    TxtSumMos           = $window.FindName('TxtSumMos')
    DgParticipants      = $window.FindName('DgParticipants')
    DgSegments          = $window.FindName('DgSegments')
    TxtAttrSearch       = $window.FindName('TxtAttrSearch')
    DgAttributes        = $window.FindName('DgAttributes')
    PnlMos              = $window.FindName('PnlMos')
    TxtNoMos            = $window.FindName('TxtNoMos')
    TxtRawJson          = $window.FindName('TxtRawJson')
    BtnCopyJson         = $window.FindName('BtnCopyJson')

    # Run Console
    TxtRunStatus        = $window.FindName('TxtRunStatus')
    EllRunDot           = $window.FindName('EllRunDot')
    TxtConsoleRunPath   = $window.FindName('TxtConsoleRunPath')
    DgConsoleEvents     = $window.FindName('DgConsoleEvents')
    BtnCopyDiagnostics  = $window.FindName('BtnCopyDiagnostics')
    BtnClearConsole     = $window.FindName('BtnClearConsole')

    # Tabs
    MainTabControl      = $window.FindName('MainTabControl')
    TabConversations    = $window.FindName('TabConversations')

    # Status bar
    TxtStatusMain       = $window.FindName('TxtStatusMain')
    TxtStatusCount      = $window.FindName('TxtStatusCount')
    TxtStatusRun        = $window.FindName('TxtStatusRun')
}

# ═══════════════════════════════════════════════════════════════════════
# Application state
# ═══════════════════════════════════════════════════════════════════════
$script:State = @{
    CurrentRunFolder       = $null
    CurrentPage            = 0
    PageSize               = 50
    SearchText             = ''
    QuickFilters           = @{}
    SelectedConversation   = $null    # Full record object
    AllAttributes          = @()      # Unfiltered attribute KV pairs
    BackgroundPS           = $null
    BackgroundHandle       = $null
    BackgroundRunspace     = $null
    SyncHash               = $null
    RefreshTimer           = $null
    ConsoleEventCount      = 0
    LastRunDatasetKey      = ''
    LastRunDatasetParams   = @{}
}

# ═══════════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════════

function Set-StatusBar {
    param([string]$Main = '', [string]$Count = '', [string]$Run = '')
    if ($Main)  { $script:Controls.TxtStatusMain.Text  = $Main  }
    if ($Count) { $script:Controls.TxtStatusCount.Text = $Count }
    if ($Run)   { $script:Controls.TxtStatusRun.Text   = $Run   }
}

function Set-RunStatusBadge {
    param([string]$Status)
    $ctrl = $script:Controls
    $ctrl.TxtRunStatus.Text = $Status
    switch ($Status) {
        'Running'  { $ctrl.EllRunDot.Fill = [System.Windows.Media.Brushes]::LimeGreen;  $ctrl.TxtRunStatus.Foreground = [System.Windows.Media.Brushes]::LimeGreen }
        'Complete' { $ctrl.EllRunDot.Fill = [System.Windows.Media.Brushes]::CadetBlue;  $ctrl.TxtRunStatus.Foreground = [System.Windows.Media.Brushes]::CadetBlue }
        'Failed'   { $ctrl.EllRunDot.Fill = [System.Windows.Media.Brushes]::Tomato;     $ctrl.TxtRunStatus.Foreground = [System.Windows.Media.Brushes]::Tomato }
        default    { $ctrl.EllRunDot.Fill = [System.Windows.Media.Brushes]::Gray;       $ctrl.TxtRunStatus.Foreground = [System.Windows.Media.Brushes]::Gray }
    }
}

function Set-ConnectionStatus {
    param([bool]$Connected, [string]$Label = '')
    $ctrl = $script:Controls
    if ($Connected) {
        $ctrl.TxtConnStatus.Text       = if ($Label) { $Label } else { 'Connected' }
        $ctrl.TxtConnStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $ctrl.EllConnDot.Fill          = [System.Windows.Media.Brushes]::LimeGreen
        $ctrl.BtnConnect.Visibility    = [System.Windows.Visibility]::Collapsed
        $ctrl.BtnDisconnect.Visibility = [System.Windows.Visibility]::Visible
    }
    else {
        $ctrl.TxtConnStatus.Text       = 'Disconnected'
        $ctrl.TxtConnStatus.Foreground = [System.Windows.Media.Brushes]::Gray
        $ctrl.EllConnDot.Fill          = [System.Windows.Media.Brushes]::DimGray
        $ctrl.BtnConnect.Visibility    = [System.Windows.Visibility]::Visible
        $ctrl.BtnDisconnect.Visibility = [System.Windows.Visibility]::Collapsed
    }
}

function Get-ActiveQuickFilters {
    $f = @{}
    if ($script:Controls.TbtnInbound.IsChecked)     { $f['Direction'] = 'inbound'  }
    if ($script:Controls.TbtnOutbound.IsChecked)    { $f['Direction'] = 'outbound' }
    if ($script:Controls.TbtnVoiceOnly.IsChecked)   { $f['MediaType'] = 'voice'    }
    if ($script:Controls.TbtnHasMOS.IsChecked)      { $f['HasMos']    = $true      }
    if ($script:Controls.TbtnHasHolds.IsChecked)    { $f['HasHolds']  = $true      }
    if ($script:Controls.TbtnDisconnected.IsChecked){ $f['Disconnected'] = $true   }
    return $f
}

function Get-PageSizeFromCombo {
    $item = $script:Controls.CboPageSize.SelectedItem
    if ($item -and $item.Content) { try { return [int]$item.Content } catch {} }
    return 50
}

function Build-ConversationsDataTable {
    param([object[]]$Records)

    $dt = [System.Data.DataTable]::new()
    $dt.Columns.Add('ConversationId') | Out-Null
    $dt.Columns.Add('StartTime')      | Out-Null
    $dt.Columns.Add('Duration')       | Out-Null
    $dt.Columns.Add('Direction')      | Out-Null
    $dt.Columns.Add('Queue')          | Out-Null
    $dt.Columns.Add('MediaTypes')     | Out-Null
    $dt.Columns.Add('Participants')   | Out-Null
    $dt.Columns.Add('DisconnectType') | Out-Null
    $dt.Columns.Add('MOS')            | Out-Null

    foreach ($rec in $Records) {
        $row = Get-ConversationDisplayRow -Conversation $rec
        $dr  = $dt.NewRow()
        $dr['ConversationId'] = [string]$row.ConversationId
        $dr['StartTime']      = [string]$row.StartTime
        $dr['Duration']       = [string]$row.Duration
        $dr['Direction']      = [string]$row.Direction
        $dr['Queue']          = [string]$row.Queue
        $dr['MediaTypes']     = [string]$row.MediaTypes
        $dr['Participants']   = [string]$row.Participants
        $dr['DisconnectType'] = [string]$row.DisconnectType
        $dr['MOS']            = [string]$row.MOS
        $dt.Rows.Add($dr)
    }

    return $dt
}

function Refresh-ConversationsGrid {
    if (-not $script:State.CurrentRunFolder) {
        $script:Controls.TxtPageInfo.Text = 'No data loaded'
        $script:Controls.DgConversations.ItemsSource = $null
        return
    }

    $pageSize = Get-PageSizeFromCombo
    $filters  = Get-ActiveQuickFilters

    try {
        $result = Get-IndexedPage `
            -RunFolder   $script:State.CurrentRunFolder `
            -PageNumber  $script:State.CurrentPage `
            -PageSize    $pageSize `
            -SearchText  $script:State.SearchText `
            -Filters     $filters

        $script:State.PageSize = $pageSize

        $dt = Build-ConversationsDataTable -Records $result.Records
        $script:Controls.DgConversations.ItemsSource = $dt.DefaultView

        # Paging info
        $script:Controls.TxtPageInfo.Text = "Page $($result.PageNumber + 1) of $($result.TotalPages)  ($($result.TotalCount) records)"
        $script:Controls.BtnPrevPage.IsEnabled = $result.HasPrev
        $script:Controls.BtnNextPage.IsEnabled = $result.HasNext

        Set-StatusBar -Count "$($result.TotalCount) records"

        # Store current page records for export
        $script:State.CurrentPageRecords = $result.Records
        $script:State.CurrentPage = $result.PageNumber
    }
    catch {
        Set-StatusBar -Main "Error loading page: $($_)"
    }
}

function Open-RunFolder {
    param([string]$RunFolder)

    if (-not (Test-Path -Path $RunFolder)) {
        [System.Windows.MessageBox]::Show("Run folder not found:`n$($RunFolder)", "Error",
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    Set-StatusBar -Main "Building index for run..." -Run $RunFolder

    try {
        Build-RunIndex -RunFolder $RunFolder | Out-Null
    }
    catch {
        [System.Windows.MessageBox]::Show("Failed to build index:`n$($_)", "Index Error",
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    $script:State.CurrentRunFolder = $RunFolder
    $script:State.CurrentPage      = 0

    # Update console path
    $script:Controls.TxtConsoleRunPath.Text = $RunFolder

    # Add to recent runs
    try {
        $manifest = Get-RunManifest -RunFolder $RunFolder
        $dKey     = if ($manifest) { [string]$manifest.datasetKey } else { '' }
        Add-RecentRun -RunFolder $RunFolder -DatasetKey $dKey
    }
    catch {}

    Refresh-ConversationsGrid
    Refresh-RecentRuns
    Refresh-ConsoleEvents -Force

    $status = Get-RunStatus -RunFolder $RunFolder
    Set-RunStatusBadge -Status $status
    Set-StatusBar -Main "Run loaded" -Run ([System.IO.Path]::GetFileName($RunFolder))
}

function Refresh-RecentRuns {
    $recent = Get-RecentRuns
    $items  = @($recent | ForEach-Object {
        $folderName = [System.IO.Path]::GetFileName([string]$_.RunFolder)
        [pscustomobject]@{
            DisplayName = "$([string]$_.DatasetKey) / $($folderName)"
            Status      = [string]$_.Status
            ItemCount   = [string]$_.ItemCount
            RunFolder   = [string]$_.RunFolder
        }
    })

    # Also scan OutputRoot
    try {
        $cfg     = Get-AppConfig
        $scanned = Get-RecentRunFolders -OutputRoot $cfg.OutputRoot -Limit 15
        $scanned | ForEach-Object {
            $folderName = [System.IO.Path]::GetFileName([string]$_.RunFolder)
            if (-not ($items | Where-Object { $_.RunFolder -eq [string]$_.RunFolder })) {
                $items += [pscustomobject]@{
                    DisplayName = "$([string]$_.DatasetKey) / $($folderName)"
                    Status      = [string]$_.Status
                    ItemCount   = [string]$_.ItemCount
                    RunFolder   = [string]$_.RunFolder
                }
            }
        }
    }
    catch {}

    $script:Controls.LstRecentRuns.ItemsSource = @($items | Select-Object -First 20)
}

function Refresh-ConsoleEvents {
    param([switch]$Force)

    if (-not $script:State.CurrentRunFolder) { return }

    try {
        $events = Get-RunEvents -RunFolder $script:State.CurrentRunFolder -Last 200

        if (-not $Force -and $events.Count -eq $script:State.ConsoleEventCount) { return }

        $script:State.ConsoleEventCount = $events.Count

        $rows = @($events | ForEach-Object {
            $ts    = if ($_.ts)      { [string]$_.ts }      else { '' }
            $level = if ($_.level)   { ([string]$_.level).ToUpper() } else { 'INFO' }
            $event = if ($_.event)   { [string]$_.event }   else { if ($_.eventType) { [string]$_.eventType } else { '' } }
            $msg   = if ($_.message) { [string]$_.message } else { if ($_.payload)   { ($_.payload | ConvertTo-Json -Compress) } else { '' } }

            [pscustomobject]@{
                Ts      = $ts
                Level   = $level
                Event   = $event
                Message = $msg
            }
        })

        $script:Controls.DgConsoleEvents.ItemsSource = $rows

        # Scroll to bottom
        if ($rows.Count -gt 0) {
            $script:Controls.DgConsoleEvents.ScrollIntoView($rows[-1])
        }
    }
    catch {}
}

function Populate-Drilldown {
    param([object]$Conversation)

    $script:State.SelectedConversation = $Conversation
    $ctrl = $script:Controls

    $flat = ConvertTo-FlatRow -Conversation $Conversation

    # Summary
    $ctrl.TxtDrilldownId.Text  = [string]$flat.ConversationId
    $ctrl.TxtSumId.Text        = [string]$flat.ConversationId
    $ctrl.TxtSumStart.Text     = [string]$flat.StartTime
    $ctrl.TxtSumEnd.Text       = [string]$flat.EndTime
    $ctrl.TxtSumDur.Text       = [string]$flat.Duration
    $ctrl.TxtSumDir.Text       = [string]$flat.Direction
    $ctrl.TxtSumParts.Text     = [string]$flat.ParticipantCount
    $ctrl.TxtSumMedia.Text     = [string]$flat.MediaTypes
    $ctrl.TxtSumDisconn.Text   = [string]$flat.DisconnectType
    $ctrl.TxtSumQueue.Text     = [string]$flat.Queues
    $ctrl.TxtSumHolds.Text     = "$($flat.HoldCount) hold(s)  total=$($flat.HoldTotalMs)ms  max=$($flat.HoldMaxMs)ms"
    $ctrl.TxtSumTransfers.Text = [string]$flat.TransferCount
    $mosText = if ($flat.MosAverage) { "avg=$($flat.MosAverage) / min=$($flat.MosMin)" } else { 'N/A' }
    $ctrl.TxtSumMos.Text = $mosText

    # Participants
    $partRows = [System.Collections.Generic.List[object]]::new()
    if ($Conversation.participants) {
        foreach ($p in @($Conversation.participants)) {
            $mt  = ''
            $dir = ''
            $q   = ''
            $mos = ''
            if ($p.sessions) {
                $sess = @($p.sessions)[0]
                if ($sess) {
                    $mt  = [string]$sess.mediaType
                    $dir = [string]$sess.direction
                    $q   = [string]$sess.queueName
                    if ($sess.mos) { $mos = [string]$sess.mos }
                }
            }
            $partRows.Add([pscustomobject]@{
                Purpose   = [string]$p.purpose
                UserId    = [string]$p.userId
                Name      = [string]$p.name
                MediaType = $mt
                Direction = $dir
                Queue     = $q
                Mos       = $mos
            })
        }
    }
    $ctrl.DgParticipants.ItemsSource = $partRows.ToArray()

    # Segments
    $segRows = [System.Collections.Generic.List[object]]::new()
    $seqNo   = 0
    if ($Conversation.participants) {
        foreach ($p in @($Conversation.participants)) {
            if (-not $p.sessions) { continue }
            foreach ($sess in @($p.sessions)) {
                if (-not $sess.segments) { continue }
                foreach ($seg in @($sess.segments)) {
                    $durFmt = ''
                    if ($seg.segmentStart -and $seg.segmentEnd) {
                        try {
                            $ds  = [datetime]::Parse([string]$seg.segmentStart, [System.Globalization.CultureInfo]::InvariantCulture)
                            $de  = [datetime]::Parse([string]$seg.segmentEnd,   [System.Globalization.CultureInfo]::InvariantCulture)
                            $sp  = $de - $ds
                            $durFmt = '{0:D2}:{1:D2}' -f $sp.Minutes, $sp.Seconds
                        }
                        catch {}
                    }
                    $segRows.Add([pscustomobject]@{
                        SeqNo          = $seqNo
                        Participant    = [string]$p.purpose
                        SegmentType    = [string]$seg.segmentType
                        SegStart       = [string]$seg.segmentStart
                        SegEnd         = [string]$seg.segmentEnd
                        Duration       = $durFmt
                        DisconnectType = [string]$seg.disconnectType
                        QueueFlow      = ((@([string]$seg.queueName, [string]$seg.flowName) | Where-Object { $_ }) -join ' / ')
                        IsHold         = ([string]$seg.segmentType -eq 'hold')
                        IsTransfer     = ([string]$seg.segmentType -eq 'transfer')
                    })
                    $seqNo++
                }
            }
        }
    }
    $ctrl.DgSegments.ItemsSource = $segRows.ToArray()

    # Attributes
    $attrRows = [System.Collections.Generic.List[object]]::new()
    if ($Conversation.attributes) {
        foreach ($key in $Conversation.attributes.PSObject.Properties.Name) {
            $attrRows.Add([pscustomobject]@{
                Key   = $key
                Value = [string]$Conversation.attributes.$key
            })
        }
    }
    $script:State.AllAttributes = $attrRows.ToArray()
    $ctrl.DgAttributes.ItemsSource = $script:State.AllAttributes

    # MOS / Quality
    $mosItems = [System.Collections.Generic.List[object]]::new()
    if ($Conversation.participants) {
        foreach ($p in @($Conversation.participants)) {
            if (-not $p.sessions) { continue }
            foreach ($sess in @($p.sessions)) {
                if ($sess.mos) {
                    $mosItems.Add([pscustomobject]@{
                        Participant = [string]$p.purpose
                        UserId      = [string]$p.userId
                        MediaType   = [string]$sess.mediaType
                        MOS         = [string]$sess.mos
                    })
                }
            }
        }
    }

    # Remove placeholder and rebuild MOS panel
    $ctrl.PnlMos.Children.Clear()
    if ($mosItems.Count -gt 0) {
        $dg = [System.Windows.Controls.DataGrid]::new()
        $dg.IsReadOnly   = $true
        $dg.Background   = [System.Windows.Media.Brushes]::Transparent
        $dg.Foreground   = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(226,229,236))
        $dg.BorderThickness = [System.Windows.Thickness]::new(0)
        $dg.ItemsSource  = $mosItems.ToArray()
        $ctrl.PnlMos.Children.Add($dg)
    }
    else {
        $tb = [System.Windows.Controls.TextBlock]::new()
        $tb.Text = 'No MOS data for this conversation.'
        $tb.Foreground = [System.Windows.Media.Brushes]::Gray
        $tb.FontSize   = 12
        $ctrl.PnlMos.Children.Add($tb)
    }

    # Raw JSON
    $ctrl.TxtRawJson.Text = ($Conversation | ConvertTo-Json -Depth 20)

    # Enable drilldown tab and switch to it
    $ctrl.TabDrilldown.IsEnabled = $true
    $ctrl.MainTabControl.SelectedItem = $ctrl.TabDrilldown
}

# ═══════════════════════════════════════════════════════════════════════
# Background Extraction (Runspace + SyncHash)
# ═══════════════════════════════════════════════════════════════════════

function Start-BackgroundRun {
    param(
        [string]$Mode,            # 'preview' | 'full'
        [hashtable]$DatasetParams,
        [string]$OutputRoot,
        [hashtable]$Headers,
        [string]$AdapterModule,
        [string]$CoreModulePath,
        [string]$CatalogPath,
        [string]$SchemaPath
    )

    # Create synchronized state hashtable
    $script:State.SyncHash = [hashtable]::Synchronized(@{
        Status    = 'Starting'
        RunFolder = $null
        Error     = $null
        Done      = $false
        Dispatcher = $window.Dispatcher
    })

    $syncRef = $script:State.SyncHash

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = 'MTA'
    $runspace.ThreadOptions  = 'ReuseThread'
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    [void]$ps.AddScript({
        param($SyncHash, $Mode, $DatasetParams, $OutputRoot, $Headers, $AdapterModule, $CoreModulePath, $CatalogPath, $SchemaPath)

        try {
            Import-Module $AdapterModule -Force -ErrorAction Stop
            Initialize-CoreAdapter -CoreModulePath $CoreModulePath -CatalogPath $CatalogPath -SchemaPath $SchemaPath

            $SyncHash.Status = 'Running'

            $runCtx = if ($Mode -eq 'preview') {
                Start-PreviewRun -DatasetParameters $DatasetParams -OutputRoot $OutputRoot -Headers $Headers
            }
            else {
                Start-FullRun -DatasetParameters $DatasetParams -OutputRoot $OutputRoot -Headers $Headers
            }

            $SyncHash.RunFolder = $runCtx.runFolder
            $SyncHash.Status    = 'Complete'
        }
        catch {
            $SyncHash.Error  = $_.Exception.Message
            $SyncHash.Status = 'Failed'
        }
        finally {
            $SyncHash.Done = $true
        }
    })

    [void]$ps.AddParameters(@{
        SyncHash      = $syncRef
        Mode          = $Mode
        DatasetParams = $DatasetParams
        OutputRoot    = $OutputRoot
        Headers       = $Headers
        AdapterModule = $AdapterModule
        CoreModulePath = $CoreModulePath
        CatalogPath    = $CatalogPath
        SchemaPath     = $SchemaPath
    })

    $script:State.BackgroundPS       = $ps
    $script:State.BackgroundRunspace = $runspace
    $script:State.BackgroundHandle   = $ps.BeginInvoke()
}

function Stop-BackgroundRun {
    param([switch]$Synchronous)

    $ps   = $script:State.BackgroundPS
    $rs   = $script:State.BackgroundRunspace
    $ar   = $script:State.BackgroundHandle

    $script:State.BackgroundPS       = $null
    $script:State.BackgroundRunspace = $null
    $script:State.BackgroundHandle   = $null

    if (-not $ps -and -not $rs) { return }

    $cleanupState = @{
        PS = $ps
        Runspace = $rs
        AsyncResult = $ar
    }

    $cleanupAction = {
        param($s)
        try {
            if ($s.AsyncResult -and -not $s.AsyncResult.IsCompleted) {
                if (-not $s.AsyncResult.AsyncWaitHandle.WaitOne(3000)) {
                    try { $s.PS.Stop() } catch {}
                }
            }
        }
        catch {}
        finally {
            try { $s.PS.Dispose() } catch {}
            try { $s.Runspace.Close() } catch {}
            try { $s.Runspace.Dispose() } catch {}
        }
    }

    if ($Synchronous) {
        & $cleanupAction $cleanupState
    }
    else {
        [void][System.Threading.ThreadPool]::QueueUserWorkItem($cleanupAction, $cleanupState)
    }
}

function Build-RunDatasetParams {
    param([string]$StartDate, [string]$EndDate, [string]$Direction, [string]$MediaType, [string]$QueueId, [int]$PageSize)

    $interval = "$($StartDate)T00:00:00.000Z/$($EndDate)T23:59:59.999Z"

    $params = [ordered]@{
        interval = $interval
    }

    if ($Direction -and $Direction -ne '(any)') {
        $params['segmentFilters'] = @(@{
            type       = 'and'
            predicates = @(@{
                type      = 'dimension'
                dimension = 'direction'
                operator  = 'matches'
                value     = $Direction
            })
        })
    }

    if ($MediaType -and $MediaType -ne '(any)') {
        if (-not $params['segmentFilters']) {
            $params['segmentFilters'] = @()
        }
        $params['segmentFilters'] += @{
            type       = 'and'
            predicates = @(@{
                type      = 'dimension'
                dimension = 'mediaType'
                operator  = 'matches'
                value     = $MediaType
            })
        }
    }

    if ($QueueId) {
        if (-not $params['segmentFilters']) {
            $params['segmentFilters'] = @()
        }
        $params['segmentFilters'] += @{
            type       = 'and'
            predicates = @(@{
                type      = 'dimension'
                dimension = 'queueId'
                operator  = 'matches'
                value     = $QueueId
            })
        }
    }

    if ($PageSize -gt 0) {
        $params['paging'] = @{ pageSize = $PageSize; pageNumber = 1 }
    }

    return $params
}

# ═══════════════════════════════════════════════════════════════════════
# Polling timer — updates UI from background sync hash
# ═══════════════════════════════════════════════════════════════════════

function Start-PollingTimer {
    $timer          = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [System.TimeSpan]::FromMilliseconds(800)
    $timerRef       = $timer

    $timer.Add_Tick({
        if (-not $script:State.SyncHash) { return }

        $sh = $script:State.SyncHash

        $script:Controls.TxtRunProgress.Text = "Status: $($sh.Status)"
        Set-RunStatusBadge -Status $sh.Status

        # Tail console events
        Refresh-ConsoleEvents

        if ($sh.Done) {
            $timerRef.Stop()
            $script:State.SyncHash = $null

            $script:Controls.BdrProgress.Visibility  = [System.Windows.Visibility]::Collapsed
            $script:Controls.BtnCancelRun.Visibility  = [System.Windows.Visibility]::Collapsed
            $script:Controls.BtnRun.Visibility        = [System.Windows.Visibility]::Visible

            if ($sh.Status -eq 'Complete' -and $sh.RunFolder) {
                Open-RunFolder -RunFolder $sh.RunFolder
                Set-StatusBar -Main "Run complete" -Run $sh.RunFolder
            }
            elseif ($sh.Status -eq 'Failed') {
                Set-StatusBar -Main "Run failed: $($sh.Error)"
                [System.Windows.MessageBox]::Show(
                    "Extraction failed:`n$($sh.Error)", "Run Failed",
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Error)
            }

            Stop-BackgroundRun
        }
    })

    $script:State.RefreshTimer = $timer
    $timer.Start()
}

# ═══════════════════════════════════════════════════════════════════════
# Auth Dialog (inline WPF window)
# ═══════════════════════════════════════════════════════════════════════

function Show-ConnectDialog {
    $cfg = Get-AppConfig

    $dlg = [System.Windows.Window]::new()
    $dlg.Title                 = 'Connect to Genesys Cloud'
    $dlg.Width                 = 440
    $dlg.Height                = 400
    $dlg.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    $dlg.Owner                 = $window
    $dlg.Background            = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(34,38,46))
    $dlg.ResizeMode            = [System.Windows.ResizeMode]::NoResize

    $grid        = [System.Windows.Controls.Grid]::new()
    $grid.Margin = [System.Windows.Thickness]::new(20)
    $sp          = [System.Windows.Controls.StackPanel]::new()

    # ── Helpers
    $mkLabel = { param($t)
        $lb = [System.Windows.Controls.TextBlock]::new()
        $lb.Text = $t; $lb.Foreground = [System.Windows.Media.Brushes]::LightGray
        $lb.FontSize = 11; $lb.Margin = [System.Windows.Thickness]::new(0,6,0,2)
        $lb
    }
    $mkBox = {
        $b = [System.Windows.Controls.TextBox]::new()
        $b.Background  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(44,49,64))
        $b.Foreground  = [System.Windows.Media.Brushes]::White
        $b.BorderBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(55,65,81))
        $b.Padding = [System.Windows.Thickness]::new(8,5,8,5); $b.FontSize = 12
        $b
    }
    $mkCboItemStyle = {
        $s = [System.Windows.Style]::new([System.Windows.Controls.ComboBoxItem])
        $s.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::BackgroundProperty, [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(44,49,64))))
        $s.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::ForegroundProperty, [System.Windows.Media.Brushes]::White))
        $s.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::PaddingProperty,    [System.Windows.Thickness]::new(8,5,8,5)))
        $hl = [System.Windows.Trigger]::new()
        $hl.Property = [System.Windows.Controls.ComboBoxItem]::IsHighlightedProperty; $hl.Value = $true
        $hl.Setters.Add([System.Windows.Setter]::new([System.Windows.Controls.Control]::BackgroundProperty, [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(56,64,90))))
        $s.Triggers.Add($hl); $s
    }

    # ── Title
    $title = [System.Windows.Controls.TextBlock]::new()
    $title.Text = 'Genesys Cloud Authentication'
    $title.Foreground = [System.Windows.Media.Brushes]::White
    $title.FontSize = 14; $title.FontWeight = [System.Windows.FontWeights]::SemiBold
    $title.Margin = [System.Windows.Thickness]::new(0,0,0,8)
    $sp.Children.Add($title)

    # ── Auth method selector
    $methodRow = [System.Windows.Controls.StackPanel]::new()
    $methodRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $methodRow.Margin = [System.Windows.Thickness]::new(0,0,0,6)

    $methodLbl = [System.Windows.Controls.TextBlock]::new()
    $methodLbl.Text = 'Method:'; $methodLbl.Width = 56
    $methodLbl.Foreground = [System.Windows.Media.Brushes]::LightGray
    $methodLbl.FontSize = 11; $methodLbl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $methodRow.Children.Add($methodLbl)

    $rbCC = [System.Windows.Controls.RadioButton]::new()
    $rbCC.Content = 'Client Credentials'; $rbCC.IsChecked = $true
    $rbCC.Foreground = [System.Windows.Media.Brushes]::White; $rbCC.FontSize = 11
    $rbCC.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $methodRow.Children.Add($rbCC)

    $rbPkce = [System.Windows.Controls.RadioButton]::new()
    $rbPkce.Content = 'Browser Login (PKCE)'
    $rbPkce.Foreground = [System.Windows.Media.Brushes]::White; $rbPkce.FontSize = 11
    $rbPkce.Margin = [System.Windows.Thickness]::new(16,0,0,0)
    $rbPkce.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $methodRow.Children.Add($rbPkce)
    $sp.Children.Add($methodRow)

    # ── Region (shared)
    $sp.Children.Add((& $mkLabel 'Region'))
    $cboRegion = [System.Windows.Controls.ComboBox]::new()
    $cboRegion.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(44,49,64))
    $cboRegion.Foreground = [System.Windows.Media.Brushes]::White
    @('usw2.pure.cloud','mypurecloud.com') | ForEach-Object { $cboRegion.Items.Add($_) | Out-Null }
    $cboRegion.SelectedIndex    = 0
    $cboRegion.ItemContainerStyle = (& $mkCboItemStyle)
    $sp.Children.Add($cboRegion)

    # ── Client Credentials panel
    $pnlCC = [System.Windows.Controls.StackPanel]::new()
    $pnlCC.Children.Add((& $mkLabel 'Client ID'))
    $txtCCClientId = & $mkBox
    $pnlCC.Children.Add($txtCCClientId)
    $pnlCC.Children.Add((& $mkLabel 'Client Secret'))
    $pwdSecret = [System.Windows.Controls.PasswordBox]::new()
    $pwdSecret.Background  = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(44,49,64))
    $pwdSecret.Foreground  = [System.Windows.Media.Brushes]::White
    $pwdSecret.BorderBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(55,65,81))
    $pwdSecret.Padding = [System.Windows.Thickness]::new(8,5,8,5); $pwdSecret.FontSize = 12
    $pnlCC.Children.Add($pwdSecret)
    $sp.Children.Add($pnlCC)

    # ── PKCE panel (hidden by default)
    $pnlPkce = [System.Windows.Controls.StackPanel]::new()
    $pnlPkce.Visibility = [System.Windows.Visibility]::Collapsed

    $pnlPkce.Children.Add((& $mkLabel 'Client ID'))
    $txtPkceClientId = & $mkBox
    $txtPkceClientId.Text = if ($cfg.PkceClientId) { [string]$cfg.PkceClientId } else { '' }
    $pnlPkce.Children.Add($txtPkceClientId)

    $pnlPkce.Children.Add((& $mkLabel 'Redirect URI'))
    $txtRedirectUri = & $mkBox
    $txtRedirectUri.Text = if ($cfg.RedirectUri) { [string]$cfg.RedirectUri } else { 'http://localhost:8180/callback' }
    $pnlPkce.Children.Add($txtRedirectUri)

    $pkceHint = [System.Windows.Controls.TextBlock]::new()
    $pkceHint.Text = 'Your browser will open for login. Ensure the redirect URI matches your OAuth client configuration.'
    $pkceHint.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(138,145,159))
    $pkceHint.FontSize = 10; $pkceHint.Margin = [System.Windows.Thickness]::new(0,4,0,0)
    $pkceHint.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $pnlPkce.Children.Add($pkceHint)
    $sp.Children.Add($pnlPkce)

    # ── PKCE status line (shown while waiting for browser)
    $txtPkceStatus = [System.Windows.Controls.TextBlock]::new()
    $txtPkceStatus.Foreground = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0,153,204))
    $txtPkceStatus.FontSize = 11; $txtPkceStatus.Margin = [System.Windows.Thickness]::new(0,8,0,0)
    $txtPkceStatus.Visibility = [System.Windows.Visibility]::Collapsed
    $sp.Children.Add($txtPkceStatus)

    # ── Buttons
    $btnRow = [System.Windows.Controls.StackPanel]::new()
    $btnRow.Orientation = [System.Windows.Controls.Orientation]::Horizontal
    $btnRow.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $btnRow.Margin = [System.Windows.Thickness]::new(0,14,0,0)

    $btnCancel = [System.Windows.Controls.Button]::new()
    $btnCancel.Content = 'Cancel'; $btnCancel.Width = 80; $btnCancel.Height = 32
    $btnCancel.Margin = [System.Windows.Thickness]::new(0,0,8,0)
    $btnCancel.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(44,49,64))
    $btnCancel.Foreground = [System.Windows.Media.Brushes]::White
    $btnRow.Children.Add($btnCancel)

    $btnOk = [System.Windows.Controls.Button]::new()
    $btnOk.Content = 'Connect'; $btnOk.Width = 100; $btnOk.Height = 32
    $btnOk.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0,153,204))
    $btnOk.Foreground = [System.Windows.Media.Brushes]::White
    $btnRow.Children.Add($btnOk)
    $sp.Children.Add($btnRow)

    $grid.Children.Add($sp)
    $dlg.Content = $grid

    # ── State
    $dlgResult = @{ Success = $false; Headers = $null; Region = '' }
    $pkceCtx   = @{
        Runspace = $null
        PS = $null
        Timer = $null
        SyncHash = $null
        Region = ''
        AsyncResult = $null
        CleanupQueued = $false
    }

    $queuePkceCleanup = {
        if ($pkceCtx.CleanupQueued) { return }
        if (-not $pkceCtx.PS -and -not $pkceCtx.Runspace) { return }

        $pkceCtx.CleanupQueued = $true
        $state = @{
            PS = $pkceCtx.PS
            Runspace = $pkceCtx.Runspace
            AsyncResult = $pkceCtx.AsyncResult
            SyncHash = $pkceCtx.SyncHash
        }

        [void][System.Threading.ThreadPool]::QueueUserWorkItem({
            param($s)
            try {
                if ($s.SyncHash) { $s.SyncHash.CancelRequested = $true }
                if ($s.AsyncResult -and -not $s.AsyncResult.IsCompleted) {
                    if (-not $s.AsyncResult.AsyncWaitHandle.WaitOne(3000)) {
                        try { $s.PS.Stop() } catch {}
                    }
                }
            }
            catch {}
            finally {
                try { $s.PS.Dispose() } catch {}
                try { $s.Runspace.Close() } catch {}
                try { $s.Runspace.Dispose() } catch {}
            }
        }, $state)

        $pkceCtx.PS = $null
        $pkceCtx.Runspace = $null
        $pkceCtx.AsyncResult = $null
    }

    $schedulePkceCleanup = {
        [void]$dlg.Dispatcher.BeginInvoke([System.Action]{
            & $queuePkceCleanup
        }, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    # ── Radio toggle handlers
    $rbCC.Add_Checked({
        $pnlCC.Visibility   = [System.Windows.Visibility]::Visible
        $pnlPkce.Visibility = [System.Windows.Visibility]::Collapsed
        $btnOk.Content = 'Connect'; $btnOk.Width = 100
    })
    $rbPkce.Add_Checked({
        $pnlCC.Visibility   = [System.Windows.Visibility]::Collapsed
        $pnlPkce.Visibility = [System.Windows.Visibility]::Visible
        $btnOk.Content = 'Open Browser & Connect'; $btnOk.Width = 180
    })

    # ── Cancel / cleanup
    $btnCancel.Add_Click({
        if ($pkceCtx.SyncHash) { $pkceCtx.SyncHash.CancelRequested = $true }
        if ($pkceCtx.Timer) { $pkceCtx.Timer.Stop() }
        & $schedulePkceCleanup
        $dlg.Close()
    })

    $dlg.Add_Closed({
        if ($pkceCtx.SyncHash) { $pkceCtx.SyncHash.CancelRequested = $true }
        if ($pkceCtx.Timer) { $pkceCtx.Timer.Stop() }
        & $schedulePkceCleanup
    })

    # ── Connect (mode-aware)
    $btnOk.Add_Click({
        $region = [string]$cboRegion.SelectedItem

        if ($rbCC.IsChecked) {
            # ─── Client Credentials (synchronous)
            $clientId = $txtCCClientId.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($clientId)) {
                [System.Windows.MessageBox]::Show('Client ID is required.', 'Validation',
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return
            }
            $secSecret = [System.Security.SecureString]::new()
            foreach ($c in $pwdSecret.Password.ToCharArray()) { $secSecret.AppendChar($c) }
            try {
                $headers = Connect-GenesysCloudApp -ClientId $clientId -ClientSecret $secSecret -Region $region
                $dlgResult.Success = $true; $dlgResult.Headers = $headers; $dlgResult.Region = $region
                $dlg.Close()
            }
            catch {
                [System.Windows.MessageBox]::Show("Connection failed:`n$($_)", 'Authentication Error',
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
            }
        }
        else {
            # ─── PKCE (async: runspace + polling timer)
            $clientId    = $txtPkceClientId.Text.Trim()
            $redirectUri = $txtRedirectUri.Text.Trim()

            if ([string]::IsNullOrWhiteSpace($clientId)) {
                [System.Windows.MessageBox]::Show('Client ID is required.', 'Validation',
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return
            }
            if ([string]::IsNullOrWhiteSpace($redirectUri)) {
                [System.Windows.MessageBox]::Show('Redirect URI is required.', 'Validation',
                    [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
                return
            }

            # Persist client ID + redirect URI to config
            try {
                $cfgSave = Get-AppConfig
                $cfgSave | Add-Member -NotePropertyName 'PkceClientId' -NotePropertyValue $clientId    -Force
                $cfgSave | Add-Member -NotePropertyName 'RedirectUri'  -NotePropertyValue $redirectUri -Force
                Save-AppConfig -Config $cfgSave
            } catch {}

            # Start background runspace for PKCE flow
            $pkceCtx.SyncHash = [hashtable]::Synchronized(@{
                Done = $false
                Headers = $null
                Error = $null
                CancelRequested = $false
            })
            $pkceCtx.Region   = $region
            $authMod = [System.IO.Path]::Combine($script:AppRoot, 'App.Auth.psm1')

            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.ApartmentState = 'MTA'; $runspace.Open()
            $ps = [powershell]::Create(); $ps.Runspace = $runspace

            [void]$ps.AddScript({
                param($SyncHash, $ClientId, $RedirectUri, $Region, $AuthMod)
                try {
                    Import-Module $AuthMod -Force -ErrorAction Stop
                    $h = Connect-GenesysCloudPkce `
                        -ClientId $ClientId `
                        -RedirectUri $RedirectUri `
                        -Region $Region `
                        -TimeoutSeconds 120 `
                        -ControlState $SyncHash
                    $SyncHash.Headers = $h
                }
                catch { $SyncHash.Error = $_.Exception.Message }
                finally { $SyncHash.Done = $true }
            })
            [void]$ps.AddParameters(@{
                SyncHash    = $pkceCtx.SyncHash
                ClientId    = $clientId
                RedirectUri = $redirectUri
                Region      = $region
                AuthMod     = $authMod
            })

            $pkceCtx.PS = $ps; $pkceCtx.Runspace = $runspace
            $pkceCtx.AsyncResult = $ps.BeginInvoke()
            $pkceCtx.CleanupQueued = $false

            # Update UI to waiting state
            $btnOk.IsEnabled = $false; $btnOk.Content = 'Waiting for browser...'
            $txtPkceStatus.Text = 'Browser opened — complete login and return here.'
            $txtPkceStatus.Visibility = [System.Windows.Visibility]::Visible

            # Poll for completion
            $timer = [System.Windows.Threading.DispatcherTimer]::new()
            $timer.Interval = [System.TimeSpan]::FromMilliseconds(500)
            $pkceCtx.Timer  = $timer

            $timer.Add_Tick({
                if (-not $pkceCtx.SyncHash.Done) { return }
                $pkceCtx.Timer.Stop()
                try { $pkceCtx.PS.Dispose()       } catch {}
                try { $pkceCtx.Runspace.Dispose()  } catch {}
                $pkceCtx.PS = $null; $pkceCtx.Runspace = $null; $pkceCtx.AsyncResult = $null

                if ($pkceCtx.SyncHash.Error) {
                    if ($pkceCtx.SyncHash.Error -eq 'Authentication cancelled.') {
                        return
                    }
                    $btnOk.IsEnabled = $true; $btnOk.Content = 'Open Browser & Connect'
                    $txtPkceStatus.Visibility = [System.Windows.Visibility]::Collapsed
                    [System.Windows.MessageBox]::Show(
                        "PKCE authentication failed:`n$($pkceCtx.SyncHash.Error)",
                        'Authentication Error',
                        [System.Windows.MessageBoxButton]::OK,
                        [System.Windows.MessageBoxImage]::Error)
                }
                else {
                    $dlgResult.Success = $true
                    $dlgResult.Headers = $pkceCtx.SyncHash.Headers
                    $dlgResult.Region  = $pkceCtx.Region
                    $dlg.Close()
                }
            })
            $timer.Start()
        }
    })

    try {
        $dlg.ShowDialog() | Out-Null
    }
    finally {
        # Defensive: if modal owner state gets stuck, force the main window interactive again.
        try { $window.IsEnabled = $true } catch {}
        try { $window.Activate() } catch {}
    }
    return $dlgResult
}

# ═══════════════════════════════════════════════════════════════════════
# Settings Dialog
# ═══════════════════════════════════════════════════════════════════════

function Show-SettingsDialog {
    $cfg = Get-AppConfig

    $dlg = [System.Windows.Window]::new()
    $dlg.Title = 'Settings'
    $dlg.Width = 560; $dlg.Height = 340
    $dlg.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    $dlg.Owner = $window
    $dlg.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(34,38,46))
    $dlg.ResizeMode = [System.Windows.ResizeMode]::NoResize

    $sp = [System.Windows.Controls.StackPanel]::new()
    $sp.Margin = [System.Windows.Thickness]::new(20)

    $mkRow = { param($label, $value)
        $row = [System.Windows.Controls.DockPanel]::new()
        $row.Margin = [System.Windows.Thickness]::new(0,6,0,0)
        $lb = [System.Windows.Controls.TextBlock]::new()
        $lb.Text = $label; $lb.Width = 160; $lb.Foreground = [System.Windows.Media.Brushes]::LightGray
        $lb.FontSize = 11; $lb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.DockPanel]::SetDock($lb, [System.Windows.Controls.Dock]::Left)
        $tb = [System.Windows.Controls.TextBox]::new()
        $tb.Text = $value
        $tb.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(44,49,64))
        $tb.Foreground = [System.Windows.Media.Brushes]::White
        $tb.BorderBrush = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(55,65,81))
        $tb.Padding = [System.Windows.Thickness]::new(6,4,6,4); $tb.FontSize = 11
        $row.Children.Add($lb)
        $row.Children.Add($tb)
        @{ Row = $row; TextBox = $tb }
    }

    $rowCore   = & $mkRow 'Core Module Path'  ([string]$cfg.CoreModulePath)
    $rowCatalog= & $mkRow 'Catalog Path'      ([string]$cfg.CatalogPath)
    $rowOutput = & $mkRow 'Output Root'       ([string]$cfg.OutputRoot)

    $sp.Children.Add($rowCore.Row)
    $sp.Children.Add($rowCatalog.Row)
    $sp.Children.Add($rowOutput.Row)

    $btnSave = [System.Windows.Controls.Button]::new()
    $btnSave.Content = 'Save'; $btnSave.Width = 80; $btnSave.Height = 32
    $btnSave.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Right
    $btnSave.Margin = [System.Windows.Thickness]::new(0,20,0,0)
    $btnSave.Background = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0,153,204))
    $btnSave.Foreground = [System.Windows.Media.Brushes]::White

    $btnSave.Add_Click({
        $cfg | Add-Member -NotePropertyName 'CoreModulePath' -NotePropertyValue $rowCore.TextBox.Text.Trim()   -Force
        $cfg | Add-Member -NotePropertyName 'CatalogPath'   -NotePropertyValue $rowCatalog.TextBox.Text.Trim() -Force
        $cfg | Add-Member -NotePropertyName 'OutputRoot'    -NotePropertyValue $rowOutput.TextBox.Text.Trim()  -Force
        Save-AppConfig -Config $cfg
        $dlg.Close()
    })

    $sp.Children.Add($btnSave)
    $dlg.Content = $sp
    $dlg.ShowDialog() | Out-Null
}

# ═══════════════════════════════════════════════════════════════════════
# Event Handler Wiring
# ═══════════════════════════════════════════════════════════════════════
$ctrl = $script:Controls

# --- Run type radio description
$ctrl.RbPreview.Add_Checked({ $ctrl.TxtRunTypeDesc.Text = 'Fast, small page. Use for filter validation.' })
$ctrl.RbFullRun.Add_Checked({ $ctrl.TxtRunTypeDesc.Text = 'Job-based bulk extraction. Streams to disk.' })

# --- Connect
$ctrl.BtnConnect.Add_Click({
    $result = Show-ConnectDialog
    if ($result.Success) {
        $info = Get-ConnectionInfo
        if ($info) { Set-ConnectionStatus -Connected $true -Label "$($info.Region)" }
        else        { Set-ConnectionStatus -Connected $true }
        Set-StatusBar -Main 'Connected to Genesys Cloud'
    }
})

# --- Disconnect
$ctrl.BtnDisconnect.Add_Click({
    Clear-StoredToken
    Set-ConnectionStatus -Connected $false
    Set-StatusBar -Main 'Disconnected'
})

# --- Settings
$ctrl.BtnSettings.Add_Click({ Show-SettingsDialog })

# --- Run button
$ctrl.BtnRun.Add_Click({
    # Validate inputs
    if (-not $ctrl.DtpStart.SelectedDate -or -not $ctrl.DtpEnd.SelectedDate) {
        [System.Windows.MessageBox]::Show('Please select Start and End dates.', 'Input Required',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $headers = Get-StoredHeaders
    if (-not $headers) {
        [System.Windows.MessageBox]::Show('Not connected. Please connect first.', 'Not Connected',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $startDate = $ctrl.DtpStart.SelectedDate.Value.ToString('yyyy-MM-dd')
    $endDate   = $ctrl.DtpEnd.SelectedDate.Value.ToString('yyyy-MM-dd')
    $direction = if ($ctrl.CboDirection.SelectedItem) { [string]$ctrl.CboDirection.SelectedItem.Content } else { '' }
    $mediaType = if ($ctrl.CboMediaType.SelectedItem) { [string]$ctrl.CboMediaType.SelectedItem.Content } else { '' }
    $queueId   = $ctrl.TxtQueueFilter.Text.Trim()

    $previewPs = if ($ctrl.CboPreviewPageSize.SelectedItem) { try { [int]$ctrl.CboPreviewPageSize.SelectedItem.Content } catch { 25 } } else { 25 }
    $isPreview = $ctrl.RbPreview.IsChecked

    $dsParams = Build-RunDatasetParams -StartDate $startDate -EndDate $endDate `
        -Direction $direction -MediaType $mediaType -QueueId $queueId `
        -PageSize $(if ($isPreview) { $previewPs } else { 0 })

    $cfg = Get-AppConfig

    $script:State.LastRunDatasetKey    = if ($isPreview) { 'analytics-conversation-details-query' } else { 'analytics-conversation-details' }
    $script:State.LastRunDatasetParams = $dsParams

    # Show progress UI
    $ctrl.BtnRun.Visibility       = [System.Windows.Visibility]::Collapsed
    $ctrl.BtnCancelRun.Visibility = [System.Windows.Visibility]::Visible
    $ctrl.BdrProgress.Visibility  = [System.Windows.Visibility]::Visible
    $ctrl.TxtRunProgress.Text     = 'Starting extraction...'

    Set-RunStatusBadge -Status 'Running'
    Set-StatusBar -Main 'Extraction running...' -Run $script:State.LastRunDatasetKey

    $mode          = if ($isPreview) { 'preview' } else { 'full' }
    $adapterModule = [System.IO.Path]::Combine($script:AppRoot, 'App.CoreAdapter.psm1')
    $coreModulePath = if ($env:GENESYS_CORE_MODULE)  { $env:GENESYS_CORE_MODULE }  else { [string]$cfg.CoreModulePath }
    $catalogPath    = if ($env:GENESYS_CORE_CATALOG) { $env:GENESYS_CORE_CATALOG } else { [string]$cfg.CatalogPath }
    $schemaPath     = if ($env:GENESYS_CORE_SCHEMA)  { $env:GENESYS_CORE_SCHEMA }  else { [string]$cfg.SchemaPath }

    Start-BackgroundRun -Mode $mode -DatasetParams $dsParams -OutputRoot $cfg.OutputRoot `
        -Headers $headers -AdapterModule $adapterModule `
        -CoreModulePath $coreModulePath -CatalogPath $catalogPath -SchemaPath $schemaPath

    Start-PollingTimer
})

# --- Cancel run
$ctrl.BtnCancelRun.Add_Click({
    Stop-BackgroundRun
    $ctrl.BdrProgress.Visibility  = [System.Windows.Visibility]::Collapsed
    $ctrl.BtnCancelRun.Visibility = [System.Windows.Visibility]::Collapsed
    $ctrl.BtnRun.Visibility       = [System.Windows.Visibility]::Visible
    Set-RunStatusBadge -Status 'Cancelled'
    Set-StatusBar -Main 'Run cancelled'
    if ($script:State.RefreshTimer) { $script:State.RefreshTimer.Stop() }
})

# --- Paging
$ctrl.BtnPrevPage.Add_Click({
    if ($script:State.CurrentPage -gt 0) {
        $script:State.CurrentPage--
        Refresh-ConversationsGrid
    }
})
$ctrl.BtnNextPage.Add_Click({
    $script:State.CurrentPage++
    Refresh-ConversationsGrid
})
$ctrl.CboPageSize.Add_SelectionChanged({ $script:State.CurrentPage = 0; Refresh-ConversationsGrid })

# --- Search
$script:SearchDebounceTimer = [System.Windows.Threading.DispatcherTimer]::new()
$script:SearchDebounceTimer.Interval = [System.TimeSpan]::FromMilliseconds(350)
$script:SearchDebounceTimer.Add_Tick({
    $script:SearchDebounceTimer.Stop()
    $script:State.SearchText   = $script:Controls.TxtSearch.Text
    $script:State.CurrentPage  = 0
    Refresh-ConversationsGrid
})
$ctrl.TxtSearch.Add_TextChanged({ $script:SearchDebounceTimer.Stop(); $script:SearchDebounceTimer.Start() })

# --- Quick filter toggles
$filterHandler = { $script:State.CurrentPage = 0; Refresh-ConversationsGrid }
$ctrl.TbtnInbound.Add_Checked($filterHandler);     $ctrl.TbtnInbound.Add_Unchecked($filterHandler)
$ctrl.TbtnOutbound.Add_Checked($filterHandler);    $ctrl.TbtnOutbound.Add_Unchecked($filterHandler)
$ctrl.TbtnVoiceOnly.Add_Checked($filterHandler);   $ctrl.TbtnVoiceOnly.Add_Unchecked($filterHandler)
$ctrl.TbtnHasMOS.Add_Checked($filterHandler);      $ctrl.TbtnHasMOS.Add_Unchecked($filterHandler)
$ctrl.TbtnHasHolds.Add_Checked($filterHandler);    $ctrl.TbtnHasHolds.Add_Unchecked($filterHandler)
$ctrl.TbtnDisconnected.Add_Checked($filterHandler);$ctrl.TbtnDisconnected.Add_Unchecked($filterHandler)

$ctrl.BtnClearFilters.Add_Click({
    $ctrl.TbtnInbound.IsChecked     = $false
    $ctrl.TbtnOutbound.IsChecked    = $false
    $ctrl.TbtnVoiceOnly.IsChecked   = $false
    $ctrl.TbtnHasMOS.IsChecked      = $false
    $ctrl.TbtnHasHolds.IsChecked    = $false
    $ctrl.TbtnDisconnected.IsChecked= $false
    $ctrl.TxtSearch.Text            = ''
    $script:State.SearchText        = ''
    $script:State.CurrentPage       = 0
    Refresh-ConversationsGrid
})

# --- DataGrid row double-click → drilldown
$ctrl.DgConversations.Add_MouseDoubleClick({
    $row = $ctrl.DgConversations.SelectedItem
    if ($null -eq $row) { return }
    $convId = [string]$row['ConversationId']
    if ([string]::IsNullOrWhiteSpace($convId)) { return }

    $rec = Get-ConversationRecord -RunFolder $script:State.CurrentRunFolder -ConversationId $convId
    if ($rec) { Populate-Drilldown -Conversation $rec }
})

# --- DataGrid selection changed
$ctrl.DgConversations.Add_SelectionChanged({
    $row = $ctrl.DgConversations.SelectedItem
    if ($row) {
        $convId = [string]$row['ConversationId']
        Set-StatusBar -Main "Selected: $($convId)"
    }
})

# --- Context menu
$ctrl.CmiCopyId.Add_Click({
    $row = $ctrl.DgConversations.SelectedItem
    if ($row) { [System.Windows.Clipboard]::SetText([string]$row['ConversationId']) }
})

$ctrl.CmiCopyRow.Add_Click({
    $row = $ctrl.DgConversations.SelectedItem
    if ($row) {
        $vals = @($row.Row.ItemArray | ForEach-Object { [string]$_ })
        [System.Windows.Clipboard]::SetText($vals -join ',')
    }
})

$ctrl.CmiOpenDrilldown.Add_Click({
    $row = $ctrl.DgConversations.SelectedItem
    if ($null -eq $row) { return }
    $convId = [string]$row['ConversationId']
    $rec = Get-ConversationRecord -RunFolder $script:State.CurrentRunFolder -ConversationId $convId
    if ($rec) { Populate-Drilldown -Conversation $rec }
})

$ctrl.CmiExportJson.Add_Click({
    $row = $ctrl.DgConversations.SelectedItem
    if ($null -eq $row) { return }
    $convId = [string]$row['ConversationId']
    $rec    = Get-ConversationRecord -RunFolder $script:State.CurrentRunFolder -ConversationId $convId
    if (-not $rec) { return }

    $dlgSave = [Microsoft.Win32.SaveFileDialog]::new()
    $dlgSave.FileName   = "$($convId).json"
    $dlgSave.DefaultExt = '.json'
    $dlgSave.Filter     = 'JSON files (*.json)|*.json'
    if ($dlgSave.ShowDialog()) {
        Export-ConversationToJson -Conversation $rec -OutputPath $dlgSave.FileName
        Set-StatusBar -Main "Exported JSON: $($dlgSave.FileName)"
    }
})

# --- Drilldown back button
$ctrl.BtnBackToList.Add_Click({ $ctrl.MainTabControl.SelectedItem = $ctrl.TabConversations })

# --- Drilldown copy ID
$ctrl.BtnDrillCopyId.Add_Click({
    if ($script:State.SelectedConversation) {
        [System.Windows.Clipboard]::SetText([string]$script:State.SelectedConversation.conversationId)
    }
})

# --- Drilldown export JSON
$ctrl.BtnDrillExportJson.Add_Click({
    if (-not $script:State.SelectedConversation) { return }
    $convId  = [string]$script:State.SelectedConversation.conversationId
    $dlgSave = [Microsoft.Win32.SaveFileDialog]::new()
    $dlgSave.FileName   = "$($convId).json"
    $dlgSave.DefaultExt = '.json'
    $dlgSave.Filter     = 'JSON files (*.json)|*.json'
    if ($dlgSave.ShowDialog()) {
        Export-ConversationToJson -Conversation $script:State.SelectedConversation -OutputPath $dlgSave.FileName
        Set-StatusBar -Main "Exported: $($dlgSave.FileName)"
    }
})

# --- Copy JSON
$ctrl.BtnCopyJson.Add_Click({
    if ($ctrl.TxtRawJson.Text) { [System.Windows.Clipboard]::SetText($ctrl.TxtRawJson.Text) }
})

# --- Attribute search
$ctrl.TxtAttrSearch.Add_TextChanged({
    $q = $ctrl.TxtAttrSearch.Text.ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($q)) {
        $ctrl.DgAttributes.ItemsSource = $script:State.AllAttributes
    }
    else {
        $filtered = @($script:State.AllAttributes | Where-Object {
            ([string]$_.Key).ToLowerInvariant().Contains($q) -or
            ([string]$_.Value).ToLowerInvariant().Contains($q)
        })
        $ctrl.DgAttributes.ItemsSource = $filtered
    }
})

# --- Export current page to CSV
$ctrl.BtnExportPage.Add_Click({
    if (-not $script:State.CurrentPageRecords -or $script:State.CurrentPageRecords.Count -eq 0) {
        [System.Windows.MessageBox]::Show('No data on current page.', 'Export',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        return
    }
    $dlgSave = [Microsoft.Win32.SaveFileDialog]::new()
    $dlgSave.FileName   = 'conversations-page.csv'
    $dlgSave.DefaultExt = '.csv'
    $dlgSave.Filter     = 'CSV files (*.csv)|*.csv'
    if ($dlgSave.ShowDialog()) {
        $count = Export-PageToCsv -Records $script:State.CurrentPageRecords -OutputPath $dlgSave.FileName
        Set-StatusBar -Main "Exported $($count) records to $($dlgSave.FileName)"
    }
})

# --- Export entire run to CSV (streaming)
$ctrl.BtnExportRun.Add_Click({
    if (-not $script:State.CurrentRunFolder) {
        [System.Windows.MessageBox]::Show('No run loaded.', 'Export',
            [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }
    $dlgSave = [Microsoft.Win32.SaveFileDialog]::new()
    $dlgSave.FileName   = 'conversations-full.csv'
    $dlgSave.DefaultExt = '.csv'
    $dlgSave.Filter     = 'CSV files (*.csv)|*.csv'
    if ($dlgSave.ShowDialog()) {
        Set-StatusBar -Main 'Exporting run...'
        try {
            $count = Export-RunToCsv -RunFolder $script:State.CurrentRunFolder -OutputPath $dlgSave.FileName -OnProgress {
                param($n)
                $window.Dispatcher.Invoke([Action]{ Set-StatusBar -Main "Exporting... $($n) records written" })
            }
            Set-StatusBar -Main "Exported $($count) records to CSV"
        }
        catch {
            [System.Windows.MessageBox]::Show("Export failed:`n$($_)", 'Export Error',
                [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        }
    }
})

# --- Open run folder (browse)
$ctrl.BtnOpenRunFolder.Add_Click({
    $selected = $ctrl.LstRecentRuns.SelectedItem
    if ($selected -and $selected.RunFolder) {
        Open-RunFolder -RunFolder $selected.RunFolder
        return
    }
    # Show folder browser
    $dlg = [System.Windows.Forms.FolderBrowserDialog]::new()
    $dlg.Description = 'Select a Genesys.Core run folder (contains manifest.json)'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        Open-RunFolder -RunFolder $dlg.SelectedPath
    }
})

# --- Recent runs double-click
$ctrl.LstRecentRuns.Add_MouseDoubleClick({
    $item = $ctrl.LstRecentRuns.SelectedItem
    if ($item -and $item.RunFolder) { Open-RunFolder -RunFolder $item.RunFolder }
})

# --- Refresh recent runs
$ctrl.BtnRefreshRuns.Add_Click({ Refresh-RecentRuns })

# --- Copy Diagnostics
$ctrl.BtnCopyDiagnostics.Add_Click({
    $text = Get-DiagnosticsText `
        -RunFolder         $script:State.CurrentRunFolder `
        -DatasetParameters $script:State.LastRunDatasetParams `
        -DatasetKey        $script:State.LastRunDatasetKey `
        -LastEventCount    50
    [System.Windows.Clipboard]::SetText($text)
    Set-StatusBar -Main 'Diagnostics copied to clipboard'
})

# --- Clear console
$ctrl.BtnClearConsole.Add_Click({
    $script:Controls.DgConsoleEvents.ItemsSource = $null
    $script:State.ConsoleEventCount = 0
})

# ═══════════════════════════════════════════════════════════════════════
# Startup initialization
# ═══════════════════════════════════════════════════════════════════════

# Set default dates
$ctrl.DtpStart.SelectedDate = [datetime]::Now.AddDays(-1)
$ctrl.DtpEnd.SelectedDate   = [datetime]::Now

# Load config-based state
$initCfg = Get-AppConfig
if ($initCfg.LastStartDate) { try { $ctrl.DtpStart.SelectedDate = [datetime]::Parse($initCfg.LastStartDate) } catch {} }
if ($initCfg.LastEndDate)   { try { $ctrl.DtpEnd.SelectedDate   = [datetime]::Parse($initCfg.LastEndDate)   } catch {} }

# Check existing connection
try {
    if (Test-GenesysConnection) {
        $info = Get-ConnectionInfo
        if ($info) { Set-ConnectionStatus -Connected $true -Label "$($info.Region)" }
        else        { Set-ConnectionStatus -Connected $true }
    }
    else { Set-ConnectionStatus -Connected $false }
}
catch { Set-ConnectionStatus -Connected $false }

# Populate recent runs
Refresh-RecentRuns

Set-StatusBar -Main 'Ready — Core initialized' -Count '0 records' -Run 'No active run'
