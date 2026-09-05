# LifeOS V2.0

> 个人生活管理系统 —— 一站式管理健康、财务、生活方式、投资与日常提醒

LifeOS 将个人生活的核心维度整合到一个统一平台：记录健康数据、掌控财务状况、整理生活方式、追踪投资表现，并通过通知中心自动推送到期提醒。所有数据存储在你自有的数据库中，可随时备份，隐私安全可控。

**当前版本：** v2.0　**项目状态：** 活跃开发中

***

## 目录

- [功能特性](#功能特性)
- [效果预览](#效果预览)
- [技术栈](#技术栈)
- [项目结构](#项目结构)
- [本地快速开始](#本地快速开始)
- [服务器部署方案](#服务器部署方案)
- [注意事项](#注意事项)
- [数据与隐私](#数据与隐私)
- [开发约定](#开发约定)

***

## 功能特性

### 健康中心

| 功能 | 说明 |
| --- | --- |
| 健康总览 | 聚合展示各项健康数据的看板 |
| 体征与睡眠 | 血压、心率、睡眠时长等日常追踪 |
| 健身 / 饮食 / 身体 | 运动、饮食与身体指标记录 |
| 步数统计 | 按日 / 按月双视图，含每日趋势图与时间段分布 |
| 体检管理 | 体检记录、指标面板与项目化追踪 |
| 用药记录 | 早 / 午 / 晚分餐次服药管理，购药记录与药品库存按粒实时计算 |
| 健康报告 | 支持近 7 / 30 / 90 天与自定义周期，一键导出 PDF / Excel |

### 财务管理

| 功能 | 说明 |
| --- | --- |
| 财务总览 | 收支与债务概览、月度统计与趋势 |
| 购物记录 | 多平台购物账本，金额精确管理 |
| 旅行开支 | 行程账本式记录，按行程生成旅行报告 |
| 房租水电 | 住房信息、付款期次、水电燃气账单、押金退还渠道一体化管理，自动折算单日成本 |
| 网贷借还 | 借款平台、账单月份、还款记录与优惠计算 |
| 账单提醒 | 按账单月管理各类到期提醒 |
| 理财规划 | 未来资金安排与目标规划 |
| 债务管理 | 债务备忘录卡片，清晰掌握每笔往来 |
| 财务报告 | 周期化收支分析报告 |

### 生活方式

| 功能 | 说明 |
| --- | --- |
| 物品清单 | 个人物品登记与整理 |
| 卡片管理 | 银行卡、电话卡等卡片信息维护 |
| 待办事项 | 日常待办与打卡 |
| 生活报告 | 周期化生活数据汇总 |

### 投资管理

| 功能 | 说明 |
| --- | --- |
| 投资总览 | 账户净值、入金出金与收益总览 |
| 外汇交易 | 资金流记录（入金 / 出金 / 体验金），净值实时计算 |
| 基金记录 | 基金持仓与交易记录 |
| 投资报告 | 周期化收益分析 |

### 通知中心

| 功能 | 说明 |
| --- | --- |
| 渠道管理 | 多渠道配置，敏感字段加密存储 |
| 通知模板 | 自定义消息模板，结构化排版 |
| 定时提醒 | 每日自动扫描并发送到期提醒 |
| 发送日志 | 完整记录每次通知投递情况 |
| 邮件配置 | 邮件渠道独立配置 |

### 系统功能

| 功能 | 说明 |
| --- | --- |
| 用户认证 | 注册 / 登录，基于 JWT 的身份认证 |
| 用户中心 | 个人资料与账户设置 |
| 活动日志 | 全站操作审计，变更可追溯 |

***

## 效果预览

> **以下区域为效果图预留位**，正式发布时在此处插入首页、各模块核心页面的截图（建议存入 `docs/images/` 目录）。

| 首页 | 健康中心 | 财务总览 |
| --- | --- | --- |
| ![首页](docs/images/home.png) | ![健康中心](docs/images/health.png) | ![财务总览](docs/images/finance.png) |

| 投资管理 | 通知中心 | 移动端适配 |
| --- | --- | --- |
| ![投资管理](docs/images/investment.png) | ![通知中心](docs/images/notification.png) | ![移动端](docs/images/mobile.png) |

***

## 技术栈

| 端 | 技术 |
| --- | --- |
| 后端 | Python 3 · FastAPI · SQLAlchemy · MySQL 8 |
| 前端 | React 19 · TypeScript · Vite · Tailwind CSS · shadcn/ui |
| 认证 | JWT |
| 图表 | Recharts |
| 报告导出 | PDF（ReportLab）· Excel（openpyxl） |
| 任务调度 | APScheduler |

***

## 项目结构

```
LifeOS V2.0/
├── backend/            # 后端服务（FastAPI，端口 8000）
│   ├── app/            # 应用代码（模型 / 接口 / 服务）
│   ├── migrations/     # 数据库迁移脚本
│   └── backups/        # 数据库备份归档（仅本地，不入库）
├── frontend/           # 前端应用（Vite，端口 5173）
│   └── src/            # 页面与组件源码
├── docs/
│   └── images/         # 文档配图（效果图）
└── README.md
```

***

## 本地快速开始

### 环境要求

| 依赖 | 版本 |
| --- | --- |
| Python | 3.10+ |
| Node.js | 18+ |
| MySQL | 8.0+ |

### 1. 启动后端（端口 8000）

```bash
cd backend

# 安装依赖
pip install -r requirements.txt

# 配置环境变量：复制 .env.example 为 .env，按需修改数据库连接与密钥
cp .env.example .env

# 启动服务
.\.venv\Scripts\python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

首次启动会自动创建数据库表，并初始化通知渠道等基础数据。

### 2. 启动前端（端口 5173）

```bash
cd frontend
npm install
npm run dev
```

浏览器访问 `http://localhost:5173`，注册账号后即可开始使用。

> 前端已配置 `/api` 代理到后端；局域网设备可通过 `http://<局域网IP>:5173` 访问。

### 3. 接口文档（可选）

后端启动后，可通过以下地址查看与调试接口：

- Swagger UI：`http://localhost:8000/docs`
- ReDoc：`http://localhost:8000/redoc`

***

## 服务器部署方案

以下以 **Ubuntu 22.04 / Debian 12** 为例，介绍经典的单机部署架构：

```
用户浏览器
    │  HTTPS (443)
    ▼
Nginx ──┬── / 前端静态资源（frontend/dist 构建产物）
        │
        └── /api 反向代理
                 │  HTTP (8000)
                 ▼
            Uvicorn 后端（systemd 守护）
                 │
                 ▼
              MySQL（3306，仅本机监听）
```

### 服务器要求

- 系统：Ubuntu 22.04 / Debian 12（64 位）
- 配置：2 核 4G 起步（含 MySQL）
- 域名：可选（有域名可配置 HTTPS）

### 1. 基础环境

```bash
# 安装系统依赖
apt update
apt install -y python3 python3-venv python3-pip mysql-server nginx git

# 安装 Node.js（建议 NodeSource 或 nvm）
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
```

### 2. 获取代码

```bash
git clone https://github.com/ZeroOneCN/LifeOS2.git /opt/lifeos
cd /opt/lifeos
```

### 3. 初始化数据库

```bash
# 启动 MySQL 并创建数据库（utf8mb4）
systemctl enable --now mysql
mysql -uroot -p
> CREATE DATABASE lifeos CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
> CREATE USER 'lifeos'@'localhost' IDENTIFIED BY '你的强密码';
> GRANT ALL PRIVILEGES ON lifeos.* TO 'lifeos'@'localhost';
> FLUSH PRIVILEGES;
```

### 4. 部署后端

```bash
cd /opt/lifeos/backend

# 创建虚拟环境并安装依赖
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 配置环境变量
cp .env.example .env
vim .env
```

`.env` 关键配置（生产环境务必修改）：

| 配置项 | 说明 |
| --- | --- |
| `DATABASE_URL` | 改为上一步创建的数据库账号连接串 |
| `JWT_SECRET_KEY` | 改为随机长字符串，禁止使用默认值 |
| `CORS_ALLOW_ALL` | 设为 `False`，并配置 `CORS_ORIGINS` 白名单 |

创建 systemd 服务，实现开机自启与崩溃自动拉起：

```ini
# /etc/systemd/system/lifeos.service
[Unit]
Description=LifeOS Backend
After=network.target mysql.service

[Service]
WorkingDirectory=/opt/lifeos/backend
ExecStart=/opt/lifeos/backend/.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=3
User=www-data

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload
systemctl enable --now lifeos
```

### 5. 构建并部署前端

```bash
cd /opt/lifeos/frontend
npm ci
npm run build          # 构建产物输出到 dist/
```

### 6. 配置 Nginx

```nginx
# /etc/nginx/sites-available/lifeos
server {
    listen 80;
    server_name your-domain.com;          # 无域名可留空或填服务器 IP

    # 前端静态资源
    root /opt/lifeos/frontend/dist;
    index index.html;

    # 前端路由支持（Vue/React 类单页应用）
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 后端 API 反向代理
    location /api/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
ln -s /etc/nginx/sites-available/lifeos /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx
```

### 7. 启用 HTTPS（可选，需域名）

```bash
apt install -y certbot python3-certbot-nginx
certbot --nginx -d your-domain.com
```

### 8. 数据库自动备份

通过 crontab 每日备份数据库，保留最近 N 份：

```bash
crontab -e
# 每日凌晨 3 点备份
0 3 * * * mysqldump -ulifeos -p'你的强密码' lifeos | gzip > /var/backups/lifeos_$(date +\%Y\%m\%d).sql.gz && find /var/backups -name "lifeos_*.sql.gz" -mtime +30 -delete
```

### 9. 部署验证清单

- [ ] 后端服务运行中：`systemctl status lifeos`，访问 `http://<IP>:8000/docs` 可打开接口文档
- [ ] 前端可访问：浏览器打开 `http://<IP>` 能正常登录使用
- [ ] 注册 / 登录、数据增删改查、报告导出均正常
- [ ] 通知提醒在设定时间正常触发（检查发送日志）
- [ ] HTTPS 证书有效（如已配置）

> **内网 / 局域网部署**：若仅个人或家庭使用，可不启用 Nginx，直接以 `uvicorn ... --host 0.0.0.0 --port 8000` 运行后端、`npm run dev` 运行前端，并将 `CORS_ALLOW_ALL` 保持 `True` 即可。

***

## 注意事项

### 安全

- **生产环境必须修改 `JWT_SECRET_KEY`**，使用默认值存在严重安全隐患
- 生产环境建议将 `CORS_ALLOW_ALL` 设为 `False`，仅放行实际访问来源
- 数据库账号使用强密码，禁止使用 root 直连业务库
- 通知渠道的敏感凭据（如邮件密钥）经加密存储，请妥善保管生成的 `NOTIFICATION_ENC_KEY`，丢失后将无法解密已存凭据
- `.env` 等环境变量文件一律不提交到版本库

### 数据

- **任何数据库结构变更、数据导入操作前，必须先创建备份**（见「部署方案」备份章节）
- 数据库备份归档保留在 `backend/backups/`，不会同步到远程仓库
- 报告生成周期统一支持近 7 / 30 / 90 天与自定义起止日期，请确认所选周期在数据范围内

### 运维

- 每日提醒扫描时间默认为 `08:30`，可通过 `.env` 的 `NOTIFY_SCAN_TIME` 调整
- 服务器时区务必正确配置（提醒任务基于服务器本地时间）
- 首次启动会自动建表；后续数据库结构变更请按 `backend/migrations/` 目录中的脚本执行
- 升级代码前先 `git pull` 并阅读变更记录，避免数据口径不一致

### 使用

- 所有删除操作均需二次确认，误删不可恢复，请谨慎操作
- 数据保存后页面实时刷新，无需手动刷新浏览器
- 步数等数据录入支持连续录入（Enter 保存并跳转下一时段）

***

## 数据与隐私

- 所有业务数据存储在你自有的 MySQL 数据库中，服务器数据只属于你
- 数据库备份文件保留在本地归档目录，不纳入版本库
- 密钥、环境变量、本地临时文件均通过 `.gitignore` 排除，不会推送到远程仓库
- 通知渠道的敏感凭据（如密钥）经加密后存储
- 本项目不收集、不上传任何用户行为数据

***

## 开发约定

- 代码变更遵循「先拉取、后修改、完成后提交推送」的流程，每步完成即提交
- 提交信息使用中文，描述清晰准确
- 前端遵循 shadcn/ui 组件规范，样式统一使用主题变量
- 所有 CRUD 操作需实现实时刷新，并展示主题样式 toast 提示

***

## 许可证与声明

本项目为个人生活管理工具，代码与数据均归项目所有者所有。使用过程中产生的任何数据安全风险由使用者自行承担。
