SUMMARY = "YP full image —— 演示与开发"
DESCRIPTION = "base + demo 业务 + 调试工具。"

require recipes-core/images/core-image-minimal.bb
include yp-image.inc
include yp-image-runtime.inc

# 与 base 的差集：业务 + 调试。任何新包想进 full 而不进 base，加在这一行下面。
IMAGE_INSTALL += "wget python3 strace gdbserver"

# 业务参考实现。装真实包名而不是 "virtual/cpp-hello"：
# IMAGE_INSTALL 的虚拟名在 rootfs 阶段按 RPROVIDES 解析，而 RPROVIDES 不能带
# virtual/ 前缀（6.0 QA virtual-slash），3.1~5.0 也会因此报
# “Nothing RPROVIDES 'virtual/cpp-hello'”。虚拟名的用处只剩 bitbake virtual/cpp-hello。
IMAGE_INSTALL += "cpp-hello"

# CVE 检查的类由 distro（yp.conf）在全局 INHERIT 里加载，这里不就近 inherit：
# 只 inherit 到镜像上会让 cve-update-nvd2-native 被 SkipRecipe。

# ---- 演示层特性（#59）----
# full 是演示与开发层，允许 root 空密码登录：自动取证、串口 demo 都要它。
# 这条是「有意为之的降级」，已在 config/degraded.txt 登记；minimal / base 不开。
# 注意 6.0 把 debug-tweaks 拆成了具体项，所以这里写拆开后的两个名字。
IMAGE_FEATURES += "allow-empty-password allow-root-login"

# sshd 由 distro 的 YP_SSH 决定（见 yp-common.inc），默认 dropbear —— 那是
# core-image-minimal 通过 packagegroup-core-ssh-dropbear 已经装进来的。
# 这里硬装 openssh-sshd 会与 dropbear 直接冲突（rpm 报 package ... conflicts with）。

# 日志落盘（覆盖 systemd 主配置的 volatile），只在 full 层。
IMAGE_INSTALL += "yp-journald-persist"

# 服务模板示例：v0.6.0 的 HTTP 服务与 v0.4.0 的六构建系统都复用同一个 bbclass。
IMAGE_INSTALL += "yp-hello-svc"
