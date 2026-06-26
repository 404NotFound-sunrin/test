#!/bin/bash
# AgentCluster Worker 자동 설정 스크립트
# 사용법: bash <(curl -s https://raw.githubusercontent.com/404NotFound-sunrin/test/main/setup-worker.sh)

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

case "$HOSTNAME_CLEAN" in
  *macmini*) WORKER_ID="claude-macmini" ;;
  *macbook*) WORKER_ID="claude-macbook" ;;
  *mac*)     WORKER_ID="claude-mac" ;;
esac

AGENT_NAME="${WORKER_ID#claude-}"
BRANCH="agents/${WORKER_ID}"

IP=$(ipconfig getifaddr en0 2>/dev/null || \
     ipconfig getifaddr en1 2>/dev/null || \
     hostname -I 2>/dev/null | awk '{print $1}' || \
     echo "unknown")

echo "Worker ID : $WORKER_ID"
echo "Branch    : $BRANCH"
echo "User      : $USERNAME"
echo "IP        : $IP"
echo ""

# ── 1. Homebrew ────────────────────────────────────────────────────────────────
echo "[1/9] Homebrew 확인..."
if ! command -v brew &>/dev/null; then
    echo "  → Homebrew 설치 중..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Apple Silicon PATH 설정
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    fi
else
    echo "  → 이미 설치됨: $(brew --version | head -1)"
fi

# ── 2. Node.js ────────────────────────────────────────────────────────────────
echo "[2/9] Node.js 확인..."
if ! command -v node &>/dev/null; then
    echo "  → Node.js 설치 중..."
    brew install node
else
    echo "  → 이미 설치됨: $(node --version)"
fi

# ── 3. Claude CLI ─────────────────────────────────────────────────────────────
echo "[3/9] Claude CLI 확인..."
if ! command -v claude &>/dev/null; then
    echo "  → Claude CLI 설치 중..."
    npm install -g @anthropic-ai/claude-code

    # PATH에 npm global bin 추가
    NPM_BIN=$(npm root -g | sed 's|/lib/node_modules||')/bin
    if ! echo "$PATH" | grep -q "$NPM_BIN"; then
        echo "export PATH=\"$NPM_BIN:\$PATH\"" >> ~/.zshrc
        echo "export PATH=\"$NPM_BIN:\$PATH\"" >> ~/.zprofile
        export PATH="$NPM_BIN:$PATH"
    fi
    echo "  → Claude CLI 설치 완료"
else
    echo "  → 이미 설치됨: $(claude --version 2>/dev/null || echo 'ok')"
fi

# claude PATH 재확인
CLAUDE_BIN=$(command -v claude 2>/dev/null || npm root -g | sed 's|/lib/node_modules||')/bin/claude
if [ ! -f "$CLAUDE_BIN" ]; then
    CLAUDE_BIN=$(find /usr/local/bin /opt/homebrew/bin "$HOME/.npm-global/bin" -name claude 2>/dev/null | head -1)
fi
echo "  → claude 경로: $CLAUDE_BIN"

# ── 4. Claude 로그인 확인 ─────────────────────────────────────────────────────
echo "[4/9] Claude 로그인 확인..."
if ! "$CLAUDE_BIN" --version &>/dev/null; then
    echo "  ⚠ claude 실행 불가. 수동으로 'claude login' 필요."
elif "$CLAUDE_BIN" -p "hi" --dangerously-skip-permissions &>/dev/null; then
    echo "  → 로그인됨"
else
    echo ""
    echo "  ┌──────────────────────────────────────────────┐"
    echo "  │  Claude 로그인이 필요합니다.                  │"
    echo "  │  아래 명령어를 실행하고 다시 스크립트 재실행:  │"
    echo "  │                                              │"
    echo "  │    claude login                              │"
    echo "  │                                              │"
    echo "  └──────────────────────────────────────────────┘"
    echo ""
    "$CLAUDE_BIN" login
fi

# ── 5. Claude 전역 권한 설정 ──────────────────────────────────────────────────
echo "[5/9] Claude 권한 설정..."
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
echo "  → 전역 권한 설정 완료 (yes/no 없이 자율 실행)"

# ── 6. SSH 키 등록 + Remote Login ─────────────────────────────────────────────
echo "[6/9] SSH 설정..."
mkdir -p ~/.ssh && chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
if ! grep -qF "agentcluster-orchestrator" ~/.ssh/authorized_keys; then
    echo "$ORCHESTRATOR_PUBKEY" >> ~/.ssh/authorized_keys
    echo "  → orchestrator 키 등록"
else
    echo "  → 이미 등록됨"
fi
if [[ "$OSTYPE" == "darwin"* ]]; then
    sudo systemsetup -setremotelogin on 2>/dev/null && echo "  → Remote Login ON" || echo "  → 시스템 설정에서 Remote Login 수동 활성화 필요"
fi

# ── 7. Git repo ────────────────────────────────────────────────────────────────
echo "[7/9] Git repo 설정..."
mkdir -p "$WORKER_BASE/repos" "$WORKER_BASE/logs"
REPO_DIR="$WORKER_BASE/repos/test"
if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR" && git fetch --all --quiet
else
    git clone "$REPO_URL" "$REPO_DIR"
    cd "$REPO_DIR"
fi
git checkout main --quiet && git pull origin main --quiet
git checkout -B "$BRANCH" 2>/dev/null || git checkout "$BRANCH"
git merge main --no-edit --quiet 2>/dev/null || true
git push origin "$BRANCH" --quiet 2>/dev/null || true

# ── 8. worker.sh 설치 + 자동 시작 ─────────────────────────────────────────────
echo "[8/9] worker.sh 설치..."
cat > "$WORKER_BASE/worker.sh" << WORKEREOF
#!/bin/bash
set -uo pipefail
REPO="$WORKER_BASE/repos/test"
BRANCH="$BRANCH"
AGENT_NAME="$AGENT_NAME"
WORKER_ID="$WORKER_ID"
CLAUDE="${CLAUDE_BIN:-claude}"
STATE_DIR="$WORKER_BASE/state"
LAST_TASK_FILE="\$STATE_DIR/last_task_hash"

mkdir -p "\$STATE_DIR" "$WORKER_BASE/logs"

# PATH 보장
export PATH="/opt/homebrew/bin:/usr/local/bin:\$HOME/.npm-global/bin:\$PATH"

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*"; }
log "AgentWorker [\$WORKER_ID] started."

while true; do
    cd "\$REPO" 2>/dev/null || { log "Repo 없음"; sleep 60; continue; }

    git fetch origin main "\$BRANCH" --quiet 2>/dev/null || true

    # task.md 내용 hash만 비교 (README 등 다른 파일 변경은 무시)
    TASK_HASH=\$(git show origin/main:coordination/task.md 2>/dev/null | shasum | cut -d' ' -f1 || true)
    LAST_TASK_HASH=\$(cat "\$LAST_TASK_FILE" 2>/dev/null || true)

    if [ -n "\$TASK_HASH" ] && [ "\$TASK_HASH" != "\$LAST_TASK_HASH" ]; then
        log "task.md 변경 감지. Claude 실행 중..."

        git checkout "\$BRANCH" --quiet 2>/dev/null || git checkout -B "\$BRANCH" "origin/\$BRANCH" --quiet
        git merge origin/main --no-edit --quiet 2>/dev/null || { git merge --abort; sleep 60; continue; }

        TASK=\$(cat coordination/task.md 2>/dev/null || true)
        OTHER_AGENTS=""
        for f in agents/*.md; do
            [ "\$(basename \$f)" = "\${AGENT_NAME}.md" ] && continue
            OTHER_AGENTS="\$OTHER_AGENTS\n### \$(basename \$f .md)\n\$(cat \$f)\n"
        done
        DISCUSSION=\$(cat coordination/discussion.md 2>/dev/null || true)

        "\$CLAUDE" --dangerously-skip-permissions -p "
너는 \$WORKER_ID 에이전트다. 워크스페이스: \$REPO

현재 task:
---
\$TASK
---

다른 에이전트 상태:
---
\$OTHER_AGENTS
---

토론 내용:
---
\$DISCUSSION
---

확인 없이 끝까지 자율 수행. 결과는 agents/\${AGENT_NAME}.md, 의견은 coordination/discussion.md에 추가.
git commit/push는 worker 스크립트가 처리하므로 직접 실행하지 마라.
" 2>&1 | tee -a "$WORKER_BASE/logs/claude.log"

        git add . 2>/dev/null || true
        if ! git diff --cached --quiet; then
            git commit -m "agent: \$WORKER_ID 작업 완료"
            git push origin "\$BRANCH"
            log "push 완료"
        else
            log "변경 없음"
        fi

        echo "\$TASK_HASH" > "\$LAST_TASK_FILE"
        log "Done."
    fi
    sleep 60
done
WORKEREOF

chmod +x "$WORKER_BASE/worker.sh"

# 자동 시작 등록
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
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.npm-global/bin</string>
    </dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$WORKER_BASE/logs/worker.log</string>
    <key>StandardErrorPath</key><string>$WORKER_BASE/logs/worker.log</string>
</dict>
</plist>
PLISTEOF
    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST"
    echo "  → LaunchAgent 등록 완료 (재부팅 후 자동 시작)"

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    mkdir -p ~/.config/systemd/user
    cat > ~/.config/systemd/user/agentcluster.service << SVCEOF
[Unit]
Description=AgentCluster Worker ($WORKER_ID)
After=network.target

[Service]
ExecStart=/bin/bash $WORKER_BASE/worker.sh
Restart=always
RestartSec=10
Environment=PATH=/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin

[Install]
WantedBy=default.target
SVCEOF
    systemctl --user daemon-reload
    systemctl --user enable --now agentcluster
    echo "  → systemd 등록 완료"
fi

# ── 9. GitHub 등록 push ────────────────────────────────────────────────────────
echo "[9/9] 서버에 등록 신청..."
cd "$REPO_DIR"
git checkout "$BRANCH" --quiet
mkdir -p workers/register agents

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

cat > "agents/${AGENT_NAME}.md" << INTROEOF
# ${WORKER_ID} Agent

## 기기 정보
- hostname : $(hostname)
- IP       : $IP
- OS       : $(uname -s) $(uname -r)
- 사용자   : $USERNAME
- Claude   : $(claude --version 2>/dev/null || echo "설치됨")
- 등록     : $(date '+%Y-%m-%d %H:%M:%S')

## 상태
worker.sh 실행 중 — 대기 중
INTROEOF

git add -A
git commit -m "worker: ${WORKER_ID} 자동 등록" 2>/dev/null || true
git push origin "$BRANCH" --quiet

echo ""
echo "================================"
echo "  설정 완료!"
echo "================================"
echo "  Worker ID : $WORKER_ID"
echo "  IP        : $IP"
echo "  Branch    : $BRANCH"
echo ""
echo "  Windows 서버가 60초 내 자동 감지합니다."
echo "  로그: tail -f $WORKER_BASE/logs/worker.log"
echo "================================"
