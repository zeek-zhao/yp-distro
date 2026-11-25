# 换机 Runbook · 从零到构建成功

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-RUNBOOK-001 |
| 版本 | v1.0 |
| 状态 | Approved（文档交付；实机验证边界见 §7） |
| 适用范围 | 在一台新机器上复现 M0：取回 S5 缓存 → 构建 prod 镜像 → 验证缓存命中 |
| 事实源 | `docs/m0/plan.md`（进度）、`docs/m0/acceptance.md`（验收）、`CHG-012`/`ISS-019`/`ISS-020`（全量缓存）、`RV-005`（构建时长与命中率） |

> 宿主机只装 Docker。**宿主机没有 kas**，所有 `kas` 命令都在 builder 容器内执行。

## 1. 机器要求

| 项 | 要求 | 依据 / 说明 |
|---|---|---|
| 操作系统 | Ubuntu 24.04 | Yocto 6.0 官方支持矩阵（ADR-003） |
| Docker | ≥ 24 | `docker version` 与 daemon 均可用；本流程不依赖 compose |
| CPU | ≥ 8 核（建议） | RV-005 实测在 4 核有效配额下可完成，但首次构建约 2h51m |
| 内存 | ≥ 16 GB（建议 32 GB） | RV-005 实测 8 GB cgroup 限额需下调并发（ISS-011/CHG-005）；16 GB 为舒适下限 |
| 磁盘空闲 | ≥ 200 GB（建议） | 预算见下表 |
| 出网 | ghcr.io、git.openembedded.org、git.yoctoproject.org、api.github.com | 镜像、层源码、release 资产；无远程 sstate/hashserv |

磁盘预算（均为量级值，以 `df -h` 实测为准）：

| 占用项 | 量级 |
|---|---|
| 缓存数据（`downloads/` + `sstate/` 解包后） | 11.15 GB |
| 重组 tar（`cache-full.tar`） | 11.15 GB |
| release 分片（如保留不清理） | 11.15 GB |
| build tmp（两次构建，`build/`） | 视目标，预留 ≥ 50 GB |
| 容器镜像层 | 约 0.6 GB |
| **建议总空闲** | **≥ 200 GB** |

## 2. 产物与分发事实（不要重新推断）

| 对象 | 事实 |
|---|---|
| builder 镜像 | `ghcr.io/zeek-zhao/yp-builder:wrynose-m0`，匿名可拉，kas 5.5，用户 jenkins/1000 |
| release tag | `m0-s5-payload-full` |
| release 资产 | `cache-full.part-00` … `cache-full.part-06` 各 `1,572,864,000 B`；`cache-full.part-07` 为 `143,339,520 B`；`cache-full.sha256` 为 `81 B` |
| release 重组校验 | `cache-full.sha256` 内容：`1c8126d4b1c57d5dc5a4f772617cd74dacbeab475d79e8ce2ee49bbcea1be624  cache-full.tar` |
| 全量切片（GHCR） | 源 tar `11,153,397,760 B`、`sha256=a8870b50f2b262d90978a17c6bcdf28794659e1dfd7f500f24ddf097dad4febc`；2 片：`8,589,934,592 B` + `2,563,463,168 B` |
| 全量分片 tag / digest | `ghcr.io/zeek-zhao/yp-cache:wrynose-m0-full-part-00` → `sha256:f1404012d98fb7956619aa4c89b293a435a322b67fcc57227b1c15baef974390`；`-part-01` → `sha256:899af6fa46c9223223d978fa110dabb5215f161e1d1a4b6d8352e6d1e2271d36`；均匿名可拉 |
| 切片 manifest | 由 `split.sh` 产出 `manifest.json`（序号、字节数、sha256、`source_sha256`），消费端必须用它调 `merge.sh`；持久副本提交在 `manifests/full-slices-manifest.json`，release 资产清单在 `manifests/cache-full.release.json` |

> **两个 tar 不是同一个对象**：release 8 分片重组的 tar 以 `1c8126d4…` 为 sha256（分片合计 `11,153,387,520 B`）；GHCR 全量切片所用的源 tar 以 `a8870b50…` 为 sha256（`11,153,397,760 B`，见 ISS-019）。两者相差 10,240 B，不可混用哈希或大小校验。release 走 §3 步骤 5；GHCR 分片走 `--mode ghcr`，两者都解包出同构的两个卷。

## 3. 从零到构建成功（完整命令序列）

在空目录开始；每条命令后给出期望输出。命令以仓库根目录为当前目录。

### 步骤 1 · clone

```bash
git clone --branch feat-m0-kas-bootstrap https://github.com/zeek-zhao/yp-distro.git
cd yp-distro
git status --short
```

期望：分支为 `feat-m0-kas-bootstrap`；`git status --short` 无输出（干净工作区）。

### 步骤 2 · 环境只读检查

```bash
bash scripts/verify-env.sh --downloads ./downloads --sstate ./sstate --min-disk-gb 200
```

期望：docker / 磁盘 / 内存 / CPU / uid / `editions` 链接 / `threshold.conf` / 镜像 registry 探测 / 目标卷空间 / 网络逐项打印 `PASS` 或 `WARN`，退出码 `0`；内存 <16 GB 或 UID≠1000 时为 `WARN`、退出码 `2`；任一 `FAIL` 为退出码 `1`，先按 §5 处理再继续。

### 步骤 3 · 拉 builder 镜像

```bash
docker pull ghcr.io/zeek-zhao/yp-builder:wrynose-m0
docker run --rm ghcr.io/zeek-zhao/yp-builder:wrynose-m0 sh -c 'whoami; id -u; kas --version'
```

期望：拉取显示 `Downloaded newer image` 或 `Image is up to date`；三段输出为 `jenkins`、`1000`、`kas 5.5`（或版本兼容输出）。

### 步骤 4 · 初始化挂载卷

```bash
bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate
```

期望：`INIT`（首次）或 `KEEP`（已有）`downloads/sstate` 标记；`OWNER_OK` 或 `CHOWN` 行；`PREFLIGHT=0`，退出码 `0`。UID 不一致时脚本会给出两条修复路径，按 §5.2 处理。

### 步骤 5 · 取回全量缓存（release 模式）

```bash
bash scripts/cache/fetch-cache.sh --mode release \
  --dest-parent . \
  --work ./cache-work \
  --release-tag m0-s5-payload-full
```

期望：逐片 `ASSET_OK index=NN bytes=...`；`REASSEMBLE_OK`；`SHA256_OK sha256=1c8126d4b1c57d5dc5a4f772617cd74dacbeab475d79e8ce2ee49bbcea1be624`；两步解包后 `UNPACK_OK`、`STRUCT_OK downloads=<文件数> sstate=<文件数>`；退出码 `0`。

无网或小磁盘环境可先做不下载的自检：

```bash
bash scripts/cache/fetch-cache.sh --mode release --dry-run \
  --dest-parent . --work ./cache-work --release-tag m0-s5-payload-full
```

期望：只打印 8 个资产 URL、大小与校验期望值，不产生下载文件，退出码 `0`。

### 步骤 6 · 卷预检

```bash
bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate
```

期望：`OK role=downloads dir=... owner=1000 avail_bytes=...` 与 `OK role=sstate ...`；脚本自身无输出 `PREFLIGHT=0` 时以退出码 `0` 表示可继续。

### 步骤 7 · 容器内构建（可执行写法）

README 的三步保留为最简示意；builder 镜像不含仓库的 `kas/` 配置，因此必须把仓库挂载进容器并复制出可写工作副本。用命名容器保留 `build/` 与日志，供步骤 8/9 核对：

```bash
docker run -d --name yp-m0-build \
  -v "$PWD:/mnt/repo:ro" \
  -v "$PWD/downloads:/work/downloads" \
  -v "$PWD/sstate:/work/sstate" \
  ghcr.io/zeek-zhao/yp-builder:wrynose-m0 sleep infinity

docker exec yp-m0-build bash -c \
  'mkdir -p /work/build-run && tar -C /mnt/repo --exclude=./.git --exclude=./downloads --exclude=./sstate -cf - . | tar -C /work/build-run -xf -'

docker exec -w /work/build-run yp-m0-build \
  kas build kas/yp.yml:editions/prod.yml
```

期望：容器状态 `Up`；复制命令无输出、退出码 `0`；构建末尾 `Tasks Summary: Attempted ... and all succeeded`，退出码 `0`。

### 步骤 8 · 产物核对

```bash
docker exec yp-m0-build bash -c \
  'ls -lh /work/build-run/build/tmp/deploy/images/qemux86-64/'
docker exec yp-m0-build bash -c \
  'file /work/build-run/build/tmp/deploy/images/qemux86-64/core-image-minimal-qemux86-64.rootfs.ext4'
```

期望：`core-image-minimal-qemux86-64.rootfs-*.ext4` 约 42M，软链 `core-image-minimal-qemux86-64.rootfs.ext4` 就绪；`file` 输出 `Linux rev 1.0 ext4 filesystem data ...`。`IMAGE_FSTYPES = "ext4"` 由 prod edition 生效（ci edition 产出 `.ext4.zst`，不要混用证据）。

### 步骤 9 · 二次构建命中率检查

```bash
docker exec -w /work/build-run yp-m0-build bash -c \
  'rm -rf build && kas build kas/yp.yml:editions/prod.yml'

docker exec yp-m0-build bash -c \
  'grep -c "from sstate" /work/build-run/build/tmp/log/cooker/qemux86-64/console-latest.log || true'
docker exec yp-m0-build bash -c \
  'grep -E "Sstate summary|Tasks Summary" /work/build-run/build/tmp/log/cooker/qemux86-64/console-latest.log | tail -n 4'
```

期望：二次构建退出码 `0`、耗时约 200–300s；`grep -c "from sstate"` 在本 Yocto 版本**通常为 0**（RV-005 实测 `from_sstate_lines=0`，日志用 `Sstate summary` + `Tasks Summary` 表达复用，不伪造模式行）；真正的命中率证据是 `Sstate summary` 的高 `match%` 与 `Tasks Summary` 中大量 `didn't need to be rerun`（RV-005 实测 `2049/2054`、`3829/4083`，`fetching_lines=0`）。

## 4. 缓存恢复：两步解包

`pack.sh` 产出的**外层 tar 顶层是两个内层归档**，不是 `downloads/`、`sstate/`。实测 `tar -tf` 输出：

```text
./
./downloads.tar
./sstate.tar
```

内层归档各自以卷名为顶层：

```text
$ tar -tf downloads.tar | head
downloads/
downloads/<file> ...

$ tar -tf sstate.tar | head
sstate/
sstate/<file> ...
```

因此恢复必须两步（`--dest-parent` 的父目录下应得到 `downloads/` 与 `sstate/`）：

```bash
# 第 1 步：外层 tar → 两个内层 tar
tar -xf cache-full.tar -C "$DEST_PARENT"

# 第 2 步：内层 tar → 两个卷目录（各自解到同一父目录）
tar -xf "$DEST_PARENT/downloads.tar" -C "$DEST_PARENT"
tar -xf "$DEST_PARENT/sstate.tar"    -C "$DEST_PARENT"

# 结构断言
[ -d "$DEST_PARENT/downloads" ] && [ -d "$DEST_PARENT/sstate" ] && echo STRUCT_OK
```

`fetch-cache.sh` 在临时目录完成校验后才执行解包并 `mv` 到目标，失败不留半成品；已有非空目标且未带 `--force` 时拒绝覆盖。

## 5. 故障判定与处理

### 5.1 磁盘 / 内存不足

- **判定**：`verify-env.sh` 打印 `FAIL DISK` → 退出码 `1`；`preflight.sh` 打印 `LOW_SPACE` → 退出码 `3`；`free -h` 明显低于 16 GB 或构建日志出现 `Killed` / cgroup `oom_kill`。
- **处理**：清理旧 `cache-work/`、`build/`、无用镜像（`docker image prune`）；扩容到 ≥200 GB；内存不足时不要提高并发——仓库已把 `BB_NUMBER_THREADS=4`、`PARALLEL_MAKE="-j 2"` 固定为 8 GB 可跑的值（CHG-005）。
- **不要**：直接删 `downloads/` 或 `sstate/`，那会让二次构建退回冷构建。

### 5.2 UID 不一致（新机用户 UID≠1000）

- **判定**：`verify-env.sh` 打印 `WARN UID` → 退出码 `2`；`bootstrap.sh` / `preflight.sh` 打印 `ERROR[2] UID_MISMATCH` → 退出码 `2`；容器内 `entrypoint.sh` 报 `属主 UID=… 与 jenkins UID=1000 不一致` 并退出。
- **根因**：无条件 `chown` 到 1000 需要 sudo，chown 完当前用户反而不可写，流程自锁。
- **脚本契约（T4）**：`bootstrap.sh` 与 `preflight.sh` 均支持 `--uid <n>`、`--gid <n>`，**默认取当前用户** `id -u`/`id -g`；`JENKINS_UID/JENKINS_GID`（1000）保留为镜像默认与文档默认。当前用户为 1000 时行为与 M0 验收命令完全一致；目标 UID/GID 与当前非 root 用户不一致时脚本 exit 2，明确给出下面两条路径，禁止静默 chown；以 root（sudo）执行时视为 sudo 路径，允许显式 `--uid/--gid`，因为 root 仍可写。
- **两条路径（二选一）**：
  1. 用 sudo 执行，卷属主保持镜像默认 1000：
     ```bash
     sudo bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate --uid 1000 --gid 1000
     ```
  2. 按当前用户重建镜像，保持卷可写：
     ```bash
     docker build --build-arg JENKINS_UID=$(id -u) --build-arg JENKINS_GID=$(id -g) -t yp-builder:local docker/
     export YP_BUILDER_IMAGE=yp-builder:local
     bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate
     ```
- **preflight 附加检查**：目录属主 == 目标 UID 且当前用户可写；任一不符即 exit 2 并给出具体 `sudo chown -R` 或重建镜像命令。验证过的三种情形：非 root 目标不一致 → exit 2 且打印两条路径；root + `--uid 1000` → `WARN SUDO_PATH` 后 chown 成功（属主 1000、root 仍可写）；当前用户 1000 且不带参数 → `OWNER_OK` 与 M0 一致。

### 5.3 GHCR 拉取 401

- **判定**：`docker pull` 返回 `unauthorized: authentication required` 或 registry API 返回 401。
- **处理**：先确认匿名可拉的是 `ghcr.io/zeek-zhao/yp-builder:wrynose-m0` 与两个全量分片 tag；执行 `docker logout ghcr.io` 清除过期凭据；检查代理/网络到 `ghcr.io`；确认 tag 拼写（完整 tag 见 §2）。
- **不要**：把 CI 的 `GHCR_PAT` 拿到本地用；该 secret 只在 workflow 中使用，不入库、不写脚本。本地只读环境变量 `GH_TOKEN` 用于公开仓库的匿名/限流兜底下载。

### 5.4 sstate 命中率低

- **判定**：二次构建 `Sstate summary` 的 `match%` 远低于预期，或 `Tasks Summary` 中 `didn't need to be rerun` 接近 0。
- **处理**：确认两个卷确实挂到 `/work/downloads` 与 `/work/sstate`（`ls` 可见 `.yp-volume` 标识）；确认缓存按 §4 两步解包且 `STRUCT_OK`；确认二次构建前只清 `build/` 未清 `sstate/`；若首次构建后未取缓存，按 §3 步骤 5 重新取回。
- **注意**：ci edition 与 prod edition 的命中率不同（RV-005：ci 二次 99%，prod 冷启 55%）；不要用 ci 的数字判 prod 的失败。

## 6. 构建时长预期（避免误以为卡死）

| 场景 | 实测时长 | 来源 |
|---|---|---|
| 首次冷构建（ci edition） | 7096s（约 1h58m） | RV-005 |
| 首次冷构建（prod edition） | 10253s（约 2h51m） | RV-005 |
| 二次构建（命中缓存） | 214s，量级 **200–300s** | RV-005 |

以上是在 4 核有效配额 / 8 GB cgroup 下的实测值；更宽的配额通常更快。首次构建长时间无输出属正常，先看 `cooker` 日志是否仍在增长，不要中途 `docker rm -f`。

## 7. 验证边界

- 本 runbook 是文档交付：§3 中 `verify-env.sh`（T2）与 `fetch-cache.sh`（T3）的脚本尚未实现时，命令与输出 token 是**目标契约**，不是已实跑结果；完成后按本节命令逐条验证。
- release 资产名称与大小经 GitHub API 匿名查询核对；`cache-full.sha256` 内容经资产下载核对；外层 tar 的两层结构经本地 `pack.sh` 实跑核对（`./`、`./downloads.tar`、`./sstate.tar`）。
- **全量 11 GB 路径标 `UNVERIFIED`**：按本轮约束不在本机下载全量包；样本 release `m0-s5-payload-sample`（18 MB，sha256 `ca3063ab1d164b4c7556896507912a5a23bd4ccab341b924d57615704028cf1d`）的下载→校验→两步解包自测在 T3 完成。全量分片 digest 沿用 CHG-012/ISS-020 的 GHCR registry API 独立核验记录，本轮未重验。
- 构建时长与命中率引用 RV-005 的真实输出，本轮未重新构建。
