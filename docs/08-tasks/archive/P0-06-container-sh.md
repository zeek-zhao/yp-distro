# P0-06 · scripts/container.sh（命名 / 非 root / UID 映射 / 磁盘落点）

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-06` |
| 里程碑 | `v0.1.0` |
| 分支 | `feat/P0-06-container-sh`（从 `dev` 切出） |
| 关联 Issue | #10（磁盘策略部分同 #16） |
| 依赖 | 已完成：#6 构建镜像、#7 BATS 骨架、#8 CI |
| 预计改动文件 | `scripts/container.sh`（新增）、`tests/bats/03_container.bats`（新增）、`config/features.txt`（加一行）、`scripts/dev.sh`（加 `-e WB_HOST_REPO_DIR`）、`scripts/image.sh`（加 build label）、`docs/03-build/container.md`（新增）、`README.md`（目录树加一行） |

## 背景

`scripts/dev.sh` 解决「开发容器」，本卡解决「**构建容器**」：进到某个 release 的工具链镜像里干活（`kas`/`bitbake` 都在镜像里，见 #14/#15 已补齐）。它是后续 `project.sh shell` / `project.sh build`（#9）与 P1 真实构建的唯一入口。

需求依据：§4.1（磁盘模型）、§7.1-7、C22/C23/C35。

## 现状（`79705d0` 之后，可直接读代码确认）

- `scripts/lib/common.sh` 提供：`load_release <r>`、`load_variant <v>`、`load_machine <m>`、`resolve_all <release> <variant> <machine>`（导出 `RELEASE REPO_MODE TAG VARIANT DISTRO IMAGE MACHINE`）、`work_dir <kind> [release]`（kind ∈ `src|build|artifacts|lock|downloads|sstate`）、`check_disk_watermark [pct]`（打印 `Disk usage: N%`，超阈值返回 1）。
- `scripts/lib/log.sh` 提供 `log_info/log_warn/log_error/die`。
- `scripts/image.sh` 的 `image_name <release>` 输出 `ghcr.io/zeek-zhao/yp-distro/<release>`，本地已构建的 tag 是 **`:local`**（4 个 release 都有），远端公开 tag 是 `:latest`。
- `scripts/dev.sh` 有 `in_dev_container()`（判 `/.dockerenv` + `/work` + PWD 前缀）与 `build_run_args()`（生成 `RUN_ARGS`）。
- `config/variants/general.env`：`DISTRO=poky`、`IMAGE=core-image-minimal`；`config/variants/custom.env`：`DISTRO=yp`、`IMAGE=yp-image`（C42 命名，见 `docs/02-development/naming.md`）。
- `config/machines/` 下有 machine env（如 `qemux86-64`）。

## 要做的事

### 1. 新增 `scripts/container.sh`

CLI（两种写法都要支持）：

```
scripts/container.sh --release <r> [--variant <v>=general] [--machine <m>=qemux86-64] [--check | --dry-run] [-- <cmd>...]
```

行为：

| 项 | 要求 |
|---|---|
| 命名 | 容器名 `yocto-<release>-<variant>`（加 `-<machine>` 后缀会破坏 `docker ps` 可读性则不作为容器名，machine 只进标签 `yocto.machine=<m>`） |
| 用户 | `--user $(id -u):$(id -g)`；**禁止 root**；容器内 `HOME=/work/work/home/<release>`（可写，挂在 `/home` 分区） |
| 镜像 | 优先 `$(image_name <r>):local`；不存在则 `:latest` 并 `docker pull`；都没有 → `die` 并提示 `scripts/image.sh build <release>` |
| 仓库挂载 | `${HOST_REPO_DIR}:/work`（`HOST_REPO_DIR="${WB_HOST_REPO_DIR:-${ROOT_DIR}}"`，见第 4 条） |
| 构建目录 | `--workdir /work`，并把 `work/{src,build,artifacts,downloads,sstate}` 显式落到 `/home` 分区（即仓库内 `work/`，**不得**用 `/tmp`、`${HOME}/.cache` 或容器可写层） |
| DL/SSTATE | 通过 `-e DL_DIR=/work/work/downloads -e SSTATE_DIR=/work/work/sstate` 显式传入，**禁止**依赖镜像默认值 |
| 磁盘水位 | 起容器**前**调 `check_disk_watermark "${WATERMARK_PCT:-85}"`；失败即 `die` 且提示「清理 `work/` 或调整 WATERMARK_PCT」，**不得**启动容器 |
| docker socket | 与 `dev.sh` 一致：宿主有 socket 就挂进去（`--group-add`），容器内可直接 `docker` 干活 |
| 嵌套 | 检测到 `in_dev_container` 时**不套第二层挂载**：仍调宿主 docker（socket 已挂），但挂载源用 `WB_HOST_REPO_DIR` 拼绝对路径，避免把容器内 `/work` 当宿主路径挂成空目录 |
| `--check` | 只做前置检查并打印：解析后的 `RELEASE/VARIANT/MACHINE/DISTRO/IMAGE/TAG`、镜像解析结果、宿主 uid/gid、DL_DIR/SSTATE_DIR 绝对路径、磁盘水位行。rc=0 表示可以起容器 |
| `--dry-run` | 打印最终 `docker run` 命令行（**一行一条参数，带换行缩进**，便于 grep 断言），**不执行** |
| 退出码 | `--check`/`--dry-run` 前置不满足 → 非 0；带 `-- <cmd>` 时透传 cmd 的退出码 |
| 帮助 | `-h/--help` 打印用法，rc=0 |

### 2. 更新 `scripts/dev.sh`

在 `build_run_args()` 里加一项（紧跟挂载仓库之后）：

```bash
-e "WB_HOST_REPO_DIR=${ROOT_DIR}"
```

理由：copilot 本身跑在 dev 容器里，它调 `container.sh` 时需要知道**宿主**上仓库的绝对路径才能正确挂载。不改这条，嵌套场景必挂空目录（P0-03 踩过完全相同的坑）。

### 3. 更新 `scripts/image.sh`

`build_image()` 的 `docker build` 增加标签，让清理可定向（#16 待决项）：

```bash
--label project=yocto --label yocto.release=<release>
```

**不要**改 `verify_image()` 的断言逻辑，也不要真的重建镜像（本卡允许 `docker build` 一次做标签验证，但必须自己收尾清理或复用缓存）。

### 4. 新增 `tests/bats/03_container.bats`（tag `container`）

至少 6 个用例，全部**不依赖网络**：

1. `--help` rc=0 且输出含 `--dry-run`；
2. `--check` 对 4 个 release 都 rc=0（镜像 `:local` 都在）；
3. `--dry-run` 输出含 `--name yocto-scarthgap-general`；
4. `--dry-run` 输出含 `--user $(id -u):$(id -g)`，且**不含** `--user 0` / `--privileged`；
5. `--dry-run` 输出里 `DL_DIR` / `SSTATE_DIR` 的路径以 **`/work/work/`** 开头（落 `/home` 分区，不是 `/tmp`、不是容器内 `$HOME`）；
6. `WATERMARK_PCT=1` 时 `--check` 返回非 0，且 stderr/stdout 含 `work/`（可执行提示）；
7. 未知 release（如 `--release foo`）rc 非 0 且提示 release 名。

负向控制必须真跑（例：临时把 `WATERMARK_PCT` 设 1）；用例里**不要**做真实构建、不要 `docker pull`。

### 5. `config/features.txt` 加一行

```
container-runtime | all | tests/bats/03_container.bats | container
```

### 6. 新增 `docs/03-build/container.md`（≤ 60 行）

写清：容器命名规则、UID 映射、DL/SSTATE 落点与磁盘水位、`--check`/`--dry-run` 用法、`#16` 的清理边界（只 `docker image prune --filter label=project=yocto`，**禁止** `-a`，因为构建机是共享 Jenkins 节点）、嵌套场景为什么要 `WB_HOST_REPO_DIR`。

### 7. `README.md` 目录树加一行

`scripts/container.sh  构建容器入口（命名/UID/磁盘落点）`

## 不要做的事

- **不要**改 `docker/*/Dockerfile`、`docker/common/install-yocto-deps.sh`（镜像已定，动它要重跑 4 次构建）；
- **不要**改 `.github/workflows/*`（CI 已定）；
- **不要**引入新依赖（不装 jq/yq，只用 bash + 现有 docker CLI）；
- **不要**改 `config/*.env`、`config/variants/*`、`config/machines/*` 的既有字段值；
- **不要**把 `meta-zeek` / `zeek-distro` / `core-image-zeek` 写进任何新文件（命名已由 C42 定为 `meta-yp` / `yp` / `yp-image`）；
- **不要**跑真实 yocto 构建、不要 `docker pull` 新镜像、不要 `docker system prune`；
- **不要**碰 `docs/08-tasks/` 下历史任务卡。

## 验收标准

```bash
# 门禁不许退（三条都必须全绿）
bash scripts/dev.sh bash scripts/ci/lint.sh          # shellcheck 11+ / shfmt / hadolint 5 / actionlint 3 全 ok
bash scripts/dev.sh bash scripts/ci/secret-scan.sh   # clean
bash scripts/dev.sh bats tests/bats/                 # 0 not ok、0 skip（数量 = 33 + 新增）

# container.sh 自身
bash scripts/container.sh --help                                   # rc=0
for r in dunfell kirkstone scarthgap wrynose; do
  bash scripts/container.sh --release $r --check || exit 1
done
bash scripts/container.sh --release scarthgap --variant general --dry-run | grep -- '--name yocto-scarthgap-general'
bash scripts/container.sh --release scarthgap --variant general --dry-run | grep -- "--user $(id -u):$(id -g)"
WATERMARK_PCT=1 bash scripts/container.sh --release scarthgap --check; echo "expect_nonzero=$?"

# 真起一次容器（:local 镜像本地已有，不联网）
bash scripts/container.sh --release scarthgap --variant general -- bash -lc 'id -u; id -un'
#   期望：第一行 == 宿主 uid，第二行 == builder（≠ root）

# 嵌套场景（copilot 自己就在 dev 容器里，这条必须通）
bash scripts/dev.sh bash scripts/container.sh --release wrynose --variant general -- bash -lc 'id -un; pwd'

# 镜像标签
bash scripts/dev.sh bash scripts/image.sh build scarthgap 2>&1 | tail -3
docker image inspect ghcr.io/zeek-zhao/yp-distro/scarthgap:local --format '{{index .Config.Labels "project"}}'
#   期望输出 project=yocto 对应的值：yocto
```

- [ ] 上面每条命令 rc=0（`WATERMARK_PCT=1` 那条**期望非 0**）
- [ ] `git status` 只包含本卡「预计改动文件」列出的文件
- [ ] `03_container.bats` 用例数 ≥ 6，含负向控制（`WATERMARK_PCT=1`）
- [ ] `git grep -n "meta-zeek\|zeek-distro\|core-image-zeek" -- scripts/ tests/ config/` 无输出

## 参考

- `scripts/dev.sh`（容器参数构造的现成写法，尤其 `build_run_args()` 与 `in_dev_container()`）
- `scripts/lib/common.sh`（`resolve_all` / `work_dir` / `check_disk_watermark` 三个函数直接复用，不要重写）
- 需求 §4.1 磁盘模型的结论：构建产物一律落 `/home`（构建机上 `/home` 余 ~1.2T，`/` 只剩 ~349G）
