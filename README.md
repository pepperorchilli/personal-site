# 个人网站

把几个个人项目整合成一个网站的**编排层**：首页、部署配置、运维脚本。

> 本仓库**不包含项目代码** —— 机械臂和图书管理各有自己的仓库，
> 靠 `git clone` 拉到服务器上。这样避免了两份代码、改一处忘一处的问题。

---

## 站点结构

```
  浏览器 ──HTTPS :443──>┌──────────────────────────────────────┐
                        │  Nginx                               │
                        │  /          → 静态首页（本仓库）       │
                        │  /control   → Node  :3000  机械臂     │
                        │  /set       → Node  :3000  (需登录)   │
                        │  /messages  → Node  :3000  留言板     │
                        │  /api/      → Node  :3000  留言 API   │
                        │  /library/  → Flask :5001  图书管理    │
                        └──────────────────────────────────────┘

  HTTP :80 只做三件事 —— 不做全站兜底跳转（否则会打断下面第二条）：
    /.well-known/acme-challenge/  → 证书续期验证
    /ws   → Node :3000  ESP32 的明文 WebSocket ←── ESP32-S3 主动连出
    其它  → 301 https://qiudai.site
```

**为什么用 Nginx 而不是一个后端全包？**
两个后端的语言不同（机械臂是 Node.js，图书管理是 Python），
无法合并进同一个进程，所以用 Nginx 按路径分发。

### ⚠️ 关于 `/ws` 这个路径

`/` 被**静态首页**和 **ESP32 的 WebSocket** 同时占用，
而 Nginx 无法按请求头区分 `location`。

解法：让固件连到 **`/ws`**。服务器只校验 token 不校验路径，
所以改路径不需要动后端代码，只需固件里改一行。

### ⚠️ `/ws` 必须留在 80 端口，不能跟着跳 HTTPS

固件用的是**明文 `ws://`**，而 **WebSocket 握手不跟随 301 重定向**。
如果 80 端口的兜底规则把它一起跳走，设备会静默掉线 ——
浏览器里看不出任何异常，只有服务器日志里少了一行「✅ ESP32 认证通过」。

所以 80 端口块里 `/ws` 的 `location` 必须**排在兜底跳转之前**：

```nginx
location ^~ /.well-known/acme-challenge/ { ... }   # 证书续期，同样不能跳
location ^~ /ws { proxy_pass http://127.0.0.1:3000; ... }   # ESP32 明文通道
location / { return 301 https://qiudai.site$request_uri; }  # 其余一律跳
```

这是可接受的取舍：`/ws` 是独立的设备通道，走 token 鉴权、不传用户密码，
所以留在明文不影响网页侧的安全性（网页本身全程 HTTPS）。
若要彻底收敛，可让固件改用 `wss://` + `WiFiClientSecure`，
代价是 ESP32 上多一份 TLS 开销与证书管理。

---

## 目录结构

```
personal-site/
├── site/                        首页（Nginx 直接托管）
│   ├── index.html
│   └── style.css
├── deploy/
│   ├── nginx.conf               统一入口配置
│   ├── ecosystem.config.js      pm2 守护机械臂服务
│   ├── library-system.service   systemd 守护图书管理服务
│   ├── setup-server.sh          服务器初始化（只跑一次）
│   └── deploy.sh                日常更新（每次改完代码跑）
└── docs/
    └── DEPLOY.md                完整部署指南
```

---

## 相关仓库

| 仓库 | 内容 |
|---|---|
| `robot-arm` | 六自由度机械臂 —— ESP32 固件 + Node 服务 + Vue 前端 + MySQL |
| `JC1503-Library-System` | 图书管理系统 —— Python 手写数据结构 + Flask Web 版 |

---

## 快速开始

### 本地开发

三个仓库并排放，分别启动：

```bash
# 机械臂后端（:3000）
cd robot-arm/robot-arm2/server && npm start

# 图书管理（:5001）
cd JC1503-Library-System && .venv/bin/python webapp/app.py

# 首页 —— 用任意静态服务器，或直接浏览器打开 site/index.html
```

> 本地跑的时候，首页里的 `/control`、`/library/` 等链接需要 Nginx 才能正确路由。
> 单纯看首页样式的话直接打开 HTML 文件即可。

### 部署到服务器

完整步骤见 **[docs/DEPLOY.md](docs/DEPLOY.md)**，简版：

```bash
# 服务器上（只需一次）
bash /opt/personal-site/deploy/setup-server.sh

# 之后每次更新代码 —— 在【本地】跑
cd ~/Desktop/personal-site
bash deploy/push.sh
```

> ⚠️ **本服务器连不上 GitHub**（国内网络），所以服务器上没法 `git pull`。
> `push.sh` 是从你电脑 rsync 推代码过去，并远程重建前端、重启服务。
>
> `deploy.sh` 是给「服务器能访问 GitHub」的场景用的（在服务器上跑 `git pull`），
> 本机不适用。

---

## HTTPS 与证书

站点全程 HTTPS（`https://qiudai.site`），80 端口只保留验证与 ESP32 两条通道。

| 项目 | 值 |
|---|---|
| 证书 | Let's Encrypt，覆盖 `qiudai.site` + `www.qiudai.site` |
| 签发方式 | `certbot --webroot -w /opt/personal-site/site` |
| 续期 | `certbot-renew.timer`（systemd 定时器，自动续期） |

### 三条不能动的约束

1. **`/.well-known/acme-challenge/` 必须能在 80 端口访问**，且要排在跳转之前 ——
   否则 CA 拿不到验证文件，**续期会静默失败，证书到期当天整站打不开**。
2. **`/ws` 必须留在 80 端口**（原因见上文）。
3. **证书路径写死在 nginx.conf 里**：`/etc/letsencrypt/live/qiudai.site/`。
   换域名或重新签发后要同步改。

### 续期自检

续期是**静默失败**的典型：证书还剩 30 天时定时器就开始尝试，
但失败只写进 `/var/log/letsencrypt/letsencrypt.log`，没人会去看。
**建议每半年手动验一次**：

```bash
certbot renew --dry-run        # 走 Let's Encrypt 测试环境，不动生产证书
```

看到 `Congratulations, all simulated renewals succeeded` 才算通过。

查当前证书到期时间：

```bash
openssl x509 -in /etc/letsencrypt/live/qiudai.site/cert.pem -noout -enddate
```

---

## 部署前必须改的三处密码

| 位置 | 默认值 | 说明 |
|---|---|---|
| `ecosystem.config.js` 的 `ADMIN_PASSWORD` | `CHANGE_ME_...` | 留言板管理密码 |
| `ecosystem.config.js` 的 `ESP32_TOKEN` | `CHANGE_ME_...` | ESP32 连接暗号 |
| `ecosystem.config.js` 的 `DB_PASSWORD` | `CHANGE_ME_...` | 数据库密码 |

> 机械臂仓库的 `config.js` 里也要改成一致的值。

---

## 部署前检查清单

- [ ] 云服务器**安全组已放行 80 和 443 端口** ← 最容易忘，不做的话浏览器打不开
- [ ] 证书已签发（`certbot --webroot`），且 `certbot renew --dry-run` 通过
- [ ] 三处密码已改成自己的
- [ ] 数据库已建表（`schema.sql`）
- [ ] 机械臂前端已构建（`npm run build`，产物不入库）
- [ ] ESP32 的 `secrets.h` 里 `SERVER_PORT` 填的是 **80**（走 Nginx），不是 3000
