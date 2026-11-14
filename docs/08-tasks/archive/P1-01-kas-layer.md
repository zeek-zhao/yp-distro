# P1-01 · kas 层落地（静态段）：15 个 yml + 无 clone 校验器

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P1-01` |
| 里程碑 | `v0.2.0` |
| 分支 | 已切到 `feat/P1-01-kas-layer`（从 `dev` 切出，见 `docs/06-process/branching.md`） |
| 关联 Issue | `#17`（本卡只做其中的静态段；`kas lock`/真检出见 P1-02） |
| 依赖 | #14 已关闭（GHCR 镜像含 kas 4.6）；本卡**不依赖** dev 镜像已装 kas |
| 预计改动文件 | 见「文件清单」，**不得超范围** |

## 背景

P0 已全部关闭（`dev` = `main` = `5d9ffad`，BATS 68 ok）。现在要把「4 版本 × 2 variant」的**检出 / layers / conf 生成**从自研脚本迁到 kas（决策 C36–C40，设计见 OB 的 `Yocto-多版本工程-kas设计.md`）。本卡只做**配置面与 L1 静态校验**，不 clone 任何上游仓库。

## 已实测的事实（**不要重新试错，直接按这个做**）

以下全部在构建机的 `ghcr.io/zeek-zhao/yp-distro/scarthgap:5.0` 镜像里实测过（kas 4.6）：

1. **`kas` 没有 `validate` 子命令。** 子命令只有 `build / checkout / dump / for-all-repos / lock / shell / menu`。
2. **`kas dump` 无法在 L1 用。** 9 个 step 全 `--skip` 也会崩：`KeyError: 'header'`（`kas/plugins/dump.py:240`）。带 repos 时则必然 clone。
3. **`kas lock` 必然要网络**（要 fetch 出 SHA）→ 本卡不做。
4. **正解是 `kas.includehandler.IncludeHandler`** —— 纯解析 + **自带 JSON-schema 校验**，不 clone、不联网：
   ```python
   from kas.includehandler import IncludeHandler
   h = IncludeHandler([target_yml], repo_root, use_lock=False)
   cfg, missing_repos = h.get_config()   # cfg 是合并后的 dict
   ```
   非法结构会直接抛 `IncludeException`（实测：`layers: {meta: {}}` 被判非法）。
5. **`layers` 的值必须写 `null`，不能写 `{}`。** 正确写法：
   ```yaml
   layers:
     meta:
     meta-poky:
   ```
   写成 `meta: {}` → schema 拒绝。
6. **`layers` 的 key 就是相对仓库根的路径**，所以本仓库的 layer 可以这样取（已实测通过）：
   ```yaml
   repos:
     yp:
       url: https://github.com/zeek-zhao/yp-distro
       tag: main
       layers:
         layers/meta-yp:
   ```
   **不要**用 `path:` + `layers: {.: null}`（设计文档的旧写法，已验证不必要）。
7. **`repos.<name>: null` 不是"删除父层仓库"。** schema 语义是「把**当前配置文件所在仓库**命名为 `<name>` 并作为 layer 加入」—— 用它来"删掉 base 里的 poky"会得到一个语义错误的配置。
8. **include 路径基准是仓库根**（`os.path.join(repo_root, include)`），找不到才回退到「当前文件所在目录」。所以 `kas/targets/*.yml` 里统一写 `kas/base.yml` 这种**相对仓库根**的路径。
9. **深合并、后者覆盖前者**；同一 key 的 dict 会递归合并，不会整体替换。

> 因为第 7 条，**设计文档 §4.1「只在 base.yml 定义 poky」的做法作废**。本卡改用：`base.yml` 不定义任何 `repos`，每个 `releases/*.yml` 自己定义 repo（见下）。

## 设计（已定稿，照做）

### 目录与文件（15 个 yml）

```
kas/
├── base.yml                        # header + machine + distro + target + local_conf_header（不含 repos）
├── releases/dunfell.yml            # include base + repos.poky (tag yocto-3.1.33)
├── releases/kirkstone.yml          # 同上 (yocto-4.0.35)
├── releases/scarthgap.yml          # 同上 (yocto-5.0.20)
├── releases/wrynose.yml            # include base + 三仓库（oe-core / bitbake / meta-yocto，均 yocto-6.0.4）
├── variants/general.yml            # distro=poky / target=core-image-minimal
├── variants/custom.yml             # distro=yp / target=yp-image + repos.yp + custom local_conf
├── machines/qemux86-64.yml         # machine=qemux86-64 + QEMU 相关 local_conf
└── targets/{dunfell,kirkstone,scarthgap,wrynose}-{general,custom}.yml   # 8 个，只有 include 列表
```

### `kas/base.yml`

```yaml
header:
  version: 14

machine: qemux86-64
distro: poky
target: core-image-minimal

local_conf_header:
  base: |
    CONF_VERSION = "2"
    PACKAGE_CLASSES = "package_rpm"
    INHERIT += "rm_work"
    DL_DIR = "${TOPDIR}/../downloads"
    SSTATE_DIR = "${TOPDIR}/../sstate"
```

- **不写 `repos`**（见实测第 7 条）。
- 不要用 `${KAS_RELEASE}` 这种未定义变量（kas 不提供它）。按 release 分 sstate 属 #23 缓存卡，本卡不做。

### `kas/releases/<r>.yml`（四版同构）

```yaml
header:
  version: 14
  includes:
    - kas/base.yml

repos:
  poky:
    url: https://git.yoctoproject.org/poky
    tag: yocto-5.0.20
    layers:
      meta:
      meta-poky:
```

- tag 从 `config/<r>.env` 的 `POKY_TAG` 抄（dunfell `yocto-3.1.33` / kirkstone `yocto-4.0.35` / scarthgap `yocto-5.0.20`）。
- `url` 从 `config/<r>.env` 的 `POKY_REPO` 抄。

### `kas/releases/wrynose.yml`

```yaml
header:
  version: 14
  includes:
    - kas/base.yml

repos:
  openembedded-core:
    url: https://git.openembedded.org/openembedded-core
    tag: yocto-6.0.4
    layers:
      meta:
  bitbake:
    url: https://git.openembedded.org/bitbake
    tag: yocto-6.0.4
  meta-yocto:
    url: https://git.yoctoproject.org/meta-yocto
    tag: yocto-6.0.4
    layers:
      meta-poky:
```

- 三仓库的 url/tag 全部从 `config/wrynose.env` 的 `OE_CORE_REPO/OE_CORE_TAG/BITBAKE_REPO/BITBAKE_TAG/META_YOCTO_REPO/META_YOCTO_TAG` 抄。
- **不写 `poky: null`**（实测第 7 条）。

### `kas/variants/custom.yml`

```yaml
header:
  version: 14

distro: yp
target: yp-image

repos:
  yp:
    url: https://github.com/zeek-zhao/yp-distro
    tag: main
    layers:
      layers/meta-yp:

local_conf_header:
  custom: |
    YP_VARIANT = "custom"
    INHERIT += "cve-check"
    require conf/multilib.conf
    MULTILIBS = "multilib:lib32"
    DEFAULTTUNE:virtclass-multilib-lib32 = "x86"
```

- 变量名用 **`YP_VARIANT`**（C42 命名），不要用设计文档里的 `ZEEK_VARIANT`。
- `distro: yp` / `target: yp-image` 要与 `config/variants/custom.env` 的 `DISTRO`/`IMAGE` 一致。
- `tag: main` 是因为 layer 就在本仓库；P1-02 会改成具体 commit。

### `kas/variants/general.yml`

```yaml
header:
  version: 14

distro: poky
target: core-image-minimal
```

### `kas/machines/qemux86-64.yml`

```yaml
header:
  version: 14

machine: qemux86-64

local_conf_header:
  qemu: |
    QB_MEM = "-m 1024"
```

### `kas/targets/<release>-<variant>.yml`（8 个，形状完全一样）

以 `scarthgap-custom.yml` 为例：

```yaml
header:
  version: 14
  includes:
    - kas/base.yml
    - kas/releases/scarthgap.yml
    - kas/machines/qemux86-64.yml
    - kas/variants/custom.yml
```

`-general` 版本把最后一行换成 `kas/variants/general.yml`。

## 校验器：`scripts/kas-verify.py`

**这是本卡的技术核心。** 要求**双引擎**，因为 dev 镜像当前**还没有装 kas**（本卡只改 Dockerfile、不重建镜像）：

| 引擎 | 条件 | 合并逻辑来源 |
|---|---|---|
| `kas` | `import kas.includehandler` 可用 | 调 `IncludeHandler([yml], repo_root, use_lock=False).get_config()`，**自带 JSON-schema 校验** |
| `builtin` | kas 包不可用 | 自己实现（规则见下） |
| `auto`（默认） | 有 kas 用 kas，否则 builtin | — |

- 用法：
  ```
  python3 scripts/kas-verify.py                              # auto，校验全部 8 个 target
  python3 scripts/kas-verify.py --engine builtin             # 强制内置实现
  python3 scripts/kas-verify.py --release R --variant V      # 只校验一个
  python3 scripts/kas-verify.py --root DIR                   # 换仓库根（BATS 用临时副本时必需）
  ```
- 启动时打印一行 `engine=builtin` 或 `engine=kas`（BATS 会检查）。

### `builtin` 引擎必须复刻的合并规则（从 kas 4.6 源码读出，**不要自己发挥**）

1. **include 路径解析**：先试 `os.path.join(repo_root, inc)`；该路径不存在时回退 `os.path.join(os.path.dirname(当前文件), inc)`；两者都不存在 → 报错退出。
2. **合并顺序**：深度优先，按 `header.includes` 列表顺序依次展开，**最后合并文件自身内容**；冲突时**后者覆盖前者**。
3. **dict 深合并**：两边都是 mapping → 递归合并；否则（含 `None`、列表、标量）**直接覆盖**。
4. **`repos.<id>: null` 保留为 `None`**（不要删除 key）——与 kas 的 schema 语义保持一致。
5. **字段白名单校验**（等价于 kas 的 schema 收紧版）：
   - 顶层只允许：`header / machine / distro / target / repos / local_conf_header / bblayers_conf_header / env / defaults / overrides / build_system / task / proxy_config / menu_configuration / artifacts`
   - `repos.<id>` 只允许：`name / url / type / commit / branch / tag / refspec / path / layers / patches`
   - `layers` 的值只允许 `null / str / int / bool`（**写 `{}` 必须报错**，这是实测过的真实坑）
6. 任一环节失败 → 打印 `FAIL <target>: <原因>`，最终 `exit 1`。
- 对每个 target 断言（任一失败 → 打印 `FAIL <target>: <原因>` 并最终 `exit 1`）：
  1. `IncludeHandler(...).get_config()` 不抛异常（含 kas 的 schema 校验）
  2. `distro` 与 `config/variants/<v>.env` 的 `DISTRO` 一致
  3. `target` 与 `config/variants/<v>.env` 的 `IMAGE` 一致
  4. `machine` 与 `config/machines/qemux86-64.env` 的 `MACHINE` 一致
  5. **repo 集合与 release 的 `REPO_MODE` 一致**：`poky` 模式 = 恰好 `{poky}`；`split` 模式 = 恰好 `{openembedded-core, bitbake, meta-yocto}`。
  6. **双轨 tag 一致性（防漂移，C37）**：每个 repo 的 `tag` 必须等于 `config/<r>.env` 里对应的 `POKY_TAG` / `OE_CORE_TAG` / `BITBAKE_TAG` / `META_YOCTO_TAG`。
  7. custom variant 额外要求：存在 repo `yp`，其 `layers` 恰好含 key `layers/meta-yp`。
  8. 每个 yml 的 `header.version` == 14。
- 成功输出一行汇总：`8 targets OK`（BATS 会断言这行）。
- `repo_root` 用脚本自身位置推导（`Path(__file__).resolve().parents[1]`），不依赖 cwd。
- 脚本要被 `shellcheck` 关掉（它是 Python，不受影响），但**必须通过 `scripts/ci/lint.sh` 的 python 段**（若有；若无则忽略）。

## 文件清单（只允许动这些）

| 路径 | 动作 |
|---|---|
| `kas/base.yml` | 新增 |
| `kas/releases/{dunfell,kirkstone,scarthgap,wrynose}.yml` | 新增（4 个） |
| `kas/variants/{general,custom}.yml` | 新增（2 个） |
| `kas/machines/qemux86-64.yml` | 新增 |
| `kas/targets/{dunfell,kirkstone,scarthgap,wrynose}-{general,custom}.yml` | 新增（8 个） |
| `scripts/kas-verify.py` | 新增（双引擎校验器） |
| `tests/bats/05_kas.bats` | 新增（tag = `kas`） |
| `config/features.txt` | 追加一行 |
| `project.sh` | 新增 `kas` 子命令 |
| `Makefile` | `PROJECT_TARGETS` 加 `kas` |
| `docs/03-build/kas.md` | 新增（把本卡的设计落成文档） |
| `docs/03-build/cli.md` | 追加 `kas` 子命令条目 |
| `docker/dev/Dockerfile` | 加 kas 4.6 层（见下） |
| `README.md` | 仅在命令清单里补 `make kas`（若无该清单则不动） |

## `docker/dev/Dockerfile` 的改动

在 **apt 层之后、`/etc/yocto-dev-versions` 指纹层之前**（建议紧接现有第 4 节 Python 质量工具之后）加：

```dockerfile
###############################################################################
# 4b. kas —— Yocto 配置层工具（仅用于 kas/*.yml 的静态解析校验，不跑 bitbake）
#     ubuntu 24.04 是 PEP668 受管环境；以 root 装到 /usr/local/bin
###############################################################################
ARG KAS_VERSION=4.6
RUN python3 -m pip install --no-cache-dir --break-system-packages -i "${PIP_INDEX}" \
        "kas==${KAS_VERSION}" \
    && kas --version
```

并在指纹层里追加一行（与现有 `printf` 风格一致）：

```dockerfile
        printf 'kas=%s\n'        "$(kas --version | awk '{print $2}')"; \
```

- `ARG KAS_VERSION=4.6` 要放在文件顶部的「工具版本」区，与其它 `ARG` 并列（不要写在层中间）。
- **本卡不重建镜像**（`scripts/dev.sh --build` 由人工在 P1-02 前执行）。BATS 只做 Dockerfile 文本断言，**不要**写「镜像里必须能跑 kas」的运行时用例。

## `tests/bats/05_kas.bats`（tag = `kas`）

每个用例都要 `# bats test_tags=kas`。至少覆盖：

1. `kas/` 下恰好 15 个 `.yml`，且 8 个 `targets/*.yml` 文件名与 4×2 矩阵一一对应
2. **校验器全绿**：`run python3 scripts/kas-verify.py --engine builtin` → `status == 0` 且输出含 `8 targets OK`
3. **双轨漂移会被抓到**：把 `kas/` 与 `config/` 复制到 `$BATS_TEST_TMPDIR`，用 `sed` 改坏某个 `releases/*.yml` 的 tag，再以该临时目录为 root 跑内置引擎（校验器需要支持 `--root DIR` 参数指向临时根），断言 rc != 0 且输出含 `FAIL`。**这条必须真测**（防校验器写成永远返回 0 的空壳）。
4. 所有 yml 的 `header.version` 都是 14（`grep -L` 风格或 python 一行）
5. `base.yml` **不含** `repos:` 段落（防回退到已作废设计）
6. `releases/wrynose.yml` 不含 `poky:`，且含 `openembedded-core` / `bitbake` / `meta-yocto` 三个 repo
7. `variants/custom.yml` 用 `YP_VARIANT`，且 `grep -c ZEEK_VARIANT` 为 0
8. `docker/dev/Dockerfile` 含 `kas==${KAS_VERSION}`（文本断言）与指纹行 `kas=`
9. `Makefile` 的 `PROJECT_TARGETS` 含 `kas`；`project.sh` 的 usage 含 `kas`
10. `config/features.txt` 有 `kas-layer` 行且 bats 文件/tag 与实际一致

## `config/features.txt` 追加行

```
kas-layer | all | tests/bats/05_kas.bats | kas
```

（四列：能力 ID | 适用 release | bats 文件 | bats tag，tag 必须与文件内 `test_tags` 一致。不追加 → `99_coverage.bats` 必红。）

## `project.sh` 的 `kas` 子命令

- `./project.sh kas` → 在容器内跑 `python3 scripts/kas-verify.py`（即 `scripts/dev.sh python3 scripts/kas-verify.py`）
- `./project.sh kas --release R --variant V` → 透传两个参数给校验器
- 沿用现有框架：`usage()` 里加一行说明、`command_usage()` 加分支、`OPT_RELEASE`/`OPT_VARIANT` 复用现有解析、`case "${COMMAND_NAME}"` 里加分支。
- `Makefile`：`PROJECT_TARGETS` 列表加 `kas`，并加 `kas:` 目标 `./project.sh kas`。**不要**手写 `.PHONY`（现有是 `$(PROJECT_TARGETS)` 变量展开）。

## 不要做的事

- **不改** `layers/meta-yp/**`（legacy 冒号 override 整改属 P1-03，本卡不动）
- **不跑** `kas checkout` / `kas dump` / `kas lock`（要 clone，属 P1-02）
- **不重建** dev 镜像（`scripts/dev.sh --build` 需人工执行）
- 不改 `config/*.env`（取值只读不写）
- 不改 `.github/workflows/**`
- 不改 `docs/` 下除 `kas.md`/`cli.md` 之外的文档
- 不新增 `scripts/source.sh`（C40 已取消该脚本）

## 环境铁律（违反即返工）

1. **所有验收命令经 `scripts/dev.sh` 在容器内执行**（CI 与派单同环境）。
2. `set -o pipefail` 下不要用 `printf | grep -q` 做断言，先存变量再判断。
3. 新增 `.py` 必须能被 `python3 -m py_compile` 通过；新增 `.bats` 必须过 `shfmt -i 4 -ci`（`scripts/ci/lint.sh` 会查）。
4. 新 BATS 文件必须被 `config/features.txt` 引用。
5. 提交信息用 Conventional Commits，中文正文；**多行 message 必须 `git commit -F -` 从 stdin 读**，禁止内联 `-m "a\nb"`（会写进字面 `\n`）。

## 验收标准

### A. 静态门禁

```bash
bash scripts/dev.sh bash scripts/ci/lint.sh          # 全 ok
bash scripts/dev.sh bash scripts/ci/secret-scan.sh   # clean
```

### B. 结构与数量

```bash
test "$(find kas -name '*.yml' | wc -l)" -eq 15
test "$(find kas/targets -name '*.yml' | wc -l)" -eq 8
test -f scripts/kas-verify.py
test -f docs/03-build/kas.md
```

### C. 校验器（本卡核心）

```bash
bash scripts/dev.sh python3 scripts/kas-verify.py
# 期望 rc=0，含 "engine=builtin"（镜像未装 kas）与 "8 targets OK"

bash scripts/dev.sh python3 scripts/kas-verify.py --engine builtin
# 期望 rc=0，"8 targets OK"

bash scripts/dev.sh python3 scripts/kas-verify.py --release wrynose --variant custom
# 期望 rc=0
```

> 若镜像里已有 kas（P1-02 之后），`auto` 会自动打印 `engine=kas`，两种引擎结论必须一致。

### D. 双轨一致性（人工抽查，与校验器互为印证）

```bash
grep -q 'tag: yocto-6.0.4' kas/releases/wrynose.yml
grep -q 'tag: yocto-5.0.20' kas/releases/scarthgap.yml
grep -q 'tag: yocto-4.0.35' kas/releases/kirkstone.yml
grep -q 'tag: yocto-3.1.33' kas/releases/dunfell.yml
grep -q 'layers/meta-yp:' kas/variants/custom.yml
grep -c 'ZEEK_VARIANT' kas/variants/custom.yml || true   # 期望 0（grep 无匹配 rc=1）
```

### E. 已作废设计未回退

```bash
# base.yml 不含 repos
! grep -q '^repos:' kas/base.yml
# wrynose 不写 poky: null
! grep -q 'poky:' kas/releases/wrynose.yml
```

### F. CLI 面

```bash
bash scripts/dev.sh ./project.sh kas
# 期望 rc=0，输出 8 targets OK
bash scripts/dev.sh make kas
# 期望同上
bash scripts/dev.sh ./project.sh kas --release dunfell --variant general
# 期望 rc=0
bash scripts/dev.sh ./project.sh doctor
# 期望 8 行组合（doctor 未改动，仅回归）
```

### G. BATS 全量

```bash
bash scripts/dev.sh bats tests/bats/
```

期望：总数 ≥ 68 + 本卡新增（≥10），`0 not ok`、`0 skip`。

```bash
bash scripts/dev.sh bats --filter-tags kas tests/bats/
bash scripts/dev.sh bats tests/bats/99_coverage.bats
```

### H. 工作区洁净

```bash
git status --short
# 期望只出现「文件清单」里列出的路径
```

## 完成定义（DoD）

- [ ] A–H 全部 rc=0
- [ ] `python3 scripts/kas-verify.py --engine builtin` 输出 `8 targets OK`
- [ ] 15 个 yml 全部通过内置引擎的结构校验；`auto` 在无 kas 时自动降级并打印 `engine=builtin`
- [ ] 校验器不是空壳：BATS 里「改坏 tag → rc != 0」的用例真测过
- [ ] `base.yml` 无 `repos:`；`wrynose.yml` 无 `poky:`；`custom.yml` 用 `YP_VARIANT`
- [ ] 8 个 target 的 include 列表都指向 `kas/...` 相对仓库根路径
- [ ] `config/features.txt` 有 `kas-layer` 行，`99_coverage.bats` 全绿
- [ ] BATS ≥ 78、`0 not ok`、`0 skip`
- [ ] `docs/03-build/kas.md` 记录本卡的 9 条实测事实与两处设计修正（`poky: null` 作废、`layers: {}` 作废）
- [ ] `docker/dev/Dockerfile` 含 kas 层与指纹行（**未重建镜像**，在 PR 描述里注明留给 P1-02）
- [ ] PR 描述贴 A/C/F/G 实际输出

## 参考

- 需求：`40-项目/YP/Yocto-多版本工程需求.md` §14.1（C36–C40）
- 设计：`40-项目/YP/Yocto-多版本工程-kas设计.md`（§4.1/§4.3/§4.5 的三处写法以本卡「已实测的事实」为准）
- 配置面：`config/{dunfell,kirkstone,scarthgap,wrynose}.env`、`config/variants/*.env`、`config/machines/qemux86-64.env`
- 命名：`docs/02-development/naming.md`（C42：layer `meta-yp` / distro `yp` / 镜像 `yp-image`）
- 分支：`docs/06-process/branching.md`（C41）
- 现有 layer：`layers/meta-yp/conf/layer.conf`（`LAYERSERIES_COMPAT_meta-yp` 已含四版）
- 现有 BATS 风格参考：`tests/bats/04_layer.bats`
