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

### 2. ⚠️ 放行 80 和 443 端口（最容易忘的一步）

**云服务器控制台 → 安全组 → 添加规则 → 放行 TCP 80 和 TCP 443**

这一步只能在控制台做，脚本帮不了。**不做的话你在浏览器里永远打不开网站**，
而服务器上 `curl localhost` 却一切正常——这是最常见的坑。

> 两个都要放：443 给正常访问，80 给证书续期验证和 ESP32 的明文 WebSocket。

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

## 第四步：Nginx、HTTPS 与整体验证

```bash
cp /opt/personal-site/deploy/nginx.conf /etc/nginx/conf.d/personal-site.conf
nginx -t && systemctl reload nginx
```

### ⚠️ 首次部署：先签证书，再套用 HTTPS 配置

**顺序反了会开不了机。** `nginx.conf` 里写着
`ssl_certificate /etc/letsencrypt/live/qiudai.site/fullchain.pem`，
证书还不存在时 `nginx -t` 直接失败、nginx 起不来 ——
而 certbot 的 webroot 验证又需要 nginx 在 80 端口服务验证文件。
鸡生蛋问题，所以首次部署按下面的顺序走：

```bash
# 1) 装 certbot（系统不同命令不同）
dnf install -y certbot        # OpenCloudOS / RHEL 系
# apt install -y certbot      # Ubuntu / Debian 系

# 2) 先临时注释掉 nginx.conf 里的 443 那个 server 块，只跑 80
#    （80 块里的 /.well-known/acme-challenge/ 正好用于验证）
nginx -t && systemctl reload nginx

# 3) 签证书
certbot certonly --webroot -w /opt/personal-site/site \
  -d qiudai.site -d www.qiudai.site \
  --agree-tos -m <你的邮箱>

# 4) 取消注释，恢复完整配置并 reload
nginx -t && systemctl reload nginx

# 5) 确认续期定时器在跑
systemctl list-timers | grep certbot
```

> ⚠️ 第 2 步不能省。cert 没签出来就直接上含 443 的配置，
> nginx 会起不来，**整个站点（包括 80 端口）一起挂掉**。

### 逐项自检

```bash
# 本机直连（绕过 nginx 的 HTTPS，验证后端活着）
for p in "/" "/control" "/library/" "/messages" "/api/state"; do
  echo "$p → $(curl -s -o /dev/null -w '%{http_code}' http://localhost$p)"
done

# 走 HTTPS 验证公网链路
for p in "/" "/control" "/library/" "/messages"; do
  echo "$p → $(curl -s -o /dev/null -w '%{http_code}' https://qiudai.site$p)"
done
```

> `/api/state` 会 404（它实际在 `/library/api/state`），这是正常的。
> `/control`、`/library/` 返回 301/302 也是正常的（补斜杠、跳登录页）。

### 最终验证

**用手机 4G 网络**访问 `https://qiudai.site/`（不要用 WiFi，要验证公网可达）。

- 浏览器地址栏显示**锁头**，没有"不安全"警告
- 首页能看到项目卡片
- 点「机械臂」→ 能打开控制台
- 点「图书管理」→ 能借书还书
- 点「留言板」→ 能发留言

### 顺手确认续期没坏

证书续期是**静默失败**的：定时器每天照跑，失败了只写日志，没人会去看，
等证书到期当天整站打不开才发现。**建议每次部署顺手验一次**：

```bash
certbot renew --dry-run     # 走测试环境，不动生产证书
```

看到 `Congratulations, all simulated renewals succeeded` 才算通过。

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

### ⚠️ 本服务器连不上 GitHub

实测：服务器 `curl https://github.com` 超时（国内网络常见），
所以**服务器上 `git pull` 是拉不动的**。

改成**从你电脑推送**——在**本地**跑一条命令：

```bash
cd ~/Desktop/personal-site
bash deploy/push.sh
```

它会：rsync 三个仓库 → 重建 Vue 前端 → 更新 Python 依赖 → 重启服务 → 健康检查。

`push.sh` 顶部的配置项（服务器 IP、密钥路径、本地仓库路径）按需修改。

> ⚠️ **别漏掉前端构建**：`public/control/` 在 `.gitignore` 里，rsync 也排除了它，
> 服务器上必须 `npm run build` 才有内容。`push.sh` 已经包含了这步。

---

## ⚠️ 已知陷阱（都是实际踩过的）

### 1. rsync 不认 .gitignore，会覆盖服务器上的凭据

**症状**：跑完部署，机械臂服务起不来，日志报
`Access denied for user 'arm_app'@'localhost'`。

**原因**：本地的 `server/config.js`（开发用密码）被 rsync 覆盖到服务器，
替换掉了生产配置。同理 `secrets.h` 也会被覆盖。

**避免**：`push.sh` 里已加 `--exclude 'config.js' --exclude 'secrets.h'`。
**如果你自己写同步命令，务必带上这两个排除项。**

### 2. uv 装的 Python 在 /root 下，服务账号访问不了

**症状**：systemd 报 `Failed to execute gunicorn: Permission denied`。

**原因**：uv 默认把 Python 装在 `/root/.local/share/uv/python/`，
venv 里的 `python` 是指向那里的符号链接，而 `library` 用户无权进入 `/root`。

**解决**：安装时指定公共目录：

```bash
export UV_PYTHON_INSTALL_DIR=/opt/uv-python
uv python install 3.13
chmod -R a+rX /opt/uv-python
```

### 3. RHEL 系用 conf.d 而不是 sites-available

本服务器是 **OpenCloudOS 9**（RHEL 系），nginx 配置放
`/etc/nginx/conf.d/personal-site.conf`，不是 Ubuntu 的
`/etc/nginx/sites-available/`。

`setup-server.sh` 现在会按 `/etc/nginx/conf.d` 是否存在自动选目录，
但**如果你手动装，记得放对位置**。

**另外**：RHEL 自带的 `nginx.conf` 里有一个 `listen 80` 的默认 server 块，
会和我们的配置冲突（日志报 `conflicting server name "_"`），
需要把它注释掉。`setup-server.sh` 只在检测到冲突时**提示**你改，
不会自动动系统文件。

### 4. gunicorn 需要用户家目录

**症状**：`Control server error: [Errno 13] Permission denied: '/home/library'`

**解决**：`mkdir -p /home/library && chown library:library /home/library`

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
