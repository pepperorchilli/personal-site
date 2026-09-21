#!/usr/bin/env bash
#
# 备份服务器数据到本地 —— 在你自己的电脑上运行
#
#   bash deploy/backup.sh
#
# 备份什么（只备"丢了就找不回来"的东西）：
#   - MySQL 数据库     账号、留言、回复        ← 最重要的
#   - 图书馆数据       藏书、借阅记录、全文映射表
#   - 服务器配置       config.js / .env（含数据库密码、ESP32 暗号）
#
# 不备份：代码（在 git 里）、公版书全文（能重新下载）
#
# 备份位置：~/Backups/robot-arm-site/日期时间/
# 保留策略：默认留最近 14 份，更早的自动删除
#
# ---- 恢复方法 ----
#   数据库：  mysql -u root robot_arm < 数据库.sql
#   图书馆：  rsync -a 图书馆数据/ root@<服务器>:/opt/library-system/data/
#   配置：    rsync -a 配置/    root@<服务器>:/opt/robot-arm/robot-arm2/server/

set -euo pipefail

# ============ 配置 ============
SERVER_IP="82.157.162.144"
SSH_KEY="$HOME/Downloads/QiuDai.pem"
REMOTE_USER="root"

BACKUP_ROOT="$HOME/Backups/robot-arm-site"
KEEP=14          # 保留最近多少份
# =============================

SSH="ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=20 $REMOTE_USER@$SERVER_IP"
STAMP=$(date +%Y-%m-%d_%H%M%S)
DEST="$BACKUP_ROOT/$STAMP"

log() { echo -e "\033[36m▶ $1\033[0m"; }

log "备份到 $DEST"
mkdir -p "$DEST/配置"

# ---------- 1. 数据库 ----------
log "[1/3] 导出数据库"
$SSH "mysqldump -u root --single-transaction --routines robot_arm" \
  > "$DEST/数据库.sql"
echo "  $(grep -c 'INSERT INTO' "$DEST/数据库.sql" 2>/dev/null || echo 0) 条 INSERT，$(du -h "$DEST/数据库.sql" | cut -f1)"

# ---------- 2. 图书馆数据 ----------
log "[2/3] 同步图书馆数据"
# 排除 books/（8MB 公版书全文，能重新下载）
rsync -az --exclude 'books/' \
  -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$REMOTE_USER@$SERVER_IP:/opt/library-system/data/" "$DEST/图书馆数据/"
echo "  $(find "$DEST/图书馆数据" -type f | wc -l | tr -d ' ') 个文件"

# ---------- 3. 服务器配置 ----------
log "[3/3] 取回服务器配置"
rsync -az -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$REMOTE_USER@$SERVER_IP:/opt/robot-arm/robot-arm2/server/config.js" "$DEST/配置/" 2>/dev/null || \
  echo "  ⚠️ config.js 取不到"
rsync -az -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$REMOTE_USER@$SERVER_IP:/opt/library-system/.env" "$DEST/配置/" 2>/dev/null || \
  echo "  ⚠️ .env 取不到"

chmod -R go-rwx "$DEST"   # 含密码，收紧权限

# ---------- 清理旧备份 ----------
log "清理旧备份（保留最近 $KEEP 份）"
cd "$BACKUP_ROOT"
ls -1dt */ 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -rf "$old"
  echo "  删除 $old"
done

# ---------- 汇总 ----------
TOTAL=$(du -sh "$DEST" | cut -f1)
COUNT=$(ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "=================================================="
echo "  备份完成"
echo "=================================================="
echo "  本次：$DEST  ($TOTAL)"
echo "  共  ：$COUNT 份"
echo ""
echo "  目录内容："
find "$DEST" -maxdepth 2 -type f | sed "s|$DEST/|    |"
