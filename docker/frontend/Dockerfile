# ============================================================
# HOJ Frontend (Vue) - 从源码构建
# ============================================================
FROM node:14.21.3 AS builder

WORKDIR /build
COPY hoj-vue/package*.json ./
RUN npm install --registry=https://registry.npmmirror.com
COPY hoj-vue/ ./
RUN npm run build

# ============================================================
# Nginx 生产镜像
# ============================================================
FROM nginx:1.24-alpine

LABEL maintainer="tianyu9527"
LABEL description="HOJ Frontend (Nginx)"

# 移除默认配置
RUN rm /etc/nginx/conf.d/default.conf

# 复制自定义 nginx 配置
COPY docker/frontend/nginx.conf /etc/nginx/conf.d/hoj.conf

# 复制构建产物
COPY --from=builder /build/dist /usr/share/nginx/html

# 设置时区
ENV TZ=Asia/Shanghai
RUN apk add --no-cache tzdata \
    && cp /usr/share/zoneinfo/$TZ /etc/localtime \
    && echo $TZ > /etc/timezone

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
