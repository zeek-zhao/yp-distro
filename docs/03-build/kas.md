> **历史记录（#135，2026-11-12）**：本文件写于四版保障时期（dunfell / kirkstone /
> scarthgap / wrynose 全量受保），「四个 release × 2 variant = 8 组合」描述的是
> 当时的组合面。现行保障范围只有 wrynose 6.0（单一事实源
> `config/supported-releases.txt`），其余三版的 kas 配置已冻结保留、不再受保。
> 正文按历史原样保留，不随范围收缩更新。

# kas 静态配置层

`kas/` 为四个 Yocto release 和 `general`/`custom` 两种 variant 提供 8 个
组合配置。target 通过仓库根相对路径依次 include base、release、machine 和
variant 配置。release 仓库及 tag 与 `config/*.env` 双轨维护，由
`scripts/kas-verify.py` 检查一致性。

```bash
./project.sh kas
./project.sh kas --release wrynose --variant custom
```

校验器默认在 `kas` Python 包可用时调用 `kas.includehandler.IncludeHandler`；
否则使用内置 YAML 解析和深合并校验。两种模式都只解析配置，不会 clone、
联网或调用 `kas checkout`、`kas dump`、`kas lock`。内置实现可通过
`--engine builtin` 指定，`--root DIR` 可用于临时副本测试。

## 静态约束

- `header.version` 固定为 14；顶层字段及 `repos` 项字段受白名单约束。
- `check_shared_cache`（#23）要求 `kas/base.yml` 用 `=` 固定
  `DL_DIR = "${TOPDIR}/../../downloads"` 和
  `SSTATE_DIR = "${TOPDIR}/../../sstate"`，禁止缺失、弱赋值或每版本独立缓存。
- `check_build_env` 要求 `kas/base.yml` 提供：并行度上限
  `min(oe.utils.cpu_count(), N)`（`BB_NUMBER_THREADS` 与 `PARALLEL_MAKE`
  的上限必须相等）、`BB_DISKMON_DIRS` 的 STOPTASKS/ABORT 两档、按
  `<release>-<variant>` 分仓的 `buildhistory`、以及
  `BB_GENERATE_MIRROR_TARBALLS = "1"`。这四项都不进 basehash，写错了
  构建照样成功，所以只能靠断言兜。说明见 [build-env.md](build-env.md)。
- `layers` 的每个 layer 值必须是 null、字符串、整数或布尔值；空 mapping
  作为 layer 值无效。
- include 先按仓库根解析，找不到时再相对当前文件解析；按列表顺序深度优先
  合并，后出现的值覆盖先前值，mapping 递归合并。
- poky release 的 repo 集合为 `{poky}`；split release 为
  `{openembedded-core, bitbake, meta-yocto}`。custom variant 另含本仓库的
  `yp` layer。
- `kas/` 中列出的基础、release、variant、machine 和 target 文件共 16 个
  YAML 文件（需求清单的“15 个”与列出的文件数量不一致）。

## 串行构建与共享缓存（#23）

```bash
bash scripts/build.sh --release scarthgap --variant general --dry-run
bash scripts/build.sh --release scarthgap --variant general
# 在宿主机也可经 dev 容器直通入口：
bash scripts/dev.sh bash scripts/build.sh --release wrynose --variant custom
```

默认 `--image-mode release` 经 `./project.sh shell` 使用对应 release 镜像；
`--image-mode dev` 经 `scripts/dev.sh` 使用开发环境（需自行满足该版本的
HOSTTOOLS，正式构建推荐 release 镜像）。两者共用 `work/build.lock` 的 fd 9
非阻塞锁，第二个构建立即提示串行约束并退出 3，dry-run 也取锁。
参数错误退出 2；真构建保留命令退出码。
锁文件保留，不要在构建中删除它；`project.sh build` 暂保留未实现接口。

入口预建缓存、日志及 kas 工作目录，在容器内设置 `KAS_CLONE_DEPTH=1`、
`KAS_WORK_DIR=/work/work/kas-<release>-<variant>`。
日志 `work/logs/build-<release>-<variant>.log` 记录起止时间、标准输出和错误；
同名 `.meta` 为纯整数耗时秒数，失败构建同样记录。
报告的「构建统计」读取它们，缺失时显示 `n/a`，不产生新的 degraded 项。

`TOPDIR` 是 `/work/work/kas-<release>-<variant>/build`，所以缓存必须退两层
才落到共享的 `work/downloads` 和 `work/sstate`；退一层会每版本复制一份。
bitbake 不自动导入环境中的 `DL_DIR` / `SSTATE_DIR`，`??=` 也不能覆盖
bitbake.conf 已有的 `?=` 默认值，因此真值只在 `kas/base.yml` 用 `=` 定义。
`container.sh` 的同名环境变量仅作人工排查的契约声明。

**#23 验收偏差说明（供 PR 描述沿用）**：原要求在 `config/*.env` 显式写
宿主绝对缓存路径已作废；不增加第二份路径配置，唯一真本是 `kas/base.yml`。
本任务不迁移已有的各版本缓存，也不运行真构建。
报告渲染前先提交源文件变更以保持 `SOURCE_FINGERPRINT` 可复现；
验证用 `--render-only`，完成后删除临时 `*-render.md`，不改已归档报告。

## 实测结论与设计修正

kas 4.6 的以下行为已在目标镜像实测；L1 校验按这些行为实现：

1. kas 没有 `validate` 子命令；其子命令包括 `build`、`checkout`、`dump`、
   `for-all-repos`、`lock`、`shell` 和 `menu`。
2. `kas dump` 不适用于 L1：即使跳过全部步骤也会因 `KeyError: 'header'`
   失败；包含仓库时还会触发 clone。
3. `kas lock` 需要联网 fetch SHA，本静态阶段不运行它。
4. `kas.includehandler.IncludeHandler` 可做纯解析并执行 kas 自带的
   JSON-schema 校验，不 clone、不联网。
5. kas 要求 `layers` 的路径值写成 `null`；`layers: {meta: {}}` 会被 schema
   拒绝。
6. `layers` 的 key 就是仓库内相对路径；本仓库层使用
   `layers/meta-yp:`，不需要额外的 `path:` 配置。
7. `repos.<name>: null` 表示把当前配置文件所在仓库命名为该 repo 并作为 layer，
   不是删除继承来的 repo。
8. include 优先相对仓库根解析，找不到时才相对当前文件目录回退；配置统一使用
   kas/ 开头的仓库根相对路径。
9. 合并为深合并，后者覆盖前者；同名 mapping 递归合并。

因此两处旧设计明确作废：**不使用 `poky: null` 删除 base 中的 poky**，
release 文件各自定义其仓库；**不使用 `layers: {}`**，layer 路径必须写成
`meta:`、`meta-poky:` 或 `layers/meta-yp:` 这样的 null 值。

custom layer 配置使用 `YP_VARIANT`，distro/镜像分别为 `yp` 和 `yp-image`。
`yp` repo 暂以 `tag: main` 引用本仓库；custom variant 的检出尚未验证（私有仓库自引用，见下节）。

开发 Dockerfile 已加入 kas 4.6 安装层与版本指纹；镜像已重建，容器内 `kas --version` 为 `kas 4.6 (configuration format version 18, earliest compatible version 1)`，校验器 `auto` 引擎已切到真 kas，与 `--engine builtin` 结论一致。

## 实际检出实测（P1-02 前半，2026-10-28）

4 个 release 的 `-general` target 全部 `kas checkout` + `kas lock` 通过。

### 浅克隆是必需的，否则不可用

`git.openembedded.org` / `git.yoctoproject.org` 直连很慢：全量克隆 20 分钟只拉了
249M（按此速度 poky 需 2 小时以上）。kas 认 `KAS_CLONE_DEPTH` 环境变量
（`0` = 全量，`N` = 浅克隆 N 层），设 `KAS_CLONE_DEPTH=1` 后：

| release | 耗时 | 磁盘 |
|---|---|---|
| dunfell | 30s | 79M |
| kirkstone | 27s | 85M |
| scarthgap | 34s | 88M |
| wrynose（三仓库） | 17s | 69M |

合计约 **340M**，而不是原先担心的 20GB。构建仍需要 `DL_DIR` 里的上游 tarball，
那部分由 bitbake 下载，与源码检出无关。

### `KAS_WORK_DIR` 必须预先存在

kas 不会创建它，直接 `os.chdir` 过去，否则报
`FileNotFoundError: [Errno 2] No such file or directory`。检出前先 `mkdir -p`。

### 检出结果与 `config/*.env` 完全对齐

`kas checkout` 解析 tag 得到的 commit 与 `config/*.env` 的 `EXPECT_SHA` 逐字一致：

| release | tag | SHA | 比对 |
|---|---|---|---|
| dunfell | `yocto-3.1.33` | `63d05fc061006bf1a88630d6d91cdc76ea33fbf2` | MATCH |
| kirkstone | `yocto-4.0.35` | `93431249a6260da7bd29ee3ca32145d89e5b8259` | MATCH |
| scarthgap | `yocto-5.0.20` | `64e69ed23703f6358ec431d3f5f1f8483f974cae` | MATCH |
| wrynose（三仓库） | `yocto-6.0.4` | oe-core `0f03c732a0a2d0506b41b1abe60b3f368b2300dc`<br>bitbake `51fd94a67fa17650a9ff623492005972bbc7d26f`<br>meta-yocto `7c25b11156553145fa6b241a2d4f65d94438f804` | 记录备用（`config/wrynose.env` 无 `EXPECT_SHA`） |

双轨（C36）的 tag 副本没有漂移。

### wrynose 三仓库的 layers 推导可靠（#24）

`kas checkout kas/targets/wrynose-general.yml` 生成的 `build/conf/bblayers.conf`：

```text
BBLAYERS ?= " \
    ${TOPDIR}/../bitbake \
    ${TOPDIR}/../meta-yocto/meta-poky \
    ${TOPDIR}/../openembedded-core/meta"
```

- 三条路径全部正确，kas 没有把 poky 组合仓库的假设套到拆分仓库上；
- `bitbake` 目录本身就作为 layer 进入 `BBLAYERS`，**不需要额外的 `env:` 段**
  来补 `BBPATH` / `PATH`；
- `kas lock` 对多仓库**逐个固化**：`wrynose-general.lock.yml` 的
  `overrides.repos` 下三个 repo 各有一条 `commit`。

### lockfile 的落点与格式

`kas lock kas/targets/<r>-general.yml` 在 **target 同级**生成
`kas/targets/<r>-general.lock.yml`（不是 kas/locks/，kas 不会自建目录），内容是：

```yaml
header:
    version: 14
overrides:
    repos:
        poky:
            commit: 64e69ed23703f6358ec431d3f5f1f8483f974cae
```

`IncludeHandler` 会在读配置时自动找同目录的 `<file>.lock.yml` 并注入，
所以 lockfile 入库后，`kas checkout` 就按 commit 而非可变 tag 执行。

### custom variant：本仓库自身的 layer

`kas/variants/custom.yml` 的 `repos.yp` **刻意不写 `url`**。kas 的 `repos.py` 里
`url is None` 分支会：

1. 把 path 设为 `Repo.get_root_path(top_repo_path)`，即**当前配置文件所在仓库的根**；
2. 置 `disable_operations = True`，对该仓库不做任何 VCS 操作。

于是 `layers: {layers/meta-yp: null}` 直接命中 `<仓库根>/layers/meta-yp`。
日志里对应的是 `Using /work as root for repository yp`。

如果把 `url` 写回去（哪怕指向本仓库自己），`kas checkout` 会去 clone 这个私有仓库，
慢且需要凭证，而 layer 其实已经在磁盘上——这是 P1-03 之前的错误写法。

4 个 `-custom` target 实测（构建机，`KAS_CLONE_DEPTH=1`）：

| release | checkout | lock | workdir 有 `yp/` | `bblayers.conf` |
|---|---|---|---|---|
| dunfell | rc=0 | rc=0 | 否 | `${TOPDIR}/../../../layers/meta-yp` |
| kirkstone | rc=0 | rc=0 | 否 | 同上 |
| scarthgap | rc=0 | rc=0 | 否 | 同上 |
| wrynose | rc=0（三仓库） | rc=0 | 否 | 同上 |

### custom 的 lockfile 里没有 `yp`

`kas lock` 的 `_filter_enabled`（kas 上游 `plugins/lock.py`）会过滤掉
`operations_disabled` 的仓库，注释是 "when locking, only consider repos managed by kas"。
所以 `kas/targets/*-custom.lock.yml` 里只有上游仓库。

这是**正确**行为，不是缺陷：把本仓库自己的 commit 写进 lockfile 会自指——
lockfile 一提交，记录的那个 commit 就不再是 HEAD。本仓库版本的审计由 git
commit / tag 与 `config/releases/*.env` 的 `EXPECT_SHA` 承担。

4 个 custom lockfile 与同版本 general lockfile 的 SHA **逐字一致**
（dunfell `63d05fc0…` / kirkstone `93431249…` / scarthgap `64e69ed2…` /
wrynose 三仓库 `51fd94a6…` `7c25b111…` `0f03c732…`），
证明 variant 层没有扰动版本锁。

### 四版真实解析（`bitbake -p`）

配置能被 kas 解析 ≠ bitbake 能接受。8 个 target 全部用对应 release 镜像
真跑了一次 `bitbake -p`（只用 release 镜像，dev 镜像缺 HOSTTOOLS）：

| release | bitbake | 解析 .bb（general / custom） | 结果 |
|---|---|---|---|
| dunfell | 1.46.0 | 775 / 781 | 均 0 errors |
| kirkstone | 2.0.0 | 882 / 888 | 均 0 errors |
| scarthgap | 2.8.1 | 920 / 926 | 均 0 errors |
| wrynose | 2.18.0 | 950 / 956 | 均 0 errors |

custom 比 general 多 6 个 recipe，来自 multilib（lib32）。

这一轮暴露了 5 个只有真解析才会发现的问题：

1. **`bitbake` 仓库不能当 layer**。kas 的 `Repo.factory` 里
   `layers_dict = repo_config.get('layers', {'': None})`——不写 `layers` 时
   默认把**仓库根**当一层。于是 `bitbake/` 进了 `BBLAYERS`，而它没有
   `conf/layer.conf`，报 `file .../bitbake/conf/layer.conf not found`。
   修法：`wrynose.yml` 的 `bitbake` 显式写 `layers: {}`。
   （空 dict 合法；被 schema 拒绝的是 `layers: {meta: {}}` 这种**值**为 `{}` 的写法。）
2. **`CONF_VERSION` 各版本不同**：dunfell 的 `local.conf.sample` 是 1，
   kirkstone+ 是 2。base 里写死 2 会让 dunfell 直接 `NotImplementedError`。
3. **6.0+ 禁止 `S = "${WORKDIR}"`**，`file://` 解包改到 `${UNPACKDIR}`，
   而 3.1/4.0/5.0 没有这个变量。解法**不是**去 `??=` 上游的 `UNPACKDIR`——
   实测那会污染默认值，导致 96 个 recipe 报
   `Using UNPACKDIR = ${WORKDIR} is not supported`。而是定义自己的
   `YP_SRC_DIR`：base 默认 `${WORKDIR}`，只有 wrynose 覆盖成 `${UNPACKDIR}`。
4. **wrynose 删掉了 `cve-check.bbclass`**，换成 SBOM 驱动的 `sbom-cve-check`；
   且从 5.0 起它在 `classes-recipe/`，配置层 `INHERIT += "cve-check"` 找不到。
   解法：`YP_CVE_ENABLE`（variant 决定开关）+ `YP_CVE_CLASS`（release 决定类名），
   由 **distro**（`conf/distro/yp.conf`）用全局 `INHERIT += "${@bb.utils.contains(...)}"`
   条件打开。不能就近 inherit 到 `yp-image`：`cve-update-nvd2-native.bb` 自带
   `SkipRecipe` 守卫，类没在全局 INHERIT 里，解析期就报
   `Nothing PROVIDES 'cve-update-nvd2-native'`。6.0 的 `sbom-cve-check.bbclass`
   落在 `classes-recipe/` 下、全局 INHERIT 找不到，因此 wrynose 用
   `YP_CVE_GLOBAL_INHERIT = "0"` 关掉这一层（它的 CVE 本来就是 degraded）。
   **不能在 local.conf 里拼 `IMAGE_CLASSES += " ${YP_CVE_CLASS}"`**：
   `+=` 立即展开，而 kas 的 `local_conf_header` 段顺序是
   base → custom → machine → release，展开时还拿不到 release 定义的值。
5. **`RPROVIDES = "virtual/cpp-hello"` 在 6.0 报 QA `virtual-slash`**。
   `IMAGE_INSTALL` 里的 `virtual/cpp-hello` 由 build 期 `PROVIDES` 解析，
   runtime 的 `RPROVIDES` 不该带 `virtual/` 前缀。

这 5 条都已变成 `kas-verify.py` 的 `check_version_knobs` 断言，
并有 5 个反向用例（改坏配置必须报错）证明断言不是空壳。

### 已解决：冒号 override 在 dunfell 上的行为（分变量级与任务级）

**变量级：静默失效。** dunfell 3.1 的 bitbake 把 `:` 当作变量名的一部分，
`FILES:${PN}`、`SUMMARY:${PN}` 这类冒号写法**不报错也不生效**；4.0+ 反过来只认冒号，
而且下划线写法在 4.0+ 是**致命**解析错误（`data_smart.py`「old override syntax」），
报错会连带挂到所有求值到同名变量的 recipe 上。两种写法**没有交集**，所以做法是：

1. **变量级**：两种分隔符各写一行（`FILES:${PN}-cus` + `FILES_${PN}-cus`）。
   未命中的那一行在该版本里就是惰性变量，没人读，无副作用。
   已覆盖 `FILES`、`SUMMARY`、`PREFERRED_PROVIDER_virtual/*`、
   `DEFAULTTUNE_virtclass-multilib-lib32`。
   变量名里带 `${PN}` 展开的（`IMAGE_INSTALL` / `OS_RELEASE_FIELDS` 这类）没法并列
   两行——下划线版会在 4.0+ 炸掉解析，只能按 `LAYERSERIES_CORENAMES` 用
   `python __anonymous` 给 3.1 补下划线版，见 `images/yp-image.inc`。
2. **任务级有退路，而且冒号就能用**：`do_install:append()` 在 3.1 上**是生效的**
   （实测 yocto-3.1.33 / BitBake 1.46.0，见下面的探针），所以任务级一律只写冒号一份，
   四版通用。

> **曾被搞错一次**：早期笔记写「任务级没有退路，冒号在 3.1 上静默失效」，于是给每个
> `do_install:append` 又补了一份 `do_install_append`。3.1 上两份都生效，同一个
> `do_install` 里那段逻辑跑了两遍，症状是 `xxx: not found` 的 exit 127（`f66f35b` 修掉）。
>
> 复现探针（放进任意在 `BBLAYERS` 里的层，跑 `bitbake -c install -f colon-probe`）：
>
> ```bitbake
> SUMMARY = "probe"
> LICENSE = "MIT"
> LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"
>
> do_install() {
>     install -d ${D}/probe
>     echo base > ${D}/probe/result.txt
> }
>
> do_install:append() {
>     echo append >> ${D}/probe/result.txt
> }
> ```
>
> `image/probe/result.txt` 里出现 `base` + `append` 两行即证明冒号任务 override 生效；
> `run.do_install` 里也能看到 append 的函数体被并进了 `do_install`。
>
> **也不要改成「独立任务 + `addtask`」**：自定义任务不在 `PSEUDO_TASKS` 里，不经
> pseudo，装出来的文件属主是真实宿主 uid，`do_package_qa` 立刻判 `host-user-contaminated`。

代价是变量级 recipe 里成对出现两行，收益是同一份 recipe 四版语义一致，
不需要按版本拆 recipe 或分版本 `.bbappend`。`tests/bats/04_layer.bats`
仍只对 `conf/` 与 `recipes-core/` 禁冒号写法（白名单文件除外，`recipes-example/` 是
兼容性演示）——这条 lint 针对的是**变量级**在 3.1 上不起作用，不是任务级。

`recipes-example/` 里 `cpp-hello-cus-pack` 的 `do_compile`/`do_install` 整体重定义**保留不动**：
它在那里充当「不分版本拆 recipe 也能四版一致」的另一种示范，没有功能问题，改它只是重新烧一遍构建时间。
