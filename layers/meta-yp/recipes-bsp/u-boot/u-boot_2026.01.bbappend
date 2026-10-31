# 把 u-boot 源码从 git clone 换成 release tarball。
# 动机：source.denx.de 的 git clone 在 215 出口只跑到 39~48 KiB/s（完整历史 114 万
# 对象，几小时起步），而 GitHub tag tarball 能到 750+ KB/s（41 MB，约 1 分钟）。
# 内容一致：都是 v2026.01 tag 的源码快照，CVE patch 仍由上游 .bb 的 SRC_URI 追加。

# 用 tarball 取代 git 项，保留上游 .bb 里的 file:// 补丁（CVE-2026-46728 等）。
# 精确 remove 掉 git 那一项（含其参数），避免误删 file:// patch。
SRC_URI:remove = "git://source.denx.de/u-boot/u-boot.git;protocol=https;branch=master;tag=v${PV}"

# 追加 tarball（GitHub tag 快照，解压目录 u-boot-${PV}）。
SRC_URI:prepend = "https://github.com/u-boot/u-boot/archive/refs/tags/v${PV}.tar.gz;downloadfilename=u-boot-${PV}.tar.gz"

SRC_URI[sha256sum] = "03bb43c58d2343ee48dd191e0f181f0108425b179d84519add3a977071c3f654"

# tarball 解压目录是 u-boot-${PV}，而 git fetcher 默认 ${WORKDIR}/git。
S = "${WORKDIR}/u-boot-${PV}"
