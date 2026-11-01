# P1-02 报告真构建化 + 降级清单三处一致

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P1-02` |
| 里程碑 | `v0.2.0` |
| 分支 | `feat/P1-02-qa-report`（已由 WorkBuddy 从 `dev` 切好，直接在当前分支提交工作区改动，**不要自己 switch/create 分支**） |
| 关联 Issue | `#18` |
| 依赖 | `P1-01`（kas 层）已完成 |
| 预计改动文件 | `config/features.txt`、`config/degraded.txt`（新增）、`scripts/lib/artifacts.sh`（新增）、`scripts/report.sh`、`tests/bats/06_report.bats`（新增）、`tests/bats/99_coverage.bats`、`docs/qa/README.md`（新增）、`docs/qa/wrynose/20261028-2b643c3.md`（**删除**）、`.gitignore` |

## 背景

P1 要求每个版本每个 variant 有一次真实构建 + QEMU 通过，并把结果归档成可追溯报告（需求 §6.2、§7.3）。

现状有两个缺口：

1. `scripts/report.sh` 生成的归档里，`Image digest` 和 `Artifact SHA-256` 是硬编码的 `n/a（P0 未实现）`，报告因此**不能证明真构建发生过**；
2. 需求 §7.3 定义了一张「降级白名单」（SPDX 产物格式、CVE 清单工具、multilib、do_scancode），并要求：**降级项必须写进报告「降级清单」+ 在 `config/features.txt` 标注 `degraded`，由 `99_coverage.bats` 校验其与报告一致，不允许静默通过**。这三处目前一处都没有。

本卡只做「把报告变成真构建报告 + 把降级清单做成三处一致」，**不跑真实构建**（真构建由 WorkBuddy 在构建机上用 `kas build` 跑），也不实现 `project.sh build` / `project.sh qemu`（另有任务卡）。

## 已定的设计口径（照此实现，不要自行发挥）

### 1. `config/features.txt` 升级为 5 列

格式：`feature_id | 适用 release | bats 文件 | bats tag | status`

- 第 5 列 `status` 只允许两个取值：`ok` / `degraded`
- 现有 6 行全部补第 5 列 `ok`
- 新增以下 6 行（`bats 文件`、`bats tag` 都写 `-`，表示用例待 P2 落地；`-` 是合法占位符）

```
spdx-format | dunfell,kirkstone,scarthgap | - | - | ok
spdx-format | wrynose | - | - | degraded
cve-tool | dunfell,kirkstone,scarthgap | - | - | ok
cve-tool | wrynose | - | - | degraded
distro-backfill | wrynose | - | - | degraded
report-archive | all | tests/bats/06_report.bats | report | ok
```

最后一行是必须的：`99_coverage.bats` 的 test 3 要求**每个非 meta 的 `.bats` 文件都被 features.txt 引用**，新增 `06_report.bats` 就必须登记。

注意列对齐风格与现有行保持一致（` | ` 分隔）。

### 2. 新增 `config/degraded.txt`

理由文案的唯一真本。格式：`aspect | release | 理由 | 需求条款`，允许 `#` 注释行与空行。

```
spdx-format | wrynose | SPDX 2.x 产物已在 6.0 移除，只能产出新的 SBOM 格式 | §7.3
cve-tool | wrynose | cve-check.bbclass 已在 6.0 移除，改用 sbom-cve-check | §7.3
distro-backfill | wrynose | DISTRO_FEATURES_BACKFILL 已在 6.0 移除 | §7.3
```

### 3. 新增 `scripts/lib/artifacts.sh`

只放函数，被 `report.sh` 与 BATS source。函数签名固定（BATS 会直接调）：

```bash
# 打印 deploy 目录下所有 rootfs 产物（每行一个绝对路径，按文件名排序）
artifact_list <deploy_dir> <image> <machine>

# 打印主产物绝对路径：优先最新的 *.rootfs.ext4，否则最新的 *.rootfs.tar.bz2，
# 否则最新的任意 *.rootfs.*；一个都没有则打印空串并 return 1
artifact_primary <deploy_dir> <image> <machine>

# 打印 <path> 的 32 字节十六进制 sha256；文件不存在 return 1
artifact_sha256 <path>

# 打印 <path> 的字节数（stat -c %s）
artifact_bytes <path>
```

约束：

- 必须 source `scripts/lib/common.sh` 拿 `die` / `log_*`，路径用 `ROOT_DIR` 推导，不要用相对路径；
- 必须能容忍 deploy 目录不存在（`artifact_list` 打印空、return 0；`artifact_primary` return 1）；
- `artifact_list` 排除 `*.manifest`、`*.testdata.json`、`*.spdx.*`、`*.json`，只留真实镜像文件（`*.rootfs.ext4` / `*.rootfs.tar.bz2` / `*.rootfs.tar.xz` / `*.rootfs.wic*` / `*.rootfs.jffs2` 等）；
- 用 `set -euo pipefail` 友好的写法；shellcheck `-S warning` 零告警；shfmt `-i 4 -ci` 无 diff。

### 4. `scripts/report.sh` 改造

**a) CLI 兼容两种写法**（Issue 验收用的是第 2 种，现有 BATS 用的是第 1 种，两种都必须工作）：

```bash
scripts/report.sh wrynose                    # 位置参数
scripts/report.sh --release wrynose           # 选项形式
scripts/report.sh --release wrynose --variant general
scripts/report.sh all
scripts/report.sh --print-fingerprint          # 行为不变
```

**b) 归档新增三节**（顺序：`## Test statistics` → `## Failures` → `## 构建产物` → `## QEMU 串口` → `## 降级清单`）：

```markdown
## 构建产物

- Deploy dir: `work/kas-wrynose-general/build/tmp/deploy/images/qemux86-64`
- Artifact: `core-image-minimal-qemux86-64.rootfs.ext4`
- Artifact bytes: `123456789`
- Artifact SHA-256: `abcdef...`
- Image digest: `n/a（本地构建无 registry digest）`
- 全部产物 sha256: 见 `artifacts.sha256`（同目录）
```

- deploy 目录默认 `work/kas-<release>-<variant>/build/tmp/deploy/images/<machine>`，可用环境变量 `YP_DEPLOY_DIR` 覆盖；
- `<machine>` 从 `resolve_all` 得到；
- **产物缺失时**（还没构建过）：`Artifact` / `bytes` / `SHA-256` 全部输出 `n/a（未构建）`，**报告仍然生成、退出码仍由 bats 决定**（不许因为没产物就 die）；
- 产物存在时，同时在 `docs/qa/<release>/` 同目录写 `artifacts.sha256`（`sha256sum` 格式，覆盖 `artifact_list` 全部产物），首行加注释说明来源 release/variant/commit。

**c) 新增「QEMU 串口」节**：

- 串口日志约定路径：`work/artifacts/<release>/<variant>/qemu-serial.log`；
- 存在则写：

```markdown
## QEMU 串口

- 串口日志: `work/artifacts/wrynose/general/qemu-serial.log`
- 启动到 login prompt: `yes`（匹配到 `login:`）
- 日志字节数: `12345`
```

- 不存在则写 `- 串口日志: n/a（本次未执行 QEMU）`。

**d) 新增「降级清单」节**（由 `config/degraded.txt` 生成，按当前 release 过滤）：

```markdown
## 降级清单

| aspect | 理由 | 需求条款 |
|---|---|---|
| `spdx-format` | SPDX 2.x 产物已在 6.0 移除，只能产出新的 SBOM 格式 | §7.3 |
```

- 该 release 无降级项时输出 `无（本版本全部能力按标准实现）`；
- 标题必须是 `## 降级清单`（Issue 验收 `grep -q '降级清单'`）。

**e) 现有内容保持不变**：`Release` / `Variant` / `Commit` / `Tag` / `SOURCE_FINGERPRINT` / `Hostname` / `Start time` / `End time` / `Duration` / `## Test statistics` / `## Failures`，以及 `--print-fingerprint` 的输出格式。

**f) 文件头注释**：在 `report.sh` 顶部加 3–6 行注释说明「本脚本跑 BATS 并生成真构建报告，产物信息来自 work/ 下的 kas 构建输出，不负责构建本身」。

### 5. `tests/bats/99_coverage.bats` 改造

- **test 4**（现在是「四字段 + release 选择器」）改为「**五字段** + 合法 release 选择器 + status 合法」：
  - `|` 数量必须是 4；
  - 第 5 列 ∈ {`ok`,`degraded`}；
  - `bats 文件`/`bats tag` 允许为 `-`，此时跳过后续存在性校验；
- **test 1 / test 2** 加 `-` 跳过逻辑（值为 `-` 时不检查文件存在、不检查 tag 声明）；
- **test 3** 不变；
- **新增 test 5**「每个 degraded 标注都能在 `config/degraded.txt` 找到理由」：对 features.txt 中每条 `status=degraded` 的行，`config/degraded.txt` 里必须存在同 `aspect`（= feature 名）且 release 覆盖该行的记录；
- **新增 test 6**「报告降级清单与 degraded.txt 双向一致」：
  - 目录 `docs/qa/<release>/` 下没有 `.md` → `skip "需要报告归档"`；
  - 取**文件名排序最后**的一个 `.md`（最新归档）；
  - 该文件缺 `## 降级清单` 节 → **fail**，提示 `最新报告缺少降级清单节，需重新生成`（不允许静默放过旧格式报告）；
  - 解析该节的表格，抓第一列的 `` `aspect` `` 反引号标识集合，记为 R；
  - 从 `config/degraded.txt` 取该 release 的 aspect 集合，记为 D；
  - 断言 `R == D`（双向：报告少的要报错、报告多的也要报错）。

### 6. 新增 `tests/bats/06_report.bats`

`# bats test_tags=report`，覆盖：

1. `project report --help` 退出 0（已有用例在 00_project.bats，这里只测新 CLI）；
2. `scripts/report.sh --release wrynose --variant general` 与 `scripts/report.sh wrynose` **等价**（都不真跑，用 `--print-fingerprint` 之外的方式不行 —— 见下方「严禁」）；
3. `artifact_primary`：临时目录造 3 个假产物（`.rootfs.ext4` / `.rootfs.tar.bz2` / `.manifest`），断言选中 `.ext4`、且 `.manifest` 被排除；
4. `artifact_primary` 在空目录 return 非 0；
5. `artifact_sha256` 对固定内容文件（`printf 'hello'`）断言等于已知值 `2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824`；
6. 「降级清单」渲染：把 `config/degraded.txt` 用临时副本替换（**用 `YP_DEGRADED_FILE` 环境变量指向临时文件**，为此 `report.sh` 需支持该覆盖）后生成报告，断言含 `## 降级清单` 与 `spdx-format`。

**严禁**：`06_report.bats` 里**不得**调用会真正执行 `bats -r tests/bats` 的路径（`report.sh` 主体会递归跑全量 BATS，直接调用会造成无限递归）。所以 `report.sh` 必须支持 `--render-only`（只渲染归档、不跑 BATS、不写 `reports/*.xml`，退出 0）—— 06 的用例 6 用 `--render-only` 调。`--render-only` 与 `--release` 一起用；它写出的归档文件名后缀加 `-render`（如 `20261028-abc1234-render.md`），避免覆盖真报告。

### 7. 新增 `docs/qa/README.md`

说明：报告三层的目录约定、`docs/qa/<release>/<date>-<sha>.md` 命名、`artifacts.sha256` 旁证、「降级清单」三处一致（features.txt 标注 → degraded.txt 理由 → 报告呈现 → 99_coverage 校验）。30 行以内。

### 8. 删除 P0 期旧归档 + 忽略 render 产物

- 删除 `docs/qa/wrynose/20261028-2b643c3.md`：它是 commit `2b643c3` 时**旧版** report.sh 生成的纯 BATS 报告，`Image digest` / `Artifact SHA-256` 都是 `n/a（P0 未实现）`，也没有「降级清单」节，已被 #18 的真构建报告取代（用 `git rm`）；
- `.gitignore` 增加一行 `docs/qa/**/*-render.md`（`--render-only` 的临时产物不入库）。

## 不要做的事

- **不要跑真实构建**（不 `kas build`、不 `bitbake`、不进构建容器）；也不要删改 `work/` 下任何东西（那是 WorkBuddy 正在用的构建目录）。
- 不改 `kas/`、`docker/`、`layers/`、`.github/workflows/`、`project.sh` 的其它子命令。
- 不实现 `project.sh build` / `project.sh qemu`（另行派单）。
- 不新增第三方命令依赖（只用 bash / coreutils / grep / awk / python3）。
- 不改 `scripts/report.sh --print-fingerprint` 的算法与输出格式（CI 的 `report-check.yml` 依赖它）。
- 不动 `01_dockerfile.bats` / `02_workflows.bats` / `03_container.bats` / `04_layer.bats` / `05_kas.bats`。
- 不要 `git commit`。

## 验收标准

全部在仓库根目录执行：

```bash
# 1. 静态检查
bash scripts/dev.sh shfmt -d -i 4 -ci scripts/ 
bash scripts/dev.sh shellcheck -S warning scripts/*.sh scripts/lib/*.sh

# 2. 全量 BATS（改动前 82 ok / 0 not ok，改动后必须 0 not ok，skip 仅限 require_* 白名单）
bash scripts/dev.sh bats -r tests/bats/

# 3. 新的降级清单链路
bash scripts/dev.sh bats --filter-tags report tests/bats/
bash scripts/dev.sh grep -c 'degraded' config/features.txt        # >= 3
bash scripts/dev.sh bash -c 'source scripts/lib/artifacts.sh && type artifact_primary'

# 4. 只渲染一份报告（不跑 BATS），必须含降级清单
bash scripts/dev.sh bash scripts/report.sh --release wrynose --variant general --render-only
grep -q '## 降级清单' docs/qa/wrynose/*-render.md
grep -q 'spdx-format' docs/qa/wrynose/*-render.md

# 5. 有了归档之后再跑一次全量 BATS：test 6 必须真实校验（不能是 skip）
bash scripts/dev.sh bats -r tests/bats/
```

- [ ] 上述命令全部退出码 0
- [ ] 第 5 步里 test 6（报告↔degraded.txt 一致）是 **ok** 而不是 skip
- [ ] `bash scripts/report.sh --print-fingerprint` 输出格式与改动前逐字一致
- [ ] `git status --porcelain` 只包含本卡「预计改动文件」里的路径
- [ ] `config/features.txt` 每行 5 个字段，`99_coverage.bats` 6 个用例全绿
- [ ] 报告里「构建产物」「QEMU 串口」「降级清单」三节都在，产物缺失时是 `n/a（未构建）` 而不是报错

## 参考

- `scripts/report.sh`（现有实现，BATS 报告 + 指纹）
- `scripts/lib/common.sh`（`ROOT_DIR` / `die` / `log_*` / `resolve_all` / `work_dir`）
- `tests/bats/99_coverage.bats`（现有 4 个元测试的写法与 `_trim` 辅助函数）
- `tests/bats/setup.bash`（`ROOT_DIR`、`project()` 包装、`skip` 白名单）
- 需求 §6.2「报告三层」、§6.3「门禁规则」、§7.3「降级白名单」（原文在 Obsidian，仓库里没有，本卡已把口径写全）
