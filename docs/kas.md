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
`yp` repo 暂以 `tag: main` 引用本仓库，后续 P1-02 再固定到 commit。

开发 Dockerfile 已加入 kas 4.6 安装层与版本指纹；本卡不重建镜像，镜像构建
留给 P1-02 前执行。
