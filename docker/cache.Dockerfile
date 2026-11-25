# yp-cache — 缓存卷基线布局镜像（DES-006 / DES-007 / DES-008）
# 仅提供 downloads/sstate 的目录布局与卷属主，供 --volumes-from 组合复用（无缓存服务器，约束 6）
# 【结论降级 · RV-010 F-02】本镜像是「仅布局基线」，不含真实缓存载荷，不得称为「预热缓存完成」。
#   真实缓存数据由 S5 构建产物经 pack.sh 打包、split.sh 切分后以分片镜像发布（ADR-005）；
#   基线镜像分发已验证（B-08），真实缓存载荷以 S5 产物为准。公共 Actions 可独立构建本基线。
FROM alpine:3.20

# 卷属主须与 builder 镜像的 jenkins UID/GID 一致，否则 --volumes-from 挂载时被 entrypoint 拒绝（ISS-006）
ARG CACHE_UID=1000
ARG CACHE_GID=1000

RUN mkdir -p /work/downloads /work/sstate /work/cache \
    && chown -R "${CACHE_UID}:${CACHE_GID}" /work/downloads /work/sstate

# 基线元数据：记录缓存格式与来源，sha256 由 pack.sh 对真实数据生成
COPY cache-meta.json /work/cache/cache-meta.json

VOLUME ["/work/downloads", "/work/sstate"]
CMD ["/bin/sh", "-c", "echo 'yp-cache: downloads & sstate data volume image'; ls -la /work"]
