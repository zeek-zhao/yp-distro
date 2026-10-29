SUMMARY = "YP reference image"
require recipes-core/images/core-image-minimal.bb

# custom variant 的额外工具链包（需求 §4.2）
IMAGE_INSTALL += "curl wget python3 procps tar strace gdbserver"

# 装真实包名而不是 "virtual/cpp-hello"：
# IMAGE_INSTALL 的虚拟名是在 rootfs 阶段按 RPROVIDES 解析的，而 RPROVIDES 不能带
# virtual/ 前缀（6.0 QA virtual-slash），3.1~5.0 也会因此在 do_rootfs 报
# “Nothing RPROVIDES 'virtual/cpp-hello'”。虚拟名的用处只剩 bitbake virtual/cpp-hello。
IMAGE_INSTALL += "cpp-hello"

# CVE 检查的类由 distro（yp.conf）在全局 INHERIT 里加载，这里不就近 inherit：
# 只 inherit 到镜像上会让 cve-update-nvd2-native 被 SkipRecipe。
