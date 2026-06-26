#!/bin/bash
set -e

REPO="$HOME/ai-workers/test"
BRANCH="agents/claude-macmini"
LAST_HASH=""

echo "Worker started. Polling for tasks..."

while true; do
    cd "$REPO"
    git fetch origin main --quiet

    CURRENT_HASH=$(git rev-parse origin/main)

    if [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
        echo "[$(date)] New task detected. Running..."
        git pull origin main --quiet
        git checkout "$BRANCH" --quiet
        git merge main --no-edit --quiet 2>/dev/null || true

        TASK=$(cat coordination/task.md)

        claude --permission-mode bypassPermissions -p "
너는 claude-macmini 에이전트다. 워크스페이스는 $REPO 이다.

아래는 현재 task 내용이다:
---
$TASK
---

지시에 따라 작업해라.
- 결과는 agents/macmini.md 에 작성
- 의견은 coordination/discussion.md 에 추가
- 완료 후 반드시 아래 명령으로 push:
  git add .
  git commit -m 'agent: macmini 작업 완료'
  git push origin agents/claude-macmini
"
        LAST_HASH="$CURRENT_HASH"
        echo "[$(date)] Done."
    else
        echo "[$(date)] No new task."
    fi

    sleep 60
done
