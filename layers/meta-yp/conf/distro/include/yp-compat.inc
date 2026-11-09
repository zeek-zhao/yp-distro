# Release-specific syntax differences belong only in this file.
# No release branches are currently required.
#
# dunfell (3.1): BitBake does not support colon overrides.
# kirkstone (4.0) and scarthgap (5.0): the shared assignment syntax works.
# wrynose (6.0): DISTRO_FEATURES_BACKFILL was removed and systemd became
# the nodistro default. We leave the poky DISTRO_FEATURES / IMAGE_FEATURES
# baseline and INIT_MANAGER untouched, so these changes need no workaround.
#
# Add any future required release-specific branches below.

# ---------------------------------------------------------------------------
# override 分隔符（C11：dunfell 与其它三版同等支持）
#
# 3.1 只认 `_`，4.0+ 只认 `:`，没有任何一种写法能同时生效。
# 碰到必须按包名/override 赋值的变量时，**两种分隔符各写一行**，
# 未命中的那一行在对方版本里只是个没人读的惰性变量：
#
#   FILES:${PN}-cus = "a"      # 4.0+ 生效
#   FILES_${PN}-cus = "a"      # 3.1 生效
#
# 已知使用点（改一处要同步改另一处）：
#   - layers/meta-yp/recipes-example/cpp-hello/cpp-hello-cus-pack_0.1.bb
#   - layers/meta-yp/conf/distro/yp.conf（PREFERRED_PROVIDER_virtual/cpp-hello）
#   - kas/variants/custom.yml（DEFAULTTUNE virtclass-multilib-lib32）
#
# 任务级追加（do_install:append / do_configure:prepend）**不受影响**：3.1 也认
# 任务级冒号语法。实测见 2026-11-01 的探针配方（3.1.33 / BitBake 1.46.0）：
# do_install 写 base、do_install:append 写 append，产物里两行都在，run.do_install
# 里 append 的函数体已并入。
#
# 所以任务级**只能写一份**。再补一份 do_install_append 会让同一任务执行两遍，
# 症状是 do_install 里出现重复调用、最后以 exit 127 收尾（"xxx: not found"）。
#
# 变量级与任务级不对称，别互相类推：
#   变量级 3.1 不认冒号 → 双写（未命中的那行是惰性变量）
#   任务级 3.1 认冒号   → 单写（写了下划线版就是 bug）
# ---------------------------------------------------------------------------
