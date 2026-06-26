# AgentCluster Worker 자동 설정 스크립트 (Windows)
# 사용법 (PowerShell 관리자): irm https://raw.githubusercontent.com/404NotFound-sunrin/test/main/setup-worker.ps1 | iex

$REPO_URL = "https://github.com/404NotFound-sunrin/test.git"
$ORCHESTRATOR_PUBKEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILHunEsxEocdkUNCOGHH0kNSDRS6wxUhg+iKbUBq5Wds agentcluster-orchestrator"
$WORKER_BASE = "$env:USERPROFILE\AgentWorker"

Write-Host "==============================" -ForegroundColor Cyan
Write-Host " AgentCluster Worker Setup (Windows)" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan

# --- Worker ID 자동 결정 ---
$HOSTNAME_CLEAN = $env:COMPUTERNAME.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-' -replace '^-|-$', ''
$WORKER_ID = "claude-$HOSTNAME_CLEAN"
$USERNAME = $env:USERNAME
$AGENT_NAME = $WORKER_ID -replace '^claude-', ''
$BRANCH = "agents/$WORKER_ID"

# IP 주소
$IP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notmatch '^169' } | Select-Object -First 1).IPAddress

Write-Host "Worker ID : $WORKER_ID"
Write-Host "Branch    : $BRANCH"
Write-Host "User      : $USERNAME"
Write-Host "IP        : $IP"
Write-Host ""

# ── 1. Node.js ────────────────────────────────────────────────────────────────
Write-Host "[1/8] Node.js 확인..." -ForegroundColor Yellow
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Host "  → Node.js 설치 중 (winget)..."
    winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements
    # PATH 갱신
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
    Write-Host "  → 설치 완료. PowerShell 재시작 후 PATH 반영됨."
} else {
    Write-Host "  → 이미 설치됨: $(node --version)"
}

# ── 2. Claude CLI ─────────────────────────────────────────────────────────────
Write-Host "[2/8] Claude CLI 확인..." -ForegroundColor Yellow
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "  → Claude CLI 설치 중..."
    npm install -g @anthropic-ai/claude-code
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH", "User")
} else {
    Write-Host "  → 이미 설치됨"
}

# ── 3. Claude 로그인 확인 ─────────────────────────────────────────────────────
Write-Host "[3/8] Claude 로그인 확인..." -ForegroundColor Yellow
$claudeOk = $false
try {
    $null = & claude --version 2>&1
    $claudeOk = $true
} catch {}

if ($claudeOk) {
    Write-Host "  → Claude CLI 확인됨. 로그인이 필요하면 'claude login' 실행."
} else {
    Write-Host "  ⚠ claude 명령을 찾을 수 없습니다. PowerShell을 재시작 후 다시 실행하거나 'claude login'을 직접 실행하세요." -ForegroundColor Red
}

# ── 4. Claude 전역 권한 설정 ──────────────────────────────────────────────────
Write-Host "[4/8] Claude 권한 설정..." -ForegroundColor Yellow
$claudeDir = "$env:USERPROFILE\.claude"
New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
@'
{
  "permissions": {
    "allow": [
      "Bash(*)", "Edit(*)", "Write(*)", "Read(*)",
      "Glob(*)", "Grep(*)", "WebFetch(*)", "WebSearch(*)"
    ],
    "deny": []
  }
}
'@ | Set-Content "$claudeDir\settings.json" -Encoding UTF8
Write-Host "  → 전역 권한 설정 완료"

# ── 5. SSH 키 등록 ────────────────────────────────────────────────────────────
Write-Host "[5/8] SSH 키 등록..." -ForegroundColor Yellow
$sshDir = "$env:USERPROFILE\.ssh"
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null
$authKeys = "$sshDir\authorized_keys"
if (-not (Test-Path $authKeys) -or -not (Select-String -Path $authKeys -Pattern "agentcluster-orchestrator" -Quiet)) {
    Add-Content -Path $authKeys -Value $ORCHESTRATOR_PUBKEY -Encoding UTF8
    Write-Host "  → orchestrator 키 등록 완료"
} else {
    Write-Host "  → 이미 등록됨"
}

# OpenSSH 서버 설치 및 시작
Write-Host "  → OpenSSH 서버 확인..."
$sshFeature = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }
if ($sshFeature.State -ne "Installed") {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue
Write-Host "  → OpenSSH 서버 실행 중"

# ── 6. Git repo ────────────────────────────────────────────────────────────────
Write-Host "[6/8] Git repo 설정..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path "$WORKER_BASE\repos" | Out-Null
New-Item -ItemType Directory -Force -Path "$WORKER_BASE\logs" | Out-Null
$REPO_DIR = "$WORKER_BASE\repos\test"

if (Test-Path "$REPO_DIR\.git") {
    Push-Location $REPO_DIR
    git fetch --all --quiet
    Pop-Location
} else {
    git clone $REPO_URL $REPO_DIR
}

Push-Location $REPO_DIR
git checkout main --quiet
git pull origin main --quiet
git checkout -B $BRANCH 2>$null
git merge main --no-edit --quiet 2>$null
git push origin $BRANCH --quiet 2>$null
Pop-Location
Write-Host "  → 완료"

# ── 7. worker.ps1 설치 + 자동 시작 ───────────────────────────────────────────
Write-Host "[7/8] worker.ps1 설치..." -ForegroundColor Yellow

$workerScript = @"
`$REPO = "$WORKER_BASE\repos\test"
`$BRANCH = "$BRANCH"
`$AGENT_NAME = "$AGENT_NAME"
`$WORKER_ID = "$WORKER_ID"
`$LOG = "$WORKER_BASE\logs\worker.log"
`$LAST_HASH = ""

function Log(`$msg) { "[`$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] `$msg" | Out-File `$LOG -Append -Encoding UTF8 }

Log "AgentWorker [`$WORKER_ID] started."

while (`$true) {
    Set-Location `$REPO
    git fetch origin main --quiet 2>`$null
    `$CURRENT_HASH = git rev-parse origin/main 2>`$null

    if (`$CURRENT_HASH -and `$CURRENT_HASH -ne `$LAST_HASH) {
        Log "New task detected. Running Claude..."
        git pull origin main --quiet 2>`$null
        git checkout `$BRANCH --quiet 2>`$null
        git merge main --no-edit --quiet 2>`$null

        `$TASK = Get-Content "coordination\task.md" -Raw -ErrorAction SilentlyContinue
        `$OTHER = ""
        Get-ChildItem "agents\*.md" | Where-Object { `$_.BaseName -ne `$AGENT_NAME } | ForEach-Object {
            `$OTHER += "### `$(`$_.BaseName)`n`$(Get-Content `$_.FullName -Raw)`n"
        }
        `$DISCUSSION = Get-Content "coordination\discussion.md" -Raw -ErrorAction SilentlyContinue

        `$PROMPT = @"
너는 `$WORKER_ID 에이전트다. 워크스페이스: `$REPO

현재 task:
---
`$TASK
---

다른 에이전트 상태:
---
`$OTHER
---

토론 내용:
---
`$DISCUSSION
---

확인 없이 끝까지 자율 수행. 결과는 agents\`$AGENT_NAME.md, 의견은 coordination\discussion.md에 추가.
완료 후 git add -A; git commit -m 'agent: `$WORKER_ID 작업 완료'; git push origin `$BRANCH
"@
        claude --dangerously-skip-permissions -p `$PROMPT 2>&1 | Out-File "$WORKER_BASE\logs\claude.log" -Append -Encoding UTF8
        `$LAST_HASH = `$CURRENT_HASH
        Log "Done."
    }
    Start-Sleep -Seconds 60
}
"@

$workerScript | Set-Content "$WORKER_BASE\worker.ps1" -Encoding UTF8

# 시작 프로그램에 등록
$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$batContent = "@echo off`r`npowershell.exe -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WORKER_BASE\worker.ps1`""
Set-Content -Path "$startupFolder\AgentClusterWorker.bat" -Value $batContent -Encoding ASCII

# 지금 바로 시작
Start-Process -FilePath powershell -ArgumentList "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WORKER_BASE\worker.ps1`"" -WindowStyle Hidden
Write-Host "  → worker.ps1 설치 + 자동 시작 등록 완료"

# ── 8. GitHub 등록 ────────────────────────────────────────────────────────────
Write-Host "[8/8] 서버에 등록 신청..." -ForegroundColor Yellow
Push-Location $REPO_DIR
git checkout $BRANCH --quiet

New-Item -ItemType Directory -Force -Path "workers\register" | Out-Null
New-Item -ItemType Directory -Force -Path "agents" | Out-Null

@"
{
  "id": "$WORKER_ID",
  "host": "$IP",
  "sshUser": "$USERNAME",
  "branch": "$BRANCH",
  "agentName": "$AGENT_NAME",
  "os": "Windows",
  "hostname": "$env:COMPUTERNAME",
  "registeredAt": "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ' -AsUTC)"
}
"@ | Set-Content "workers\register\$WORKER_ID.json" -Encoding UTF8

@"
# $WORKER_ID Agent

## 기기 정보
- hostname : $env:COMPUTERNAME
- IP       : $IP
- OS       : Windows
- 사용자   : $USERNAME
- 등록     : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## 상태
worker.ps1 실행 중 — 대기 중
"@ | Set-Content "agents\$AGENT_NAME.md" -Encoding UTF8

git add -A
git commit -m "worker: $WORKER_ID 자동 등록" 2>$null
git push origin $BRANCH --quiet

Pop-Location

Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host "  설정 완료!" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host "  Worker ID : $WORKER_ID"
Write-Host "  IP        : $IP"
Write-Host "  Branch    : $BRANCH"
Write-Host ""
Write-Host "  Windows 서버가 60초 내 자동 감지합니다." -ForegroundColor Cyan
Write-Host "  로그: $WORKER_BASE\logs\worker.log"
Write-Host "================================" -ForegroundColor Green
