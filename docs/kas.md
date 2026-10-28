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
- `layers` 的每个 layer 值必须是 null、字符串、整数或布尔值；空 mapping
  作为 layer 值无效。
- include 先按仓库根解析，找不到时再相对当前文件解析；按列表顺序深度优先
  合并，后出现的值覆盖先前值，mapping 递归合并。
- poky release 的 repo 集合为 `{poky}`；split release 为
  `{openembedded-core, bitbake, meta-yocto}`。custom variant 另含本仓库的
  `yp` layer。
- `kas/` 中列出的基础、release、variant、machine 和 target 文件共 16 个
  YAML 文件（需求清单的“15 个”与列出的文件数量不一致）。

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
   `kas/...` 仓库根相对路径。
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
`kas/targets/<r>-general.lock.yml`（不是 `kas/locks/`），内容是：

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

4 个 `-custom` target 实测（215，`KAS_CLONE_DEPTH=1`）：

| release | checkout | lock | workdir 有 `yp/` | `bblayers.conf` |
|---|---|---|---|---|
| dunfell | rc=0 | rc=0 | 否 | `${TOPDIR}/../../../layers/meta-yp` |
| kirkstone | rc=0 | rc=0 | 否 | 同上 |
| scarthgap | rc=0 | rc=0 | 否 | 同上 |
| wrynose | rc=0（三仓库） | rc=0 | 否 | 同上 |

### custom 的 lockfile 里没有 `yp`

`kas lock` 的 `_filter_enabled`（`kas/plugins/lock.py`）会过滤掉
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
3. **5.0+ 禁止 `S = "${WORKDIR}"`**，`file://` 解包改到 `${UNPACKDIR}`，
   而 3.1/4.0 没有这个变量。解法**不是**去 `??=` 上游的 `UNPACKDIR`——
   实测那会污染默认值，导致 96 个 recipe 报
   `Using UNPACKDIR = ${WORKDIR} is not supported`。而是定义自己的
   `YP_SRC_DIR`：base 默认 `${WORKDIR}`，scarthgap/wrynose 覆盖成 `${UNPACKDIR}`。
4. **wrynose 删掉了 `cve-check.bbclass`**，换成 SBOM 驱动的 `sbom-cve-check`；
   且从 5.0 起它在 `classes-recipe/`，配置层 `INHERIT += "cve-check"` 找不到。
   解法：`YP_CVE_ENABLE`（variant 决定开关）+ `YP_CVE_CLASS`（release 决定类名），
   由 `yp-image.bb` 用 `inherit ${@bb.utils.contains(...)}` 条件继承。
   **不能在 local.conf 里拼 `IMAGE_CLASSES += " ${YP_CVE_CLASS}"`**：
   `+=` 立即展开，而 kas 的 `local_conf_header` 段顺序是
   base → custom → machine → release，展开时还拿不到 release 定义的值。
5. **`RPROVIDES = "virtual/cpp-hello"` 在 6.0 报 QA `virtual-slash`**。
   `IMAGE_INSTALL` 里的 `virtual/cpp-hello` 由 build 期 `PROVIDES` 解析，
   runtime 的 `RPROVIDES` 不该带 `virtual/` 前缀。

这 5 条都已变成 `kas-verify.py` 的 `check_version_knobs` 断言，
并有 5 个反向用例（改坏配置必须报错）证明断言不是空壳。

### 仍未解决：冒号 override 在 dunfell 上静默失效

`cpp-hello-cus-pack_0.1.bb` 里还有 `FILES:${PN}`、`do_compile:append()` 这类
冒号写法。dunfell 3.1 的 bitbake 把 `:` 当作变量名/函数名的一部分，
**不报错但也不生效**；scarthgap+ 只认冒号写法。所以同一份 recipe 在四版上
「都能解析」，但 dunfell 上这些行的语义是丢的。

不影响 `bitbake -p`，但会影响 dunfell 的打包（`FILES` 不生效）。
留到 dunfell 真构建（#21）时按版本拆 recipe 或分版本 `.bbappend` 处理。
