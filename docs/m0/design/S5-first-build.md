# YP-M0-DES-005 · S5 首次构建与缓存命中设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-005 |
| 版本 | v1.0 |
| 状态 | Approved（见 YP-M0-RV-005） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-25 |
| 覆盖需求 | B-12（缓存指标）、B-13（离线构建）、B-01/B-05/B-06 的端到端闭环 |
| 关联设计 | DES-002（kas 入口、DL_DIR/SSTATE_DIR 指向挂载卷）、DES-004（两卷挂载与幂等）、DES-003（jenkins 容器） |
| 验收判据 | 判据 1（容器内一条命令出 prod 镜像） |

## 1. 目的与边界

- **目的**：用 S2 的 kas 入口与 S4 的挂载卷，在 builder 容器内真实执行两次 `kas build`，用**两次 wall time、产物路径、cooker 日志原始行**证明下载/缓存卷被复用，闭环判据 1 与 B-12/B-13。
- **不做的事**：不改 kas 配置与镜像 tag；不改 `DL_DIR`/`SSTATE_DIR` 变量（DES-002 已定）；不做镜像切分与发布（S6/S7，Stage E）；不做门禁脚本（S8）；不引入远程缓存服务器或 `bitbake-setup`。

## 2. 输入

| 输入 | 值 | 来源 |
|---|---|---|
| kas 入口 | `kas/yp.yml:kas/editions/ci.yml` | DES-002 §3.1；路径按 cwd 解析（ISS-007） |
| 构建目标 | `core-image-minimal`（base.yml 的 `target`） | DES-002 `kas/base.yml` |
| 机器 | `qemux86-64` | `kas/machines/qemux86-64.yml` |
| 下载/缓存卷 | 宿主 `/tmp/yp-dl`、`/tmp/yp-st` → 容器 `/work/downloads`、`/work/sstate` | Stage C 已初始化，卷内无下载/缓存载荷（仅 `.yp-volume` 标识与 `.probe` 探针） |
| 容器内工作副本 | `/work/build-run`（含 `kas/`、`meta-yp-distro/`） | ISS-007：kas clone repos 到 cwd，须用 jenkins 可写副本 |
| 构建容器 | `ghcr.io/zeek-zhao/yp-builder:wrynose-m0` | S3/S7 已验证资产；`user=jenkins uid=1000` |
| 日志位置 | `build/tmp/log/cooker/qemux86-64/console-latest.log` | bitbake 默认布局 |

## 3. 设计

### 3.1 两次构建流程

| 阶段 | build 目录 | downloads/sstate 卷 | 目的 | 采集 |
|---|---|---|---|---|
| 首次 | 清空 | 空（无载荷） | 冷构建，填充下载与 sstate | wall time、stdout 日志、产物路径与 `file` 输出 |
| 第二次 | 清空 | **保留**（不清、不重建） | 验证 sstate 命中与下载复用 | wall time、stdout 日志、cooker 日志原始复用行、`Fetching` 计数 |

关键点：两次都清 `build/`，只保留两个卷。若误清卷，第二次将退化为冷构建，命中率归零——这正是判据 3/4 要防的错配（RV-010 F-03）。

### 3.2 计时与日志

- 用 `date +%s` 取前后时间戳计算 wall time（秒），不依赖 `/usr/bin/time` 是否安装。
- 每次 `kas build` 的 stdout/stderr 用 `tee` 同时写屏与日志文件（`first.log`、`second.log`），保存原始输出，不做摘要替代。
- 两次结束后从第二次的 `console-latest.log` 提取原始行（见 §3.3），日志保留在挂载卷外的 `/work/measure-logs`，随容器销毁而消失；关键行回填 RV-005。

### 3.3 缓存指标统计（B-12）

统计口径（对首次与第二次日志分别计算，贴原始行，不只写百分比）：

| 指标 | 统计方式 | 说明 |
|---|---|---|
| `from sstate` 行 | `grep -c "from sstate" console-latest.log` | 交接指定模式；若为 0 仍如实写 0 |
| `Reusing` 行 | `grep -c "Reusing" console-latest.log` | 交接指定模式 |
| Sstate 摘要行 | `grep -E "Sstate summary|Tasks Summary" console-latest.log` | Yocto 6.0 实际输出的权威命中摘要，含 `Found … Missed …` 与 `didn't need to be rerun` |
| 执行任务数 | 从 `Tasks Summary: Attempted N tasks` 提取 N | 命中率分母 |
| 复用任务数 | 从 `of which M didn't need to be rerun` 提取 M | 命中率分子，M/N 即任务复用率 |
| `Fetching` 行 | `grep -c "Fetching" second.log` | B-13 离线证据：为 0 表示第二次未重新下载 |

> 若 `from sstate`/`Reusing` 计数为 0 但 `Tasks Summary` 显示大量 `didn't need to be rerun`，以摘要行作为缓存命中的直接证据，`from sstate` 仍记 0，不改写原始模式。

### 3.4 失败模式与可检测信号

| 失败模式 | 可检测信号 | 处理 |
|---|---|---|
| kas 路径写错（ISS-007） | `Configuration file not found` | 用 `kas/yp.yml:kas/editions/<n>.yml`（cwd 相对路径） |
| 工作副本只读导致 clone 失败 | `could not create work tree dir … Permission denied` | 复制到 jenkins 属主的 `/work/build-run` |
| 卷属主不符 | preflight `BAD_OWNER_EXIT=2` 或 entrypoint exit 1 | 先跑 `bootstrap.sh` 对齐属主 |
| 网络下载失败 | 首次日志含 `Fetching` 错误/`Network is unreachable` | 如实记 UNVERIFIED + 开 ISS，不虚报 |
| sstate 未命中 | 第二次 wall time 未下降、`Tasks Summary` 中 `didn't need to be rerun` 为 0 | 检查卷是否被清、变量是否指向容器本地路径 |
| 构建超时 | 命令超过沙箱时限 | 后台运行并记录真实耗时，不截断数据 |
| 产物路径不符预期 | `ls build/tmp/deploy/images/qemux86-64/` 为空 | 检查 target/machine 配置 |

### 3.5 实现载体

新增 `scripts/build/measure.sh`，容器内运行，串起两次构建、计时、统计与摘要输出。脚本不修改 kas 配置，不写死数字常量；目标机器/edition 由参数指定，默认 `ci`/`qemux86-64`。

## 4. 验收命令（用户指定：全部在 Docker 容器内执行）

```bash
# 宿主准备持久容器：只读挂载仓库，可写卷来自 Stage C
docker run -d --name kas-build -v "$PWD":/mnt/repo:ro \
  -v /tmp/yp-dl:/work/downloads -v /tmp/yp-st:/work/sstate \
  ghcr.io/zeek-zhao/yp-builder:wrynose-m0 sleep 86400
docker exec kas-build bash -c \
  'mkdir -p /work/build-run /work/measure-logs && cp -r /mnt/repo/kas /mnt/repo/meta-yp-distro /work/build-run/'

# 容器内执行两次构建与统计
docker exec kas-build bash -c 'cd /work/build-run && \
  bash /mnt/repo/scripts/build/measure.sh --logs /work/measure-logs'

# 容器内核对产物
docker exec kas-build bash -c \
  'ls -lh /work/build-run/build/tmp/deploy/images/qemux86-64/ && \
   file /work/build-run/build/tmp/deploy/images/qemux86-64/core-image-minimal-qemux86-64.rootfs.ext4'
```

期望：第二次 wall time 显著小于第一次；`Tasks Summary` 有 `didn't need to be rerun`；第二次 `Fetching` 计数为 0；产物存在且 `file` 可识别 ext4 镜像。

## 5. 回滚

- 删除 `scripts/build/measure.sh`；文档状态回退；已产生的构建产物与卷内容可保留（它们是证据，不影响仓库状态）。
- 本阶段不触碰镜像、kas 配置、缓存脚本与挂载脚本，回滚无跨阶段影响。

## 6. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-25 | 初稿：两次构建流程、命中率口径、离线证据、失败模式与验收命令 | zeek.zhao |
