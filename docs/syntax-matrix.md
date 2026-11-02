# BitBake syntax matrix

| Item | dunfell (3.1) | kirkstone (4.0) | scarthgap (5.0) | wrynose (6.0) | 来源 / 证据 |
|---|---|---|---|---|---|
| 变量 override（`VAR_append` / `VAR:append`） | `_append` / `_remove` | `:append` / `:remove` | `:append` / `:remove` | `:append` / `:remove` | `docs/kas.md`「冒号 override 在 dunfell 上的行为」；`layers/meta-yp/conf/distro/yp.conf` |
| 任务/函数 override（`do_x:append()`） | `:append()` 可用（与 `_append` 等价） | `:append()` | `:append()` | `:append()` | `f66f35b`：删掉全部 python 补丁后 `bitbake -c install -f yp-demo-python`，dunfell 生成的 `do_install` 里仍带 `yp_service_install_unit` 与 `yp_demo_python_install_script` |
| 源码解包目录（`file://`） | `${WORKDIR}` | `${WORKDIR}` | `${WORKDIR}` | `${UNPACKDIR}`（`${WORKDIR}/sources`） | `docs/kas.md`「6.0+ 禁止 `S = "${WORKDIR}"`」；`layers/meta-yp/classes/yp-service.bbclass` 注释 |
| `CONF_VERSION` | `1` | `2` | `2` | `2` | `docs/kas.md`「CONF_VERSION 各版本不同」；上游 `local.conf.sample` 版本差异 |
| 默认 init（poky 默认） | sysvinit | sysvinit | sysvinit | sysvinit | 待验证：需逐版核对上游 `meta-poky/conf/distro/poky.conf` |
| 默认 init（YP 实际） | systemd | systemd | systemd | systemd | `layers/meta-yp/conf/distro/yp.conf` 显式设置 `INIT_MANAGER = "systemd"` |
| Python 构建类 | `setuptools3` | `setuptools3` | `setuptools3` | `python_setuptools_build_meta` | `yp-demo-python` 在 5.0 用 `setuptools3` 真构建通过（#82 配方级验证，2026-11-03）；6.0 列见 `docs/plan/milestones.md` v0.4.0 |
| CVE 检查类 / 工具 | `cve-check` | `cve-check` | `cve-check` | `sbom-cve-check` | `docs/cve.md` §3；`docs/compliance.md` §2 |
| SPDX 输出格式版本 | SPDX 2.2 | SPDX 2.2 | SPDX 2.2 | SPDX 3.0.1 | `docs/compliance.md` §2；各版本 `docs/qa/<release>/compliance` 记录 |
| systemd adds `usrmerge` | No | No | Yes | Yes | `docs/distro-features.md`；本表原有记录 |
| systemd suppresses sysvinit backfill | `_append` | `:append` | `:append` | No backfill line | `docs/distro-features.md`；`layers/meta-yp/conf/distro/yp-common.inc` |
| `systemd_system_unitdir` | `/lib/systemd/system` | `/lib/systemd/system` | `/usr/lib/systemd/system` | `/usr/lib/systemd/system` | 逐版 rpm 元数据（`yp-collectd` 包内路径：dunfell/kirkstone=`/lib`、scarthgap=`/usr/lib`，2026-11-03 #82 取证）；wrynose 由真机 `systemctl show -p FragmentPath` 确认。与第 14 行 usrmerge 一致：3.1/4.0 无 usrmerge |
| `YP_SRC_DIR` 兜底 | `UNPACKDIR` 不存在，取 `${WORKDIR}` | `UNPACKDIR` 不存在，取 `${WORKDIR}` | `UNPACKDIR` 不存在，取 `${WORKDIR}` | 取 `${UNPACKDIR}`（`${WORKDIR}/sources`） | `layers/meta-yp/classes/yp-service.bbclass`；`docs/kas.md`「6.0+ 禁止 `S = "${WORKDIR}"`」 |
| `cargo.bbclass` 位置 | 不存在 | `meta/classes/` | `meta/classes-recipe/` | `meta/classes-recipe/` | `f66f35b`：dunfell 上 `inherit cargo` 直接 ParseError；`yp-demo-rust` 用 `BBMASK` + `YP_DEMO_RUST` 摘包 |
| cargo `--config <file>` | n/a | 不支持（1.59，需 `-Z unstable-options`） | 支持（≥1.63） | 支持（≥1.63） | `f66f35b`：改写到 `${B}/.cargo/config.toml`，`directory` 换成绝对路径 |
| Go 工具链版本 | 1.14 | 1.16 | 1.20+ | 1.22+ | `f66f35b`：`signal.NotifyContext`（1.16+）在 3.1 上 `undefined`；`go.mod` 的 `go` 指令须 ≥1.14 才自动启用 `vendor/` |

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

新增配方时，先按目标版本查「源码解包目录」和两行 override；这几处写错会导致源码路径
找不到、override 不生效或同一个任务被执行两次，构建因此失败。

**override 的两行别混为一谈**：变量不认冒号（3.1），函数认冒号（四版都认）。
把后者当前者处理，症状很隐蔽 —— 不报语法错，只是 `do_install` 里那段逻辑跑了两遍，
最后表现为 `xxx: not found` 的 exit 127 或重复安装。

**3.1 的 Rust 缺口只有两条出路**：`BBMASK` 屏蔽配方 + 镜像层摘包（**两件都要做**——
只屏蔽配方会因为镜像仍写死包名变成 `Nothing RPROVIDES`，只摘包则单配方构建仍撞
ParseError），或者不写 Rust 配方。没有第三条：`cargo.bbclass` 在 3.1 里根本不存在。
