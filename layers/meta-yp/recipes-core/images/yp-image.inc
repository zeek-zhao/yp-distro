# 三层镜像的公共部分。
#
# 包含关系必须保持 minimal ⊂ base ⊂ full：体积单调递增既是 12_distro.bats 的断言，
# 也是「启动时间三点基线」成立的前提（裸底多快 / 有工具之后慢多少 / 有服务再慢多少）。
#
# IMAGE_FSTYPES 与 IMAGE_ROOTFS_SIZE 刻意不在这里写死：三层共用同一个 distro 的
# 默认值，天然一致；写死会连带影响 3.1（dunfell 没有 ext4.zst）的历史产物名，
# 报告链路按 .rootfs.<fstype> 匹配，改了就要连报告一起改。

# 品牌文件 /etc/yp-release。issue / motd / hostname 在 base-files 的 bbappend 里，
# 那三个路径原本属于 base-files，另起包安装会在 do_rootfs 撞 file conflict。
IMAGE_INSTALL:append = " yp-branding"

# 预留 rootfs 余量：默认值在 full 层会触发 ext4 自动扩容，扩容后的体积随构建
# 环境漂移，体积对比就失去意义。
IMAGE_ROOTFS_EXTRA_SPACE ?= "16384"
