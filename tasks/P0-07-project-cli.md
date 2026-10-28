# P0-07 · project.sh 子命令补全（唯一入口收口）

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-07` |
| 里程碑 | `v0.1.0` |
| 分支 | 已在 `feat/P0-07-project-cli`（从 `dev` 切出，见 `docs/branching.md`） |
| 关联 Issue | `#9` |
| 依赖 | 已完成：`P0-01`（配置骨架）、`P0-06`（`scripts/container.sh`）；未完成：`#17` kas（P1） |
| 预计改动文件 | `project.sh`、`Makefile`、`tests/bats/00_project.bats`、`docs/cli.md`（新增） |

## 背景

需求 §4.1 要求 `project.sh` 是**唯一入口**，`Makefile` 只做薄转发；§7.1 第 3 项即本卡。
当前 `project.sh` 只有 `config` / `doctor` / `image`（转发）/ `test`（裸 bats）/ `report`，
`source|build|qemu|review|e2e` 一律 `exit 2`；`Makefile` 里 `lint` / `secret-scan` / `ci-tools`
绕过 `project.sh` 直接 `bash scripts/ci/*.sh`，`hooks` 目标内联 3 行 git 命令 —— 都不是"唯一入口"。

P0-06 交付 `scripts/container.sh` 之后，`shell` 子命令已经没有技术障碍，本卡把它接上。

## 环境铁律（违反即返工）

1. **所有验收命令必须经 `scripts/dev.sh` 在容器内执行** —— CI 与派单环境同容器，宿主直跑会漏掉嵌套路径与 PATH 差异（P0-06 就是这么红的）。
2. **BATS 用例必须环境密闭**：涉及 `WB_HOST_*` 的用例用 `env -u WB_HOST_REPO_DIR -u WB_HOST_DOCKER_BIN -u WB_HOST_DOCKER_PLUGIN_DIR` 显式清空，不许依赖调用者环境。
3. **BATS 不得硬依赖本地镜像**：`shell` 用例只用 `--dry-run`（不启容器、不需要镜像）。若某用例确实需要真实镜像，照 `tests/bats/03_container.bats:14` 的本地 `require_release_image` 写法加守卫 skip，不许红（该函数定义在 `03_container.bats` 内部，不在 `setup.bash`，需要就自己声明一份）。
4. **嵌套时绝不允许用容器内路径做 `-v` 源**（P0-06 因此在宿主建出 root 拥有的空目录）。
5. `set -o pipefail` 下不要 `printf ... | grep -q ...` 做断言（`grep -q` 提前退出会让管道 SIGPIPE，产生假失败），先存变量再判断。
6. 新增/修改的 `*.sh` 必须过 `scripts/ci/lint.sh`（shellcheck `-S warning` + shfmt `-i 4 -ci`）。

## CLI 契约（最终态，逐条实现）

### 已实现子命令

| 子命令 | 行为 | 选项 |
|---|---|---|
| `config` | 打印解析后的最终配置（`DISTRO`/`IMAGE`/`MACHINE`/`RELEASE`/`REPO_MODE`/`TAG`/`VARIANT`，`LC_ALL=C sort`） | `--release`（必填）、`--variant`（必填）、`--machine`（必填） |
| `doctor` | 打印 8 个 release×variant 组合 + 磁盘水位检查，返回值沿用现状（水位超限非 0） | 无 |
| `test` | 跑 BATS：`bats -r tests/bats`，**不写报告**（报告归 `report`） | `--tags <tag>` → 追加 `--filter-tags <tag>` |
| `report` | 转发 `scripts/report.sh <release> --variant <v>`（三层报告，需求 §6） | `--release`（默认 `all`）、`--variant`（默认 `general`） |
| `lint` | 转发 `bash scripts/ci/lint.sh`，参数直通 | 直通 |
| `secret-scan` | 转发 `bash scripts/ci/secret-scan.sh`，参数直通 | 直通 |
| `ci-tools` | 转发 `bash scripts/ci/install-tools.sh`，参数直通 | 直通 |
| `hooks` | 内置：`git config core.hooksPath .githooks` + `chmod +x .githooks/*` + 打印 `core.hooksPath = <值>`（**从 Makefile 迁来，语义不变**） | 无 |
| `image` | 转发 `scripts/image.sh`，参数直通 | 直通 |
| `shell` | 转发 `scripts/container.sh`；**未给 `--` 之后的命令时默认容器内跑 `bash -l`** | `--release`（必填）、`--variant`（默认 `general`）、`--machine`（默认 `qemux86-64`）、`--dry-run`、`--check`、`-- <cmd>...` |

### 未实现子命令（必须保留占位，不许"顺手实现"）

`source`、`build`、`qemu`、`review`、`e2e`

输出格式**固定**（stderr，一行）：

```
not implemented yet: <cmd>（<阻塞原因>）
```

阻塞原因逐条写死：
- `source` → `C40 已改由 kas checkout 取代`
- `build` → `P1 #17 kas 落地后接管`
- `qemu`、`review`、`e2e` → `P2 阶段`

必须 `exit 2`。**不允许**在 stdout 打印任何内容，**不允许** `exit 0`。

### `--help` 契约

- `./project.sh --help` 与 `./project.sh <已实现子命令> --help` 一律 **rc=0**，打印用法；
- 子命令级 `--help` 必须额外列出该子命令独有选项（例如 `shell --help` 必须出现 `--dry-run`）；
- 未实现子命令的 `--help` 允许 `exit 2`，但必须打印 `not implemented yet: <cmd>`；
- 用法错误（未知命令 / 未知选项 / 缺参数）沿用 `die`（**rc=1**），不改 `scripts/lib/log.sh`。

## 要做的事

1. **重构 `project.sh` 的参数解析**：先解析全局 `-h|--help`，再按子命令分派；把选项解析抽成一个函数，避免每个子命令复制粘贴。注意现有 `doctor` 分支在循环里复用了 `release` 变量 —— 重构时改用局部变量，别让 `doctor` 的循环污染后续逻辑。
2. 按上表补齐 `lint` / `secret-scan` / `ci-tools` / `hooks` / `shell` 五个子命令。
3. `test` 增加 `--tags`；`report` 的 `--release` 改为可选（默认 `all`）。
4. 未实现子命令统一走一个 `not_implemented()` 函数（stderr 一行 + `exit 2`）。
5. **`Makefile` 收薄**：每个 target 一行 `./project.sh <cmd>`；`hooks` 改调 `./project.sh hooks`；`help` 输出与实际 target 集合一致；保留 `.PHONY`。
6. **新增 `docs/cli.md`**（中文）：CLI 契约表（照抄本卡的上表）+ 三个典型流程（`config` 查配置 → `shell --dry-run` 看 docker 命令 → `shell --release X` 进容器）+ 未实现子命令的阻塞原因 + 「谁转发谁」的调用关系图（纯文本树）。
7. **`tests/bats/00_project.bats` 追加用例**（全部 `# bats test_tags=entry`）。

## 不要做的事

- 不改 `scripts/container.sh`、`scripts/image.sh`、`scripts/report.sh`、`scripts/ci/*`、`.github/workflows/*`、`docker/**`、`config/**`、`layers/**`。
- 不实现 `source` / `build` / `qemu` / `review` / `e2e`（P1/P2 的活）。
- 不新增 `config/*.env` 里的 `export`（有 BATS 断言守着）。
- 不引入新依赖、不加 npm/pip 包。
- 不改 `docs/branching.md`、`docs/naming.md`、`docs/container.md`、`docs/ci.md` 的既有约定（发现与本卡冲突就停下来在 PR 描述里说明，不要擅自改约定）。

## 验收标准

### A. 静态门禁（必须全绿）

```bash
bash scripts/dev.sh bash scripts/ci/lint.sh          # 期望：shellcheck / shfmt / hadolint / actionlint 四段全 ok
bash scripts/dev.sh bash scripts/ci/secret-scan.sh   # 期望：clean
```

### B. BATS 全量（必须 0 not ok、0 fail）

```bash
bash scripts/dev.sh bats tests/bats/
```

期望：用例总数 = 原有 47 + 本卡新增（≥8），`0 failures`，`0 not ok`；因环境缺席产生的 `skip` 允许但必须逐条说明原因。

### C. `--help` 逐个子命令（rc 必须为 0）

```bash
for c in config doctor test report lint secret-scan ci-tools hooks image shell; do
  bash scripts/dev.sh ./project.sh "$c" --help >/dev/null || { echo "FAIL: $c"; exit 1; }
done
echo "all help ok"
```

### D. 未实现子命令语义（rc 必须为 2，stderr 含 not implemented）

```bash
for c in source build qemu review e2e; do
  out="$(bash scripts/dev.sh ./project.sh "$c" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 2 ] || { echo "FAIL rc=$rc for $c"; exit 1; }
  case "$out" in *"not implemented yet: $c"*) ;; *) echo "FAIL msg for $c: $out"; exit 1 ;; esac
done
echo "all not-implemented ok"
```

### E. `shell` 干跑（不需要镜像、不启容器）

```bash
bash scripts/dev.sh ./project.sh shell --release scarthgap --variant general --dry-run
# 期望：stdout 恰好 1 行；包含 --name yocto-scarthgap-general；该行不含 "privileged"
bash scripts/dev.sh ./project.sh shell --release wrynose --variant custom --dry-run | head -1
# 期望：包含 --name yocto-wrynose-custom
bash scripts/dev.sh ./project.sh shell ; echo "rc=$?"
# 期望：rc=1（缺 --release，来自 die）
```

### F. `Makefile` 薄转发

```bash
bash scripts/dev.sh make -n shell | grep -qx './project.sh shell'
bash scripts/dev.sh make -n lint  | grep -qx './project.sh lint'
bash scripts/dev.sh make -n hooks | grep -qx './project.sh hooks'
bash scripts/dev.sh make help
# 期望：help 输出里出现的 target 集合 == Makefile 的 .PHONY 列表（help 自身除外）
bash scripts/dev.sh make secret-scan     # 真实转发一条，证明 wiring 通（期望 clean）
```

> 注：`make -n` 要能被容器内的 `make` 执行；若 `make` 在镜像里缺失，用等价的静态断言（`git grep` 比对 target 与转发行）替代并在 PR 里说明 —— **但不许跳过 F 段**。
> 不要把 `--release` 之类的参数跟在 make 目标后面（`make config --release x` 会被 make 当成自己的选项而报错）；带参数的场景一律直接调 `./project.sh`。

### G. 真实入容器（可选，215 有镜像时才跑）

```bash
bash scripts/dev.sh ./project.sh shell --release scarthgap --variant general -- bash -lc 'id -un; command -v kas'
# 期望：builder / /usr/local/bin/kas
```

### H. 工作区洁净

```bash
git status --short
# 期望：只有 project.sh / Makefile / tests/bats/00_project.bats / docs/cli.md 四个路径
```

## 完成定义（DoD）

- [ ] A、B、C、D、E、F、H 全部 rc=0
- [ ] 未实现子命令一律 `exit 2` + stderr 一行 `not implemented yet: <cmd>（原因）`
- [ ] `Makefile` 每个 target 一行转发，无业务逻辑；`hooks` 的实现已迁进 `project.sh`
- [ ] `docs/cli.md` 存在且与本卡上表逐项一致（含未实现子命令的阻塞原因）
- [ ] BATS 总数 ≥ 55，`0 not ok` / `0 fail`
- [ ] `git status` 只有声明的 4 个路径
- [ ] PR 描述里贴 B/C/D/E/F 的实际输出

## 参考

- 现有实现：`project.sh`（`config`/`doctor`/`image`/`test`/`report` 已在）
- 容器入口契约：`scripts/container.sh` 的 `usage()` 与 `docs/container.md`
- 分支约定：`docs/branching.md`
- 报告契约：`scripts/report.sh` 的 `usage()`（`report <release|all> [--variant V]`）
- 需求原文段落：§4.1（目录与入口）、§6（三层报告）、§7.1 第 3 项
