#!/usr/bin/env bash
#
# 一键部署/更新 —— 在**你自己的电脑上**运行（不是服务器）
#
#   bash deploy/push.sh
#
# 为什么需要这个脚本：
#   这台云服务器**连不上 GitHub**（国内网络常见），
#   所以服务器上没法 `git pull`。改成从本地 rsync 推代码过去。
#
# 做的事：
#   1. rsync 三个仓库到服务器
#   2. 远程重建 Vue 前端、更新 Python 依赖
#   3. 重启 Node 和 Flask 服务
#   4. 健康检查

set -euo pipefail

# ============ 配置（按需修改）============
SERVER_IP="82.157.162.144"
SSH_KEY="$HOME/Downloads/QiuDai.pem"
REMOTE_USER="root"

# 本地仓库路径
LOCAL_SITE="$HOME/Desktop/personal-site"
LOCAL_ROBOT="$HOME/Desktop/机器人研究(vscode)"
LOCAL_LIB="$HOME/Desktop/JC1503-Library-System"
# =========================================

SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=20 $REMOTE_USER@$SERVER_IP"

# rsync 的排除项
#
# ⚠️⚠️ 凭据文件必须排除 ⚠️⚠️
#   rsync **不认 .gitignore**，如果不过滤，本地的开发用 config.js /
#   secrets.h 会直接覆盖服务器上的生产配置，导致：
#     - 数据库密码被换成开发密码 → 服务连不上 MySQL 直接退出
#     - ESP32 token 被换掉 → 设备认证失败
#   （这个坑实际踩过一次，见 docs/DEPLOY.md 的「已知陷阱」）
RSYNC_EXCLUDES=(
  # ---- 凭据（绝对不能覆盖服务器上的）----
  --exclude 'config.js'
  --exclude 'secrets.h'
  # ---- 依赖和构建产物（服务器上重新生成）----
  --exclude node_modules
  --exclude .venv
  --exclude __pycache__
  --exclude 'server/public/control'
  # ---- 其它 ----
  --exclude .DS_Store
  --exclude .git
  --exclude SO-ARM101          # 12MB 参考模型，服务器不需要
)

log() { echo -e "\n\033[36m▶ $1\033[0m"; }

# ---------- 0. 连通性检查 ----------
log "[0/5] 检查服务器连接"
if ! $SSH "echo ok" >/dev/null 2>&1; then
  echo "  ❌ 连不上 $SERVER_IP"
  echo "     检查：1) IP 是否正确  2) 密钥路径  3) 网络"
  exit 1
fi
echo "  ✅ 连接正常"

# ---------- 1. 同步代码 ----------
log "[1/5] 同步代码到服务器"

$SSH "mkdir -p /opt/personal-site /opt/robot-arm /opt/library-system"

echo "  personal-site"
rsync -az --delete "${RSYNC_EXCLUDES[@]}" \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$LOCAL_SITE/" "$REMOTE_USER@$SERVER_IP:/opt/personal-site/"

echo "  robot-arm"
rsync -az "${RSYNC_EXCLUDES[@]}" \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$LOCAL_ROBOT/" "$REMOTE_USER@$SERVER_IP:/opt/robot-arm/"

echo "  library-system"
rsync -az --exclude .venv --exclude __pycache__ --exclude .DS_Store \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$LOCAL_LIB/" "$REMOTE_USER@$SERVER_IP:/opt/library-system/"

# 属主修正（本地是 macOS 的 uid，服务器上是 root）
$SSH "chown -R root:root /opt/personal-site /opt/robot-arm && \
      chown -R library:library /opt/library-system"
echo "  ✅ 同步完成"

# ---------- 2. 重建前端 ----------
log "[2/5] 重建机械臂前端"
# ⚠️ public/control/ 在 .gitignore 里，rsync 也排除了，服务器上必须重新构建
$SSH "cd /opt/robot-arm/robot-arm2/server/web && npm run build 2>&1 | tail -4"

# ---------- 3. 更新依赖 ----------
log "[3/5] 更新依赖"
$SSH "cd /opt/robot-arm/robot-arm2/server && npm install --omit=dev --no-audit --no-fund 2>&1 | tail -2"
$SSH "export PATH=/root/.local/bin:\$PATH UV_PYTHON_INSTALL_DIR=/opt/uv-python; \
      cd /opt/library-system && uv pip install -q -r requirements-web.txt && echo '  Python 依赖已更新'"

# ---------- 4. 重启服务 ----------
log "[4/5] 重启服务"
$SSH "pm2 reload robot-arm 2>&1 | tail -2"
$SSH "systemctl restart library-system && echo '  图书管理已重启'"

# ---------- 5. 健康检查 ----------
log "[5/5] 健康检查"
sleep 3
$SSH '
  echo "  服务状态:"
  printf "    %-16s %s\n" "nginx"          "$(systemctl is-active nginx)"
  printf "    %-16s %s\n" "mysqld"         "$(systemctl is-active mysqld)"
  printf "    %-16s %s\n" "library-system" "$(systemctl is-active library-system)"
  printf "    %-16s %s\n" "robot-arm"      "$(pm2 jlist 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0][\"pm2_env\"][\"status\"] if d else \"?\")" 2>/dev/null)"
  echo ""
  echo "  路径检查:"
  for p in / /control/ /library/ /messages; do
    printf "    %-14s HTTP %s\n" "$p" "$(curl -s -o /dev/null -w "%{http_code}" -L "localhost$p")"
  done
'

echo ""
echo "=================================================="
echo "  部署完成 —— http://$SERVER_IP"
echo "=================================================="
