# yp-cache — 下载/缓存预热数据镜像（DES-006 / DES-007）
# 携带 downloads 与 sstate 缓存数据，供构建容器挂载复用（无缓存服务器，约束 6）
# 说明：真实缓存由 S5 构建产物经 pack.sh 打包；本镜像提供可复现的基线结构，
#       公共 Actions 可独立构建（不依赖入库二进制），数据内容可用 pack 产物覆盖。
FROM alpine:3.20

RUN mkdir -p /work/downloads /work/sstate /work/cache

# 基线元数据：记录缓存格式与来源，sha256 由 pack.sh 对真实数据生成
COPY cache-meta.json /work/cache/cache-meta.json

VOLUME ["/work/downloads", "/work/sstate"]
CMD ["/bin/sh", "-c", "echo 'yp-cache: downloads & sstate data volume image'; ls -la /work"]
