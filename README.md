# 个人网站

把几个个人项目整合成一个网站的**编排层**：首页、部署配置、运维脚本。

> 本仓库**不包含项目代码** —— 机械臂和图书管理各有自己的仓库，
> 靠 `git clone` 拉到服务器上。这样避免了两份代码、改一处忘一处的问题。

---

## 站点结构

```
                         ┌────────────────────────────────────┐
   访客 ──── HTTP :80 ───>│  Nginx                             │
                         │  /          → 静态首页（本仓库）     │
                         │  /control   → Node  :3000  机械臂   │
                         │  /set       → Node  :3000  (需登录) │
                         │  /messages  → Node  :3000  留言板   │
                         │  /api/      → Node  :3000  留言 API │
                         │  /ws        → Node  :3000  ESP32    │
                         │  /library/  → Flask :5001  图书管理  │
                         └────────────────────────────────────┘
                                          ▲
                                          │ WebSocket
                                    ESP32-S3（主动连出）
```

**为什么用 Nginx 而不是一个后端全包？**
两个后端的语言不同（机械臂是 Node.js，图书管理是 Python），
无法合并进同一个进程，所以用 Nginx 按路径分发。

### ⚠️ 关于 `/ws` 这个路径

`/` 被**静态首页**和 **ESP32 的 WebSocket** 同时占用，
而 Nginx 无法按请求头区分 `location`。

解法：让固件连到 **`/ws`**。服务器只校验 token 不校验路径，
所以改路径不需要动后端代码，只需固件里改一行。

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
git clone <本仓库> /opt/personal-site
bash /opt/personal-site/deploy/setup-server.sh

# 之后每次更新代码
bash /opt/personal-site/deploy/deploy.sh
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

- [ ] 云服务器**安全组已放行 80 端口** ← 最容易忘，不做的话浏览器打不开
- [ ] 三处密码已改成自己的
- [ ] 数据库已建表（`schema.sql`）
- [ ] 机械臂前端已构建（`npm run build`，产物不入库）
- [ ] ESP32 的 `secrets.h` 里 `SERVER_PORT` 填的是 **80**（走 Nginx），不是 3000
