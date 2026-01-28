# Configuration
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Web  # For query string parsing

$Config = @{
  UserAgent = "Mozilla/5.0"
  AppCode = @{
    U8 = "973bd727dd11cbb6ead8"
  }
  Channel = 6
  BaseUrl = @{
    U8      = "https://u8.gryphline.com"
    Webview = "https://ef-webview.gryphline.com"
  }
  ApiLanguage = "en-us"
}

function Invoke-ApiRequest {
  param(
    [string]$Uri,
    [string]$Method = "GET",
    [hashtable]$Body = @{},
    [hashtable]$Query = @{}
  )

  if ([string]::IsNullOrWhiteSpace($Uri)) {
    throw "Invoke-ApiRequest: URI cannot be empty."
  }

  $Uri = $Uri -replace '\s+', ''
  $Headers = @{
    "User-Agent" = $Config.UserAgent
  }

  try {
    $UriBuilder = [System.UriBuilder]$Uri
  } catch {
    throw "Invalid Base URI: $Uri"
  }
  
  if ($Query.Count -gt 0) {
    $QueryString = ($Query.GetEnumerator() | ForEach-Object { 
      $Val = if ($null -ne $_.Value) { [System.Uri]::EscapeDataString($_.Value) } else { "" }
      "$([System.Uri]::EscapeDataString($_.Key))=$Val" 
    }) -join "&"
    
    if ($UriBuilder.Query.Length -gt 1) {
      $UriBuilder.Query = $UriBuilder.Query.Substring(1) + "&" + $QueryString
    } else {
      $UriBuilder.Query = $QueryString
    }
  }

  $FinalUri = $UriBuilder.Uri
  $RequestParams = @{
    Uri         = $FinalUri
    Method      = $Method
    Headers     = $Headers
    ContentType = "application/json"
  }

  if ($Method -ne "GET" -and $Body.Count -gt 0) {
    $RequestParams.Body = $Body | ConvertTo-Json -Depth 32 -Compress
  }

  try {
    $Response = Invoke-RestMethod @RequestParams
    if ($null -ne $Response.status -and $Response.status -ne 0) { throw "API Error Status: $($Response.status) Msg: $($Response.msg)" }
    if ($null -ne $Response.code -and $Response.code -ne 0) { throw "API Error Code: $($Response.code) Msg: $($Response.msg)" }
    return $Response
  } catch {
    Write-Error "Request Failed for URI: $($FinalUri.AbsoluteUri)`nError: $_"
    exit 1
  }
}

Write-Host "=== Arknights: Endfield Gacha Link Generator ===" -ForegroundColor Cyan

# Log file path
$LogPath = "$env:USERPROFILE\AppData\LocalLow\Gryphline\Endfield\sdklogs\HGWebview.log"

if (-not (Test-Path $LogPath)) {
  Write-Error "Log file not found at: $LogPath`nPlease launch the game and open gacha history at least once."
  exit 1
}

Write-Host "Reading log file: $LogPath" -ForegroundColor Yellow
$Content = Get-Content $LogPath -Raw

if ([string]::IsNullOrWhiteSpace($Content)) {
  Write-Error "Log file is empty. Please launch the game and open gacha history first."
  exit 1
}

# Extract URLs with u8_token (using safe regex pattern with proper quote escaping)
$Pattern = 'https://ef-webview\.gryphline\.com[^\s''"<>]*u8_token=[^&\s''"<>]+[^\s''"<>]*'
$Matches = [regex]::Matches($Content, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

if ($Matches.Count -eq 0) {
  Write-Error "No valid gacha history URL found in log.`nPlease open gacha history in-game first."
  exit 1
}

# Use the LAST match (most recent entry)
$LastUrl = $Matches[$Matches.Count - 1].Value
Write-Host "Found gacha link in log file." -ForegroundColor Green

# Parse query parameters safely
try {
  $Uri = [System.Uri]$LastUrl
  $Query = [System.Web.HttpUtility]::ParseQueryString($Uri.Query)
  $U8Token = $Query["u8_token"]
  $ServerId = $Query["server"]

  if ([string]::IsNullOrWhiteSpace($U8Token)) {
    throw "u8_token parameter missing in URL"
  }
  if ([string]::IsNullOrWhiteSpace($ServerId)) {
    throw "server parameter missing in URL"
  }
} catch {
  Write-Error "Failed to parse URL parameters: $_`nURL: $LastUrl"
  exit 1
}

# Write-Host "Extracted credentials:" -ForegroundColor Yellow
# Write-Host "  Server ID: $ServerId" -ForegroundColor White
# Write-Host "  Token length: $($U8Token.Length) characters" -ForegroundColor White

# Confirm server session (required for API access)
Write-Host "`nConfirming server session ..." -ForegroundColor Yellow
try {
  $null = Invoke-ApiRequest -Uri "$($Config.BaseUrl['U8'])/game/role/v1/confirm_server" -Method "POST" -Body @{
    token    = $U8Token
    serverId = [string]$ServerId
  }
  Write-Host "Server session confirmed." -ForegroundColor Green
} catch {
  Write-Error "Server confirmation failed. Token may be expired.`nPlease reopen gacha history in-game and retry."
  exit 1
}

# Generate gacha history URL
$EncodedToken = [System.Uri]::EscapeDataString($U8Token)
$EncodedServerId = [System.Uri]::EscapeDataString([string]$ServerId)
$GachaUrl = "$($Config.BaseUrl['Webview'])/api/record/char?server_id=$EncodedServerId&pool_type=E_CharacterGachaPoolType_Standard&lang=$($Config.ApiLanguage)&token=$EncodedToken"

# Verify URL accessibility
Write-Host "Verifying generated link ..." -ForegroundColor Yellow
try {
  $VerifyRsp = Invoke-RestMethod -Uri $GachaUrl -Method GET -TimeoutSec 10
  if ($VerifyRsp.code -eq 40100) {
    Write-Error "Verification failed: Token is invalid or expired"
    Write-Host "Please reopen gacha history in-game and run this script again." -ForegroundColor Yellow
    exit 1
  } elseif ($null -ne $VerifyRsp.code -and $VerifyRsp.code -ne 0) {
    Write-Warning "Verification warning: Code $($VerifyRsp.code) - $($VerifyRsp.msg)"
  } else {
    Write-Host "Verification successful." -ForegroundColor Green
  }
} catch {
  Write-Warning "Verification request failed (this may be normal for some regions): $_"
}

# Output final URL
Write-Host "`n=== Gacha History URL ===" -ForegroundColor Cyan
Write-Host $GachaUrl -ForegroundColor White
Write-Host "=========================`n" -ForegroundColor Cyan

Set-Clipboard -Value $GachaUrl
Write-Host "URL copied to clipboard!" -ForegroundColor Green
# Write-Host "Open this URL in your browser to view gacha history." -ForegroundColor Yellow
