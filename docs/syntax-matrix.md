# BitBake syntax matrix

| Item | dunfell (3.1) | kirkstone (4.0) | scarthgap (5.0) | wrynose (6.0) | 来源 / 证据 |
|---|---|---|---|---|---|
| Override operator | `_append` / `_remove` | `:append` / `:remove` | `:append` / `:remove` | `:append` / `:remove` | `docs/kas.md`「冒号 override 在 dunfell 上静默失效」；`layers/meta-yp/conf/distro/yp.conf` |
| 源码解包目录（`file://`） | `${WORKDIR}` | `${WORKDIR}` | `${WORKDIR}` | `${UNPACKDIR}`（`${WORKDIR}/sources`） | `docs/kas.md`「6.0+ 禁止 `S = "${WORKDIR}"`」；`layers/meta-yp/classes/yp-service.bbclass` 注释 |
| `CONF_VERSION` | `1` | `2` | `2` | `2` | `docs/kas.md`「CONF_VERSION 各版本不同」；上游 `local.conf.sample` 版本差异 |
| 默认 init（poky 默认） | sysvinit | sysvinit | sysvinit | sysvinit | 待验证：需逐版核对上游 `meta-poky/conf/distro/poky.conf` |
| 默认 init（YP 实际） | systemd | systemd | systemd | systemd | `layers/meta-yp/conf/distro/yp.conf` 显式设置 `INIT_MANAGER = "systemd"` |
| Python 构建类 | `setuptools3` | `setuptools3` | `setuptools3` | `python_setuptools_build_meta` | 待验证：需逐版核对上游 `setuptools3` 与 `python_setuptools_build_meta` classes |
| CVE 检查类 / 工具 | `cve-check` | `cve-check` | `cve-check` | `sbom-cve-check` | `docs/cve.md` §3；`docs/compliance.md` §2 |
| SPDX 输出格式版本 | SPDX 2.2 | SPDX 2.2 | SPDX 2.2 | SPDX 3.0.1 | `docs/compliance.md` §2；各版本 `docs/qa/<release>/compliance` 记录 |
| systemd adds `usrmerge` | No | No | Yes | Yes | `docs/distro-features.md`；本表原有记录 |
| systemd suppresses sysvinit backfill | `_append` | `:append` | `:append` | No backfill line | `docs/distro-features.md`；`layers/meta-yp/conf/distro/yp-common.inc` |
| `systemd_system_unitdir` | 待验证 | 待验证 | 待验证 | 待验证 | 待验证：本仓库没有逐版解析该变量取值的构建记录 |
| `YP_SRC_DIR` 兜底 | `UNPACKDIR` 不存在，取 `${WORKDIR}` | `UNPACKDIR` 不存在，取 `${WORKDIR}` | `UNPACKDIR` 不存在，取 `${WORKDIR}` | 取 `${UNPACKDIR}`（`${WORKDIR}/sources`） | `layers/meta-yp/classes/yp-service.bbclass`；`docs/kas.md`「6.0+ 禁止 `S = "${WORKDIR}"`」 |

Do not force `usrmerge` on 3.1 or 4.0 to make this matrix uniform. On 3.1 it
requires `CONVERSION_CMD` and substantial QA adjustments, while its benefit is
limited to merged-/usr path layout. `yp-common.inc` uses `:remove` on 4.0+ and
sets the equivalent `_remove` operation from an anonymous configuration block
only on 3.1. This conditional is necessary because BitBake 6.x fatally rejects
even an inactive legacy `_remove` assignment during parsing.

Other `init-manager-systemd.inc` details, including provider, initscript,
device-manager and `ROOT_HOME` differences, are recorded in
[`distro-features.md`](distro-features.md).

## 怎么用这张表

新增配方时，先按目标版本查「源码解包目录」和「Override operator」两行；
这两处写错会导致源码路径找不到或 override 不生效，构建因此失败。
