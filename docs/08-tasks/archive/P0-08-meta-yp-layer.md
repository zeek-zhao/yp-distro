# P0-08 · meta-yp layer 升级（4 版本 LAYERSERIES_COMPAT + yp distro / yp-image）

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-08` |
| 里程碑 | `v0.1.0` |
| 分支 | 已在 `feat/P0-08-meta-yp-layer`（从 `dev` 切出，见 `docs/06-process/branching.md`） |
| 关联 Issue | `#11` |
| 依赖 | 无（#9 已完成，`project.sh config` 可用） |
| 预计改动文件 | 见下表「文件清单」，**不得超范围** |

## 背景

`layers/meta-yp/` 是 `79705d0`（C42 改名）从老工程的 `meta-zeek/` 迁来的单 distro 骨架：只有
`conf/layer.conf` + 一个 `core-image-minimal.bbappend` + 若干示例 recipe。它现在**只能解析
kirkstone/scarthgap**，且**没有自己的 distro**，因此 custom variant（C27：独立 distro `yp`、
镜像 `yp-image`）在配置面已经写死、在 layer 面还是空的。

本卡只做**结构与静态一致性**：让 layer 在 4 个 release 的 `LAYERSERIES_COMPAT` 上自洽、
distro 与镜像骨架落地、命名与 `docs/02-development/naming.md`（C42）逐项对齐。
**真实 `bitbake -p` 解析不在本卡**（需要 poky 检出，属 P1 kas 卡 #17）。

## 命名（C42，已定死，不许改）

Layer = `meta-yp`（目录 `layers/meta-yp/`）· distro = `yp` · 镜像 = `yp-image` / `yp-image-minimal`。
旧名 `meta-zeek` / `zeek-distro` / `core-image-zeek` 一律不得出现在新增文件里。

## 关键设计决策（照做，不要自己发挥）

1. **自定义 distro 只有 custom variant 用**。`general` variant 走 poky distro + `core-image-minimal`，
   **不会**加载 `layers/meta-yp/conf/distro/`。所以差异隔离文件不叫 `general.inc`，而是：
   - `conf/distro/include/yp-common.inc` —— 共用基线（版本号、维护者、留给后续追加的占位），必须被 `yp.conf` `require`；
   - `conf/distro/include/yp-compat.inc` —— **4 个版本语法差异唯一允许出现的地方**，必须被 `yp.conf` `require`；
   - `yp.conf` 本体里**不许出现条件分支**（`if`/`python`/`@...` 判断）。
2. **本层禁用 override 语法**：`layers/meta-yp/conf/**` 与 `layers/meta-yp/recipes-core/**` 下
   **不许出现** `:append` / `:prepend` / `:remove` / `:${PN}` 这类冒号 override 写法。
   原因：dunfell（3.1）的 bitbake 不识别 `:` override，字符会被当成变量名的一部分。
   只能用 `=` / `+=` / `=+` / `??=`。
3. **不改基线特性**：不要增删 `DISTRO_FEATURES` / `IMAGE_FEATURES` 的 poky 默认值，也不要碰
   `INIT_MANAGER`。wrynose（6.0）移除了 `DISTRO_FEATURES_BACKFILL`、systemd 成了 nodistro 默认 ——
   正因为我们不动基线，这三点自动免疫；把这句话写进 `yp-compat.inc` 的注释。
4. **`core-image-minimal.bbappend` 保留不动**。不要改名为 `yp-image.bbappend`：bbappend 按 `PN` 精确匹配，
   改名后对 `core-image-minimal` 立刻失效（general variant 就丢了 cpp-hello 示例）。`yp-image.bb`
   自己写 `IMAGE_INSTALL`。
5. **`yp-image*.bb` 继承方式**：`require recipes-core/images/core-image-minimal.bb`（oe-core 路径，4 版一致），
   不要复制粘贴 `core-image-minimal` 的内容，也不要 `inherit core-image` 后从零拼（会丢包组依赖）。

## 文件清单（只允许动这些）

| 路径 | 动作 |
|---|---|
| `layers/meta-yp/conf/layer.conf` | 改：`LAYERSERIES_COMPAT_meta-yp` 覆盖四版 |
| `layers/meta-yp/conf/distro/yp.conf` | 新增 |
| `layers/meta-yp/conf/distro/include/yp-common.inc` | 新增 |
| `layers/meta-yp/conf/distro/include/yp-compat.inc` | 新增 |
| `layers/meta-yp/recipes-core/images/yp-image.bb` | 新增 |
| `layers/meta-yp/recipes-core/images/yp-image-minimal.bb` | 新增 |
| `tests/bats/04_layer.bats` | 新增（tag = `layer`） |
| `config/features.txt` | 追加一行（**必须**，见下） |
| `docs/02-development/naming.md` | 只做「与实际文件对齐」的勘误 |

## 要做的事

1. `layer.conf`：`LAYERSERIES_COMPAT_meta-yp = "dunfell kirkstone scarthgap wrynose"`（其余行不动）。
2. `yp.conf`：
   ```
   require conf/distro/poky.conf
   require conf/distro/include/yp-common.inc
   require conf/distro/include/yp-compat.inc

   DISTRO = "yp"
   DISTRO_NAME = "YP (Yocto Platform)"
   DISTRO_VERSION = "0.1.0"
   DISTRO_CODENAME = "yp-phase0"
   ```
   顺序固定：先 `require poky.conf` 再覆盖，最后两个 include 放在覆盖之后（`yp-common.inc` 里要能覆盖版本号）。
3. `yp-common.inc`：`DISTRO_VERSION` / `DISTRO_CODENAME` / `MAINTAINER` 的唯一来源 + 注释说明
   「将来的 DISTRO_FEATURES 增补写在这里，且只能用 `+=`」。
4. `yp-compat.inc`：目前**没有**必需的版本分支 → 文件内容为注释（列出四版差异要点与将来加分支的位置），
   不要写空 `if`，不要写 `python __anonymous()`。
5. `yp-image.bb`：
   ```
   SUMMARY = "YP reference image"
   require recipes-core/images/core-image-minimal.bb
   IMAGE_INSTALL += " virtual/cpp-hello"
   ```
   `yp-image-minimal.bb`：同样 `require`，不加示例包（纯基线镜像）。
6. **`tests/bats/04_layer.bats`**（新文件，每个用例都要 `# bats test_tags=layer`）至少覆盖：
   - `LAYERSERIES_COMPAT_meta-yp` 四值齐全（精确字符串断言）
   - `yp.conf` 存在且 `grep -q '^DISTRO = "yp"'`
   - `yp.conf` 同时 `require` 了两个 include（`yp-common.inc`、`yp-compat.inc`）
   - `yp-image.bb` / `yp-image-minimal.bb` 存在且都 `require recipes-core/images/core-image-minimal.bb`
   - `conf/**` 与 `recipes-core/**` 下无 `:append`/`:prepend`/`:remove`/`:${PN}` override 写法（扫 `layers/meta-yp/conf`、`layers/meta-yp/recipes-core`）
   - `core-image-minimal.bbappend` 仍存在（防误删/误改名）
   - 旧命名零残留：`git grep -n "meta-zeek\|zeek-distro\|core-image-zeek" -- layers config tests docs` 无输出
7. **`config/features.txt` 追加一行**（不追加 `99_coverage.bats` 三条断言必红 → BATS 直接失败）：
   ```
   layer-structure | all | tests/bats/04_layer.bats | layer
   ```
   四列格式：能力 ID | 适用 release | bats 文件 | bats tag，tag 必须与文件内 `# bats test_tags=layer` 一致。
8. `docs/02-development/naming.md`：逐项核对定名表与实际文件；**只改文档不改约定**。若发现约定本身与 C42 冲突，
   在 PR 描述里写清楚，不要擅自改约定。

## 不要做的事

- 不改 `layers/meta-yp/recipes-example/**`（里面的 `FILES:${PN}` 等 override 是老工程带过来的遗留写法，
  统一整改属 P1 #17 的真实解析阶段，本卡不动它 —— 但也**不许**把它的写法抄进新文件）。
- 不改 `docker/**`、`scripts/**`、`project.sh`、`Makefile`、`.github/**`、`config/*.env`。
- 不新增 kas yml（P1 #17 的活）。
- 不增删 `DISTRO_FEATURES` / `IMAGE_FEATURES` 基线，不碰 `INIT_MANAGER`。
- 不试图跑 `bitbake` / `kas`（没有 poky 检出，跑了只会浪费时间）。

## 环境铁律（违反即返工）

1. **所有验收命令必须经 `scripts/dev.sh` 在容器内执行**（CI 与派单同环境）。
2. `set -o pipefail` 下不要用 `printf | grep -q` 做断言，先存变量再判断。
3. 新增/修改的 `.sh`（本卡不含）与新 `.bats` 必须过 `scripts/ci/lint.sh`（shellcheck `-S warning` + shfmt `-i 4 -ci`；`tests/bats/*.bats` 也在 shfmt 范围）。
4. 新 BATS 文件**必须**被 `config/features.txt` 引用，否则 `99_coverage.bats` 三条用例会红。

## 验收标准

### A. 静态门禁

```bash
bash scripts/dev.sh bash scripts/ci/lint.sh          # 四段全 ok
bash scripts/dev.sh bash scripts/ci/secret-scan.sh   # clean
```

### B. 结构与语义断言

```bash
test -f layers/meta-yp/conf/distro/yp.conf
test -f layers/meta-yp/conf/distro/include/yp-common.inc
test -f layers/meta-yp/conf/distro/include/yp-compat.inc
test -f layers/meta-yp/recipes-core/images/yp-image.bb
test -f layers/meta-yp/recipes-core/images/yp-image-minimal.bb
test -f layers/meta-yp/recipes-core/images/core-image-minimal.bbappend

grep -q 'LAYERSERIES_COMPAT_meta-yp = "dunfell kirkstone scarthgap wrynose"' layers/meta-yp/conf/layer.conf
grep -q '^DISTRO = "yp"' layers/meta-yp/conf/distro/yp.conf
grep -q 'require conf/distro/poky.conf' layers/meta-yp/conf/distro/yp.conf
grep -q 'require conf/distro/include/yp-common.inc' layers/meta-yp/conf/distro/yp.conf
grep -q 'require conf/distro/include/yp-compat.inc' layers/meta-yp/conf/distro/yp.conf

grep -q 'require recipes-core/images/core-image-minimal.bb' layers/meta-yp/recipes-core/images/yp-image.bb
grep -q 'require recipes-core/images/core-image-minimal.bb' layers/meta-yp/recipes-core/images/yp-image-minimal.bb
grep -q 'virtual/cpp-hello' layers/meta-yp/recipes-core/images/yp-image.bb
```

### C. override 语法零残留（四版兼容的硬约束）

```bash
# 期望：无输出
grep -rnE ':(append|prepend|remove)\b' layers/meta-yp/conf layers/meta-yp/recipes-core || true
grep -rnE ':[$][{]PN[}]' layers/meta-yp/conf layers/meta-yp/recipes-core || true
```

### D. 旧命名零残留

```bash
git grep -n "meta-zeek\|zeek-distro\|core-image-zeek" -- layers config tests docs || echo "clean"
```

### E. 配置面仍通

```bash
bash scripts/dev.sh ./project.sh config --release wrynose --variant custom --machine qemux86-64
# 期望含：DISTRO=yp / IMAGE=yp-image / REPO_MODE=split
bash scripts/dev.sh ./project.sh doctor
# 期望：8 行组合，rc=0（磁盘水位未超限时）
```

### F. BATS 全量

```bash
bash scripts/dev.sh bats tests/bats/
```

期望：总数 = 56（P0-07 基线）+ 本卡新增（≥8）→ **≥ 64**，`0 not ok`、`0 fail`、`0 skip`。
单独确认覆盖用例：

```bash
bash scripts/dev.sh bats --filter-tags layer tests/bats/
bash scripts/dev.sh bats tests/bats/99_coverage.bats
```

### G. 工作区洁净

```bash
git status --short
# 期望只有：layers/meta-yp/conf/layer.conf、layers/meta-yp/conf/distro/{yp.conf,include/yp-common.inc,include/yp-compat.inc}、
#           layers/meta-yp/recipes-core/images/{yp-image.bb,yp-image-minimal.bb}、
#           tests/bats/04_layer.bats、config/features.txt、docs/02-development/naming.md（若需勘误）
```

## 完成定义（DoD）

- [ ] A–G 全部 rc=0；C 段两条 grep 无输出
- [ ] `yp.conf` 里没有任何条件分支；版本差异只出现在 `yp-compat.inc`
- [ ] 新增的 4 个 layer 文件只用 `=`/`+=`/`=+`/`??=`，无冒号 override
- [ ] `config/features.txt` 有 `layer-structure` 行，`99_coverage.bats` 三用例全绿
- [ ] BATS ≥ 64、`0 not ok`、`0 skip`
- [ ] `docs/02-development/naming.md` 与实际文件一致
- [ ] PR 描述里贴 A/B/C/E/F 的实际输出，并注明「真实 `bitbake -p` 解析留到 P1 #17」

## 参考

- 命名约定：`docs/02-development/naming.md`（C42）
- 分支约定：`docs/06-process/branching.md`
- 配置面：`config/variants/{general,custom}.env`（custom 的 `DISTRO=yp` / `IMAGE=yp-image` 已就位）
- layer 现状：`layers/meta-yp/conf/layer.conf`、`layers/meta-yp/recipes-core/images/core-image-minimal.bbappend`
- kas 设计（**P1 才落代码，本卡不要碰**）：`layers/` 必须能被 `kas` 以 `repos.yp` 引用
- 需求段落：§4.1、§4.2（variant 表）、§7.1 第 10 项、C27、C42
