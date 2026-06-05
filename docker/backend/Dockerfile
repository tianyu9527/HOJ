# ============================================================
# HOJ Backend (DataBackup) - 从源码构建
# ============================================================
FROM maven:3.8-eclipse-temurin-8 AS builder

WORKDIR /build
COPY docker/maven-settings.xml /root/.m2/settings.xml
COPY hoj-springboot/ ./
RUN mvn clean package -pl api,DataBackup -am -DskipTests -B

FROM eclipse-temurin:8-jre-jammy

LABEL maintainer="tianyu9527"
LABEL description="HOJ Backend Service (DataBackup)"

# 设置时区
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 创建日志目录
RUN mkdir -p /hoj/log/backend

WORKDIR /hoj

COPY --from=builder /build/DataBackup/target/hoj-backend-4.6.jar ./hoj-backend.jar

# JVM 参数
ENV JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError"

EXPOSE 6688

ENTRYPOINT ["sh", "-c", "java ${JAVA_OPTS} -jar hoj-backend.jar"]
