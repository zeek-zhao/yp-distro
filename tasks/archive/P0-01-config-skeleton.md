# P0-01 配置骨架与统一入口

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-01` |
| 里程碑 | `v0.1.0` |
| 依赖 | 无 |
| 预计改动文件 | `config/*.env`、`config/variants/*.env`、`config/machines/*.env`、`config/features.txt`、`scripts/lib/log.sh`、`scripts/lib/common.sh`、`project.sh`、`Makefile` |

## 背景

需求 §2（版本锁）、§4（工程结构）、§4.1（目录与磁盘模型）、§4.2（variant 定义）。
后续所有脚本（`source.sh` / `build.sh` / `report.sh`）都只从 `config/` 读参数，所以配置 schema 必须先定死，否则后面每加一个脚本都要改参数解析。

**本任务只做「配置 + 入口骨架」，不碰 docker、不做真实下载、不动 `meta-zeek/`。**

## 要做的事

### 1. 四份 release 配置 `config/<release>.env`

字段严格按需求 §2，取值**必须**用下面这些实测值，不得自行改成别的 tag：

| 文件 | 必含字段 |
|---|---|
| `config/dunfell.env` | `RELEASE=dunfell` / `REPO_MODE=poky` / `POKY_REPO=https://git.yoctoproject.org/poky` / `POKY_TAG=yocto-3.1.33` / `EXPECT_SHA=63d05fc0...` |
| `config/kirkstone.env` | 同上，`POKY_TAG=yocto-4.0.35` |
| `config/scarthgap.env` | 同上，`POKY_TAG=yocto-5.0.20` |
| `config/wrynose.env` | `REPO_MODE=split` + `OE_CORE_REPO`/`OE_CORE_TAG`、`BITBAKE_REPO`/`BITBAKE_TAG`、`META_YOCTO_REPO`/`META_YOCTO_TAG` 各 `yocto-6.0.4` |

- `EXPECT_SHA` 用需求 §2 表里的 40 位（`scripts/source.sh` 后续版本用它做一致性校验，本任务只放值不校验）。
- 每份文件顶部写 3 行注释：release / Yocto 系列版本 / 对应 Ubuntu base（dunfell→20.04、kirkstone→22.04、scarthgap→24.04、wrynose→24.04）。
- 文件是 **bash 可 source 的纯赋值**，不要写 `export`，不要有逻辑。

### 2. variant 与 machine 配置

- `config/variants/general.env`：`VARIANT=general` / `DISTRO=poky` / `IMAGE=core-image-minimal` / `CUSTOM_HOSTNAME=0` / `ENABLE_CVE_CHECK=0` / `ENABLE_MULTILIB=0`
- `config/variants/custom.env`：`VARIANT=custom` / `DISTRO=zeek-distro` / `IMAGE=core-image-zeek` / `CUSTOM_HOSTNAME=1` / `ENABLE_CVE_CHECK=1` / `ENABLE_MULTILIB=1`
- `config/machines/qemux86-64.env`：`MACHINE=qemux86-64` / `QEMU_SSH_PORT=2222`
- 严格按需求 §4.2 的表，多一个字段都不要加。

### 3. `config/features.txt`

格式：每行 `能力标识|适用release(逗号分隔或 all)|对应测试文件|阶段`，`#` 开头为注释。
先只列 P0 的 5 项能力（对应需求 §3 能力矩阵标 P0 的行）：

```
# 能力标识|适用release|测试文件|阶段
version-lock-dual-mode|all|tests/bats/02_source.bats|P0
entry-unified|all|tests/bats/00_project.bats|P0
dockerfile-static|all|tests/bats/01_dockerfile.bats|P0
bats-report|all|tests/bats/03_report.bats|P0
ci-l1-l2|all|tests/bats/04_ci.bats|P0
```

> 测试文件此时还不存在，`99_coverage.bats` 是后续 P0-02 的任务，**本任务不要创建 tests/**。

### 4. `scripts/lib/log.sh` 与 `scripts/lib/common.sh`

`log.sh`：

- `log_info` / `log_warn` / `log_error` / `die`
- 遵守 `NO_COLOR` 与「非 TTY 不出颜色」
- `die` 必须 `exit 1`

`common.sh`（source `log.sh`）：

- `ROOT_DIR` 由脚本自身位置推导（不依赖调用者 cwd）
- `load_release <name>`：source `config/<name>.env`，文件不存在则 `die`
- `load_variant <name>`、`load_machine <name>`：同上
- `resolve_all <release> <variant> <machine>`：依次加载三者，导出统一变量：
  `RELEASE` `REPO_MODE` `TAG`（poky 模式下 = `POKY_TAG`）`VARIANT` `DISTRO` `IMAGE` `MACHINE`
- `work_dir <kind> [release]`：返回需求 §4.1 的目录，`kind ∈ src|build|downloads|sstate|artifacts|lock`
- `check_disk_watermark <pct=85>`：`df` 检查 `work/` 所在分区，超阈值返回非 0 并打印清理提示（C23）

### 5. `project.sh`

- 用法：`./project.sh <cmd> [--release R] [--variant V] [--machine M]`
- 本任务**只实现**两个子命令：
  - `config`：打印 `resolve_all` 后的全部变量（`KEY=VALUE`，按字母序），缺参则 `die`
  - `doctor`：打印 4 release × 2 variant 的组合表（`release variant repo_mode distro image` 列）+ 磁盘水位
- 其余子命令（`image|source|build|qemu|review|test|report|e2e`）**只做占位**：打印 `not implemented yet: <cmd>` 并 `exit 2`
- `--help` 打印用法与上述子命令列表

### 6. `Makefile`

薄封装，只转发：`make <target>` → `./project.sh <target>`，另加 `make help`（列出 target）。
Makefile 里不许写业务逻辑（需求 §9 第 7 条「本地与 CI 等价」）。

## 不要做的事

- **不要创建 `tests/`、`docker/`、`layers/`** —— 属于 P0-02 / P0-03
- **不要改 `meta-zeek/`** 下任何文件
- **不要改 `scripts/dev.sh`、`scripts/wf3.sh`、`tasks/`**
- 不要引入任何新依赖（只允许 bash 内置 + coreutils + `df`）
- 不要实现 `source.sh` / `build.sh`，也不要在本任务里执行任何网络下载
- 不要 `git commit`（由 WorkBuddy 验收后提交）

## 验收标准

全部在 dev 容器内执行：

```bash
# 1. 静态检查必须零告警
bash scripts/dev.sh shellcheck -S warning scripts/lib/log.sh scripts/lib/common.sh project.sh
bash scripts/dev.sh shfmt -d -i 4 -ci scripts/ project.sh

# 2. 四份 release 配置都能加载，且 tag 与需求 §2 一致
bash scripts/dev.sh bash -c '
  source scripts/lib/common.sh
  for r in dunfell kirkstone scarthgap wrynose; do
    load_release "$r" || exit 1
    printf "%s %s %s\n" "$RELEASE" "$REPO_MODE" "${POKY_TAG:-${OE_CORE_TAG}}"
  done
'
# 期望输出正好四行：
#   dunfell poky yocto-3.1.33
#   kirkstone poky yocto-4.0.35
#   scarthgap poky yocto-5.0.20
#   wrynose split yocto-6.0.4

# 3. 正例：custom variant 解析出独立 distro
bash scripts/dev.sh ./project.sh config --release wrynose --variant custom --machine qemux86-64
# 期望包含 DISTRO=zeek-distro、IMAGE=core-image-zeek、REPO_MODE=split

# 4. 负例：不存在的 release 必须非 0 退出
bash scripts/dev.sh ./project.sh config --release bogus; echo "exit=$?"
# 期望 exit 非 0，且有清晰报错

# 5. doctor 列出 8 个组合
bash scripts/dev.sh ./project.sh doctor | grep -c -E '^(dunfell|kirkstone|scarthgap|wrynose) '
# 期望 8

# 6. 未实现子命令按约定退出 2
bash scripts/dev.sh ./project.sh build --release wrynose; echo "exit=$?"
# 期望 exit=2，输出含 not implemented
```

- [ ] 上述 6 组命令全部符合期望
- [ ] `git status --short` 只出现「预计改动文件」里列的文件
- [ ] `config/*.env` 内无 `export`、无逻辑语句（`grep -c '^export' config/*.env` 全 0）

## 参考

- 需求 `40-项目/YP/Yocto-多版本工程需求.md` §2 / §4 / §4.1 / §4.2 / §9
- 参考工程 `D:\zeek\work\repo\project\poky\scripts\conf\variant\*.conf`（variant 配置的写法风格）
- 参考工程 `D:\zeek\work\repo\project\poky\tests\bats\setup.bash`（`_detect_poky_root` 推导 ROOT_DIR 的写法可借鉴）
