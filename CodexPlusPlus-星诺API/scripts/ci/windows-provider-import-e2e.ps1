param(
  [Parameter(Mandatory = $true)][string]$ManagerPath,
  [Parameter(Mandatory = $true)][string]$LauncherPath,
  [string]$CodexCliVersion = "0.128.0"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Assert-True([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw $Message }
}

function Get-FreeTcpPort {
  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  $listener.Start()
  try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port }
  finally { $listener.Stop() }
}

function Wait-Until([scriptblock]$Condition, [string]$Failure, [int]$Seconds = 30) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    if (& $Condition) { return }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw $Failure
}

function Test-TcpPort([int]$Port) {
  $client = [Net.Sockets.TcpClient]::new()
  try {
    $wait = $client.BeginConnect("127.0.0.1", $Port, $null, $null)
    return $wait.AsyncWaitHandle.WaitOne(250) -and $client.Connected
  } catch { return $false }
  finally { $client.Dispose() }
}

function Encode([string]$Value) { return [Uri]::EscapeDataString($Value) }

function New-ImportUrl([string]$ImportId, [string]$Name, [string]$BaseUrl, [string]$ApiKey, [string]$WireApi) {
  return "codexplusplus://v1/import/provider?importId=$(Encode $ImportId)&name=$(Encode $Name)&baseUrl=$(Encode $BaseUrl)&apiKey=$(Encode $ApiKey)&wireApi=$(Encode $WireApi)&relayMode=pureApi"
}

function Open-ImportUrl([string]$Url) {
  $info = [Diagnostics.ProcessStartInfo]::new()
  $info.FileName = $Url
  $info.UseShellExecute = $true
  [Diagnostics.Process]::Start($info) | Out-Null
}

function Confirm-Import([int]$CdpPort, [string]$PendingPath) {
  Wait-Until { Test-Path -LiteralPath $PendingPath } "Provider import was not queued by the installed manager"
  & node $mockScript "click-confirm" "--cdp-port" "$CdpPort" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "WebView2 CDP could not confirm the provider import" }
  Wait-Until { -not (Test-Path -LiteralPath $PendingPath) } "Confirmed provider import was not applied"
}

function Read-ActiveProfile([string]$SettingsPath) {
  $settings = Get-Content -LiteralPath $SettingsPath -Raw -Encoding utf8 | ConvertFrom-Json
  $profile = @($settings.relayProfiles | Where-Object { $_.id -eq $settings.activeRelayId })[0]
  if ($null -eq $profile) { throw "Active imported provider is missing from settings" }
  return @{ Settings = $settings; Profile = $profile }
}

function Assert-Profile([object]$Profile, [string]$ExpectedName, [string]$ExpectedProtocol, [string]$ExpectedKey) {
  Assert-True ($Profile.name -eq $ExpectedName) "Imported provider display name was not updated"
  Assert-True ($Profile.protocol -eq $ExpectedProtocol) "Imported provider protocol was not updated"
  Assert-True ($Profile.relayMode -eq "pureApi") "Imported provider relay mode is invalid"
  Assert-True ($Profile.apiKey -ceq $ExpectedKey) "Imported provider credential was not updated"
  Assert-True ($Profile.authContents.Contains($ExpectedKey)) "Imported provider auth contents were not regenerated"
}

function Invoke-Codex([string]$Label) {
  $runner = Join-Path $tempRoot "run-$Label.cmd"
  $stdout = Join-Path $tempRoot "codex-$Label.stdout.log"
  $stderr = Join-Path $tempRoot "codex-$Label.stderr.log"
  $command = "@echo off`r`ncall `"$codexCommand`" exec --skip-git-repo-check --sandbox read-only --model ci-model `"Reply with CI_OK only.`"`r`nexit /b %ERRORLEVEL%`r`n"
  Set-Content -LiteralPath $runner -Value $command -Encoding ascii
  $process = Start-Process -FilePath "cmd.exe" -ArgumentList @("/d", "/c", "`"$runner`"") -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  if (-not $process.WaitForExit(90000)) {
    $process.Kill()
    throw "Codex CLI $Label request timed out"
  }
  if ($process.ExitCode -ne 0) { throw "Codex CLI $Label request failed with exit code $($process.ExitCode)" }
}

function Read-Captures([string]$CapturePath) {
  if (-not (Test-Path -LiteralPath $CapturePath)) { return @() }
  return @(Get-Content -LiteralPath $CapturePath -Encoding utf8 | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}

Assert-True (Test-Path -LiteralPath $ManagerPath) "Installed Codex++ manager is missing"
Assert-True (Test-Path -LiteralPath $LauncherPath) "Installed Codex++ launcher is missing"

$mockScript = Join-Path $PSScriptRoot "mock-openai-server.mjs"
Assert-True (Test-Path -LiteralPath $mockScript) "Mock server script is missing"

$tempBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$tempRoot = Join-Path $tempBase ("codexpp-provider-e2e-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot | Out-Null
$capturePath = Join-Path $tempRoot "requests.jsonl"
$mockOut = Join-Path $tempRoot "mock.stdout.log"
$mockErr = Join-Path $tempRoot "mock.stderr.log"
$stateDir = Join-Path $HOME ".codex-session-delete"
$settingsPath = Join-Path $stateDir "settings.json"
$pendingPath = Join-Path $stateDir "pending-provider-import.json"
$diagnosticPath = Join-Path $stateDir "codex-plus.log"
$codexHome = Join-Path $HOME ".codex"
$configPath = Join-Path $codexHome "config.toml"
$authPath = Join-Path $codexHome "auth.json"
$mockPort = Get-FreeTcpPort
$cdpPort = Get-FreeTcpPort
$baseUrl = "http://127.0.0.1:$mockPort/v1"
$importId = "ci-stable-provider"
$responsesKey = "sk-ci-r-" + [Guid]::NewGuid().ToString("N")
$chatKey = "sk-ci-c-" + [Guid]::NewGuid().ToString("N")
$wrongKey = "sk-ci-x-" + [Guid]::NewGuid().ToString("N")
$mockProcess = $null
$helperProcess = $null

try {
  Get-Process codex-plus-plus-manager -ErrorAction SilentlyContinue | Stop-Process -Force
  foreach ($path in @($settingsPath, $pendingPath, $diagnosticPath, $configPath, $authPath)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
  }
  New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
  New-Item -ItemType Directory -Path $codexHome -Force | Out-Null

  $env:CI_RESPONSES_KEY = $responsesKey
  $env:CI_CHAT_KEY = $chatKey
  $env:CI_WRONG_KEY = $wrongKey
  $mockProcess = Start-Process -FilePath "node" -ArgumentList @($mockScript, "serve", "--port", "$mockPort", "--capture", $capturePath) -PassThru -RedirectStandardOutput $mockOut -RedirectStandardError $mockErr
  Wait-Until { Test-TcpPort $mockPort } "Local OpenAI mock did not start"

  $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = "--remote-debugging-port=$cdpPort --remote-allow-origins=*"
  $responsesUrl = New-ImportUrl $importId "CI Responses" $baseUrl $responsesKey "responses"
  Open-ImportUrl $responsesUrl
  Confirm-Import $cdpPort $pendingPath
  Wait-Until { (Test-Path -LiteralPath $settingsPath) -and (Test-Path -LiteralPath $configPath) -and (Test-Path -LiteralPath $authPath) } "Responses import did not write settings/config/auth"

  $first = Read-ActiveProfile $settingsPath
  $stableProfileId = $first.Profile.id
  Assert-Profile $first.Profile "CI Responses" "responses" $responsesKey
  $responsesConfig = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
  $responsesAuth = Get-Content -LiteralPath $authPath -Raw -Encoding utf8
  Assert-True ($responsesConfig.Contains("base_url = `"$baseUrl`"")) "Responses config does not use the imported upstream"
  Assert-True ($responsesConfig.Contains('wire_api = "responses"')) "Responses config has the wrong wire API"
  Assert-True ($responsesAuth.Contains($responsesKey)) "Responses auth file was not updated"

  npm install --global "@openai/codex@$CodexCliVersion" --silent
  if ($LASTEXITCODE -ne 0) { throw "Pinned Codex CLI installation failed" }
  $codexCommand = (Get-Command codex.cmd -ErrorAction Stop).Source
  $env:CODEX_HOME = $codexHome
  Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
  $beforeResponses = (Read-Captures $capturePath).Count
  Invoke-Codex "responses-cold"
  Wait-Until { (Read-Captures $capturePath).Count -gt $beforeResponses } "Responses request did not reach the mock"
  $responseRequest = @(Read-Captures $capturePath | Where-Object { $_.path -eq "/v1/responses" -and $_.responsesAuthMatch })[-1]
  Assert-True ($null -ne $responseRequest -and $responseRequest.hasInput) "Responses request path, credential, or payload is invalid"

  $chatUrl = New-ImportUrl $importId "CI Chat" $baseUrl $chatKey "chat"
  Open-ImportUrl $chatUrl
  Confirm-Import $cdpPort $pendingPath
  $chat = Read-ActiveProfile $settingsPath
  Assert-True ($chat.Profile.id -eq $stableProfileId) "Stable importId created a duplicate provider"
  Assert-Profile $chat.Profile "CI Chat" "chatCompletions" $chatKey
  $chatConfig = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
  $chatAuth = Get-Content -LiteralPath $authPath -Raw -Encoding utf8
  Assert-True ($chatConfig.Contains('wire_api = "responses"')) "Chat bridge config must present Responses to Codex"
  Assert-True ($chatAuth.Contains($chatKey)) "Chat auth file was not updated"
  $proxyMatch = [regex]::Match($chatConfig, 'base_url\s*=\s*"http://127\.0\.0\.1:(\d+)/v1"')
  Assert-True $proxyMatch.Success "Chat import did not configure a local protocol proxy"
  $proxyPort = [int]$proxyMatch.Groups[1].Value
  $helperProcess = Start-Process -FilePath $LauncherPath -ArgumentList @("--helper-only", "--helper-port", "$proxyPort") -PassThru
  Wait-Until { Test-TcpPort $proxyPort } "Codex++ Chat protocol helper did not start"
  $beforeChat = (Read-Captures $capturePath).Count
  Invoke-Codex "chat-running"
  Wait-Until { (Read-Captures $capturePath).Count -gt $beforeChat } "Chat request did not reach the mock"
  $chatRequest = @(Read-Captures $capturePath | Where-Object { $_.path -eq "/v1/chat/completions" -and $_.chatAuthMatch })[-1]
  Assert-True ($null -ne $chatRequest -and $chatRequest.hasMessages) "Chat proxy path, credential, or payload is invalid"

  if ($helperProcess -and -not $helperProcess.HasExited) { $helperProcess.Kill(); $helperProcess.WaitForExit() }
  $helperProcess = $null
  $responsesAgainUrl = New-ImportUrl $importId "CI Responses Again" $baseUrl $responsesKey "responses"
  Open-ImportUrl $responsesAgainUrl
  Confirm-Import $cdpPort $pendingPath
  $responsesAgain = Read-ActiveProfile $settingsPath
  Assert-True ($responsesAgain.Profile.id -eq $stableProfileId) "Chat to Responses update created a duplicate provider"
  Assert-Profile $responsesAgain.Profile "CI Responses Again" "responses" $responsesKey
  $finalConfig = Get-Content -LiteralPath $configPath -Raw -Encoding utf8
  Assert-True ($finalConfig.Contains("base_url = `"$baseUrl`"")) "Chat to Responses update retained the local proxy"
  $beforeFinal = (Read-Captures $capturePath).Count
  Invoke-Codex "responses-running"
  Wait-Until { (Read-Captures $capturePath).Count -gt $beforeFinal } "Updated Responses request did not reach the mock"
  $finalRequest = @(Read-Captures $capturePath | Where-Object { $_.path -eq "/v1/responses" -and $_.responsesAuthMatch })[-1]
  Assert-True ($null -ne $finalRequest -and $finalRequest.hasInput) "Updated Responses request is invalid"

  & node $mockScript "assert-model-fetch-fails" "--cdp-port" "$cdpPort" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Invalid-key model fetch verification failed" }
  Write-Output "Windows installed-manager provider import E2E passed"
} finally {
  if ($helperProcess -and -not $helperProcess.HasExited) { $helperProcess.Kill() }
  Get-Process codex-plus-plus-manager -ErrorAction SilentlyContinue | Stop-Process -Force
  if ($mockProcess -and -not $mockProcess.HasExited) {
    try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$mockPort/shutdown" -TimeoutSec 2 | Out-Null } catch { $mockProcess.Kill() }
  }
  Remove-Item Env:CI_RESPONSES_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:CI_CHAT_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:CI_WRONG_KEY -ErrorAction SilentlyContinue
  Remove-Item Env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS -ErrorAction SilentlyContinue
}
