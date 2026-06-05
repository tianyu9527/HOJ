#!/bin/bash
# ============================================================
# 修复 Nacos 配置中的密码
# 使用方法: bash scripts/fix-nacos-pwd.sh
# ============================================================

set -e

cd "$(dirname "$0")/.."

if [ ! -f .env ]; then
    echo "错误: .env 文件不存在，请先创建"
    exit 1
fi

source .env

echo "=== 修复 Nacos 中的 hoj-prod.yml 配置 ==="
echo ""

# 更新 hoj-prod.yml 中的密码
docker exec hoj-mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" nacos -e "
    UPDATE config_info
    SET content = REGEXP_REPLACE(content, 'password: hoj123456', 'password: ${MYSQL_ROOT_PASSWORD}')
    WHERE data_id = 'hoj-prod.yml';
" 2>/dev/null && echo "✅ 数据库密码已更新" || echo "❌ 更新失败"

docker exec hoj-mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" nacos -e "
    UPDATE config_info
    SET content = REGEXP_REPLACE(content, 'secret: hoj-secret-init', 'secret: ${JWT_TOKEN_SECRET}')
    WHERE data_id = 'hoj-prod.yml';
" 2>/dev/null && echo "✅ JWT Secret 已更新" || echo "❌ 更新失败"

docker exec hoj-mysql mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" nacos -e "
    UPDATE config_info
    SET content = REGEXP_REPLACE(content, 'token: hoj-judge-token-init', 'token: ${JUDGE_TOKEN}')
    WHERE data_id = 'hoj-prod.yml';
" 2>/dev/null && echo "✅ Judge Token 已更新" || echo "❌ 更新失败"

echo ""
echo "重启业务服务..."
docker compose restart hoj-backend hoj-judgeserver

echo ""
echo "=== 完成 ==="
