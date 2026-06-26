# AgentCluster

여러 대의 컴퓨터를 AI 에이전트로 활용하는 멀티 에이전트 협업 클러스터.  
Windows PC가 중앙 서버 역할을 하고, 각 기기에서 Claude Code CLI가 자율적으로 작업을 수행한다.

---

## 아키텍처

```
Windows PC (서버/오케스트레이터)
├─ SSH 서버 (sshd, port 22)
├─ 모니터링 대시보드 (FastAPI, port 8080)
├─ ngrok 터널 (외부 공개 주소, 자동 시작)
└─ task.md 작성 → GitHub push → Worker 감지 → Claude 실행 → 결과 push
```

```
Worker 기기 (Mac mini / MacBook / 노트북 등)
├─ worker.sh / worker.ps1 상시 실행 (60초마다 GitHub 폴링)
├─ task.md 변경 감지 → Claude Code CLI 자동 실행
├─ 결과 → agents/<name>.md → Git push
└─ 재부팅 후 자동 시작 (LaunchAgent / 시작프로그램)
```

---

## 현재 연결된 기기 (2026-06-27 기준)

| 기기 | IP | OS | 역할 | 상태 |
|------|----|----|------|------|
| Windows PC | 192.168.219.109 | Windows | 서버/오케스트레이터 | 운영 중 |
| Mac mini | 192.168.219.112 | macOS | claude-macmini worker | 운영 중 |
| MacBook | 192.168.219.177 | macOS | claude-macbook worker | 운영 중 |
| 노트북 1~5 | - | - | 추가 예정 | 해커톤 당일 |

---

## 접근 주소

| 상황 | 대시보드 |
|------|---------|
| 집 LAN | http://192.168.219.109:8080 |
| 외부 / 해커톤 현장 | `D:\AgentCluster\logs\ngrok-url.txt` 파일 확인 |
| ngrok 관리 | http://localhost:4040 |

```bash
# Windows → Mac mini SSH
ssh -i D:\AgentCluster\keys\orchestrator_ed25519 yoonjunseo@192.168.219.112

# Windows → MacBook SSH
ssh -i D:\AgentCluster\keys\orchestrator_ed25519 dbswnstj@192.168.219.177

# 외부에서 Windows SSH (Tailscale)
ssh lovey@100.124.33.98
```

---

## 자동 시작 (PC 켜면 전부 자동 실행)

| 서비스 | 방식 |
|--------|------|
| SSH 서버 (sshd) | Windows 서비스 |
| 모니터링 서버 (port 8080) | 시작 프로그램 |
| ngrok 터널 | 시작 프로그램 |
| Mac mini worker | LaunchAgent |
| MacBook worker | LaunchAgent |

- 시작 스크립트: `D:\AgentCluster\scripts\Start-All.ps1`
- ngrok 주소: `D:\AgentCluster\logs\ngrok-url.txt` (재시작마다 갱신)

수동 재시작:
```powershell
Get-Process python, ngrok -ErrorAction SilentlyContinue | Stop-Process -Force
& 'D:\AgentCluster\scripts\Start-All.ps1'
```

---

## Worker 연결 / 해제

Worker는 **설정 후 부팅할 때마다 자동으로 연결**된다.  
원할 때만 수동으로 연결/해제하려면 아래 명령어를 사용한다.

### macOS Worker

```bash
# 연결 (worker 시작)
bash ~/AgentWorker/worker.sh &

# 해제 (worker 중지)
pkill -f worker.sh

# 상태 확인
pgrep -fl worker.sh

# 로그 보기
tail -f ~/AgentWorker/logs/worker.log
```

자동 시작 완전히 끄기 (재부팅 후에도 자동 시작 안 함):
```bash
launchctl unload ~/Library/LaunchAgents/com.agentcluster.worker.plist
```

자동 시작 다시 켜기:
```bash
launchctl load ~/Library/LaunchAgents/com.agentcluster.worker.plist
```

### Windows Worker

```powershell
# 연결 (worker 시작)
Start-Process powershell -ArgumentList "-WindowStyle Hidden -File $env:USERPROFILE\AgentWorker\worker.ps1"

# 해제 (worker 중지)
Get-Process powershell | Where-Object { $_.MainWindowTitle -eq "" } | Stop-Process

# 로그 보기
Get-Content $env:USERPROFILE\AgentWorker\logs\worker.log -Tail 20 -Wait
```

---

## 새 기기 추가하는 방법

### Step 1 — 명령어 한 줄 실행

**macOS / Linux:**
```bash
bash <(curl -s https://raw.githubusercontent.com/404NotFound-sunrin/test/main/setup-worker.sh)
```

**Windows (PowerShell 관리자로 실행):**
```powershell
irm https://raw.githubusercontent.com/404NotFound-sunrin/test/main/setup-worker.ps1 | iex
```

자동으로 처리되는 것:

| 단계 | macOS/Linux | Windows |
|------|------------|---------|
| 패키지 매니저 | Homebrew 자동 설치 | winget 사용 |
| Node.js | brew install node | winget 설치 |
| Claude CLI | npm install -g | npm install -g |
| 전역 권한 설정 | ~/.claude/settings.json | %USERPROFILE%\.claude\settings.json |
| SSH 서버 | Remote Login ON | OpenSSH Server 설치+시작 |
| Worker 스크립트 | worker.sh + LaunchAgent | worker.ps1 + 시작프로그램 |
| 서버 자동 등록 | workers/register/<id>.json push | workers/register/<id>.json push |

### Step 2 — Claude 로그인 (유일한 수동 작업)

```bash
claude login
```

브라우저가 열리면 로그인 → 완료.

### Step 3 — 서버 자동 감지 (60초 이내)

Windows 서버가 자동으로 감지해서 대시보드에 표시됨. 별도 작업 없음.

---

## Task 보내기

### 대시보드 UI
`http://192.168.219.109:8080` → "＋ 작업 전송" 버튼

### 스크립트
```powershell
.\scripts\Send-Task.ps1 -TaskContent "여기에 task 내용"
```

Worker들이 최대 60초 내에 감지 → Claude 자동 실행 → 결과 push

---

## Git 저장소 구조

- URL: `https://github.com/404NotFound-sunrin/test.git`
- `main` 브랜치: task.md, discussion.md (오케스트레이터가 관리)
- `agents/<worker-id>` 브랜치: 각 worker의 결과

```
coordination/
  task.md           ← 서버가 여기에 지시 작성
  discussion.md     ← 에이전트들 의견 교환
agents/
  macmini.md        ← Mac mini 결과
  macbook.md        ← MacBook 결과
workers/
  register/         ← 새 worker 자동 등록 신청 파일
```

---

## 레포지토리 변경하는 방법

새 GitHub 레포를 만들고 클러스터 전체를 옮기고 싶을 때.

### Step 1 — GitHub에서 새 레포 생성
- `https://github.com/new` 에서 생성
- **Public** 으로 설정 (setup 스크립트 다운로드에 필요)

### Step 2 — Windows 서버에서 실행

```powershell
$NEW_REPO = "https://github.com/<계정>/<레포이름>.git"
$NEW_NAME = "<레포이름>"   # 예: my-cluster

# 1. 기존 workspace 제거
Remove-Item -Recurse -Force "D:\AgentCluster\workspace\*"

# 2. 새 레포 클론
git clone $NEW_REPO "D:\AgentCluster\workspace\$NEW_NAME"

# 3. workers.json 업데이트
$cfg = Get-Content "D:\AgentCluster\config\workers.json" -Raw | ConvertFrom-Json
$cfg.project.repoUrl = $NEW_REPO
$cfg.orchestrator.repoPath = "D:\AgentCluster\workspace\$NEW_NAME"
$cfg | ConvertTo-Json -Depth 10 | Set-Content "D:\AgentCluster\config\workers.json" -Encoding UTF8
```

### Step 3 — setup 스크립트 새 레포에 push

```powershell
cd "D:\AgentCluster\workspace\$NEW_NAME"

# setup 스크립트 복사
Copy-Item "D:\AgentCluster\workspace\test\setup-worker.sh" .
Copy-Item "D:\AgentCluster\workspace\test\setup-worker.ps1" .

# URL 변경
(Get-Content setup-worker.sh) -replace 'https://github.com/404NotFound-sunrin/test.git', $NEW_REPO | Set-Content setup-worker.sh
(Get-Content setup-worker.ps1) -replace 'https://github.com/404NotFound-sunrin/test.git', $NEW_REPO | Set-Content setup-worker.ps1

# coordination, agents 폴더 구조 생성
New-Item -ItemType Directory -Force -Path coordination, agents, workers/register
"# Task" | Set-Content coordination/task.md
"# Discussion" | Set-Content coordination/discussion.md

git add -A
git commit -m "init: AgentCluster 초기 설정"
git push origin main
```

### Step 4 — 모니터링 서버 재시작

```powershell
Get-Process python | Stop-Process -Force
python D:\AgentCluster\monitor\main.py
```

### Step 5 — 각 Worker 기기에서 재등록

**macOS/Linux:**
```bash
rm -rf ~/AgentWorker
bash <(curl -s https://raw.githubusercontent.com/<계정>/<레포이름>/main/setup-worker.sh)
```

**Windows:**
```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\AgentWorker"
irm https://raw.githubusercontent.com/<계정>/<레포이름>/main/setup-worker.ps1 | iex
```

---

## 디렉토리 구조 (Windows 서버)

```
D:\AgentCluster\
├─ config\
│  └─ workers.json              # 전체 worker 목록
├─ workspace\
│  ├─ test\                     # Git repo (main 브랜치)
│  ├─ claude-macmini\           # Mac mini worktree
│  └─ claude-macbook\           # MacBook worktree
├─ keys\
│  ├─ orchestrator_ed25519      # Windows→Worker SSH 개인키
│  └─ orchestrator_ed25519.pub  # 공개키 (각 Worker authorized_keys에 등록)
├─ scripts\
│  ├─ Start-All.ps1             # 전체 서비스 시작 (자동 시작 등록됨)
│  ├─ Send-Task.ps1             # Task 전송
│  ├─ Get-Results.ps1           # 결과 확인
│  └─ Auto-Register.ps1         # 새 Worker 수동 감지 및 등록
├─ monitor\
│  ├─ main.py                   # FastAPI 모니터링 서버
│  └─ static\index.html         # 대시보드 UI
├─ logs\
│  ├─ startup.log               # 자동 시작 로그
│  ├─ monitor.log               # 모니터링 서버 로그
│  └─ ngrok-url.txt             # 현재 ngrok 공개 주소
└─ prompts\                     # 상황별 상세 설정 가이드
```

---

## 문제 해결

### 모니터링 서버 재시작
```powershell
Get-Process python | Stop-Process -Force
python D:\AgentCluster\monitor\main.py
```

### Worker가 task 안 받을 때
```bash
# macOS에서
tail -f ~/AgentWorker/logs/worker.log
launchctl kickstart -k gui/$(id -u)/com.agentcluster.worker
```

### 새 Worker가 대시보드에 안 뜰 때
```powershell
# 수동 감지 실행
& 'D:\AgentCluster\scripts\Auto-Register.ps1'
# 서버 재시작
Get-Process python | Stop-Process -Force
python D:\AgentCluster\monitor\main.py
```

### ngrok 주소 확인
```powershell
Get-Content D:\AgentCluster\logs\ngrok-url.txt
# 또는
start http://localhost:4040
```

### SSH 서버 재시작
```powershell
Restart-Service sshd
```
