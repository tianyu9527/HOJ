# ============================================================
# HOJ JudgeServer - 从源码构建（含完整编译器环境）
# ============================================================
FROM maven:3.8-jdk-8 AS builder

WORKDIR /build
COPY hoj-springboot/ ./
RUN mvn clean package -pl api,JudgeServer -am -DskipTests -q

# ============================================================
# 判题服务器：需要安装多种语言编译器/运行时
# ============================================================
FROM ubuntu:20.04

LABEL maintainer="tianyu9527"
LABEL description="HOJ Judge Server with compilers"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 安装基础工具和所有编译器/运行时
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 基础
    ca-certificates curl wget \
    # C/C++
    gcc g++ \
    # Java
    openjdk-8-jdk-headless \
    # Python
    python3 python3-pip python2 \
    # Go
    golang-go \
    # Mono (C#)
    mono-complete \
    # PHP
    php-cli \
    # Node.js
    nodejs npm \
    # Ruby
    ruby \
    # Rust
    rustc \
    # 其他工具
    make libc6-dev locales \
    && rm -rf /var/lib/apt/lists/*

# 设置 locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# 安装 JRE（Java 运行时）
RUN apt-get update && apt-get install -y --no-install-recommends \
    openjdk-8-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录和日志目录
RUN mkdir -p /judge/log/judgeserver /w

WORKDIR /judge

# 复制沙箱二进制文件
COPY sandbox/Sandbox-amd64-v1.8.0 /judge/sandbox
RUN chmod +x /judge/sandbox

# 复制构建产物
COPY --from=builder /build/JudgeServer/target/hoj-judgeServer-4.6.jar ./hoj-judgeServer.jar

# JVM 参数
ENV JAVA_OPTS="-Xms256m -Xmx1g -XX:+UseG1GC"

EXPOSE 8088

ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -jar hoj-judgeServer.jar"]
