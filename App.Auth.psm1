#Requires -Version 5.1
# App.Auth.psm1 — Gate E Authentication Escape Hatch
# PERMITTED: Invoke-RestMethod used ONLY here, ONLY for the OAuth login token endpoint.
# The login endpoint (https://login.{region}/oauth/token) is NOT a Genesys data API endpoint.
# Token storage uses Windows DPAPI (ProtectedData).
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Security

$script:TokenCacheDir  = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'GenesysConversationAnalysis'
$script:TokenCachePath = Join-Path -Path $script:TokenCacheDir -ChildPath 'auth.dat'

function Connect-GenesysCloudApp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$ClientSecret,

        [string]$Region = 'mypurecloud.com',

        [int]$TimeoutSeconds = 30
    )

    $bstr   = [System.IntPtr]::Zero
    $secret = $null
    try {
        $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
        $secret = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [System.IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    $credentials = [Convert]::ToBase64String(
        [System.Text.Encoding]::ASCII.GetBytes("$($ClientId):$($secret)")
    )
    $secret = $null  # Clear from memory ASAP

    $loginUri   = "https://login.$($Region)/oauth/token"
    $authHeader = @{ Authorization = "Basic $($credentials)" }

    # NOTE: Invoke-RestMethod is permitted here ONLY for the OAuth login endpoint.
    # URI: https://login.{region}/oauth/token — the OAuth token endpoint, not a data API path.
    $response = Invoke-RestMethod `
        -Uri         $loginUri `
        -Method      POST `
        -Body        'grant_type=client_credentials' `
        -Headers     $authHeader `
        -ContentType 'application/x-www-form-urlencoded' `
        -TimeoutSec  ([Math]::Max(5, $TimeoutSeconds)) `
        -ErrorAction Stop

    $token     = [string]$response.access_token
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw 'OAuth token endpoint returned no access_token.'
    }
    $expiresIn = [int]$response.expires_in
    $expiresAt = [datetime]::UtcNow.AddSeconds($expiresIn)

    Save-TokenDpapi -Token $token -ClientId $ClientId -Region $Region -ExpiresAt $expiresAt

    return @{ Authorization = "Bearer $($token)" }
}

function Get-StoredHeaders {
    [CmdletBinding()]
    param()

    $cached = Load-TokenDpapi
    if ($null -eq $cached) { return $null }

    $bufferSecs = 300  # 5-minute buffer before expiry
    if ([datetime]::UtcNow -ge $cached.ExpiresAt.AddSeconds(-$bufferSecs)) { return $null }

    return @{ Authorization = "Bearer $($cached.Token)" }
}

function Test-GenesysConnection {
    [CmdletBinding()]
    param()

    $headers = Get-StoredHeaders
    return ($null -ne $headers)
}

function Get-ConnectionInfo {
    [CmdletBinding()]
    param()

    $cached = Load-TokenDpapi
    if ($null -eq $cached) { return $null }

    return [pscustomobject]@{
        ClientId   = $cached.ClientId
        Region     = $cached.Region
        ExpiresAt  = $cached.ExpiresAt
        AuthMethod = $cached.AuthMethod
        IsValid    = ([datetime]::UtcNow -lt $cached.ExpiresAt.AddMinutes(-5))
    }
}

function Clear-StoredToken {
    [CmdletBinding()]
    param()

    if (Test-Path -Path $script:TokenCachePath) {
        Remove-Item -Path $script:TokenCachePath -Force
    }
}

function Connect-GenesysCloudPkce {
    <#
    .SYNOPSIS
        Gate E: PKCE OAuth 2.0 authorization code flow for interactive user login.
        Opens the browser, captures code via local HTTP listener, exchanges for token.
        Only calls login.{region}/oauth/authorize and login.{region}/oauth/token — NOT a data API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$RedirectUri,

        [string]$Region = 'usw2.pure.cloud',

        [int]$TimeoutSeconds = 120,

        [int]$TokenTimeoutSeconds = 30,

        [hashtable]$ControlState = $null
    )

    $rng = $null
    $sha256 = $null
    $listener = $null
    try {
        $parsedUri = [System.Uri]$RedirectUri
        if ($parsedUri.Scheme -ne 'http') {
            throw "Redirect URI must use http for local listener: $RedirectUri"
        }
        if ($parsedUri.Port -le 0) {
            throw "Redirect URI must include an explicit localhost port: $RedirectUri"
        }
        if ($parsedUri.Host -notin @('localhost', '127.0.0.1', '[::1]')) {
            throw "Redirect URI host must be localhost/loopback: $RedirectUri"
        }

        # ── 1. Generate code verifier (RFC 7636: 64 random bytes → URL-safe base64, no padding)
        $rng  = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
        $vBuf = New-Object byte[] 64
        $rng.GetBytes($vBuf)
        $codeVerifier = ([System.Convert]::ToBase64String($vBuf)) -replace '\+','-' -replace '/','_' -replace '=',''

        # ── 2. Code challenge = BASE64URL(SHA256(verifier))
        $sha256        = [System.Security.Cryptography.SHA256]::Create()
        $challengeHash = $sha256.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($codeVerifier))
        $codeChallenge = ([System.Convert]::ToBase64String($challengeHash)) -replace '\+','-' -replace '/','_' -replace '=',''

        # ── 3. Random state for CSRF protection
        $state = [System.Guid]::NewGuid().ToString('N')

        # ── 4. Build authorization URL (login endpoint only, never a data API path)
        $encodedRedirect = [System.Uri]::EscapeDataString($RedirectUri)
        $authUrl = "https://login.$Region/oauth/authorize" +
                   "?response_type=code" +
                   "&client_id=$([System.Uri]::EscapeDataString($ClientId))" +
                   "&redirect_uri=$encodedRedirect" +
                   "&code_challenge=$codeChallenge" +
                   "&code_challenge_method=S256" +
                   "&state=$state"

        # ── 5. Start local HTTP listener on the redirect URI's port
        $prefix    = "http://localhost:$($parsedUri.Port)/"
        $listener  = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add($prefix)
        try {
            $listener.Start()
        }
        catch {
            throw "Cannot start HTTP listener on $prefix — port $($parsedUri.Port) may be in use. Error: $($_)"
        }

        # ── 6. Open browser
        # In background runspaces, Process.Start(string) can fail for URLs because it may not use shell execute.
        # Prefer explicit shell execute, then fallback to Start-Process.
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $authUrl
            $psi.UseShellExecute = $true
            [System.Diagnostics.Process]::Start($psi) | Out-Null
        }
        catch {
            try {
                Start-Process -FilePath $authUrl -ErrorAction Stop | Out-Null
            }
            catch {
                throw "Failed to open browser: $($_.Exception.Message)"
            }
        }

        # ── 7. Wait for browser callback with cooperative cancellation support
        $ctxTask  = $listener.GetContextAsync()
        $deadline = [datetime]::UtcNow.AddSeconds([Math]::Max(5, $TimeoutSeconds))
        while (-not $ctxTask.IsCompleted) {
            if ($ControlState -and $ControlState.CancelRequested) {
                throw "Authentication cancelled."
            }
            if ([datetime]::UtcNow -ge $deadline) {
                throw "Browser authentication timed out ($TimeoutSeconds seconds). Please try again."
            }
            Start-Sleep -Milliseconds 200
        }

        if ($ctxTask.IsFaulted) {
            throw "Browser callback listener failed: $($ctxTask.Exception.InnerException.Message)"
        }

        $context  = $ctxTask.GetAwaiter().GetResult()
        $rawQuery = $context.Request.Url.Query.TrimStart('?')

        # Parse query params without System.Web dependency
        $qp = @{}
        foreach ($pair in ($rawQuery -split '&')) {
            if ($pair -match '^([^=]+)=(.*)$') {
                $qp[$Matches[1]] = [System.Uri]::UnescapeDataString(($Matches[2] -replace '\+',' '))
            }
        }

        # ── 8. Serve success page to browser then stop listener
        $html  = '<html><head><title>Authenticated</title></head><body style="font-family:Segoe UI,sans-serif;padding:40px;background:#1A1D23;color:#E2E5EC"><h2 style="color:#0099CC">Authentication successful</h2><p>You may close this tab and return to Genesys Conversation Analysis.</p></body></html>'
        $hBytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $context.Response.ContentType     = 'text/html'
        $context.Response.ContentLength64 = $hBytes.Length
        $context.Response.OutputStream.Write($hBytes, 0, $hBytes.Length)
        $context.Response.Close()

        # ── 9. Validate callback
        if ($qp['error']) {
            $desc = if ($qp['error_description']) { " — $($qp['error_description'])" } else { '' }
            throw "Authorization denied: $($qp['error'])$desc"
        }
        $code = $qp['code']
        if (-not $code) { throw "No authorization code received from browser callback." }
        if ($qp['state'] -ne $state) { throw "State mismatch — possible CSRF. Please try again." }

        # ── 10. Exchange code for access token
        # NOTE: Invoke-RestMethod permitted here (Gate E) ONLY for the OAuth login token endpoint.
        # URI: https://login.{region}/oauth/token — the OAuth token endpoint, not a data API path.
        $tokenUri  = "https://login.$Region/oauth/token"
        $tokenBody = "grant_type=authorization_code" +
                     "&code=$([System.Uri]::EscapeDataString($code))" +
                     "&redirect_uri=$encodedRedirect" +
                     "&client_id=$([System.Uri]::EscapeDataString($ClientId))" +
                     "&code_verifier=$([System.Uri]::EscapeDataString($codeVerifier))"

        $response  = Invoke-RestMethod `
            -Uri         $tokenUri `
            -Method      POST `
            -Body        $tokenBody `
            -ContentType 'application/x-www-form-urlencoded' `
            -TimeoutSec  ([Math]::Max(5, $TokenTimeoutSeconds)) `
            -ErrorAction Stop

        $token     = [string]$response.access_token
        if ([string]::IsNullOrWhiteSpace($token)) {
            throw 'OAuth token endpoint returned no access_token.'
        }
        $expiresIn = if ($response.expires_in) { [int]$response.expires_in } else { 86400 }
        $expiresAt = [datetime]::UtcNow.AddSeconds($expiresIn)

        Save-TokenDpapi -Token $token -ClientId $ClientId -Region $Region -ExpiresAt $expiresAt -AuthMethod 'PKCE'

        return @{ Authorization = "Bearer $token" }
    }
    finally {
        if ($listener) {
            try { if ($listener.IsListening) { $listener.Stop() } } catch {}
            try { $listener.Close() } catch {}
        }
        if ($sha256) { try { $sha256.Dispose() } catch {} }
        if ($rng) { try { $rng.Dispose() } catch {} }
    }
}

function Save-TokenDpapi {
    [CmdletBinding()]
    param(
        [string]$Token,
        [string]$ClientId,
        [string]$Region,
        [datetime]$ExpiresAt,
        [string]$AuthMethod = 'ClientCredentials'
    )

    if (-not (Test-Path -Path $script:TokenCacheDir)) {
        [System.IO.Directory]::CreateDirectory($script:TokenCacheDir) | Out-Null
    }

    $data = [pscustomobject]@{
        Token      = $Token
        ClientId   = $ClientId
        Region     = $Region
        ExpiresAt  = $ExpiresAt.ToString('o')
        AuthMethod = $AuthMethod
    } | ConvertTo-Json -Compress

    $bytes     = [System.Text.Encoding]::Unicode.GetBytes($data)
    $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )

    [System.IO.File]::WriteAllBytes($script:TokenCachePath, $encrypted)
}

function Load-TokenDpapi {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -Path $script:TokenCachePath)) { return $null }

    try {
        $encrypted = [System.IO.File]::ReadAllBytes($script:TokenCachePath)
        $bytes     = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $json = [System.Text.Encoding]::Unicode.GetString($bytes)
        $obj  = $json | ConvertFrom-Json

        return [pscustomobject]@{
            Token      = $obj.Token
            ClientId   = $obj.ClientId
            Region     = $obj.Region
            ExpiresAt  = [datetime]::Parse($obj.ExpiresAt)
            AuthMethod = if ($obj.AuthMethod) { $obj.AuthMethod } else { 'ClientCredentials' }
        }
    }
    catch {
        return $null
    }
}

Export-ModuleMember -Function Connect-GenesysCloudApp, Connect-GenesysCloudPkce, Get-StoredHeaders, Test-GenesysConnection, Get-ConnectionInfo, Clear-StoredToken
