#!/usr/bin/env bash
#
# 一键更新部署（服务器侧，用 git pull 拉代码）
#
# ⚠️ 适用场景：服务器**能访问 GitHub**
#
#    本项目实际用的服务器（82.157.162.144）连不上 GitHub，
#    所以那边用的是 **push.sh**（在本地运行，rsync 推代码过去）。
#    如果你换了能访问 GitHub 的服务器，再用这个脚本。
#
# 用法（在服务器上）：
#   bash /opt/personal-site/deploy/deploy.sh
#
# 做的事：
#   1. 拉取三个仓库的最新代码
#   2. 重建机械臂的 Vue 前端（⚠️ 构建产物不入库，必须重新构建）
#   3. 更新图书系统的 Python 依赖
#   4. 重启两个服务
#   5. Nginx 配置有变化时热重载

set -euo pipefail

SITE_DIR="/opt/personal-site"
ROBOT_DIR="/opt/robot-arm"
LIB_DIR="/opt/library-system"

log() { echo -e "\n\033[36m▶ $1\033[0m"; }

# ---------- 1. 拉取代码 ----------
log "[1/5] 拉取代码"

for d in "$SITE_DIR" "$ROBOT_DIR" "$LIB_DIR"; do
  if [ -d "$d/.git" ]; then
    echo "  $(basename "$d")"
    git -C "$d" pull --ff-only || echo "    ⚠️ 拉取失败（有本地改动？），跳过"
  else
    echo "  ⚠️ $d 不是 git 仓库，跳过"
  fi
done

# ---------- 2. 机械臂后端依赖 + 前端构建 ----------
log "[2/5] 构建机械臂前端"
cd "$ROBOT_DIR/robot-arm2/server"

npm install --omit=dev --no-audit --no-fund
# ⚠️ 关键：public/control/ 在 .gitignore 里，服务器上必须重新构建
npm run build
echo "  ✅ 前端构建完成"

# ---------- 3. 图书系统依赖 ----------
log "[3/5] 更新图书系统依赖"
cd "$LIB_DIR"
if [ -d .venv ]; then
  .venv/bin/pip install -q -r requirements-web.txt
  echo "  ✅ 依赖已更新"
else
  echo "  ⚠️ 没找到 .venv，先创建："
  echo "     cd $LIB_DIR && python3 -m venv .venv && .venv/bin/pip install -r requirements-web.txt"
fi

# ---------- 4. 重启服务 ----------
log "[4/5] 重启服务"

if pm2 describe robot-arm >/dev/null 2>&1; then
  pm2 reload robot-arm
  echo "  ✅ 机械臂服务已重载（零停机）"
else
  pm2 start "$SITE_DIR/deploy/ecosystem.config.js"
  pm2 save
  echo "  ✅ 机械臂服务已启动"
fi

if systemctl is-enabled library-system >/dev/null 2>&1; then
  systemctl restart library-system
  echo "  ✅ 图书系统已重启"
else
  echo "  ⚠️ library-system 服务未注册，跳过"
fi

# ---------- 5. Nginx ----------
log "[5/5] 检查 Nginx"

if ! diff -q "$SITE_DIR/deploy/nginx.conf" /etc/nginx/sites-available/personal-site >/dev/null 2>&1; then
  cp "$SITE_DIR/deploy/nginx.conf" /etc/nginx/sites-available/personal-site
  if nginx -t 2>/dev/null; then
    systemctl reload nginx
    echo "  ✅ Nginx 配置已更新并重载"
  else
    echo "  ❌ Nginx 配置有误，已保留旧配置"
    nginx -t
  fi
else
  echo "  Nginx 配置无变化"
fi

# ---------- 完成 ----------
cat <<'DONE'

==================================================
  部署完成
==================================================

  自检：
    curl -s -o /dev/null -w "%{http_code}\n" http://localhost/            # 首页
    curl -s -o /dev/null -w "%{http_code}\n" http://localhost/library/    # 图书管理
    curl -s -o /dev/null -w "%{http_code}\n" http://localhost/control     # 机械臂

  看日志：
    pm2 logs robot-arm
    journalctl -u library-system -f

DONE
