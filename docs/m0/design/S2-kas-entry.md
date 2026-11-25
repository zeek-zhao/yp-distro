# YP-M0-DES-002 · S2 kas 入口与层锁定设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-002 |
| 版本 | v1.1 |
| 状态 | Approved（见 YP-M0-RV-002、YP-M0-CHG-009、YP-M0-ISS-015） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-25 |
| 覆盖需求 | B-01（kas 单一入口）、B-02（层版本锁定）、B-07（不依赖缓存服务器） |
| 关联问题 | F-01（缺 kas 入口）、F-06（kas 版本未锁）、ISS-015（简写路径解析） |
| 关联决策 | ADR-003（Ubuntu 24.04 基础）、ADR-002（孤立分支方案 A）；YP-M0-CHG-009（规范性命令统一） |

## 1. 目的与边界

建立 kas 单一入口，把发行版目标（distro/machine/target）、仓库版本、可覆盖变量集中到可解析的 YAML 树，使「同一份输入两次 dump 完全一致」成为可验收事实。边界：只做入口与版本锁定，不做首次构建（S5）、不做挂载逻辑（S4）、不做 BSP/业务功能。kas 独占，不引入 `bitbake-setup`。

## 2. 输入与事实依据

| 输入 | 值 | 来源 |
|---|---|---|
| kas 版本 | 5.5（configuration format version 23, earliest compatible 1） | 容器内 `kas --version` 实跑 |
| header version | 14（kas 5.5 接受的格式；与 main 参考一致） | main `kas/base.yml` + kas dump 兼容性 |
| Yocto 版本 | 6.0.4（wrynose） | main `kas/releases/wrynose.yml` tag `yocto-6.0.4` |
| 基础镜像 | Ubuntu 24.04 LTS | ADR-003 / Yocto 6.0 官方支持矩阵 |

### 2.1 仓库 commit 锁定（真实值，`git ls-remote` 实取）

| 仓库 | URL | ref | commit（解引用后） |
|---|---|---|---|
| openembedded-core | https://git.openembedded.org/openembedded-core | tag `yocto-6.0.4` | `0f03c732a0a2d0506b41b1abe60b3f368b2300dc` |
| bitbake | https://git.openembedded.org/bitbake | tag `yocto-6.0.4` | `51fd94a67fa17650a9ff623492005972bbc7d26f` |
| meta-yocto | https://git.yoctoproject.org/meta-yocto | tag `yocto-6.0.4` | `7c25b11156553145fa6b241a2d4f65d94438f804` |
| meta-openembedded | https://git.openembedded.org/meta-openembedded | branch `wrynose` | `c0fcd7cca3760ef24e087ac4a31b8f357cb204da` |

> 注：`git ls-remote <repo> refs/tags/yocto-6.0.4` 返回 annotated tag object（如 `eb8a3f9f`），必须用 `^{}` 解引用后的 commit（如 `0f03c732`）写入 `commit:`，否则 kas checkout 失败。meta-openembedded 无 `yocto-6.0.4` tag，其 `wrynose` 分支对应 6.0 系列，故以 branch + commit 锁定。

## 3. 设计

### 3.1 目录与分层

```
kas/
├── yp.yml                     # 顶层入口：include base + 默认 machine/edition
├── base.yml                   # 通用：header、repos（全 commit pin）、变量默认值
├── machines/qemux86-64.yml    # 唯一 machine，无 BSP 代码
└── editions/
    ├── dev.yml                # 开发：可调试、保留符号、不裁体积
    ├── prod.yml               # 生产：image 精简、只读根准备（后续里程碑）
    ├── dev-kernel.yml         # 内核/驱动开发：独立内核 recipe 覆盖点、menuconfig 片段挂点
    └── ci.yml                 # CI：最小构建、缓存命中优先
```

规范性入口组合写为 `kas/yp.yml:editions/<name>.yml`（kas 多配置语法），machine 由 `yp.yml` 默认 include，无需再叠加 machine 片段。

**路径解析规则（ISS-015 实测）**：kas 5.5 把 `:` 后的第二段按**调用时的 cwd** 解析，不按第一段配置文件所在目录解析。因此从仓库根调用时，`editions/<name>.yml` 必须在 cwd 可寻址；仓库根提供符号链接 `editions -> kas/editions` 作为映射。实测：

```text
$ kas --version                                        # kas 5.5
$ kas dump kas/yp.yml:editions/prod.yml                # 无符号链接：rc=2，All concatenated config files must belong to the same repository...
$ kas dump kas/yp.yml:kas/editions/prod.yml        # 长写法：rc=0（ISS-007 的历史证据写法）
$ ln -s kas/editions editions
$ kas dump kas/yp.yml:editions/prod.yml                # 有符号链接：rc=0，dump 49 行
```

历史 ISS-007/ISS-008/RV-005 中记录的长写法是当时执行的原命令，保持原样不改写；本设计自 CHG-009 起统一为简写。

### 3.2 repos 全部 commit pin

每个 repo 写 `url` + `commit:`，禁止裸 `branch:`。meta-openembedded 用 `branch: wrynose` + `commit:`（commit 优先定版）。这样 `kas dump` 不依赖远端分支移动，两次 dump 必然一致。`meta-yp-distro` 走本地相对路径 `repo: meta-yp-distro`（子模块/同仓路径），不用绝对路径。

### 3.3 变量归口（三处不重复）

可在 edition 覆盖的变量（`DISTRO_FEATURES`、`PACKAGE_CLASSES`、`INIT_MANAGER`、`DL_DIR`、`SSTATE_DIR`）只在 `base.yml` 定义默认值；edition 仅写差异项，用 `??=` 或显式赋值覆盖。`DL_DIR`/`SSTATE_DIR` 指向 `/work/downloads`、`/work/sstate`，与 S4 挂载点对齐（此处只写变量）。

### 3.4 缓存服务器排除（B-07）

`BB_HASHSERVE = "auto"`（本地 hashserv）；不写 `SSTATE_MIRRORS`、不写远程 hash-equivalence；产物中 grep 不得命中远程缓存地址。

### 3.5 edition 差异边界

| edition | 差异项 |
|---|---|
| dev | `DISTRO_FEATURES += "debug-tweaks"`、保留符号、`INHERIT -= "rm_work"` |
| prod | `IMAGE_FSTYPES` 精简、只读根准备（仅变量，实际只读在后续里程碑） |
| dev-kernel | 独立内核 recipe 覆盖点、`KERNEL_CONFIG_FRAGMENTS` 挂点（占位，无 BSP） |
| ci | 最小 target、`BB_NO_NETWORK` 可选、`DL_DIR/SSTATE_DIR` 命中优先 |

### 3.6 kas dump 稳定性理由

kas dump 把 include 展开、变量求值、repos 解析为确定性 YAML。输入全为静态文件 + 固定 commit，无时间戳/网络分支移动，故两次 dump 逐字节相同；用 `diff -u` 断言。

## 4. 失败模式与可检测信号

| 失败模式 | 可检测信号 |
|---|---|
| kas 版本漂移 | `kas --version` 非 5.5 → dump 格式可能变 |
| 用了 tag object SHA 而非 commit | `kas dump` checkout 报 bad object |
| 裸 branch 引用 | `grep -c 'commit:' kas/base.yml` < 4 |
| edition 覆盖重复变量 | dump 中变量出现多值、两次 dump 不一致 |
| 远程缓存服务器残留 | `grep -rn "SSTATE_MIRRORS\|BB_HASHSERVE" kas/ meta-yp-distro/` 命中远程地址 |

## 5. 验收命令（在 Docker 容器内执行，用户指定）

> 两条容器实操约束（ISS-007/ISS-015）：① kas 把 `:` 后的第二段路径按 cwd 解析，规范性写法是 `kas/yp.yml:editions/<name>.yml`，前提是 cwd 有 `editions` 符号链接（容器工作副本也要复制该链接）；② kas dump 会 clone repos 到 cwd，非 root 用户不能往只读挂载点写，故先把 `kas/`、`meta-yp-distro/` 与 `editions` 链接复制到可写副本 `/work/kas-run` 再跑。

```bash
# 持久容器 + 可写工作副本（repos 只 clone 一次，后续 dump 复用）
docker run -d --name kas-verify -v "$PWD":/mnt/repo:ro \
  ghcr.io/zeek-zhao/yp-builder:wrynose-m0 sleep 86400
docker exec kas-verify bash -c \
  'mkdir -p /work/kas-run && cp -r /mnt/repo/kas /mnt/repo/meta-yp-distro /work/kas-run/ && cp -a /mnt/repo/editions /work/kas-run/'

# 容器内验收
docker exec kas-verify bash -c 'kas --version'
docker exec kas-verify bash -c 'cd /work/kas-run && \
  kas dump kas/yp.yml:editions/prod.yml > /tmp/d1.yml && \
  kas dump kas/yp.yml:editions/prod.yml > /tmp/d2.yml && \
  diff -u /tmp/d1.yml /tmp/d2.yml && echo DUMP_STABLE'
for e in dev prod dev-kernel ci; do
  docker exec kas-verify bash -c \
    "cd /work/kas-run && kas dump kas/yp.yml:editions/$e.yml >/dev/null && echo EDITION_OK $e"
done
```

期望：`kas 5.5`、`DUMP_STABLE`、四个 `EDITION_OK`、`LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"` 单值、`grep -c commit:` ≥ 4。

## 6. 回滚

删除 `kas/` 目录、还原 `Dockerfile` 的 `pipx install kas`（去版本号），即可回到 S2 前状态；记录回滚到 DES-002 v1.0。本阶段不触碰镜像 tag 与缓存脚本，回滚无跨阶段影响。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-25 | 初稿：kas 入口、repos commit 锁、变量归口、dump 稳定性验收 | zeek.zhao |
| v1.1 | 2026-11-25 | CHG-009/ISS-015：规范性命令统一为 `kas/yp.yml:editions/<name>.yml`；写明 `:` 后按 cwd 解析 + 根级 `editions` 符号链接规则及实测输出 | zeek.zhao |
