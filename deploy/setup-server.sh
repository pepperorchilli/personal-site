#!/usr/bin/env bash
#
# 服务器初始化 —— 只在**第一次**部署时跑一次
#
# 用法（在服务器上，用 root 或有 sudo 权限的账号）：
#   bash setup-server.sh
#
# 做的事：
#   1. 装系统依赖（Node.js 20、Python、MySQL、Nginx）
#   2. 创建应用目录
#   3. 配置 MySQL（建库建表建账号）
#   4. 配置 Nginx
#   5. 注册 Flask 的 systemd 服务
#
# ⚠️ 跑之前先确认：云服务器控制台的「安全组」已放行 80 端口
#    （这一步只能在控制台做，脚本帮不了你）

set -euo pipefail

APP_ROOT="/opt"
SITE_DIR="${APP_ROOT}/personal-site"
ROBOT_DIR="${APP_ROOT}/robot-arm"
LIB_DIR="${APP_ROOT}/library-system"

echo "=================================================="
echo "  个人网站 · 服务器初始化"
echo "=================================================="

# ---------- 1. 系统依赖 ----------
echo ""
echo "[1/5] 安装系统依赖…"

apt-get update -qq
apt-get install -y -qq curl git nginx mysql-server python3 python3-venv python3-pip unzip

# Node.js 20 LTS
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi

# pm2 进程守护
if ! command -v pm2 >/dev/null 2>&1; then
  npm install -g pm2
fi

echo "  Node:  $(node -v)"
echo "  npm:   $(npm -v)"
echo "  Python:$(python3 -V)"

# ---------- 2. 目录 ----------
echo ""
echo "[2/5] 创建应用目录…"
mkdir -p "${SITE_DIR}" "${ROBOT_DIR}" "${LIB_DIR}"
mkdir -p /var/log/pm2
echo "  ${SITE_DIR}"
echo "  ${ROBOT_DIR}"
echo "  ${LIB_DIR}"

# ---------- 3. MySQL ----------
echo ""
echo "[3/5] 启动 MySQL…"
systemctl enable --now mysql

cat <<'MYSQL_HINT'

  ⚠️ 接下来需要手动做两件事：
     1) 建库建表：把 robot-arm2/server/schema.sql 跑一遍
     2) 改数据库密码：schema.sql 里的默认密码是 arm_dev_password，
        生产环境必须改掉，并同步更新 pm2 配置里的 DB_PASSWORD

  示例：
     mysql -u root < /opt/robot-arm/robot-arm2/server/schema.sql
     mysql -u root -e "ALTER USER 'arm_app'@'localhost' IDENTIFIED BY '你的新密码';"

MYSQL_HINT

# ---------- 4. Nginx ----------
echo ""
echo "[4/5] 配置 Nginx…"
if [ -f "${SITE_DIR}/deploy/nginx.conf" ]; then
  cp "${SITE_DIR}/deploy/nginx.conf" /etc/nginx/sites-available/personal-site
  ln -sf /etc/nginx/sites-available/personal-site /etc/nginx/sites-enabled/personal-site
  rm -f /etc/nginx/sites-enabled/default
  nginx -t && systemctl reload nginx
  echo "  ✅ Nginx 已配置"
else
  echo "  ⚠️ 找不到 ${SITE_DIR}/deploy/nginx.conf，跳过"
  echo "     （先把站点仓库 clone 到 ${SITE_DIR}，再重跑本脚本）"
fi

# ---------- 5. Flask systemd ----------
echo ""
echo "[5/5] 注册图书管理服务…"
if [ -f "${SITE_DIR}/deploy/library-system.service" ]; then
  cp "${SITE_DIR}/deploy/library-system.service" /etc/systemd/system/
  systemctl daemon-reload
  systemctl enable library-system
  echo "  ✅ 已注册（首次启动前需要先装好 Python 依赖，见 DEPLOY.md）"
else
  echo "  ⚠️ 找不到 library-system.service，跳过"
fi

# ---------- 完成 ----------
cat <<'DONE'

==================================================
  初始化完成
==================================================

接下来（详见 docs/DEPLOY.md）：

  1. clone 两个项目仓库到 /opt/
  2. 配置机械臂的 config.js（数据库密码等）
  3. pm2 start /opt/personal-site/deploy/ecosystem.config.js
  4. 装图书系统的 Python 依赖并启动 library-system
  5. 检查：curl http://localhost/

⚠️ 别忘了云服务器控制台的安全组放行 80 端口

DONE
