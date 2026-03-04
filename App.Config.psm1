#Requires -Version 5.1
Set-StrictMode -Version Latest

$script:AppName    = 'GenesysConversationAnalysis'
$script:ConfigDir  = Join-Path -Path $env:LOCALAPPDATA -ChildPath $script:AppName
$script:ConfigFile = Join-Path -Path $script:ConfigDir -ChildPath 'config.json'

function Get-DefaultConfig {
    return [ordered]@{
        CoreModulePath  = 'G:\Development\20_Staging\GenesysCloud\Genesys.Core\src\ps-module\Genesys.Core\Genesys.Core.psd1'
        CatalogPath     = 'G:\Development\20_Staging\GenesysCloud\Genesys.Core\catalog\genesys-core.catalog.json'
        SchemaPath      = 'G:\Development\20_Staging\GenesysCloud\Genesys.Core\catalog\schema\genesys-core.catalog.schema.json'
        OutputRoot      = (Join-Path -Path $env:LOCALAPPDATA -ChildPath "$($script:AppName)\runs")
        GenesysRegion   = 'mypurecloud.com'
        PageSize        = 50
        PreviewPageSize = 25
        MaxConsoleEvents = 200
        RecentRuns      = @()
        LastStartDate   = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd')
        LastEndDate     = (Get-Date).ToString('yyyy-MM-dd')
        PkceClientId    = ''
        RedirectUri     = 'http://localhost:8180/callback'
    }
}

function Get-AppConfig {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -Path $script:ConfigFile)) {
        return Get-DefaultConfig
    }

    try {
        $raw      = [System.IO.File]::ReadAllText($script:ConfigFile)
        $obj      = $raw | ConvertFrom-Json
        $defaults = Get-DefaultConfig

        foreach ($key in $defaults.Keys) {
            if ($null -eq $obj.$key) {
                $obj | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
            }
        }

        return $obj
    }
    catch {
        Write-Warning "Failed to load config: $($_). Using defaults."
        return Get-DefaultConfig
    }
}

function Save-AppConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    if (-not (Test-Path -Path $script:ConfigDir)) {
        [System.IO.Directory]::CreateDirectory($script:ConfigDir) | Out-Null
    }

    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $script:ConfigFile -Encoding UTF8
}

function Update-AppConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $cfg = Get-AppConfig
    $cfg | Add-Member -NotePropertyName $Key -NotePropertyValue $Value -Force
    Save-AppConfig -Config $cfg
}

function Add-RecentRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunFolder,
        [string]$DatasetKey = '',
        [string]$Interval   = '',
        [int]$ItemCount     = 0
    )

    $cfg   = Get-AppConfig
    $entry = [pscustomobject]@{
        RunFolder  = $RunFolder
        DatasetKey = $DatasetKey
        Interval   = $Interval
        ItemCount  = $ItemCount
        OpenedAt   = [datetime]::UtcNow.ToString('o')
    }

    $existing = @($cfg.RecentRuns | Where-Object { $_.RunFolder -ne $RunFolder })
    $newList  = @($entry) + $existing | Select-Object -First 20

    $cfg | Add-Member -NotePropertyName 'RecentRuns' -NotePropertyValue $newList -Force
    Save-AppConfig -Config $cfg
}

function Get-RecentRuns {
    [CmdletBinding()]
    param()

    $cfg = Get-AppConfig
    return @($cfg.RecentRuns)
}

Export-ModuleMember -Function Get-AppConfig, Save-AppConfig, Update-AppConfig, Add-RecentRun, Get-RecentRuns
