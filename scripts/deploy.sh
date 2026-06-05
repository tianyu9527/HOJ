#!/bin/bash
# ============================================================
# HOJ 首次部署脚本
# 使用方法: sudo bash scripts/deploy.sh
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_banner() {
    echo -e "${BLUE}"
    echo "============================================"
    echo "   HOJ - Online Judge 部署脚本"
    echo "   基于 tianyu9527/HOJ 源码构建"
    echo "============================================"
    echo -e "${NC}"
}

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ----------------------------------------------------------
# 1. 环境检查
# ----------------------------------------------------------
check_env() {
    log_info "检查环境..."

    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker 未安装，正在安装..."
        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
        systemctl enable --now docker
        log_info "Docker 安装完成"
    fi
    log_info "Docker: $(docker --version)"

    # 检查 Docker Compose
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose 未安装，正在安装..."
        apt-get update && apt-get install -y docker-compose-plugin
        log_info "Docker Compose 安装完成"
    fi
    log_info "Docker Compose: $(docker compose version --short)"

    # 检查 Git
    if ! command -v git &> /dev/null; then
        log_error "Git 未安装，正在安装..."
        apt-get update && apt-get install -y git
    fi
    log_info "Git: $(git --version)"
}

# ----------------------------------------------------------
# 2. 系统配置
# ----------------------------------------------------------
setup_system() {
    log_info "配置系统参数..."

    # 设置时区
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || true

    # 设置 sysctl（判题沙箱需要）
    if ! grep -q "max_user_namespaces" /etc/sysctl.conf; then
        echo "user.max_user_namespaces=28633" >> /etc/sysctl.conf
        sysctl -p
        log_info "已设置 max_user_namespaces"
    fi

    # 配置防火墙
    if command -v ufw &> /dev/null; then
        ufw allow 80/tcp    # Web
        ufw allow 443/tcp   # HTTPS（如需）
        ufw allow 22/tcp    # SSH
        log_info "防火墙规则已添加"
    fi
}

# ----------------------------------------------------------
# 3. 生成安全配置
# ----------------------------------------------------------
generate_secrets() {
    if [ ! -f .env ]; then
        log_info "生成 .env 配置文件..."

        # 生成随机密码
        MYSQL_PWD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20)
        REDIS_PWD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20)
        NACOS_PWD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 20)
        JWT_SECRET=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 48)
        JUDGE_TOKEN=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 48)
        AUTH_TOKEN=$(openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 64)

        cat > .env << EOF
# 自动生成于 $(date '+%Y-%m-%d %H:%M:%S')
MYSQL_ROOT_PASSWORD=${MYSQL_PWD}
REDIS_PASSWORD=${REDIS_PWD}
NACOS_PASSWORD=${NACOS_PWD}
NACOS_AUTH_TOKEN=${AUTH_TOKEN}
NACOS_AUTH_IDENTITY_KEY=serverIdentity
NACOS_AUTH_IDENTITY_VALUE=$(openssl rand -hex 16)
JWT_TOKEN_SECRET=${JWT_SECRET}
JUDGE_TOKEN=${JUDGE_TOKEN}
EMAIL_SERVER_HOST=smtp.qq.com
EMAIL_SERVER_PORT=465
EMAIL_USERNAME=
EMAIL_PASSWORD=
EOF

        log_info ".env 已生成，请妥善保管！"
        echo ""
        echo -e "${YELLOW}========================================${NC}"
        echo -e "${YELLOW}  生成的密码（请记录！）${NC}"
        echo -e "${YELLOW}========================================${NC}"
        echo -e "  MySQL:  ${MYSQL_PWD}"
        echo -e "  Redis:  ${REDIS_PWD}"
        echo -e "  Nacos:  ${NACOS_PWD}"
        echo -e "${YELLOW}========================================${NC}"
        echo ""
    else
        log_info ".env 已存在，跳过生成"
    fi
}

# ----------------------------------------------------------
# 4. 创建数据目录
# ----------------------------------------------------------
create_dirs() {
    log_info "创建数据目录..."
    mkdir -p data/{mysql,redis,nacos,backend/log,judge/log}
    log_info "目录创建完成"
}

# ----------------------------------------------------------
# 5. 构建并启动服务
# ----------------------------------------------------------
build_and_start() {
    log_info "开始构建镜像（首次约 15-30 分钟）..."
    echo ""

    # 拉取基础镜像
    docker compose pull mysql redis nacos 2>/dev/null || true

    # 构建自定义镜像
    docker compose build --no-cache

    log_info "镜像构建完成，启动服务..."

    # 启动基础设施
    docker compose up -d hoj-mysql hoj-redis
    log_info "等待 MySQL 就绪..."
    sleep 30

    # 启动 Nacos
    docker compose up -d hoj-nacos
    log_info "等待 Nacos 就绪..."
    sleep 20

    # 启动业务服务
    docker compose up -d hoj-backend hoj-judgeserver
    log_info "等待业务服务启动..."
    sleep 30

    # 启动前端
    docker compose up -d hoj-web

    log_info "所有服务启动完成！"
}

# ----------------------------------------------------------
# 6. 更新 Nacos 配置中的密码
# ----------------------------------------------------------
update_nacos_config() {
    log_info "更新 Nacos 中的应用配置..."

    source .env

    # 等待 MySQL 完全就绪
    sleep 10

    # 更新 hoj-prod.yml 中的密码
    docker exec hoj-mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" nacos -e "
        UPDATE config_info SET content = REPLACE(content, 'password: hoj123456', 'password: ${MYSQL_ROOT_PASSWORD}')
        WHERE data_id = 'hoj-prod.yml';
        UPDATE config_info SET content = REPLACE(content, 'secret: hoj-secret-init', 'secret: ${JWT_TOKEN_SECRET}')
        WHERE data_id = 'hoj-prod.yml';
        UPDATE config_info SET content = REPLACE(content, 'token: hoj-judge-token-init', 'token: ${JUDGE_TOKEN}')
        WHERE data_id = 'hoj-prod.yml';
    " 2>/dev/null || log_warn "Nacos 配置更新失败，请手动在 Nacos 管理界面修改"

    # 更新 Redis 密码
    docker exec hoj-mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" nacos -e "
        UPDATE config_info SET content = REPLACE(content, 'password: hoj123456', 'password: ${REDIS_PASSWORD}')
        WHERE data_id = 'hoj-prod.yml' AND content LIKE '%redis%';
    " 2>/dev/null || true

    log_info "Nacos 配置更新完成"
}

# ----------------------------------------------------------
# 7. 健康检查
# ----------------------------------------------------------
health_check() {
    log_info "执行健康检查..."
    echo ""
    docker compose ps
    echo ""

    # 检查前端
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:80 | grep -q "200"; then
        log_info "✅ 前端服务正常 (http://localhost)"
    else
        log_warn "⚠️  前端服务可能还在启动中..."
    fi

    # 检查后端
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:6688/api/get-website-config 2>/dev/null | grep -q "200"; then
        log_info "✅ 后端服务正常 (http://localhost:6688)"
    else
        log_warn "⚠️  后端服务可能还在启动中..."
    fi

    # 检查 Nacos
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8848/nacos/ 2>/dev/null | grep -q "200"; then
        log_info "✅ Nacos 服务正常 (http://localhost:8848/nacos)"
    else
        log_warn "⚠️  Nacos 服务可能还在启动中..."
    fi
}

# ----------------------------------------------------------
# 8. 打印结果
# ----------------------------------------------------------
print_result() {
    SERVER_IP=$(hostname -I | awk '{print $1}')

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}   🎉 HOJ 部署成功！${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "  🌐 访问地址:     http://${SERVER_IP}"
    echo -e "  👤 管理员账号:   root"
    echo -e "  🔑 管理员密码:   hoj123456"
    echo -e "  🔧 管理后台:     http://${SERVER_IP}/admin"
    echo -e "  ⚙️  Nacos 面板:   http://${SERVER_IP}:8848/nacos"
    echo ""
    echo -e "${YELLOW}  ⚠️  请立即登录后台修改管理员密码！${NC}"
    echo ""
    echo -e "  📝 更新代码:     bash scripts/update.sh"
    echo -e "  📊 查看日志:     docker compose logs -f [服务名]"
    echo -e "  🔄 重启服务:     docker compose restart [服务名]"
    echo ""
    echo -e "${GREEN}============================================${NC}"
}

# ----------------------------------------------------------
# 主流程
# ----------------------------------------------------------
main() {
    print_banner

    # 确保在项目根目录执行
    cd "$(dirname "$0")/.."

    check_env
    setup_system
    generate_secrets
    create_dirs
    build_and_start
    update_nacos_config
    health_check
    print_result
}

main "$@"
