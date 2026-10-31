# 把 u-boot 源码从 git clone 换成 release tarball。
# 动机：source.denx.de 的 git clone 在 215 出口只跑到 39~48 KiB/s（完整历史 114 万
# 对象，几小时起步），而 ftp.denx.de 官方 release tarball 能到 700~900 KB/s（32.5 MB，约 1 分钟）。
# 内容一致：都是 v2026.01 tag 的源码快照，CVE patch 仍由上游 .bb 的 SRC_URI 追加。
#
# 为什么 remove 里写死 v2026.01 而不是 ${PV}：
#   SRC_URI:remove 做的是「字面字符串删除」，不会展开变量。主 SRC_URI 里的 ${PV}
#   （来自上游 u-boot-common.inc）在合并时已被展开成 v2026.01，若这里仍写 ${PV}
#   会永远匹配不上 → tarball 与 git URL 粘连成一条坏 URL（上一版的坑）。
#   写死 v2026.01 正好对上展开后的字面量，精确删掉 git 项、保留 file:// 补丁。

# 精确删除展开后的 git URL（注意末尾无空格，是 SRC_URI 的一个完整 token）。
SRC_URI:remove = "git://source.denx.de/u-boot/u-boot.git;protocol=https;branch=master;tag=v2026.01"

# 追加官方 release tarball（prepend 末尾带空格，与保留的 file:// 补丁分隔）。
SRC_URI:prepend = "https://ftp.denx.de/pub/u-boot/u-boot-${PV}.tar.bz2 "

SRC_URI[sha256sum] = "b60d5865cefdbc75da8da4156c56c458e00de75a49b80c1a2e58a96e30ad0d54"

# tarball 解压目录是 u-boot-${PV}，而 git fetcher 默认 ${WORKDIR}/git。
S = "${WORKDIR}/u-boot-${PV}"
