# 命名约定（C42 · P0 定死）

> 决策日期 2026-10-28。原名 `meta-zeek` / `zeek-distro` / `core-image-zeek` 是个人化命名，
> 已统一改为中性功能名 **`yp`**（Yocto Platform）。P0 之后不得再改，P1 的 kas yml、
> layer.conf、recipe、文档全部引用本约定。

## 一、定名表

| 对象 | 定名 | 落点 / 说明 |
|---|---|---|
| layer 目录 | `layers/meta-yp/` | 仓库内子目录；kas `repos.yp.path = layers/meta-yp` 自引用 |
| `BBFILE_COLLECTIONS` | `meta-yp` | `layer.conf`；`LAYERDEPENDS_meta-yp = "core"` |
| 发行版 | `yp` | `layers/meta-yp/conf/distro/yp.conf`，`DISTRO = "yp"`、`DISTRO_NAME = "YP"` |
| custom 镜像 | `yp-image` | 全量镜像（C27 独立 distro 侧） |
| custom 精简镜像 | `yp-image-minimal` | 最小可解析探针 |
| build 目录 | `build/<release>/<variant>` | 见需求 §4.1 磁盘模型 |
| 容器名 | `yocto-<release>-<variant>` | #10 `container.sh` 生成，便于 `docker ps` 识别 |
| GHCR 镜像 | `ghcr.io/zeek-zhao/yocto/<release>` | 账号路径固定为 GitHub 账号，**不随本约定改名** |

## 二、命名规则

1. layer 一律 `meta-<短名>`，短名只用小写字母数字，**不用连字符**（`meta-yp`、不写 `meta-yp-platform`）；
2. distro 名与 distro conf 文件名一致（`yp` ↔ `conf/distro/yp.conf`）；
3. image 名以 distro 名为前缀：`yp-image`、`yp-image-minimal`；
4. 变量名派生：`LAYERSERIES_COMPAT_meta-yp`、`BBFILE_PRIORITY_meta-yp`、`BBFILE_PATTERN_meta-yp` 全部随 layer 名走，不允许出现旧名残留；
5. `zeek-*` 前缀禁止用于 layer / distro / image 命名（仅允许出现在 GitHub 账号路径与开发者身份里）。

## 三、改名影响面（已改）

| 文件 | 改动 |
|---|---|
| `meta-zeek/` → `layers/meta-yp/` | `git mv`（内容除 layer.conf 集合名外零改动） |
| `layers/meta-yp/conf/layer.conf` | 集合名/模式/优先级/依赖 4 处 → `meta-yp` |
| `config/variants/custom.env` | `DISTRO=yp`、`IMAGE=yp-image` |
| `tests/bats/00_project.bats` | 断言同步为 `DISTRO=yp` / `IMAGE=yp-image` |
| `README.md` | 目录树 `layers/meta-yp/` |
| `docs/branching.md`、`docs/roadmap.md` | 示例分支名与 Issue #11 标题 |

不改动：`reference/legacy/`（原样保留的参考脚本）、`tasks/P0-0*.md`（历史任务卡，留档不追改）。

## 四、验证

```bash
make lint                 # shellcheck / shfmt / hadolint / actionlint
bash scripts/dev.sh bash tests/bats/00_project.bats
bash scripts/dev.sh ./project.sh config scarthgap --variant custom   # 期望 DISTRO=yp / IMAGE=yp-image
git grep -n "meta-zeek\|zeek-distro\|core-image-zeek"                 # 仅剩 reference/legacy 与历史任务卡
```
