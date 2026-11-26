# YP-M0 新机器端到端测试 · AI 执行提示词

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-AI-004 |
| 版本 | v1.0 |
| 日期 | 2026-11-26 |
| 适用仓库 | `https://github.com/zeek-zhao/yp-distro`，分支 `feat-m0-kas-bootstrap` |
| 编写时 HEAD | `85f0b24`（开工时以实际 `git rev-parse HEAD` 为准并记录） |
| 目标 | 在一台全新机器上，用真实 Docker、真实 S5 缓存、真实下载目录与 sstate 目录，把 M0 从 clone 跑到 prod 镜像产出与二次构建命中，并留下可审计证据 |
| 不在范围 | 新增功能、改 kas 配置、改已 Final 的判据结论、引入缓存服务器、root 构建 |

## 0. 角色、边界与硬约束

你是本轮的**测试执行方**，不是功能开发方。

1. 先测试、后修复。只有复现出阻塞问题时才做最小修复；修复前必须先开 `ISS-022` 及以后的编号（先 `ls docs/m0/issues/` 查重），涉及契约/阈值变更先开 `CHG-014` 及以后。
2. 只用 `zeek.zhao <zeek.zhao@foxmail.com>` 提交；不得出现 AI 署名 trailer。
3. 任何“通过”必须有本轮实跑输出；没跑过的写 `UNVERIFIED`，禁止把文档里的旧结论抄成新证据。
4. 不得把 token 写入仓库、脚本、日志或提交信息；推送凭据只从环境变量或一次性 URL 取用。
5. 不得删除 `downloads/`、`sstate/` 来“修复”命中率；不得用 root 跑构建；不得新增远程 sstate/hashserv。
6. 阈值只能来自 `scripts/cache/threshold.conf`，不得在脚本里写死数值。
7. 构建可能持续数小时，**不要中途 `docker rm -f` 或重启机器**；先看 cooker 日志是否还在增长。
8. 本提示词写于 HEAD `85f0b24`，已记录若干待验证缺陷（见 §11）。**不要盲信 runbook 的通过性描述**，按本提示词逐项实测。
9. **官方顺序（CHG-017 收口，2026-11-26）**：新机器为 fetch → bootstrap → preflight。先取缓存（目标为空），再 bootstrap 归一属主，再 preflight。**正常路径不得使用 `--force`**；`check_target` 已无损放行仅含 `.yp-volume` 的目标，marker 保留。若因故用了 `--force`，必须按 `docs/m0/deviations.md` 登记偏差并在报告写明。release 归档为 **direct**（顶层 `downloads/ sstate/ yp-dl/ yp-st/`），单层解包即得两卷，`STRUCT_OK mode=direct`。manifest 重组判断读 `requires_reassembly`，`layout` 只描述布局。

## 1. 开工先冻结事实（5 分钟）

```bash
git clone --branch feat-m0-kas-bootstrap https://github.com/zeek-zhao/yp-distro.git
cd yp-distro
git rev-parse HEAD
git log --oneline -3
git status --short
```

记录 HEAD SHA、分支、工作区是否干净。若 HEAD 已不是 `85f0b24`，先读最新 `docs/m0/plan.md`、`docs/m0/acceptance.md`、`docs/runbook-new-machine.md` 与 `docs/m0/reviews/RV-013.md`，确认本轮基线，再继续。

## 2. 机器基线（只读）

```bash
uname -a
cat /etc/os-release
docker version
docker info --format '{{.ServerVersion}} {{.Driver}}'
id
df -h .
free -h
nproc
date -u
```

记录：OS 版本、Docker 版本与 daemon 是否可用、当前 `uid:gid`、目标盘可用空间、物理内存、核数、UTC 时间。机器建议 Ubuntu 24.04、Docker ≥24、≥200 GB 空闲、≥16 GB 内存、≥8 核。

## 3. 只读环境预检

```bash
bash scripts/verify-env.sh --downloads ./downloads --sstate ./sstate --min-disk-gb 200
echo "ENV_EXIT=$?"
```

判定：

- `ENV_OK` / exit 0：继续。
- `ENV_WARN` / exit 2：允许继续，但必须把 warning 原文记入报告（常见为内存 <16 GB 或当前 UID≠1000）。
- `ENV_FAIL` / exit 1：停止，先按输出修网络/磁盘/Docker，不得跳过。

同时记录 `editions` 符号链接、`threshold.conf`、GHCR 匿名探测的结果行。

## 4. UID 分支决策（本轮最关键的一步）

先记录：

```bash
id -u
id -g
grep -E 'JENKINS_UID|JENKINS_GID' scripts/cache/threshold.conf
```

镜像内用户是 `jenkins/1000`。**卷属主必须与容器内 UID 一致**，否则容器入口会拒绝启动。自 CHG-014/ISS-022 起，`bootstrap.sh`/`preflight.sh` 的**默认目标 UID/GID 已是镜像用户 1000**（来自唯一源 `threshold.conf`），不再取当前用户；不带 `--uid/--gid` 时即以 1000 为目标。当前用户就是 1000 时默认路径与 M0 验收一致；root（sudo）执行视为 sudo 路径，可显式 `--uid 1000 --gid 1000`；非 root 且当前 UID≠1000 时脚本 exit 2 并给两条路径（见下）。

### 4.1 当前 UID=1000

走默认路径：

```bash
bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate
```

期望 `OWNER_OK` 或 `CHOWN ... -> 1000:1000`，`PREFLIGHT=0`，exit 0。

### 4.2 当前 UID≠1000

**禁止**直接执行不带参数的 `bootstrap.sh` 后就去构建。先做一次隔离探针（只在 `/tmp` 下，不碰正式卷）：

```bash
rm -rf /tmp/uid-probe && mkdir -p /tmp/uid-probe
bash scripts/bootstrap.sh --downloads /tmp/uid-probe/dl --sstate /tmp/uid-probe/sstate --min-free-bytes 0
echo "PROBE_EXIT=$?"
stat -c '%u:%g %n' /tmp/uid-probe/dl /tmp/uid-probe/sstate
```

判定：

- 若 exit 2 且打印 `UID_MISMATCH` + 两条路径：符合预期，选下面路径 A 或 B。
- 若 exit 0 且属主等于当前 UID：说明默认路径把卷 chown 到了非 1000，容器随后必然失败；这是**已知 P1**，记入 ISS，不得继续用这个卷构建。

两条合法路径，二选一并在报告中写明：

**路径 A（sudo，卷保持 1000）**

路径 A 需 `sudo`：root 可去掉 `sudo` 直接执行；非 root 且无 `sudo` 请走路径 B（UID=1000 非 root 无 sudo 同样走 B）。

```bash
sudo bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate --uid 1000 --gid 1000
sudo bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate --uid 1000 --gid 1000
```

路径 A 下 `preflight.sh` 带 `--uid 1000 --gid 1000` 可保持与构建时一致（CHG-014 后默认已是 1000，不带参数也不会再以当前 UID 误报 `BAD_OWNER`）。

**路径 B（按当前用户重建镜像，卷保持当前 UID）**

```bash
docker build --build-arg JENKINS_UID=$(id -u) --build-arg JENKINS_GID=$(id -g) \
  -t yp-builder:local docker/
export YP_BUILDER_IMAGE=yp-builder:local
bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate \
  --uid "$(id -u)" --gid "$(id -g)"
bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate \
  --uid "$(id -u)" --gid "$(id -g)"
```

**路径 B 必须显式 `--uid "$(id -u)" --gid "$(id -g)"`**：脚本默认目标来自 `threshold.conf` 的 1000，不读镜像的 `JENKINS_UID`；`--build-arg` 只决定容器内 UID，不会让 bootstrap/preflight 自动改用当前 UID，照抄不带 UID 参数会 exit 2。

**路径 B 的 `docker run` 必须用 `$YP_BUILDER_IMAGE`（即 `yp-builder:local`）**，不能用 GHCR 的 `wrynose-m0`——否则当前 UID（如 1234）的卷配上 1000 容器，entrypoint 拒绝启动。§5/§7 的命令都用 `"${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}"`，**同一 shell** 里设了 `export` 即可正确解析；**若另开 shell（如 §7/§9 在新终端执行），必须重新 `export YP_BUILDER_IMAGE=yp-builder:local`，或直接把该命令的 `IMAGE` 行设为 `IMAGE=yp-builder:local`**，否则静默回退 GHCR 1000。

## 5. 拉取 builder 镜像并核对身份

**不要写死 GHCR 镜像**：用与步骤 7 相同的变量解析，路径 A/B 都适用（同一 shell；跨 shell 需重新 export 或把 IMAGE 行写死）：

```bash
IMAGE="${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}"
docker image inspect "$IMAGE" --format '{{index .RepoDigests 0}}'
docker run --rm "$IMAGE" sh -c 'whoami; id -u; kas --version'
```

路径 A（`$IMAGE` = GHCR `wrynose-m0`）先 `docker pull ghcr.io/zeek-zhao/yp-builder:wrynose-m0` 再核对 `jenkins/1000` 基线；路径 B（`$IMAGE` = §4.2 构建的 `yp-builder:local`）核对**自己构建的当前 UID 镜像**，不要拉/验 GHCR 的 1000 镜像。

期望：`jenkins`、`1000`（路径 B 为当前 UID）、`kas 5.5`。记录镜像 digest（本地镜像 `RepoDigests` 为空属正常，记录 `IMAGE` 值即可）。

## 6. 取回全量 S5 缓存（真实 11 GiB）

先做不下载的自检：

```bash
bash scripts/cache/fetch-cache.sh --mode release --dry-run \
  --dest-parent . --work ./cache-work --release-tag m0-s5-payload-full
```

**关键断言**：输出最后一行应为

```text
EXPECTED_ARCHIVE name=cache-full.tar sha256=1c8126d4b1c57d5dc5a4f772617cd74dacbeab475d79e8ce2ee49bbcea1be624 bytes=11153387520
```

如果这里打印 `bytes=11153397760`，说明清单/文档仍有字节数与哈希错配，记 P1 并停止，不要用错误期望值继续。

正式下载（约 11 GiB，耗时取决于带宽；保留 work 以便复核）：

> **顺序说明（CHG-017）**：在全新机器上应**先 fetch 再 bootstrap**（此时目标为空，无需 `--force`）。若你已按 §4 在正式卷上执行过 bootstrap，仅含 `.yp-volume` 的目标现在会被 `check_target` 无损放行（marker 保留），因此**本轮不需要 `--keep` 之外的任何覆盖参数，更不要 `--force`**；fetch 后用 bootstrap 归一属主即可（root 解包会打印 `OWNER_HINT`）。

```bash
time bash scripts/cache/fetch-cache.sh --mode release --keep \
  --dest-parent . --work ./cache-work --release-tag m0-s5-payload-full
echo "FETCH_EXIT=$?"
```

逐项记录并核对：

1. 8 个 `ASSET_OK`，每个 name/bytes/sha256 与 `manifests/cache-full.release.json` 一致；
2. `REASSEMBLE_OK`，`bytes=11153387520`；
3. `SHA256_OK sha256=1c8126d4b1c57d5dc5a4f772617cd74dacbeab475d79e8ce2ee49bbcea1be624`；
4. `STRUCT_OK mode=direct downloads=... sstate=...`（CHG-017：release 归档为 direct，非 two-stage），文件数记录实际值（文档期望 1288/6945，若不同只记录，不硬判）；
5. `UNPACK_OK`，exit 0；
6. 独立复核：

```bash
stat -c '%s' cache-work/cache-full.tar
sha256sum cache-work/cache-full.tar
sha256sum cache-work/cache-full.part-* | head
ls -la downloads sstate | head
```

若 `stat` 不是 `11153387520`，或 sha256 不是 `1c8126d4…`，立即停止并开 ISS：这是发布链路或清单的事实错误，不能带病继续构建。

同时记录一个已知事实：release `m0-s5-payload-full` 目前只有 8 个分片 + `cache-full.sha256`，**没有** `cache-full.manifest.json`；`CHG-013` 写的“已上传 manifest”与事实不符。用 GitHub API 核对并记入报告：

```bash
TOKEN="${GH_TOKEN:-}"
curl -s -H "Authorization: Bearer $TOKEN" \
  https://api.github.com/repos/zeek-zhao/yp-distro/releases/tags/m0-s5-payload-full \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(len(d["assets"]), [a["name"] for a in d["assets"]])'
```

（无 token 时匿名请求可能限流；只读公开信息，不要求上传。）

## 7. 卷预检与构建

路径 A：

```bash
bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate --uid 1000 --gid 1000
```

路径 B：显式带当前 UID —— `bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate --uid "$(id -u)" --gid "$(id -g)"`。

期望两个卷 `OK role=... owner=... writable=yes`，exit 0。若 `LOW_SPACE` exit 3，先扩容/清理，不要删缓存。

构建（保留命名容器，便于二次构建）：

```bash
docker run -d --name yp-m0-build \
  -v "$PWD:/mnt/repo:ro" \
  -v "$PWD/downloads:/work/downloads" \
  -v "$PWD/sstate:/work/sstate" \
  "${YP_BUILDER_IMAGE:-ghcr.io/zeek-zhao/yp-builder:wrynose-m0}" sleep infinity

docker exec yp-m0-build bash -c \
  'mkdir -p /work/build-run && tar -C /mnt/repo --exclude=./.git --exclude=./downloads --exclude=./sstate -cf - . | tar -C /work/build-run -xf -'

time docker exec -w /work/build-run yp-m0-build \
  kas build kas/yp.yml:editions/prod.yml
```

记录：容器是否 `Up`、复制退出码、构建墙钟、末尾 `Tasks Summary`、`Sstate summary` 原文。期望 prod 产物：

```bash
docker exec yp-m0-build bash -c \
  'ls -lh /work/build-run/build/tmp/deploy/images/qemux86-64/'
docker exec yp-m0-build bash -c \
  'file /work/build-run/build/tmp/deploy/images/qemux86-64/core-image-minimal-qemux86-64.rootfs.ext4'
```

期望约 42M 的 ext4，`file` 显示 `Linux rev 1.0 ext4 filesystem data`。

## 8. 二次构建与缓存命中

```bash
time docker exec -w /work/build-run yp-m0-build bash -c \
  'rm -rf build && kas build kas/yp.yml:editions/prod.yml'

docker exec yp-m0-build bash -c \
  'grep -E "Sstate summary|Tasks Summary" /work/build-run/build/tmp/log/cooker/qemux86-64/console-latest.log | tail -n 6'
```

记录 `Sstate summary` 的 match%、`Tasks Summary` 的 `didn't need to be rerun`、墙钟。

注意：文档里的“214s / 200–300s”是 **ci edition 二次构建**的数据。prod edition 保留完整图形栈，第一次带缓存构建可能仍有大量 miss；**不要拿 ci 数字判 prod 失败**，只看本次 prod 的 match/rerun 与是否成功。

## 9. 重启/幂等验证

```bash
docker rm -f yp-m0-build
bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate [--uid 1000 --gid 1000]
bash scripts/cache/fetch-cache.sh --mode release --dry-run \
  --dest-parent . --work ./cache-work-2 --release-tag m0-s5-payload-full
bash scripts/preflight.sh --downloads ./downloads --sstate ./sstate [--uid 1000 --gid 1000]
```

上面 `[--uid 1000 --gid 1000]` 是路径 A（当前 UID=1000 或 sudo）的写法；**路径 B 必须替换为 `--uid "$(id -u)" --gid "$(id -g)"`**，与 §4.2/§7 保持同一目标 UID。

期望：`KEEP`/`OWNER_OK`、dry-run 不产生下载、`preflight` 通过；不得覆盖或清空已有缓存。若脚本要求 `--force` 才能继续，停止并记录，说明目标目录保护生效但幂等路径需修。

## 10. 留痕与提交（必须）

1. 新建 `docs/m0/reviews/RV-014.md`（若已存在则顺延编号），记录：机器规格、HEAD、UID 路径选择、每步命令与真实输出、耗时、哈希、通过/失败/UNVERIFIED、残留风险。
2. 每个复现出的缺陷开 `docs/m0/issues/ISS-022+.md`：现象、复现命令、根因、临时/永久措施、验证证据、关闭条件。禁止只写在报告正文里。
3. 若修改契约（字节数、manifest 分发方式、UID 默认值、runbook 命令），先开 `CHG-014+.md`，再改实现与文档。
4. 只改与本轮证据直接相关的文件；不要顺手重构。
5. 提交：

```bash
git -c user.name='zeek.zhao' -c user.email='zeek.zhao@foxmail.com' commit -m '<type>(m0): <summary>' \
  -m 'Refs: YP-M0-RV-014' \
  -m 'Doc: docs/m0/reviews/RV-014.md'
```

6. 提交前必跑：

```bash
bash scripts/gate.sh
bash scripts/check-vars.sh
git log --format='%h %ae' -5
```

期望 `GATE_PASS`、`VARS_OK checked=28 drift=0`，邮箱全为 `zeek.zhao@foxmail.com`。

## 11. 本轮已知待验证缺陷（先复现，再决定是否修）

| # | 级别 | 现象/疑点 | 复现与判定 | 处理 |
|---|---|---|---|---|
| K-1 | P1 | 非 1000 UID 上，`bootstrap.sh` 默认把卷 chown 到当前 UID，容器入口要求 1000，构建在启动阶段失败 | §4.2 隔离探针：exit 0 且 `stat` 显示当前 UID → 复现 | 默认目标应改为镜像 `JENKINS_UID`；非 root 且当前≠1000 必须 exit 2 给 sudo/重建镜像两条路径；开 ISS |
| K-2 | P1 | provenance/acceptance/CHG-013 把 `1c8126d4…` 配成 `11,153,397,760 B`；release 分片和是 `11,153,387,520 B`，`a8870b50…` 才是 `11,153,397,760 B` | §6 dry-run 是否打印 `11153387520`；`stat`/`sha256sum` 复核 | 统一改成 `1c8126d4 ↔ 11153387520`；重新生成 `cache-meta.json`；acceptance 升版并记录；开 ISS |
| K-3 | P2 | `CHG-013` 声称 `cache-full.manifest.json` 已上传 release，实际 release 只有 9 个资产 | §6 GitHub API 资产列表 | 要么真实上传并核对 digest，要么把契约降为“仓库持久 manifest + 上传 UNVERIFIED” |
| K-4 | P2 | `fetch-cache.sh --work <已存在目录>` 退出时会 `rm -rf` 整个目录 | 只在 `/tmp` 用一次性目录测，不要用真实数据 | 改为只清理自建临时子目录；开 ISS |
| K-5 | P2 | `--parts` 对 two-stage 归档未实现重组，会把单片当整 tar 解包 | 代码走查 + 小样本（不要下载 1.5 GB 分片） | **已由 CHG-017 修复**：重组判断改读 manifest `requires_reassembly`，`--parts` 部分取片对需重组归档显式拒绝（不再静默误解包）；历史缺陷保留供追溯，勿当成未修 |
| K-6 | P2 | `runbook §7` 仍写“脚本尚未实现”，与 T2/T3 已交付矛盾 | 读文档即可 | 更新为“已实现、样本链路已验、全量 UNVERIFIED” |
| K-7 | P2 | README 第 3 步未挂仓库，照抄必失败；README 的 200–300s 是 ci 数据 | 代码块对照 runbook §3 步骤 7 | README 指向可执行写法；时长标注 edition |
| K-8 | P3 | `--mode ghcr` 按 tag 拉取，manifest 里的 digest 未用于 `docker pull`；`check_target` 在 11 GB 下载后才执行 | 代码走查 | 可选修；不阻塞 release 路径 |

修复顺序：K-1、K-2 必须先修并复跑；K-3/K-4/K-5/K-6/K-7 在报告归档后修；K-8 可留待后续。

## 12. 通过判据（全部满足才算本轮 PASS）

1. 干净 clone，HEAD 与记录一致；
2. `verify-env.sh` 实跑并记录退出码；
3. UID 路径选择正确，容器入口不因属主拒绝启动；
4. release 8 分片全部 `ASSET_OK`，重组 `SHA256_OK=1c8126d4…`，**单层解包** `STRUCT_OK mode=direct`，目标卷可用；
5. prod edition 构建成功，产出 ext4 镜像；
6. 二次构建成功，记录 prod 的 `Sstate summary` 与 `didn't need to be rerun`；
7. 删除容器后重跑 bootstrap/preflight/dry-run 幂等，不覆盖缓存；
8. RV-014 与所有 ISS/CHG 已提交，`GATE_PASS`、`VARS_OK`，身份正确。

任一项失败：整体记 `FAIL`，不得用“部分通过”替代；修完必须从失败步骤重跑，并保留旧失败证据。

## 13. 最终回报格式（直接贴给主控）

```text
MACHINE: os=... docker=... cpu=... mem=... disk=... uid=...
HEAD: <sha>
UID_PATH: A(sudo 1000) | B(local image) | default(1000)
FETCH: assets=8 reassemble_bytes=... sha256=... struct=... exit=...
BUILD1: wall=... tasks=... sstate=... artifact=...
BUILD2: wall=... match=... rerun=... exit=...
IDEMPOTENT: bootstrap=... preflight=... dry_run=...
GATE: GATE_PASS | ...
VARS: VARS_OK checked=28 drift=...
FINDINGS: K-1 ... K-8 的复现结果（REPRO/NO_REPRO/UNVERIFIED）
ISSUES: ISS-...（新建/关闭）
CHANGES: CHG-...
COMMITS: <sha list>
RESIDUAL: ...
VERDICT: PASS | FAIL | UNVERIFIED（逐项说明）
```

## 14. 现在开始

先回复你记录到的机器基线、HEAD、`id -u` 与 `verify-env.sh` 结果；确认 UID 路径后再下载 11 GiB 缓存。不要先跑构建，也不要把文档里的旧结论当作本轮证据。
