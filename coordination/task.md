# Task #002 - AgentWorker 환경 재구성 및 Windows SSH 접속 허용

## 목표
Mac mini의 디렉토리를 AgentWorker 서비스 구조로 재구성하고,
Windows 서버가 Mac mini에 SSH로 접속할 수 있도록 설정한다.

## 수행할 작업 (확인 요청 없이 끝까지 자율 실행)

### 1. 디렉토리 구조 생성
```bash
mkdir -p ~/AgentWorker/repos
mkdir -p ~/AgentWorker/logs
```

### 2. repo 새 위치로 이동
```bash
[ -d ~/ai-workers/test ] && cp -r ~/ai-workers/test ~/AgentWorker/repos/test || git clone https://github.com/404NotFound-sunrin/test.git ~/AgentWorker/repos/test
cd ~/AgentWorker/repos/test
git checkout agents/claude-macmini
```

### 3. Windows orchestrator SSH 키 등록
아래 키가 ~/.ssh/authorized_keys 에 없으면 추가:
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILHunEsxEocdkUNCOGHH0kNSDRS6wxUhg+iKbUBq5Wds agentcluster-orchestrator
```

### 4. Remote Login 활성화 확인
```bash
sudo systemsetup -getremotelogin
```
꺼져 있으면: `sudo systemsetup -setremotelogin on`

### 5. worker.sh 새 위치에 설치
~/AgentWorker/worker.sh 를 아래 내용으로 생성:
```bash
#!/bin/bash
set -e
REPO="$HOME/AgentWorker/repos/test"
BRANCH="agents/claude-macmini"
LAST_HASH=""
echo "AgentWorker started."
while true; do
    cd "$REPO"
    git fetch origin main --quiet
    CURRENT_HASH=$(git rev-parse origin/main)
    if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
        echo "[$(date)] New task. Running..."
        git pull origin main --quiet
        git checkout "$BRANCH" --quiet
        git merge main --no-edit --quiet 2>/dev/null || true
        TASK=$(cat coordination/task.md)
        claude --dangerously-skip-permissions -p "
너는 claude-macmini 에이전트다. 워크스페이스는 $REPO 이다.
현재 task:
---
$TASK
---
확인 요청 없이 끝까지 자율적으로 수행해라.
결과는 agents/macmini.md, 의견은 coordination/discussion.md 에 작성.
완료 후: git add . && git commit -m 'agent: macmini 작업 완료' && git push origin agents/claude-macmini
"
        LAST_HASH="$CURRENT_HASH"
        echo "[$(date)] Done."
    fi
    sleep 60
done
```
실행권한: `chmod +x ~/AgentWorker/worker.sh`

### 6. LaunchAgent 등록 (재부팅 후 자동 시작)
~/Library/LaunchAgents/com.agentcluster.worker.plist 생성:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.agentcluster.worker</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/yoonjunseo/AgentWorker/worker.sh</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>/Users/yoonjunseo/AgentWorker/logs/worker.log</string>
    <key>StandardErrorPath</key><string>/Users/yoonjunseo/AgentWorker/logs/worker.log</string>
</dict>
</plist>
```
등록: `launchctl load ~/Library/LaunchAgents/com.agentcluster.worker.plist`

### 7. 기존 worker 종료 후 새 worker 시작
```bash
pkill -f worker.sh 2>/dev/null || true
sleep 2
launchctl start com.agentcluster.worker
```

### 8. 완료 후 agents/macmini.md 에 아래 항목 보고
- AgentWorker 디렉토리 생성 여부
- SSH 키 등록 여부
- LaunchAgent 등록 여부
- worker 실행 상태
```bash
git add .
git commit -m "agent: macmini 환경 재구성 완료"
git push origin agents/claude-macmini
```
