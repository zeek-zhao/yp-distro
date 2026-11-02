SUMMARY = "YP full image —— 演示与开发"
DESCRIPTION = "base + demo 业务 + 调试工具。"

require recipes-core/images/core-image-minimal.bb
include yp-image.inc
include yp-image-runtime.inc

# 与 base 的差集：业务 + 调试。任何新包想进 full 而不进 base，加在这一行下面。
IMAGE_INSTALL += "wget python3 strace gdbserver systemd-analyze"

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
#
# 6.0 把 debug-tweaks 拆成了三个正交项，名字相近但作用不同，选错会静默失效：
#   empty-root-password    阻止 zap_empty_root_password 把 root:: 改成 root:*:，
#                          即「保留空密码」—— serial-getty 空密码登录靠的是它；
#   allow-empty-password   只改 sshd/dropbear 的 PermitEmptyPasswords，对串口无效；
#   allow-root-login       允许 root 登录（本来就没禁），单独写等于没写。
# 所以串口空密码登录只要 empty-root-password 一个就够，不能拿 allow-empty-password
# 顶替（那是 #59 首版踩过的坑：写了它串口仍弹 Password: 且拒空密码）。
IMAGE_FEATURES += "empty-root-password"

# sshd 由 distro 的 YP_SSH 决定（见 yp-common.inc），默认 dropbear —— 那是
# core-image-minimal 通过 packagegroup-core-ssh-dropbear 已经装进来的。
# 这里硬装 openssh-sshd 会与 dropbear 直接冲突（rpm 报 package ... conflicts with）。

# 日志落盘（覆盖 systemd 主配置的 volatile），只在 full 层。
IMAGE_INSTALL += "yp-journald-persist"

# 服务模板示例：v0.6.0 的 HTTP 服务与 v0.4.0 的六构建系统都复用同一个 bbclass。
IMAGE_INSTALL += "yp-hello-svc"

# ---- v0.4.0 六构建系统 + v0.6.0 两个服务（#64~#70 / #76 / #77）----
# 装真包名而不是虚拟名，理由同上：IMAGE_INSTALL 的虚拟名在 rootfs 阶段按
# RPROVIDES 解析，而 RPROVIDES 不能带 virtual/ 前缀。
# 只在 full 层出现：base 是「装上工具之后慢多少」的对照面，业务包不进 base，
# 否则 minimal ⊂ base ⊂ full 的体积单调断言就失去意义（12_distro.bats）。
# yp-statusd / yp-collectd 是要真起机验证的两个：前者提供 /status JSON，
# 后者每 60s 写 journald。两者的自启由 yp-service.bbclass 的
# SYSTEMD_AUTO_ENABLE 负责，rootfs 阶段用 systemctl --root 完成。
IMAGE_INSTALL += "yp-demo-make yp-demo-cmake yp-demo-autotools yp-demo-meson yp-demo-python ${YP_DEMO_RUST} yp-demo-go yp-statusd yp-collectd"

# ---- dunfell(3.1) 的 Rust 缺口 ----
# 3.1 的 poky 里没有 cargo.bbclass：4.0 才进 meta/classes，5.0 挪到
# meta/classes-recipe。dunfell 上解析这条配方直接 ParseError
# （Could not inherit file classes/cargo.bbclass），custom variant 连解析阶段
# 都过不去。摘包必须在镜像层做而不是 BBMASK 配方 —— 镜像里还写死包名的话，
# 屏蔽配方会变成 "Nothing RPROVIDES 'yp-demo-rust'"。
YP_DEMO_RUST ??= "yp-demo-rust"
python __anonymous() {
    if "dunfell" in (d.getVar("LAYERSERIES_CORENAMES") or "").split():
        d.setVar("YP_DEMO_RUST", "")
}
