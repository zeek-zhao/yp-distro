# ScanCode CLI 供给与 recipe 内 `do_scancode`

> 决策依据见 Obsidian 笔记 `40-项目/YP/P2-28-recipe内do_scancode方案.md`。本文只写「怎么用」与「实测口径」。

## 1. 结论

| 项 | 决定 |
|---|---|
| CLI 放在哪 | **不烤进镜像**，按需下载到 `work/tools/`，容器内以 `/work/work/tools/...` 挂载使用 |
| 怎么拿 | `scripts/scancode.sh sync --release <r>`（下载 → 解压 → 容器内 `./configure`） |
| recipe 内 `do_scancode` | **demo 形态**：默认 `noexec`，不进任何镜像，不进交付 |
| FOSS 正式形态 | 构建后批量扫描（与 Obsidian 笔记 `40-项目/YP/P2-26-开源合规方案.md` §4 一致） |

## 2. 为什么不烤进镜像

`configure` 之后每个包的实际占用（实测）：

| 包 | 下载 | 解压 | configure 后 `venv/` | 落地合计 |
|---|---:|---:|---:|---:|
| `v32.0.6_py3.8`（dunfell） | 144 MB | 154 MB | 635 MB | **790 MB** |
| `v32.5.0_py3.10`（kirkstone） | 220 MB | 230 MB | 720 MB | **950 MB** |
| `v32.5.0_py3.12`（scarthgap / wrynose） | 220 MB | 230 MB | 720 MB | **950 MB** |

现有镜像 773~890 MB。若各镜像烤自己那一份，等于体积翻倍；若四个镜像都烤同一个 py 版本，又会和镜像内的系统 python 对不上（venv 里的 `typecode` / `intbitset` 是编译扩展，绑解释器版本）。

三份合计约 **2.7 GB**，只在 215 磁盘上占一次。

## 3. 版本映射

`scancode-toolkit` 的 standalone 包是**按 Python 版本**分发的，包内 `PYTHON_EXECUTABLE` 决定它只能在哪个解释器下跑。选版本的依据：

- PyPI 上 `32.5.0` 的 `requires_python` 是 `>=3.10` → dunfell（3.8）用不了；
- `v32.0.6` 的 Release 仍然出 `py3.7 / 3.8 / 3.9 / 3.10 / 3.11` 五个包；
- `v31.2.6`（被删的那个配方钉的版本）**只出 py3.8 一个包**，没有理由选它。

| release | 镜像 base | 系统 python | scancode | 资产 |
|---|---|---|---|---|
| dunfell 3.1.33 | ubuntu:20.04 | 3.8.10 | 32.0.6 | `scancode-toolkit-v32.0.6_py3.8-linux.tar.gz` |
| kirkstone 4.0.35 | ubuntu:22.04 | 3.10.12 | 32.5.0 | `..._v32.5.0_py3.10-linux.tar.gz` |
| scarthgap 5.0.20 | ubuntu:24.04 | 3.12.3 | 32.5.0 | `..._v32.5.0_py3.12-linux.tar.gz` |
| wrynose 6.0.4 | ubuntu:24.04 | 3.12.3 | 32.5.0 | 与 scarthgap 共用 |

**注意**：32.5.0 的 py3.10 与 py3.12 是两个不同的包，但包内顶层目录同名（`scancode-toolkit-v32.5.0`）。`scripts/scancode.sh` 解压后立刻按「版本-py」改名，否则两者互相覆盖。

## 4. 用法

```bash
# 准备（每个 py 版本一次，约 5 分钟下载 + 10 秒 configure）
scripts/scancode.sh sync --release dunfell
scripts/scancode.sh sync --release all        # 四份（实际三份文件）

# 看状态
scripts/scancode.sh status

# 取容器内可执行路径（给 YP_SCANCODE_BIN 用）
scripts/scancode.sh path --release scarthgap
# → /work/work/tools/scancode-v32.5.0-py3.12/scancode
```

`./configure` 全程离线：依赖 wheel 都在 bundle 的 `thirdparty/` 里，不需要 PyPI。

## 5. recipe 内 `do_scancode`（demo）

`layers/meta-yp/recipes-example/cpp-hello/cpp-hello-scancode_0.1.bb`：

```conf
# local.conf
YP_SCANCODE_ENABLE    = "1"
YP_SCANCODE_BIN       = "/work/work/tools/scancode-v32.5.0-py3.12/scancode"
YP_SCANCODE_PROCESSES = "4"
```

```bash
bitbake cpp-hello-scancode -c scancode
# 产物：tmp/work/.../cpp-hello-scancode/0.1/work/scancode/{scancode.csv,scancode.json,scancode.spdx}
```

设计要点：

- **不写 `DEPENDS`**：工具不由 bitbake 构建，运行时才校验路径，缺失时 `bbfatal` 给出下一步命令；
- **必须显式传 `--processes`**：见下；
- **`nostamp`**：每次真跑都重扫，不让 sstate 命中掩盖工具升级；
- **默认 `noexec`**：`YP_SCANCODE_ENABLE` 不为 `1` 时任务不执行，且这个 recipe 不被任何 image 引用（`04_layer.bats` 有断言）。

## 6. 实测口径

环境：215，kirkstone release 镜像（Ubuntu 22.04 / python 3.10.12 / scancode 32.5.0），参数集与 `reference/legacy/foss/scancode.sh` 一致。

| 样本 | 文件数 / 体积 | `--processes` | 耗时 | 产物 |
|---|---|---|---:|---|
| 空目录 | 0 | 32 | 5 s | — |
| `cpp-hello` | 5 / 28 KB | 32 | 4 s | JSON 16 KB，CSV 4 KB |
| `busybox-1.35.0` | 2768 / 20 MB | 32 | 46 s | JSON 14 MB，CSV 2.4 MB |
| `busybox-1.35.0`（dunfell py3.8，插件集略少） | 2768 / 20 MB | 不传 | 570 s | JSON 5.1 MB |

三条要记住的：

1. **进程启动 4~5 秒**，与内容无关（空目录 5 s、单文件 4 s）。
2. **`--processes` 默认基本是串行**：同一份 busybox 不传 570 秒、传 32 是 46 秒，**差 12 倍**。批量脚本必须显式传，并按「此刻机器有没有在跑构建」动态给值（构建期间 2~4，构建完 `min(nproc, 32)`）。
3. **JSON 约等于源体积 × 0.7**：20 MB 源出 14 MB JSON。归档要压缩，不能原样入库。

## 7. 为什么不做 recipe 内正式扫描

镜像实际涉及 **146 个 recipe**（`tmp/work/core2-64-poky-linux/` 实测目录数）。每个 recipe 一次 `scancode`，光启动开销就是 `146 × 4.5 s ≈ 11 分钟`，而它扫的源码与「构建后对同一批源码扫一遍」**完全等价**。同覆盖、不同成本，所以只保留 demo 形态。

## 8. 待办

- bundle 目前只记 SHA-256（下载后写 `<资产名>.sha256`），**没有和上游公布值做比对**。若要把「供应链校验」做实，需要把三份哈希钉进 `scripts/scancode.sh`。
- 构建后批量扫描（`scripts/foss.sh`）在 #26 里落地。
