# Configuration
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$Config = @{
  UserAgent = "Mozilla/5.0"
  AppCode = @{
    AccountService = "d9f6dbb6bbd6bb33"
    Binding        = "3dacefa138426cfe"
    U8             = "973bd727dd11cbb6ead8"
  }
  Channel = 6
  BaseUrl = @{
    AccountService = "https://as.gryphline.com"
    U8             = "https://u8.gryphline.com"
    BindingApi     = "https://binding-api-account-prod.gryphline.com"
    Webview        = "https://ef-webview.gryphline.com"
  }
  ApiLanguage = "en-us"
}

function Get-PlainText {
  param([System.Security.SecureString]$SecureString)
  $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
  try {
    return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
  } finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
  }
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

  # Use UriBuilder for safe URI construction
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

# Write-Host "=== Arknights: Endfield Gacha Link Generator ===" -ForegroundColor Cyan

# Get Account Service Token
$AsToken = Read-Host "Enter AS access token (Leave empty to login with Email/Password)"

if ([string]::IsNullOrWhiteSpace($AsToken)) {
  $Email = Read-Host "Enter email"
  $SecurePass = Read-Host "Enter password" -AsSecureString
  $Password = Get-PlainText $SecurePass

  Write-Host "Logging in ..." -ForegroundColor Yellow
  $LoginRsp = Invoke-ApiRequest -Uri "$($Config.BaseUrl['AccountService'])/user/auth/v1/token_by_email_password" -Method "POST" -Body @{
    email    = $Email
    password = $Password
    from     = 0
  }
  $AsToken = $LoginRsp.data.token
  Write-Host "Login successful." -ForegroundColor Green
}

# Get OAuth2 Code for U8 (Type 0)
Write-Host "Getting OAuth2 code for game service ..." -ForegroundColor Yellow
$OauthU8Rsp = Invoke-ApiRequest -Uri "$($Config.BaseUrl['AccountService'])/user/oauth2/v2/grant" -Method "POST" -Body @{
  appCode = $Config.AppCode.AccountService
  token   = $AsToken
  type    = 0
}
$OauthCode = $OauthU8Rsp.data.code

# Get OAuth2 Token for Binding (Type 1)
Write-Host "Getting OAuth2 token for Binding API..." -ForegroundColor Yellow
$OauthBindRsp = Invoke-ApiRequest -Uri "$($Config.BaseUrl['AccountService'])/user/oauth2/v2/grant" -Method "POST" -Body @{
  appCode = $Config.AppCode.Binding
  token   = $AsToken
  type    = 1
}
$BindingToken = $OauthBindRsp.data.token

# Get U8 Token
Write-Host "Getting U8 access token ..." -ForegroundColor Yellow
$ChannelTokenJson = @{
  code  = $OauthCode
  type  = 1
  isSuc = $true
} | ConvertTo-Json -Compress

$U8AuthRsp = Invoke-ApiRequest -Uri "$($Config.BaseUrl['U8'])/u8/user/auth/v2/token_by_channel_token" -Method "POST" -Body @{
  appCode         = $Config.AppCode.U8
  channelMasterId = $Config.Channel
  channelToken    = $ChannelTokenJson
  type            = 0
  platform        = 2
}
$U8Token = $U8AuthRsp.data.token

# Get Binding List to find Server ID
Write-Host "Retrieving game data list ..." -ForegroundColor Yellow
$BindingListRsp = Invoke-ApiRequest -Uri "$($Config.BaseUrl['BindingApi'])/account/binding/v1/binding_list" -Method "GET" -Query @{
  token = $BindingToken
}

$EndfieldApp = $BindingListRsp.data.list | Where-Object { $_.appCode -eq "endfield" }
if (-not $EndfieldApp) {
  Write-Error "No Endfield game data found."
  exit 1
}

# Find all valid roles
$ValidRoles = @()
foreach ($BindItem in $EndfieldApp.bindingList) {
  foreach ($Role in $BindItem.roles) {
    if (-not $Role.isBanned) {
      $ValidRoles += $Role
    }
  }
}

if ($ValidRoles.Count -eq 0) {
  Write-Error "No valid game data found."
  exit 1
}

if ($ValidRoles.Count -gt 1) {
  # User Selection
  Write-Host "`nAvailable game data:" -ForegroundColor Cyan
  for ($i = 0; $i -lt $ValidRoles.Count; $i++) {
    $R = $ValidRoles[$i]
    Write-Host "[$($i + 1)] Name: $($R.nickName) (Lv.$($R.level)) | Server ID: $($R.serverId)"
  }

  do {
    $Selection = Read-Host "Select (1-$($ValidRoles.Count))"
    $Index = $Selection -as [int]
  } until ($Index -ge 1 -and $Index -le $ValidRoles.Count)

  $SelectedRole = $ValidRoles[$Index - 1]
} else {
  $SelectedRole = $ValidRoles[0]
}

$ServerId = $SelectedRole.serverId
Write-Host "Selected game data: $($SelectedRole.nickName) (Lv.$($SelectedRole.level)) on Server ID $ServerId" -ForegroundColor Green

# Confirm Server (Required to activate session for this server)
Write-Host "Confirming server selection ..." -ForegroundColor Yellow
$null = Invoke-ApiRequest -Uri "$($Config.BaseUrl['U8'])/game/role/v1/confirm_server" -Method "POST" -Body @{
  token    = $U8Token
  serverId = [string]$ServerId
}

# Generate Link
$EncodedToken = [System.Uri]::EscapeDataString($U8Token)
$EncodedServerId = [System.Uri]::EscapeDataString([string]$ServerId)
$GachaUrl = "$($Config.BaseUrl['Webview'])/api/record/char?server_id=$EncodedServerId&pool_type=E_CharacterGachaPoolType_Standard&lang=$($Config.ApiLanguage)&token=$EncodedToken"

Write-Host "Verifying generated link ..." -ForegroundColor Yellow
try {
  $VerifyRsp = Invoke-RestMethod -Uri $GachaUrl -Method GET
  if ($VerifyRsp.code -eq 40100) {
    Write-Error "Verification Failed: Token is invalid"
    exit 1
  } elseif ($null -ne $VerifyRsp.code -and $VerifyRsp.code -ne 0) {
    Write-Warning "Verification returned unexpected code: $($VerifyRsp.code) Msg: $($VerifyRsp.msg)"
  } else {
    Write-Host "Verification successful." -ForegroundColor Green
  }
} catch {
  Write-Warning "Verification request failed: $_"
}

Write-Host "`n=== Gacha History URL ===" -ForegroundColor Cyan
Write-Host $GachaUrl -ForegroundColor White
Write-Host "=========================`n" -ForegroundColor Cyan

Set-Clipboard -Value $GachaUrl
Write-Host "URL copied to clipboard!" -ForegroundColor Green
