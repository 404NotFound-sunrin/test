#!/bin/bash
# AgentCluster Worker 자동 설정 스크립트
# 사용법: bash <(curl -s https://raw.githubusercontent.com/404NotFound-sunrin/test/main/setup-worker.sh)

set -e

REPO_URL="https://github.com/404NotFound-sunrin/test.git"
ORCHESTRATOR_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILHunEsxEocdkUNCOGHH0kNSDRS6wxUhg+iKbUBq5Wds agentcluster-orchestrator"
WORKER_BASE="$HOME/AgentWorker"

echo "=============================="
echo " AgentCluster Worker Setup"
echo "=============================="

# --- Worker ID 자동 결정 ---
HOSTNAME_CLEAN=$(hostname | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
WORKER_ID="claude-${HOSTNAME_CLEAN}"
USERNAME=$(whoami)

# Mac 계열 기기명 정리
case "$HOSTNAME_CLEAN" in
  *macmini*) WORKER_ID="claude-macmini" ;;
  *macbook*) WORKER_ID="claude-macbook" ;;
  *mac*)     WORKER_ID="claude-mac" ;;
esac

AGENT_NAME="${WORKER_ID#claude-}"
BRANCH="agents/${WORKER_ID}"

echo "Worker ID: $WORKER_ID"
echo "Branch:    $BRANCH"
echo "User:      $USERNAME"
echo ""

# --- IP 주소 감지 ---
IP=$(ipconfig getifaddr en0 2>/dev/null || \
     ipconfig getifaddr en1 2>/dev/null || \
     hostname -I 2>/dev/null | awk '{print $1}' || \
     echo "unknown")

echo "IP: $IP"
echo ""

# --- 1. 디렉토리 생성 ---
echo "[1/8] 디렉토리 생성..."
mkdir -p "$WORKER_BASE/repos" "$WORKER_BASE/logs"

# --- 2. repo clone 또는 업데이트 ---
echo "[2/8] Git repo 설정..."
REPO_DIR="$WORKER_BASE/repos/test"
if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR"
    git fetch --all --quiet
else
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi

# 브랜치 생성 및 체크아웃
git checkout main --quiet
git pull origin main --quiet
git checkout -B "$BRANCH" 2>/dev/null || git checkout "$BRANCH"
git merge main --no-edit --quiet 2>/dev/null || true
git push origin "$BRANCH" 2>/dev/null || true

# --- 3. Orchestrator SSH 키 등록 ---
echo "[3/8] SSH 키 등록..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
if ! grep -qF "agentcluster-orchestrator" ~/.ssh/authorized_keys 2>/dev/null; then
    echo "$ORCHESTRATOR_PUBKEY" >> ~/.ssh/authorized_keys
    echo "  → orchestrator 키 등록 완료"
else
    echo "  → 이미 등록됨"
fi

# --- 4. Remote Login 활성화 (macOS) ---
echo "[4/8] Remote Login 활성화..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo systemsetup -setremotelogin on 2>/dev/null || echo "  → 이미 활성화됨"
fi

# --- 5. Claude 전역 권한 설정 ---
echo "[5/8] Claude 권한 설정..."
mkdir -p ~/.claude
cat > ~/.claude/settings.json << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(*)", "Edit(*)", "Write(*)", "Read(*)",
      "Glob(*)", "Grep(*)", "WebFetch(*)", "WebSearch(*)"
    ],
    "deny": []
  }
}
EOF
echo "  → ~/.claude/settings.json 생성 완료"

# --- 6. worker.sh 설치 ---
echo "[6/8] worker.sh 설치..."
cat > "$WORKER_BASE/worker.sh" << WORKEREOF
#!/bin/bash
set -e
REPO="$WORKER_BASE/repos/test"
BRANCH="$BRANCH"
AGENT_NAME="$AGENT_NAME"
LAST_HASH=""
echo "[\$(date)] AgentWorker [$WORKER_ID] started."

while true; do
    cd "\$REPO"
    git fetch origin main --quiet 2>/dev/null || true
    CURRENT_HASH=\$(git rev-parse origin/main 2>/dev/null || echo "")

    if [ -n "\$CURRENT_HASH" ] && [ "\$CURRENT_HASH" != "\$LAST_HASH" ]; then
        echo "[\$(date)] New task detected. Running..."
        git pull origin main --quiet 2>/dev/null || true
        git checkout "\$BRANCH" --quiet 2>/dev/null || git checkout -B "\$BRANCH"
        git merge main --no-edit --quiet 2>/dev/null || true

        TASK=\$(cat coordination/task.md 2>/dev/null || echo "No task")
        # 다른 에이전트 응답도 컨텍스트로 포함
        OTHER_AGENTS=""
        for f in agents/*.md; do
            [ "\$(basename \$f)" = "\${AGENT_NAME}.md" ] && continue
            OTHER_AGENTS="\$OTHER_AGENTS\n### \$(basename \$f .md)\n\$(cat \$f)\n"
        done
        DISCUSSION=\$(cat coordination/discussion.md 2>/dev/null || echo "")

        claude --dangerously-skip-permissions -p "
너는 $WORKER_ID 에이전트다. 워크스페이스는 \$REPO 이다.

현재 task:
---
\$TASK
---

다른 에이전트들의 현재 상태:
---
\$OTHER_AGENTS
---

현재 토론 내용:
---
\$DISCUSSION
---

확인 요청 없이 끝까지 자율적으로 수행해라.
결과는 agents/\${AGENT_NAME}.md, 의견/토론은 coordination/discussion.md 에 추가 작성.
완료 후:
git add -A
git commit -m 'agent: $WORKER_ID 작업 완료'
git push origin \$BRANCH
"
        LAST_HASH="\$CURRENT_HASH"
        echo "[\$(date)] Done."
    fi
    sleep 60
done
WORKEREOF

chmod +x "$WORKER_BASE/worker.sh"
echo "  → $WORKER_BASE/worker.sh 생성 완료"

# --- 7. LaunchAgent 등록 (macOS) / systemd (Linux) ---
echo "[7/8] 자동 시작 등록..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    PLIST="$HOME/Library/LaunchAgents/com.agentcluster.worker.plist"
    cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.agentcluster.worker</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$WORKER_BASE/worker.sh</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$WORKER_BASE/logs/worker.log</string>
    <key>StandardErrorPath</key><string>$WORKER_BASE/logs/worker.log</string>
</dict>
</plist>
PLISTEOF
    pkill -f worker.sh 2>/dev/null || true
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "  → LaunchAgent 등록 완료"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    SERVICE_FILE="/etc/systemd/system/agentcluster-worker.service"
    sudo tee "$SERVICE_FILE" > /dev/null << SVCEOF
[Unit]
Description=AgentCluster Worker ($WORKER_ID)
After=network.target

[Service]
Type=simple
User=$USERNAME
ExecStart=/bin/bash $WORKER_BASE/worker.sh
Restart=always
RestartSec=10
StandardOutput=append:$WORKER_BASE/logs/worker.log
StandardError=append:$WORKER_BASE/logs/worker.log

[Install]
WantedBy=multi-user.target
SVCEOF
    sudo systemctl daemon-reload
    sudo systemctl enable agentcluster-worker
    sudo systemctl restart agentcluster-worker
    echo "  → systemd 서비스 등록 완료"
fi

# --- 8. 자기 등록 정보 GitHub에 push ---
echo "[8/8] 서버에 등록 신청 중..."
cd "$REPO_DIR"
git checkout "$BRANCH" --quiet

mkdir -p workers/register

cat > "workers/register/${WORKER_ID}.json" << REGEOF
{
  "id": "$WORKER_ID",
  "host": "$IP",
  "sshUser": "$USERNAME",
  "branch": "$BRANCH",
  "agentName": "$AGENT_NAME",
  "os": "$(uname -s)",
  "hostname": "$(hostname)",
  "registeredAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
REGEOF

# 초기 에이전트 소개 파일
if [ ! -f "agents/${AGENT_NAME}.md" ]; then
cat > "agents/${AGENT_NAME}.md" << INTROEOF
# ${WORKER_ID} Agent

## 기기 정보
- hostname: $(hostname)
- IP: $IP
- OS: $(uname -s) $(uname -r)
- 사용자: $USERNAME
- Claude Code: $(claude --version 2>/dev/null || echo "설치됨")

## 설정 상태
- 등록 완료: $(date '+%Y-%m-%d %H:%M:%S')
- worker.sh: 실행 중
- LaunchAgent/systemd: 등록됨
- Claude 전역 권한: 설정됨
INTROEOF
fi

git add -A
git commit -m "worker: ${WORKER_ID} 자동 등록 신청" 2>/dev/null || echo "변경 없음"
git push origin "$BRANCH" 2>/dev/null || true

echo ""
echo "=============================="
echo " 설정 완료!"
echo "=============================="
echo "Worker ID: $WORKER_ID"
echo "IP:        $IP"
echo "Branch:    $BRANCH"
echo ""
echo "Windows 서버에서 자동으로 감지됩니다 (최대 60초)."
echo "로그: tail -f $WORKER_BASE/logs/worker.log"
