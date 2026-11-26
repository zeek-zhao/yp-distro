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
| release 全量归档布局 | **direct**：顶层为 `yp-dl/`、`yp-st/`（空目录）、`downloads/`、`sstate/`，无 `downloads.tar` / `sstate.tar`；HTTP Range 读 `part-00` 前 4 KB 与 RV-014 全量实跑 `STRUCT_OK mode=direct` 均证实（CHG-017/ISS-029） |
| 本地打包 / GHCR 源 tar 布局 | `pack.sh` 本地产出已实测为 **two-stage**（顶层 `./`、`./downloads.tar`、`./sstate.tar`）；GHCR 两片分片的源 tar 是另一对象（`a8870b50…`），**布局 `UNVERIFIED`**（本轮未拉取验证）——不要与 release 的 direct 混为一谈（CHG-017/CHG-018） |
| 全量分发口径 | release 8 分片归档 + GHCR 两片分片（两种取法见 §3 步骤 4）；**不发布单一大镜像** `yp-cache:wrynose-m0-full`（该 tag 从未产出；CHG-013 §7 方案 A，CHG-012 v1.2） |
| 切片 manifest | 由 `split.sh` 产出 `manifest.json`（序号、字节数、sha256、`source_sha256`），消费端必须用它调 `merge.sh`；持久副本提交在 `manifests/full-slices-manifest.json`，release 资产清单在 `manifests/cache-full.release.json`。两 manifest 的 `layout` 仅描述各自 tar 内部布局；`requires_reassembly` 单独描述“下载后需合并分片”，重组判断读后者（CHG-017/ISS-030） |
| 元数据来源 | `docker/cache-meta.json` 的 `provenance` 段（edition/machine/kas commit/载荷哈希/文件数），静态来自 `docker/cache-provenance.json`；`CHG-013` |

> **两个 tar 不是同一个对象**：release 8 分片重组的 tar 以 `1c8126d4…` 为 sha256（分片合计 `11,153,387,520 B`）；GHCR 全量切片所用的源 tar 以 `a8870b50…` 为 sha256（`11,153,397,760 B`，见 ISS-019）。两者相差 10,240 B，不可混用哈希或大小校验。release 走 §3 步骤 4；GHCR 分片走 `--mode ghcr`，两者都解包出同构的两个卷。

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

> **路径 B 可跳过本节**：UID≠1000 且选择「本地重建镜像」路径时，构建容器用 §5.2 的 `yp-builder:local`（`docker build --build-arg JENKINS_UID=$(id -u) ...`），不使用 GHCR 的 `wrynose-m0`。上面的 GHCR pull 可省略，或仅作对照（确认 jenkins/1000 基线）。路径 A 则按本节正常拉取 GHCR 镜像。

### 步骤 4 · 取回全量缓存（release 模式）

**顺序要点（CHG-017）**：新机器先 fetch、再 bootstrap、再 preflight。此时目标卷尚不存在，`fetch` 不需要 `--force`。UID≠1000 的 PATH A/B 决策见 §5.2，放在 bootstrap 之前决定即可，**fetch 不依赖镜像 UID**。正常路径不得使用 `--force`（它会删除整个目标目录，破坏性不可恢复）；只有“目标已有确认可丢弃的真实文件”才用它。若因旧顺序先 bootstrap 留下了仅含 `.yp-volume` 的卷，`fetch` 也会无损放行并保留 marker（无需 `--force`）。

```bash
bash scripts/cache/fetch-cache.sh --mode release \
  --dest-parent . \
  --work ./cache-work \
  --release-tag m0-s5-payload-full
```

期望：`MODE_INFO ... layout=direct reassemble=1`；逐片 `ASSET_OK name=cache-full.part-NN bytes=...`；`REASSEMBLE_OK`；`SHA256_OK sha256=1c8126d4b1c57d5dc5a4f772617cd74dacbeab475d79e8ce2ee49bbcea1be624`；**单层解包**直接得到 `downloads/` 与 `sstate/`，打印 `STRUCT_OK mode=direct downloads=<文件数> sstate=<文件数>`、`UNPACK_OK`；root 执行会打印 `OWNER_HINT`。退出码 `0`。

无网或小磁盘环境可先做不下载的自检：

```bash
bash scripts/cache/fetch-cache.sh --mode release --dry-run \
  --dest-parent . --work ./cache-work --release-tag m0-s5-payload-full
```

期望：只打印 8 个资产 URL、大小与校验期望值（`MODE_INFO ... layout=direct reassemble=1`、`EXPECTED_ARCHIVE ... bytes=11153387520`），不产生下载文件，退出码 `0`。

### 步骤 5 · 初始化挂载卷（归一属主）

脚本默认目标 UID/GID 是镜像用户 1000（来自 `threshold.conf`），**不是当前用户**。UID≠1000 时必须显式指定目标，按 §0/§5.2 已选路径二选一：

**路径 A（sudo，卷保持 1000，当前 UID≠1000）**

```bash
sudo bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate --uid 1000 --gid 1000
```

**路径 B（本地重建镜像，卷保持当前 UID）**

```bash
bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate \
  --uid "$(id -u)" --gid "$(id -g)"
```

当前 UID 恰为 1000 时可直接用默认（等价于路径 A 的 `--uid 1000 --gid 1000`）。

期望：`KEEP`（fetch 已建卷）`downloads/sstate` 标记；`OWNER_OK` 或 `CHOWN -> <目标UID>:<目标GID>` 行；把 root 解包带出的非目标属主归一；脚本末尾 `PREFLIGHT=0`，退出码 `0`。非 root 且目标 UID 与当前不一致而**未显式**给 `--uid/--gid` 时，脚本 exit 2 并打印 `UID_MISMATCH` 与两条路径——不要把它当成脚本故障，按上面选路径重跑。

### 步骤 6 · 卷预检

与步骤 5 同一路径，**必须显式带与 bootstrap 一致的目标 UID/GID**（裸 `preflight` 在 UID≠1000 上会直接 exit 2）：

**路径 A**

```bash
sudo bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate --uid 1000 --gid 1000
```

**路径 B**

```bash
bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate \
  --uid "$(id -u)" --gid "$(id -g)"
```

期望：`OK role=downloads dir=... owner=<目标UID> avail_bytes=...` 与 `OK role=sstate ...`，退出码 `0`。UID 不一致时脚本 exit 2（`UID_MISMATCH`），按 §5.2 处理，不要删缓存。

### 步骤 7 · 容器内构建（可执行写法）

README 的三步保留为最简示意；builder 镜像不含仓库的 `kas/` 配置，因此必须把仓库挂载进容器并复制出可写工作副本。用命名容器保留 `build/` 与日志，供步骤 8/9 核对：

```bash
IMAGE="${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}"
docker run -d --name yp-m0-build \
  -v "$PWD:/mnt/repo:ro" \
  -v "$PWD/downloads:/work/downloads" \
  -v "$PWD/sstate:/work/sstate" \
  "$IMAGE" sleep infinity

docker exec yp-m0-build bash -c \
  'mkdir -p /work/build-run && tar -C /mnt/repo --exclude=./.git --exclude=./downloads --exclude=./sstate -cf - . | tar -C /work/build-run -xf -'

docker exec -w /work/build-run yp-m0-build \
  kas build kas/yp.yml:editions/prod.yml
```

期望：容器状态 `Up`；复制命令无输出、退出码 `0`；构建末尾 `Tasks Summary: Attempted ... and all succeeded`，退出码 `0`。

> **镜像与卷属主必须同源**：路径 A 用默认 GHCR 镜像（`jenkins/1000`）配 1000 卷；**路径 B 必须设 `export YP_BUILDER_IMAGE=yp-builder:local`，让 `"$IMAGE"` 解析为本地重建的当前 UID 镜像**。GHCR 的 `wrynose-m0`（1000）在路径 B **不用于构建**——卷是当前 UID（如 1234）配上 1000 容器会被 entrypoint 拒绝。§3 步骤 3 的 GHCR pull 在路径 B 可跳过或仅作对照。

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

## 4. 缓存恢复：direct 单层解包

**release 全量归档是 direct 布局**（CHG-017/ISS-029）：顶层直接是 `yp-dl/`、`yp-st/`（空目录）、`downloads/`、`sstate/`，**没有** `downloads.tar` / `sstate.tar` 内层归档。`tar -tf cache-full.tar` 的前几项：

```text
yp-dl/
downloads/.yp-volume
downloads/...
sstate/...
```

因此恢复只需**单层解包**（`--dest-parent` 的父目录下直接得到 `downloads/` 与 `sstate/`）：

```bash
DEST_PARENT="${DEST_PARENT:-.}"   # 解包目标父目录；默认当前目录
# 单层解包：外层 tar 直接给出两个卷目录
tar -xf cache-full.tar -C "$DEST_PARENT"

# 结构断言
[ -d "$DEST_PARENT/downloads" ] && [ -d "$DEST_PARENT/sstate" ] && echo STRUCT_OK
```

> 历史背景：`downloads.tar`/`sstate.tar` 的“两步解包”**只适用于 `pack.sh` 本地产出（已实测 two-stage）**，**不是** release 归档，也不是 GHCR 源 tar。GHCR 源 tar（`a8870b50…`）布局 **UNVERIFIED**（本轮未拉取验证，见 §2、RV-015/CHG-018）。

`fetch-cache.sh` 在临时目录完成校验后才单层解包并 `mv` 到目标，失败不留半成品；`unpack_archive` 仍保留对 direct/two-stage 两种实际布局的探测作为最后防线。目标不存在、空目录、或仅含 `.yp-volume` 视为可写并保留 marker（无需 `--force`）；含其他任何条目则拒绝覆盖并提示 `--force`（破坏性，删除整个目标目录）。root 执行时打印 `OWNER_HINT`，随后按步骤 5 bootstrap 归一属主。

## 5. 故障判定与处理

### 5.1 磁盘 / 内存不足

- **判定**：`verify-env.sh` 打印 `FAIL DISK` → 退出码 `1`；`preflight.sh` 打印 `LOW_SPACE` → 退出码 `3`；`free -h` 明显低于 16 GB 或构建日志出现 `Killed` / cgroup `oom_kill`。
- **处理**：清理旧 `cache-work/`、`build/`、无用镜像（`docker image prune`）；扩容到 ≥200 GB；内存不足时不要提高并发——仓库已把 `BB_NUMBER_THREADS=4`、`PARALLEL_MAKE="-j 2"` 固定为 8 GB 可跑的值（CHG-005）。
- **不要**：直接删 `downloads/` 或 `sstate/`，那会让二次构建退回冷构建。

### 5.2 UID 不一致（新机用户 UID≠1000）

- **判定**：`verify-env.sh` 打印 `WARN UID` → 退出码 `2`；`bootstrap.sh` / `preflight.sh` 打印 `ERROR[2] UID_MISMATCH` → 退出码 `2`；容器内 `entrypoint.sh` 报 `属主 UID=… 与 jenkins UID=1000 不一致` 并退出。
- **根因**：无条件 `chown` 到 1000 需要 sudo，chown 完当前用户反而不可写，流程自锁。
- **脚本契约（T4，CHG-014 修订）**：`bootstrap.sh` 与 `preflight.sh` 均支持 `--uid <n>`、`--gid <n>`，**默认取镜像用户** `JENKINS_UID/JENKINS_GID`（1000，来自唯一源 `threshold.conf`），与容器 `jenkins` 用户对齐；仍可显式 `--uid/--gid` 覆盖。当前用户为 1000 时行为与 M0 验收命令完全一致；目标 UID/GID 与当前非 root 用户不一致时脚本 exit 2，明确给出下面两条路径，禁止静默 chown；以 root（sudo）执行时视为 sudo 路径，允许 chown（root 仍可写）。旧版“默认取当前用户”契约已由 ISS-022/CHG-014 修订：非 1000 UID 宿主不带参数会把卷建在错误的当前 UID 上，导致容器入口拒绝启动。
- **两条路径（二选一）**：
  1. **路径 A** — 用 sudo 执行，卷属主保持镜像默认 1000；bootstrap 与 preflight 都显式 `--uid 1000 --gid 1000`：
     ```bash
     sudo bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate --uid 1000 --gid 1000
     sudo bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate --uid 1000 --gid 1000
     ```
     构建用默认 GHCR 镜像（§3 步骤 7 的 `"$IMAGE"` 解析为 `ghcr.io/.../wrynose-m0`）。
  2. **路径 B** — 按当前用户重建镜像，卷保持当前 UID 可写；**bootstrap 与 preflight 仍必须显式 `--uid "$(id -u)" --gid "$(id -g)"`**：
     ```bash
     docker build --build-arg JENKINS_UID=$(id -u) --build-arg JENKINS_GID=$(id -g) -t yp-builder:local docker/
     export YP_BUILDER_IMAGE=yp-builder:local
     bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate \
       --uid "$(id -u)" --gid "$(id -g)"
     bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate \
       --uid "$(id -u)" --gid "$(id -g)"
     ```
     **为什么不能只靠 `--build-arg`**：脚本的默认目标来自 `threshold.conf` 的 1000，不会读取镜像的 `JENKINS_UID`。重建镜像只解决「容器内 UID = 当前 UID」，脚本后续调用若不显式 `--uid` 仍以 1000 为目标、exit 2。构建时 `"$IMAGE"` 解析为 `yp-builder:local`（同源）；GHCR 的 `wrynose-m0` 在路径 B 不用于构建。
- **preflight 附加检查**：目录属主 == 目标 UID 且当前用户可写；任一不符即 exit 2 并给出具体 `sudo chown -R` 或重建镜像命令。验证过的三种情形：非 root 目标不一致 → exit 2 且打印两条路径；root + `--uid 1000` → `WARN SUDO_PATH` 后 chown 成功（属主 1000、root 仍可写）；当前用户 1000 且不带参数 → `OWNER_OK` 与 M0 一致。

### 5.3 GHCR 拉取 401

- **判定**：`docker pull` 返回 `unauthorized: authentication required` 或 registry API 返回 401。
- **处理**：先确认匿名可拉的是 `ghcr.io/zeek-zhao/yp-builder:wrynose-m0` 与两个全量分片 tag；执行 `docker logout ghcr.io` 清除过期凭据；检查代理/网络到 `ghcr.io`；确认 tag 拼写（完整 tag 见 §2）。
- **不要**：把 CI 的 `GHCR_PAT` 拿到本地用；该 secret 只在 workflow 中使用，不入库、不写脚本。本地只读环境变量 `GH_TOKEN` 用于公开仓库的匿名/限流兜底下载。

### 5.4 sstate 命中率低

- **判定**：二次构建 `Sstate summary` 的 `match%` 远低于预期，或 `Tasks Summary` 中 `didn't need to be rerun` 接近 0。
- **处理**：确认两个卷确实挂到 `/work/downloads` 与 `/work/sstate`（`ls` 可见 `.yp-volume` 标识）；确认缓存按 §4 单层解包且 `STRUCT_OK mode=direct`；确认二次构建前只清 `build/` 未清 `sstate/`；若首次构建后未取缓存，按 §3 步骤 4 重新取回。
- **注意**：ci edition 与 prod edition 的命中率不同（RV-005：ci 二次 99%，prod 冷启 55%）；不要用 ci 的数字判 prod 的失败。

## 6. 构建时长预期（避免误以为卡死）

| 场景 | 实测时长 | 来源 |
|---|---|---|
| 首次冷构建（ci edition） | 7096s（约 1h58m） | RV-005 |
| 首次冷构建（prod edition） | 10253s（约 2h51m） | RV-005 |
| 二次构建（命中缓存） | 214s，量级 **200–300s** | RV-005 |

以上是在 4 核有效配额 / 8 GB cgroup 下的实测值；更宽的配额通常更快。首次构建长时间无输出属正常，先看 `cooker` 日志是否仍在增长，不要中途 `docker rm -f`。

## 7. 验证边界

- §3 中 `verify-env.sh`（T2）与 `fetch-cache.sh`（T3）**均已实现**：样本链路自测见 RV-013 T2/T3；全量 release 11 GB 路径已由 RV-014 端到端实跑（`FETCH_OK` / `SHA256_OK=1c8126d4…` / `STRUCT_OK mode=direct downloads=1288 sstate=6945`）；`--mode ghcr` 全链路仍标 `UNVERIFIED`（release 路径已实跑，两者都产出同构两卷）。
- release 资产名称与大小经 GitHub API 匿名查询核对；`cache-full.sha256` 内容经资产下载核对。**release 归档权威布局为 direct**（顶层 `downloads/ sstate/ yp-dl/ yp-st/`，RV-014 `STRUCT_OK mode=direct`；CHG-017 收口）；`pack.sh` 本地产出已实测为 two-stage；GHCR 源 tar（`a8870b50…`）布局 **UNVERIFIED**（未拉取验证），三者不是同一对象、不得混用。`fetch-cache.sh` 对两种实际 tar 布局均探测，以实跑 `mode=` 为准；重组与否由 manifest `requires_reassembly` 决定（CHG-017/ISS-030）。本轮收口验证见 RV-015/CHG-018。
- **全量 GHCR 分片路径标 `UNVERIFIED`**：本轮未跑 `--mode ghcr`；全量分片 digest 沿用 CHG-012/ISS-020 的 GHCR registry API 独立核验记录。release 8 分片路径已由 RV-014 实跑通过。
- 构建时长与命中率：RV-005 为 4 核/8 GB 配额实测（ci 冷 7096s / prod 冷 10253s / 二次 214s）；RV-014 在本机 32 核/123 GiB 全配额下 prod 首次 5m29s、二次 3m56s、`Sstate 99% match`。时长依配额与 edition 而异，不得跨 edition 比较。
