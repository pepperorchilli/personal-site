# 部署指南

从零到网站跑起来的完整步骤。

---

## 前置准备

### 1. 租服务器

| 项目 | 建议 |
|---|---|
| 厂商 | 阿里云 / 腾讯云 轻量应用服务器 |
| 配置 | **2 核 2G**、40G 硬盘 |
| 系统 | **Ubuntu 22.04** 或 24.04 |
| 价格 | ¥24~40/月（学生认证更便宜） |

### 2. ⚠️ 放行 80 端口（最容易忘的一步）

**云服务器控制台 → 安全组 → 添加规则 → 放行 TCP 80**

这一步只能在控制台做，脚本帮不了。**不做的话你在浏览器里永远打不开网站**，
而服务器上 `curl localhost` 却一切正常——这是最常见的坑。

### 3. 登录服务器

```bash
ssh root@<你的服务器IP>
```

---

## 第一步：服务器初始化

```bash
# 下载站点仓库
git clone <你的 personal-site 仓库地址> /opt/personal-site
cd /opt/personal-site

# 跑初始化脚本（装 Node / Python / MySQL / Nginx / pm2）
bash deploy/setup-server.sh
```

---

## 第二步：部署机械臂

### 1. 拉代码

```bash
git clone <你的 robot-arm 仓库地址> /opt/robot-arm
```

### 2. 建数据库

```bash
mysql -u root < /opt/robot-arm/robot-arm2/server/schema.sql
```

**⚠️ 立刻改掉默认密码**（schema.sql 里的 `arm_dev_password` 是公开的）：

```bash
mysql -u root -e "ALTER USER 'arm_app'@'localhost' IDENTIFIED BY '你的新密码';"
```

### 3. 创建配置文件

```bash
cd /opt/robot-arm/robot-arm2/server
cp config.example.js config.js
vim config.js
```

**三个值必须改**（默认值都是公开的，不改等于没锁门）：

| 配置项 | 说明 |
|---|---|
| `ADMIN_PASSWORD` | 留言板管理密码，默认 `123456` |
| `ESP32_TOKEN` | ESP32 连接暗号 |
| `DB.password` | 上一步设的数据库密码 |

### 4. 启动

```bash
cd /opt/personal-site
pm2 start deploy/ecosystem.config.js
pm2 save
pm2 startup        # 按提示执行输出的那行命令，实现开机自启
```

> ⚠️ **`ecosystem.config.js` 里的密码也要改成和 `config.js` 一致**，
> 否则 pm2 启动时会用配置文件里的值覆盖。

### 5. 验证

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/   # 应该输出 200
pm2 logs robot-arm --lines 20                                      # 看有没有报错
```

---

## 第三步：部署图书管理系统

### 1. 拉代码

```bash
git clone <你的 JC1503-Library-System 仓库地址> /opt/library-system
```

### 2. 装 Python 依赖

```bash
cd /opt/library-system
python3 -m venv .venv
.venv/bin/pip install -r requirements-web.txt
```

### 3. 创建运行账号

```bash
useradd -r -s /bin/false library
chown -R library:library /opt/library-system
```

### 4. 启动

```bash
cp /opt/personal-site/deploy/library-system.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now library-system
```

### 5. 验证

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:5001/library/   # 应该输出 200
journalctl -u library-system -n 20
```

---

## 第四步：Nginx 与整体验证

```bash
nginx -t && systemctl reload nginx
```

### 逐项自检

```bash
for p in "/" "/control" "/library/" "/messages" "/api/state"; do
  echo "$p → $(curl -s -o /dev/null -w '%{http_code}' http://localhost$p)"
done
```

> `/api/state` 会 404（它实际在 `/library/api/state`），这是正常的。

### 最终验证

**用手机 4G 网络**访问 `http://<服务器IP>/`（不要用 WiFi，要验证公网可达）。

- 首页能看到项目卡片
- 点「机械臂」→ 能打开控制台
- 点「图书管理」→ 能借书还书
- 点「留言板」→ 能发留言

---

## 第五步：接入 ESP32

1. 修改 `arm-cloud-bus/secrets.h`：
   ```c
   #define SERVER_HOST   "你的服务器IP"
   #define SERVER_PORT   80              // 走 Nginx，不是 3000
   #define ESP32_TOKEN   "和 config.js 里一致"
   ```

2. 烧录固件

3. **看服务器日志**：
   ```bash
   pm2 logs robot-arm
   # 应该看到：✅ ESP32 认证通过
   ```

4. 浏览器打开 `/control`，登录后拖动滑块 —— 机械臂应该跟着动

> ⚠️ ESP32 的 WebSocket 路径必须是 **`/ws`**（不是 `/`），
> 因为 `/` 要留给静态首页。固件里已经写好了。

---

## 日常更新

改完代码后，在服务器上跑一条命令：

```bash
bash /opt/personal-site/deploy/deploy.sh
```

它会：拉取三个仓库 → 重建 Vue 前端 → 更新 Python 依赖 → 重启服务 → 检查 Nginx。

> ⚠️ **别漏掉前端构建**：`public/control/` 在 `.gitignore` 里，
> 服务器上必须 `npm run build` 才有内容。`deploy.sh` 已经包含了这步。

---

## 常见问题

| 现象 | 原因 / 解决 |
|---|---|
| 浏览器打不开，但 `curl localhost` 正常 | **安全组没放行 80 端口**（去控制台加规则） |
| 机械臂页面空白 | 忘了 `npm run build`，`public/control/` 是空的 |
| Node 服务起不来 | 数据库没建好或密码不对。`server.js` 启动时连不上 MySQL 会直接退出 |
| 图书管理 502 | `library-system` 没启动：`systemctl status library-system` |
| 图书管理页面样式丢失 | Nginx 的 `/library/` 代理路径写错了，检查 `proxy_pass` 末尾不要加 `/` |
| ESP32 连不上 | ① token 不一致 ② 端口填了 3000（应该填 80）③ 路径不是 `/ws` |
| ESP32 反复「已连上」又「断开」 | token 不匹配。**以服务器日志为准**，它会明确打印拒绝原因 |
| 改了代码但页面没变 | 浏览器缓存（强刷 Ctrl+Shift+R），或忘了跑 `deploy.sh` |

---

## 目录对照表

| 服务器路径 | 内容 | 来源 |
|---|---|---|
| `/opt/personal-site/` | 首页 + 部署配置 | 本仓库 |
| `/opt/robot-arm/` | 机械臂（Node + Vue） | 机器人仓库 |
| `/opt/library-system/` | 图书管理（Flask） | 图书系统仓库 |
| `/etc/nginx/sites-available/personal-site` | Nginx 配置 | 从本仓库复制 |
| `/etc/systemd/system/library-system.service` | Flask 服务 | 从本仓库复制 |
