# YP-M0 关键变量索引

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-VAR-001 |
| 版本 | v1.4 |
| 状态 | Approved（见 YP-M0-RV-009、T7 变量空间核对；M0.1.2/CHG-022 并发按 CPU+cgroup 内存分级，ISS-040 函数移 .bbclass） |
| 目的 | 记录关键变量的默认值、唯一定义处、可覆盖层与手改检测命令，使「手改配置可发现」（判据 8）闭环 |
| 检测脚本 | `scripts/check-vars.sh`（统一断言，本表所有变量的期望值来源） |

## 使用说明

- **可覆盖层**记号：`base < edition < 命令行`（后者覆盖前者）；`只读` 表示不得手改（门禁检出）。
- **手改检测命令**均可直接执行；`scripts/check-vars.sh` 对本表所有受保护变量做统一断言，任一漂移即 `DRIFT` + exit 1。
- 判据 8 的"故意手改→被检出"样例见 `docs/m0/reviews/RV-009.md` §验收输出。

## 变量表

| # | 变量 | 默认值 | 定义文件 | 可覆盖层 | 手改检测命令 |
|---|---|---|---|---|---|
| 1 | `MACHINE` | `qemux86-64` | `kas/machines/qemux86-64.yml` | edition < 命令行 | `grep -q '^machine: qemux86-64$' kas/machines/qemux86-64.yml` |
| 2 | `DISTRO` | `yp-wrynose` | `meta-yp-distro/conf/distro/yp-wrynose.conf` | 只读 | `grep -q '^DISTRO = "yp-wrynose"$' meta-yp-distro/conf/distro/yp-wrynose.conf` |
| 3 | `DISTRO_VERSION` | `0.1.0` | `meta-yp-distro/conf/distro/yp-wrynose.conf` | 只读 | `grep -q '^DISTRO_VERSION = "0.1.0"$' meta-yp-distro/conf/distro/yp-wrynose.conf` |
| 4 | `DL_DIR` | `/work/downloads` | `kas/base.yml` | 只读（S4 挂载契约） | `grep -q 'DL_DIR = "/work/downloads"' kas/base.yml` |
| 5 | `SSTATE_DIR` | `/work/sstate` | `kas/base.yml` | 只读（S4 挂载契约） | `grep -q 'SSTATE_DIR = "/work/sstate"' kas/base.yml` |
| 6 | `SSTATE_MIRRORS` | 未设置（禁止远程） | 全局禁令（AGENTS §3.6） | 只读 | `! grep -rq 'SSTATE_MIRRORS[[:space:]]*=' kas/ meta-yp-distro/ scripts/` |
| 7 | `BB_HASHSERVE` | `auto`（本地） | `kas/base.yml` | 只读 | `grep -q 'BB_HASHSERVE = "auto"' kas/base.yml` |
| 8 | `BB_HASHSERVE_DB_DIR` | `${SSTATE_DIR}` | `kas/base.yml` | 只读 | `grep -q 'BB_HASHSERVE_DB_DIR = "\${SSTATE_DIR}"' kas/base.yml`；T7 变量空间核对：`kas shell -c 'bitbake -e' kas/yp.yml:editions/ci.yml` → `BB_HASHSERVE_DB_DIR="/work/sstate"`、`BB_HASHSERVE="unix:///.../build/hashserve.sock"`（本地 socket）、`BB_SERVER_TIMEOUT="300"`，确认是真实 bitbake 变量，不改行 |
| 9 | `BB_SERVER_TIMEOUT` | `300` | `kas/base.yml` | 只读 | `grep -q 'BB_SERVER_TIMEOUT = "300"' kas/base.yml` |
| 10 | `BB_NUMBER_THREADS` | `${@yp_build_threads(d)}`（CPU + cgroup 内存分级：32c/≥120GB→32、16c/≥32GB→min(16,cpu)、8c/≥16GB→min(8,cpu)、其他→min(4,cpu)，至少 1） | `kas/base.yml` | 只读（bitbake 动态分级，CHG-022/ISS-038；函数经 `INHERIT += "yp-concurrency"` 从 `.bbclass` 引入；`oe.utils.cpu_count()` 取 CPU，回退 `os.cpu_count()`；env 变量不再作控制通道 ISS-039） | `grep -Fq 'BB_NUMBER_THREADS = "${@yp_build_threads(d)}"' kas/base.yml` |
| 11 | `PARALLEL_MAKE` | `-j ${@max(1, int(d.getVar('BB_NUMBER_THREADS')) // 2)}`（32→-j16、4→-j2，至少 -j1） | `kas/base.yml` | 只读（由 `BB_NUMBER_THREADS` 派生，不小于 1） | `grep -Fq "PARALLEL_MAKE = \"-j \${@max(1, int(d.getVar('BB_NUMBER_THREADS')) // 2)}\"" kas/base.yml` |
| 29 | `yp_mem_bytes` / `yp_build_threads` / `INHERIT` | bitbake python 函数：读 cgroup v2 `/sys/fs/cgroup/memory.max` → v1 `/sys/fs/cgroup/memory/memory.limit_in_bytes` → 回退 `/proc/meminfo` `MemTotal`；`YP_MEM_BYTES` 语义即此返回值。函数定义必须在 `.bbclass`（local.conf 的 ConfHandler 不支持多行 `def`，ISS-040），`kas/base.yml` 用 `INHERIT += "yp-concurrency"` 引入 | `meta-yp-distro/classes/yp-concurrency.bbclass`（函数）+ `kas/base.yml`（INHERIT/赋值） | 只读（分级唯一实现；`scripts/build/threads.sh` 仅为 daemon 级诊断输出 `SUGGEST_*`，非控制通道 CHG-022） | `grep -Fq 'def yp_build_threads(d):' meta-yp-distro/classes/yp-concurrency.bbclass` |
| 12 | `PACKAGE_CLASSES` | `package_rpm`（`??=`） | `kas/base.yml` | base < edition | `grep -q 'PACKAGE_CLASSES ??= "package_rpm"' kas/base.yml` |
| 13 | `DISTRO_FEATURES` | 空（`??=`） | `kas/base.yml` | base < edition（dev append debug-tweaks；ci remove 图形） | `grep -q 'DISTRO_FEATURES ??= ""' kas/base.yml` |
| 14 | `INIT_MANAGER` | `systemd`（`??=`） | `kas/base.yml` | base < edition | `grep -q 'INIT_MANAGER ??= "systemd"' kas/base.yml` |
| 15 | `CONF_VERSION` | `2` | `kas/base.yml` | 只读 | `grep -q 'CONF_VERSION = "2"' kas/base.yml` |
| 16 | `IMAGE_FSTYPES` | `ext4`（prod edition） | `kas/editions/prod.yml` | edition（prod 专属） | `grep -q 'IMAGE_FSTYPES = "ext4"' kas/editions/prod.yml` |
| 17 | `INHERIT`（rm_work） | `+= "rm_work"`（prod/ci） | `kas/editions/prod.yml`、`kas/editions/ci.yml` | edition（dev 用 `:remove`） | `grep -q 'INHERIT += "rm_work"' kas/editions/ci.yml` |
| 18 | `BB_NO_NETWORK` | `0`（`??=`，ci） | `kas/editions/ci.yml` | edition | `grep -q 'BB_NO_NETWORK ??= "0"' kas/editions/ci.yml` |
| 19 | `DEBUG_FLAGS` | `-g`（dev edition） | `kas/editions/dev.yml` | edition（dev 专属） | `grep -q 'DEBUG_FLAGS = "-g"' kas/editions/dev.yml` |
| 20 | `KERNEL_CONFIG_FRAGMENTS` | 空（`??=`，dev-kernel） | `kas/editions/dev-kernel.yml` | edition（内核挂点） | `grep -q 'KERNEL_CONFIG_FRAGMENTS ??= ""' kas/editions/dev-kernel.yml` |
| 21 | `LAYERSERIES_COMPAT_meta-yp-distro` | `wrynose`（单值） | `meta-yp-distro/conf/layer.conf` | 只读 | `grep -q 'LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"' meta-yp-distro/conf/layer.conf` |
| 22 | `LAYERDEPENDS_meta-yp-distro` | `core yocto` | `meta-yp-distro/conf/layer.conf` | 只读（按 BBFILE_COLLECTIONS，ISS-009） | `grep -q 'LAYERDEPENDS_meta-yp-distro = "core yocto"' meta-yp-distro/conf/layer.conf` |
| 23 | `SLICE_MAX_BYTES` | `8589934592`（8 GiB） | `scripts/cache/threshold.conf` | 只读（唯一源，约束 8） | `grep -q '^SLICE_MAX_BYTES=8589934592$' scripts/cache/threshold.conf` |
| 24 | `UPLOAD_TIMEOUT_SEC` | `480`（8 分钟） | `scripts/cache/threshold.conf` | 只读（唯一源） | `grep -q '^UPLOAD_TIMEOUT_SEC=480$' scripts/cache/threshold.conf` |
| 25 | `JENKINS_UID` | `1000` | `scripts/cache/threshold.conf` | 只读（与 Dockerfile ARG 对齐） | `grep -q '^JENKINS_UID=1000$' scripts/cache/threshold.conf` |
| 26 | `MIN_FREE_BYTES` | `10737418240`（10 GiB） | `scripts/cache/threshold.conf` | 只读（preflight 阈值） | `grep -q '^MIN_FREE_BYTES=10737418240$' scripts/cache/threshold.conf` |
| 27 | `MACHINE`（measure.sh 默认） | `qemux86-64` | `scripts/build/measure.sh` | 命令行 `--machine` | `grep -q '^MACHINE="qemux86-64"$' scripts/build/measure.sh` |
| 28 | `EDITION`（measure.sh 默认） | `ci` | `scripts/build/measure.sh` | 命令行 `--edition` | `grep -q '^EDITION="ci"$' scripts/build/measure.sh` |

## 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-25 | 初稿：28 个关键变量四要素索引（判据 8） | zeek.zhao |
| v1.1 | 2026-11-25 | T7：用 `kas shell` + `bitbake -e` 确认 `BB_HASHSERVE_DB_DIR` 是真实变量（值 `/work/sstate`），不删不改；记录命令与输出 | zeek.zhao |
| v1.2 | 2026-11-26 | CHG-021：`BB_NUMBER_THREADS`/`PARALLEL_MAKE` 改 `oe.utils.cpu_count()` 动态分级（32c→32/-j16、4c→4/-j2），替代写死 4/-j2；env 注入因 kas 隔离 datastore 不生效（ISS-037）；手改检测断言新串 | zeek.zhao |
| v1.3 | 2026-11-27 | CHG-022/ISS-038：`BB_NUMBER_THREADS` 改 `yp_build_threads(d)`（CPU + cgroup v2/v1 内存分级，回退 /proc/meminfo），`PARALLEL_MAKE` 从前者派生至少 -j1；新增 #29 `yp_mem_bytes`/`yp_build_threads`；`threads.sh` 仅 daemon 级 `SUGGEST_*` 诊断、去 export（ISS-039）；负向断言检出 env 控制通道残留 | zeek.zhao |
| v1.4 | 2026-11-27 | ISS-040：分级函数从 `kas/base.yml` 移到 `meta-yp-distro/classes/yp-concurrency.bbclass`（bitbake ConfHandler 不支持 local.conf 多行 `def`，实测构建 ParseError），base.yml 用 `INHERIT += "yp-concurrency"` 引入；#29/check-vars/G6 断言目标改 bbclass | zeek.zhao |
