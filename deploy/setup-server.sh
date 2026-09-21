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
# ⚠️ 跑之前先确认：云服务器控制台的「安全组」已放行 80 和 443 端口
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

# ⚠️ 包管理器不能写死。
#    本服务器实际是 **OpenCloudOS 9**（RHEL 系，用 dnf），
#    而这个脚本最初是按 Ubuntu 写的（apt-get）—— 在真机上第一步就会失败。
if   command -v dnf     >/dev/null 2>&1; then PKG=dnf
elif command -v yum     >/dev/null 2>&1; then PKG=yum
elif command -v apt-get >/dev/null 2>&1; then PKG=apt
else
  echo "  ❌ 认不出包管理器（dnf / yum / apt-get 都没有）"; exit 1
fi
echo "  包管理器：${PKG}"

case "$PKG" in
  dnf|yum)
    $PKG install -y curl git nginx mysql-server python3 python3-pip unzip certbot
    ;;
  apt)
    apt-get update -qq
    apt-get install -y -qq curl git nginx mysql-server python3 python3-venv python3-pip unzip certbot
    ;;
esac

# Node.js 20 LTS（两个发行版的源地址不同）
if ! command -v node >/dev/null 2>&1; then
  if [ "$PKG" = "apt" ]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  else
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
  fi
  $PKG install -y nodejs
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

# nginx 配置放哪，两个发行版不一样：
#   RHEL 系（OpenCloudOS / CentOS / 龙蜥）→ /etc/nginx/conf.d/
#   Debian 系（Ubuntu）                  → /etc/nginx/sites-available/
if [ -d /etc/nginx/conf.d ]; then
  NGINX_CONF=/etc/nginx/conf.d/personal-site.conf
  NGINX_LAYOUT=rhel
else
  NGINX_CONF=/etc/nginx/sites-available/personal-site
  NGINX_LAYOUT=debian
fi

if [ ! -f "${SITE_DIR}/deploy/nginx.conf" ]; then
  echo "  ⚠️ 找不到 ${SITE_DIR}/deploy/nginx.conf，跳过"
  echo "     （先把站点仓库 clone 到 ${SITE_DIR}，再重跑本脚本）"
elif [ ! -s /etc/letsencrypt/live/qiudai.site/fullchain.pem ]; then
  # ⚠️⚠️ 证书没签出来之前，绝对不能套用这份配置 ⚠️⚠️
  #
  #    配置里的 ssl_certificate 指向 /etc/letsencrypt/live/qiudai.site/，
  #    证书不存在时 `nginx -t` 直接失败 → nginx 起不来/不 reload，
  #    **连 80 端口一起挂掉，整个站点不可访问**。
  #
  #    而签证书又需要 nginx 先在 80 端口服务验证文件 —— 鸡生蛋。
  #    正确顺序见 docs/DEPLOY.md「第四步」：先签证书，再套用配置。
  echo "  ⚠️ 证书尚未签发，暂不套用 Nginx 配置"
  echo "     直接套用会让 nginx 起不来（ssl_certificate 指向不存在的文件）。"
  echo "     请按 docs/DEPLOY.md「第四步」：先签证书，再回来套用配置。"
else
  cp "${SITE_DIR}/deploy/nginx.conf" "$NGINX_CONF"
  if [ "$NGINX_LAYOUT" = "debian" ]; then
    ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/personal-site
    rm -f /etc/nginx/sites-enabled/default
  fi
  nginx -t && systemctl reload nginx
  echo "  ✅ Nginx 已配置（${NGINX_CONF}）"

  # RHEL 系自带的 /etc/nginx/nginx.conf 里通常有个 listen 80 的 server 块，
  # 会和我们的配置撞（日志报 conflicting server name "_"）。
  # 这里只提示、不自动改系统文件 —— 自动 sed nginx.conf 风险更高。
  if nginx -t 2>&1 | grep -q "conflicting server name"; then
    echo "  ⚠️ 检测到 server name 冲突：把 /etc/nginx/nginx.conf 里"
    echo "     那个 listen 80 的默认 server 块注释掉即可"
  fi
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
  5. 签发 HTTPS 证书，再套用 Nginx 配置（顺序见 docs/DEPLOY.md「第四步」）
  6. 检查：curl -I https://qiudai.site/

⚠️ 别忘了云服务器控制台的安全组放行 80 和 443 端口

DONE
