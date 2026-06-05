# HOJ 部署指南（基于 Fork 源码构建）

> 仓库：https://github.com/tianyu9527/HOJ
> 适用于 Ubuntu 20.04 / 22.04 / 24.04

---

## 📁 项目结构（新增部分）

```
D:\HOJ\
├── docker/                          # Docker 构建配置
│   ├── backend/Dockerfile           # 后端构建
│   ├── judgeserver/Dockerfile       # 判题服务构建（含编译器）
│   └── frontend/
│       ├── Dockerfile               # 前端构建（Node → Nginx）
│       └── nginx.conf               # Nginx 反向代理配置
├── scripts/
│   ├── deploy.sh                    # 首次部署脚本
│   ├── update.sh                    # 更新部署脚本（二开后用）
│   └── fix-nacos-pwd.sh            # 密码修复脚本
├── docker-compose.yml               # 服务编排
├── .env                             # 环境变量（含密码，不提交 Git）
├── .env.example                     # 环境变量模板
├── .gitignore
└── .dockerignore
```

---

## 🚀 首次部署

### 方式一：一键脚本部署（推荐）

```bash
# 1. 克隆你的仓库
git clone https://github.com/tianyu9527/HOJ.git /root/hoj
cd /root/hoj

# 2. 修改密码（重要！）
cp .env.example .env
nano .env    # 修改所有密码

# 3. 执行部署
sudo bash scripts/deploy.sh
```

脚本会自动完成：
- ✅ 安装 Docker + Docker Compose
- ✅ 配置系统参数（时区、sysctl、防火墙）
- ✅ 构建所有镜像（首次约 15-30 分钟）
- ✅ 启动全部 6 个服务
- ✅ 更新 Nacos 中的密码配置
- ✅ 健康检查

### 方式二：手动部署

```bash
# 1. 安装 Docker
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
apt install -y docker-compose-plugin

# 2. 系统配置
echo "user.max_user_namespaces=28633" >> /etc/sysctl.conf
sysctl -p
timedatectl set-timezone Asia/Shanghai

# 3. 克隆仓库
git clone https://github.com/tianyu9527/HOJ.git /root/hoj
cd /root/hoj

# 4. 配置环境变量
cp .env.example .env
nano .env    # 修改密码

# 5. 创建数据目录
mkdir -p data/{mysql,redis,nacos,backend/log,judge/log}

# 6. 构建并启动
docker compose up -d --build

# 7. 等待服务就绪（约 2 分钟）
sleep 120
docker compose ps
```

---

## 🔄 二开更新工作流

```
  本地开发                    GitHub                      服务器
  ─────────                  ─────────                   ─────────
  修改代码  ──→  git push  ──→  tianyu9527/HOJ  ──→  bash scripts/update.sh
```

### 每次更新步骤：

```bash
# 在服务器上执行
cd /root/hoj
bash scripts/update.sh
```

脚本自动执行：
1. `git pull` 拉取最新代码
2. 停止业务服务（不影响数据库）
3. 重新构建变化的镜像
4. 启动所有服务
5. 健康检查

### 本地开发常用命令：

```bash
# 提交代码
git add .
git commit -m "feat: 新功能描述"
git push origin master

# 查看服务器日志（SSH 登录后）
docker compose logs -f hoj-backend      # 后端日志
docker compose logs -f hoj-judgeserver   # 判题日志
docker compose logs -f hoj-web           # 前端/Nginx 日志

# 重启单个服务
docker compose restart hoj-backend

# 进入容器调试
docker exec -it hoj-backend bash
docker exec -it hoj-judgeserver bash
```

---

## 📋 服务说明

| 服务 | 容器名 | 端口 | 说明 |
|------|--------|------|------|
| MySQL | hoj-mysql | 3306 | 数据库 |
| Redis | hoj-redis | 6379 | 缓存 |
| Nacos | hoj-nacos | 8848 | 配置中心 |
| Backend | hoj-backend | 6688 | 核心业务 API |
| Judge | hoj-judgeserver | 8088 | 判题引擎 |
| Frontend | hoj-web | **80** | 网站入口 |

### 网络架构

```
浏览器 → :80 hoj-web (Nginx)
              │
              ├── /api/* → hoj-backend:6688
              │                │
              │                ├── hoj-mysql:3306
              │                ├── hoj-redis:6379
              │                └── hoj-nacos:8848
              │
              └── 静态文件 → /usr/share/nginx/html

hoj-backend:6688 → hoj-judgeserver:8088 (Feign 调用)
```

---

## 🔧 配置修改

### 修改网站信息

登录 Nacos 管理面板：`http://你的IP:8848/nacos`
- 用户名：`nacos`
- 密码：`.env` 中的 `NACOS_PASSWORD`

找到 `hoj-prod.yml`，修改 `web-config` 部分：

```yaml
hoj:
  web-config:
    base-url: https://oj.yourdomain.com
    name: Your OJ Name
    short-name: YOJ
    description: Your Online Judge
```

修改后重启后端：
```bash
docker compose restart hoj-backend
```

### 配置邮箱

在 Nacos 的 `hoj-prod.yml` 中修改：

```yaml
hoj:
  mail:
    username: your_email@qq.com
    password: your_email_auth_code   # QQ邮箱授权码
    host: smtp.qq.com
    port: 465
```

### 配置远程判题账号

在 Nacos 的 `hoj-prod.yml` 中修改：

```yaml
hoj:
  hdu:
    account:
      username: "your_hdu_username"
      password: "your_hdu_password"
  cf:
    account:
      username: "your_cf_username"
      password: "your_cf_password"
```

---

## 🌐 配置域名和 HTTPS

### 1. 修改 Nginx 配置

编辑 `docker/frontend/nginx.conf`：

```nginx
server {
    listen 80;
    server_name oj.yourdomain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name oj.yourdomain.com;

    ssl_certificate /etc/nginx/ssl/cert.pem;
    ssl_certificate_key /etc/nginx/ssl/key.pem;

    # ... 其余配置不变
}
```

### 2. 挂载证书

修改 `docker-compose.yml` 中 hoj-web 的 volumes：

```yaml
hoj-web:
  volumes:
    - /path/to/your/cert.pem:/etc/nginx/ssl/cert.pem:ro
    - /path/to/your/key.pem:/etc/nginx/ssl/key.pem:ro
    - docker/frontend/nginx.conf:/etc/nginx/conf.d/hoj.conf:ro
```

### 3. 使用 Let's Encrypt（免费证书）

```bash
# 安装 certbot
apt install -y certbot

# 申请证书（先停止 Nginx 或使用 standalone 模式）
certbot certonly --standalone -d oj.yourdomain.com

# 证书路径
# /etc/letsencrypt/live/oj.yourdomain.com/fullchain.pem
# /etc/letsencrypt/live/oj.yourdomain.com/privkey.pem
```

---

## 🛠 常见问题

### Q: 服务启动失败怎么办？

```bash
# 查看所有服务状态
docker compose ps

# 查看具体服务日志
docker compose logs hoj-backend
docker compose logs hoj-judgeserver

# 查看最近 100 行日志
docker compose logs --tail 100 hoj-backend
```

### Q: 判题报错 "Sandbox Error"？

```bash
# 检查 sysctl 设置
sysctl user.max_user_namespaces
# 应该 >= 28633

# 如果不对，执行
echo "user.max_user_namespaces=28633" >> /etc/sysctl.conf
sysctl -p

# 重启判题服务
docker compose restart hoj-judgeserver
```

### Q: 数据库连接失败？

```bash
# 检查 MySQL 是否正常
docker compose logs hoj-mysql

# 进入 MySQL 手动测试
docker exec -it hoj-mysql mysql -uroot -p你的密码

# 如果是密码不一致，运行修复脚本
bash scripts/fix-nacos-pwd.sh
```

### Q: 如何备份数据？

```bash
# 备份数据库
docker exec hoj-mysql mysqldump -uroot -p你的密码 --all-databases > backup_$(date +%Y%m%d).sql

# 备份整个数据目录
tar -czf hoj_data_$(date +%Y%m%d).tar.gz data/

# 恢复数据库
docker exec -i hoj-mysql mysql -uroot -p你的密码 < backup_20260605.sql
```

### Q: 如何同步上游更新？

```bash
# 添加上游仓库（只需执行一次）
git remote add upstream https://github.com/HimitZH/HOJ.git

# 拉取上游更新
git fetch upstream
git merge upstream/master

# 如果有冲突，解决后提交
git add .
git commit -m "merge: 同步上游更新"

# 重新部署
bash scripts/update.sh
```

---

## 📊 服务器配置建议

| 规模 | CPU | 内存 | 磁盘 | 说明 |
|------|-----|------|------|------|
| 小型（<100人） | 2核 | 4GB | 40GB SSD | 够用 |
| 中型（100-500人） | 4核 | 8GB | 80GB SSD | 推荐 |
| 大型（>500人） | 8核 | 16GB | 160GB SSD | 判题服务器可独立部署 |

> 判题服务是 CPU 密集型，用户量大时建议将 `hoj-judgeserver` 部署到独立服务器。
