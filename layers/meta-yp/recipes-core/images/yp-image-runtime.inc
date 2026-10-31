# base 与 full 共享的「日常能用」清单。单独成文件是为了让 full 直接复用，
# 而不是把 4 个包名抄两遍 —— 抄了两份，改一处忘另一处，两层的差集就说不清了。
#
#   curl       手工搬运与接口排查
#   tar        busybox tar 缺 --numeric-owner 等，做归档不够用
#   procps     ps / top / free —— systemd 主体镜像也不带
#   util-linux mount / lsblk / login 等，systemd 生态默认期望它们存在
#
# 不放 logrotate：日志上限交给 journald 自己管（见 #59）。引入 logrotate 还得
# 额外养一个 cron/timer，而且它处理不了 journal 的二进制文件。
IMAGE_INSTALL += "curl tar procps util-linux"
