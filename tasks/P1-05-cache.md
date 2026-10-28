# 任务卡 P1-05：缓存共享（DL_DIR / SSTATE_DIR）+ 构建并发锁（Issue #23）

## 背景（已实测，不要重新怀疑）

仓库 `zeek-zhao/yocto`，当前分支 `dev`，HEAD `0d8d13d`。BATS 现状 **93 ok / 0 not ok / 0 skip**，必须只增不减。

### 实测事实 A：环境变量对 DL_DIR/SSTATE_DIR 无效

在 215 用 `ghcr.io/zeek-zhao/yocto/wrynose:local` 实测 `bitbake -e`：

| local.conf 写法 | 容器内环境变量 | bitbake 解析结果 |
|---|---|---|
| `DL_DIR = "${TOPDIR}/../downloads"`（现状） | 无 | `/work/work/kas-wrynose-general/build/../downloads` |
| 同上 | `DL_DIR=/work/work/downloads` | **同上**（被 local.conf 覆盖） |
| `DL_DIR ??= "${TOPDIR}/../../downloads"` | `DL_DIR=/work/work/downloads` | `/work/work/kas-wrynose-general/build/downloads`（**环境变量没进 datastore**，且 `??=` 也没生效为 TOPDIR 相对值 —— 因为 bitbake.conf 先给了 `?=` 默认值） |
| 两行全部删除 | `DL_DIR=/work/work/downloads` | `/work/work/kas-wrynose-general/build/downloads`（**默认值，环境变量无效**） |

**结论**：bitbake 不会把 `DL_DIR`/`SSTATE_DIR` 从环境导入 datastore（除非在**环境**里设 `BB_ENV_PASSTHROUGH_ADDITIONS`，而 dunfell 3.1 用的是旧名 `BB_ENV_EXTRAWHITE`，跨版本又是一处分支）。
所以 `scripts/container.sh` 里那两个 `-e DL_DIR=... -e SSTATE_DIR=...` **是死代码**。不要试图靠环境变量生效，直接改 `kas/base.yml` 的赋值。

### 实测事实 B：相对路径算术

`TOPDIR` = `/work/work/kas-<release>-<variant>/build`，所以：

- `${TOPDIR}/../downloads` → `/work/work/kas-<release>-<variant>/downloads`（**现状，每版本一份**）
- `${TOPDIR}/../../downloads` → `/work/work/downloads`（**目标，四版共享**）
- `${TOPDIR}/../../sstate` → `/work/work/sstate`

这与 `scripts/container.sh` 里 `dl_dir=/work/work/downloads` / `sstate_dir=/work/work/sstate`（已被 `tests/bats/03_container.bats` 断言）**完全一致**。

### 实测事实 C：现状代价

`work/kas-wrynose-general/downloads` 已 **11 GB / 319 个包**（含 `linux-yocto` 的 3.83 GiB 全 history 包）。
不改的话，scarthgap / kirkstone / dunfell 每个都要各拉一份，按 215 出口 ~1 MB/s 算，每版本白等 1 小时以上。

## 目标改动

### 1. `kas/base.yml`：改成共享路径（核心，一行两处）

```yaml
    DL_DIR = "${TOPDIR}/../../downloads"
    SSTATE_DIR = "${TOPDIR}/../../sstate"
```

用 `=`（不是 `??=`）—— 见实测事实 A：`??=` 会被 bitbake.conf 的 `?=` 默认值抢先。
同时把这两行上面的注释补一句：说明 `../..` 是刻意的，`..` 会退化成每版本一份。

**不要**动 `scripts/container.sh` 的 `-e DL_DIR` / `-e SSTATE_DIR`：`03_container.bats` 有断言，且现在两边值一致。但请在 `container.sh` 那两行上方加注释，写明「这两个变量是给人工排查看的契约声明，真值由 `kas/base.yml` 决定（bitbake 不从环境导入它们）」。

### 2. 新增 `scripts/build.sh`：真构建入口 + 并发锁

需求：#23 验收要求「第二个并发构建被锁拒绝并给出明确提示（不是静默排队）」。当前仓库没有构建入口（`project.sh build` 是 `not_implemented`），本卡把它建起来。

接口（宿主和容器内都能跑，`scripts/dev.sh` 会直通）：

```
bash scripts/build.sh --release <r> --variant <v> [--image-mode release|dev] [--dry-run]
```

行为：

1. 参数校验：`--release` 必须是 `config/<release>.env` 里存在的四个之一；`--variant` 必须是 `general|custom`；缺失参数打印用法并以 `exit 2` 退出。
2. **取锁**：`flock -n 9` 锁文件 `<repo>/work/build.lock`（`exec 9>...`，用 fd 9）。拿不到锁时打印
   `ERROR: 另一个构建正在运行（锁：<repo>/work/build.lock）；本工程规定串行构建` 并以 **exit 3** 退出。
   **无论是否 `--dry-run` 都要走取锁逻辑**（这样 BATS 能测）。
3. `--dry-run`：拿锁成功后打印将要执行的完整命令（`./project.sh shell --release ... --variant ... -- bash -lc '<kas build ...>'`），不实际执行，exit 0。
4. 非 dry-run：在仓库根起容器执行构建（`./project.sh shell` 已在用，照抄它的调用方式），
   - 日志落 `<repo>/work/logs/build-<release>-<variant>.log`；
   - 构建前 `mkdir -p work/downloads work/sstate work/logs`；
   - 环境变量必须包含 `KAS_CLONE_DEPTH=1` 与 `KAS_WORK_DIR=/work/work/kas-<release>-<variant>`（**`KAS_WORK_DIR` 是容器视角路径**，且必须预先 `mkdir -p`）；
   - 记录起止时间，构建结束后把 `耗时秒数` 写进 `work/logs/build-<release>-<variant>.meta`。

不要在本卡里真的跑构建（跑一次 1.5 小时），只把入口做对。

### 3. `scripts/report.sh`：报告新增「构建统计」小节

数据源：`<repo>/work/logs/build-<release>-<variant>.log`（存在时）与 `.meta`（存在时）。

新增一小节（放在「构建产物」之后、「QEMU 串口」之前），字段：

- `Build duration`：`work/logs/build-<r>-<v>.meta` 里的秒数；缺失 → `n/a`
- `Tasks attempted / cached`：从日志 grep `NOTE: Tasks Summary: Attempted N tasks of which M didn't need to be rerun`；缺失 → `n/a`
- `Sstate hit`：从日志 grep `Sstate summary: Wanted A Local B Mirrors C Missed D Current E (P% match, Q missed)`，输出 `E/A (P%)`；缺失 → `n/a`
- `Build log`：日志绝对路径（存在时才写）

**硬性约束**：这些字段缺失时写 `n/a`，**不得**引入新的 `degraded` 项。理由：`config/degraded.txt` 是降级理由唯一真本，`99_coverage.bats` 的 test6 会做「最新报告降级清单 ↔ degraded.txt」双向一致校验，新增 degraded 必须同步改 `degraded.txt` 与 `config/features.txt` 第五列，本卡不做这个（CI 里没有真构建，必然缺失）。请在代码注释里写明这条约束。

`docs/qa/<release>/` 下**现存的报告文件**重跑 `report.sh` 会重新生成，这是预期行为；但生成前工作区必须干净，否则 `SOURCE_FINGERPRINT` 不可复现。

### 4. `scripts/kas-verify.py`：新增 `check_shared_cache` 规则

检查 `kas/base.yml`（只看这一处，release 层不覆盖）：

- `DL_DIR` 的值必须是 `${TOPDIR}/../../downloads`
- `SSTATE_DIR` 的值必须是 `${TOPDIR}/../../sstate`
- 若写成 `${TOPDIR}/../`（单层）→ 报错「每版本一份 downloads，会造成 4×4.5GB 重复下载」
- 若两行缺失 → 报错

错误消息要指名 `#23`。

### 5. BATS：新增用例（放在 `tests/bats/07_cache.bats`，新建文件）

文件头照抄同目录其它 bats 的写法（setup / ROOT_DIR 约定），并给每个用例打 `# bats test_tags=cache`。

1. `check_shared_cache 通过`：对当前 `kas/base.yml` 跑校验器，rc=0。
2. `check_shared_cache 能拦住每版本一份`：在临时目录里造一个 `base.yml` 副本（把 `../../` 改成 `../`），校验器必须 rc≠0 且输出含 `#23`。
   **临时目录必须建在 `<repo>/work/` 下面**，不能放 `/tmp` —— 校验器在容器里跑，`/tmp` 在两边不共享（这个坑以前踩过）。
3. `build.sh 参数校验`：缺 `--release` → exit 2，输出含 usage。
4. **`build.sh 并发锁`**：先在测试内用 `flock -n` 占住 `<repo>/work/build.lock`（后台 `sleep`），再 `run bash scripts/build.sh --release scarthgap --variant general --dry-run`，断言 `status -eq 3` 且输出含 `另一个构建正在运行`。测完确保释放锁、删除锁文件。
5. `build.sh dry-run 输出包含共享缓存路径`：正常（无竞争）时 `--dry-run` rc=0，输出含 `KAS_CLONE_DEPTH=1` 与 `KAS_WORK_DIR`。
6. `report.sh 的构建统计节`：用 `--render-only` 生成一份报告，断言输出含 `### 构建统计`（或你定的标题）与 `Build duration`。**必须用 `--render-only`** —— `report.sh` 主体会 `bats -r`，直接调会无限递归。

## 明确不要做

- 不要跑真构建（1.5 小时，本卡不做）
- 不要改 `config/features.txt` 的列数或新增 degraded 项
- 不要把 `DL_DIR` 写进 `config/*.env`（Issue #23 验收里那条「config/*.env 显式写 /home/...」**已作废**：真值唯一来源是 `kas/base.yml`，写成第二处只会漂移；CI 不跑真构建，env 里写路径没有意义）。这条偏差请在 PR 描述里写明。
- 不要动 `scripts/container.sh` 的 `-e` 传参本身，只加注释
- 不要改 `docs/qa/wrynose/` 下已归档的报告内容

## 验收（必须全部 rc=0，在容器内跑）

```bash
cd /home/jenkins/workspace/yocto

# 1. 静态检查
bash scripts/dev.sh shfmt -d -i 4 -ci scripts/ tests/
bash scripts/dev.sh shellcheck -S warning scripts/*.sh scripts/lib/*.sh

# 2. 全量 BATS：必须 >= 93 ok，且 0 not ok / 0 skip
bash scripts/dev.sh bats -r tests/bats/

# 3. 新规则与锁
bash scripts/dev.sh python3 scripts/kas-verify.py --engine builtin
bash scripts/dev.sh bats --filter-tags cache tests/bats/

# 4. 报告渲染（--render-only，不跑 BATS）
bash scripts/dev.sh bash scripts/report.sh --release wrynose --variant general --render-only
```
渲染出的报告要含「构建统计」小节。注意渲染会生成 `*-render.md`，**验收完请删掉这些临时文件**再提交。

## 提交

- 分支：`feat/P1-05-cache`（基于 `dev`，由我预先切好）
- 提交信息注明 `Refs #23`
- 完成后不要自己 push / 开 PR，我只做验收
