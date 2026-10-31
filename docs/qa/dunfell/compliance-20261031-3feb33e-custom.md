# 合规证据报告

- Kind: `compliance`
- Release: `dunfell`
- Variant: `custom`
- Machine: `qemux86-64`
- Tag: `yocto-3.1.33`
- Commit: `3feb33e`
- Date: `20261031`

> 采集口径：SBOM 与 CVE 在构建期/构建后取，FOSS 是构建后对 `work/downloads`
> 的源码包做批量扫描。三者都不参与构建增量决策。

## SBOM

| 项 | 值 |
|---|---|
| 格式 | `SPDX-2.2` |
| 文件 | `work/artifacts/dunfell/custom/sbom/yp-image-qemux86-64-20261031002057.spdx.json` |
| 体积 | 0.1 MB（144212 字节） |
| SHA-256 | `0cdd905a84118239c2aa2694405e9b2a630dea8e6716343b1ffc028d72b7c02f` |
| 打包形态 | `tar.gz` |
| 文档形态 | 索引型：文档内只有 1 个 image 包，组件清单以 `externalDocumentRefs` 指向 `deploy/spdx/` 下的 per-recipe 文档 |
| 外部文档引用 | 314 |
| 镜像组件（CONTAINS 对位） | 157 |
| 已解析外部文档 | 157 |
| 聚合包元素 | 157 |
| 聚合文件元素 | 4243 |
| PURL 非空率 | 0.0%（0/157） |
| VEX | 本版本无（`vex.bbclass` 只有 5.0/6.0 有） |
| 许可证 top | `GPL-2.0` 8，`GPL-2.0 AND DocumentRef-recipe-busybox:LicenseRef-bzip2-1.0.4` 3，`GPL-2.0 AND LGPL-2.1` 10，`GPL-2.0+` 6，`GPL-2.0+ AND LGPL-2.1+ AND BSD-3-Clause AND BSD-4-Clause` 8，`GPL-3.0` 4，`LGPL-2.1+` 4，`MIT` 21 |

索引型的包数不能直接照抄文档里的 `packages`（那是 1 个 image 包）。
上表的「镜像组件」「聚合包元素」是沿 `CONTAINS` 关系把 157 份外部文档按
`documentNamespace` 逐个对位后累加出来的，口径与 6.0 自包含文档一致。

## CVE

| 项 | 值 |
|---|---|
| 采集工具 | `cve-check` |
| 清单 | `yp-image-qemux86-64.json` |
| 包数 | 62 |
| 未修复 / 已修复 / 忽略 | 4165 / 9919 / 2592 |
| 数据源 | `nvdcve_2.db` |
| 库构建时间 | 2026-10-30T19:25:34+0800 |
| 统计口径 | `image-manifest` |

## FOSS

| 项 | 值 |
|---|---|
| 工具 | `scancode-toolkit` |
| 源码来源 | `work/downloads` |
| 镜像内软件包 | 157 |
| 本次已扫 | 10（上限 10） |
| 覆盖率 | 6.4% |
| 扫描文件数 | 25365 |
| 产物 | `work/artifacts/dunfell/custom/foss/`（每包 json/csv/spdx，前 3 个另有 html） |

许可证表达式分布（按检出次数）：

`bsd-new` 35，`curl` 9，`fsf-free` 20，`gpl-1.0-plus` 21，`gpl-2.0` 27，`gpl-2.0-plus` 38，`gpl-3.0-plus` 105，`gpl-3.0-plus AND gpl-1.0-plus` 10，`gpl-3.0-plus AND gpl-3.0` 12，`gpl-3.0-plus AND gpl-3.0 AND gpl-1.0-plus` 12

| 包 | 源码包 | 文件数 | 清晰度 | 主要许可证 |
|---|---|---:|---:|---|
| `busybox` | `work/downloads/busybox-1.31.1.tar.bz2` | 2786 | 100 | bsd-new、bsd-original-uc、bzip2-libbzip-2010 |
| `curl` | `work/downloads/curl-7.69.1.tar.bz2` | 3249 | 80 | apache-2.0 AND zlib、bsd-new、curl |
| `dropbear` | `work/downloads/dropbear-2019.78.tar.bz2` | 1038 | 80 | bsd-new、bsd-simplified、free-unknown |
| `kbd` | `work/downloads/kbd-2.2.0.tar.xz` | 1208 | 90 | fsf-ap、fsf-free、gpl-1.0-plus |
| `kmod` | `work/downloads/kmod-34.2.tar.xz` | 703 | 100 | fsf-free、fsf-unlimited-no-warranty、gpl-2.0 |
| `nettle` | `work/downloads/nettle-3.10.2.tar.gz` | 974 | 90 | ((gpl-2.0-plus OR gpl-3.0-plus) AND other-permissive AND public-domain) AND public-domain、(lgpl-3.0-plus OR gpl-2.0-plus) AND public-domain、bsd-new |
| `openssl` | `work/downloads/openssl-1.1.1w.tar.gz` | 3265 | 80 | apache-2.0、bsd-new、bsd-simplified |
| `shadow` | `work/downloads/shadow-4.11.1.tar.gz` | 1076 | 80 | ace-tao、bsd-new、fsf-free |
| `strace` | `work/downloads/strace-5.16.tar.xz` | 9947 | 90 | bsd-new、gpl-1.0-plus、gpl-2.0 |
| `tar` | `work/downloads/tar-1.32.tar.bz2` | 1119 | 100 | fsf-free、fsf-unlimited、gfdl-1.1-plus |

覆盖率不是 100% 是预期的：`work/downloads` 只覆盖有 `SRC_URI` 归档的上游源码，
`file://` 与 git 源的包不在其中，缺口按包名如实记账，不做静默补齐。

## 格式差异

SPDX 不强行统一（3.1/4.0/5.0 出 2.2，6.0 只出 3.0.1），跨版本只比
「包名 + 版本 + 许可证」，不比文档内部结构。本节把差异写死，避免把
口径不同当成回归。

| release | SPDX | 镜像级 SBOM 形态 | 文档自包含性 | VEX |
|---|---|---|---|---|
| dunfell 3.1.33 | 2.2 | `<image>-<machine>.spdx.tar.gz`（包内 `<image>-<ts>.spdx.json`） | 索引型 | 无 |
| kirkstone 4.0.35 | 2.2 | `<image>-<machine>.spdx.json` 单文件 | 索引型 | 无 |
| scarthgap 5.0.20 | 2.2（默认） | `<image>-<machine>.rootfs.spdx.tar.zst` | 索引型 | 有 |
| wrynose 6.0.4 | 3.0.1 | `<image>-<machine>.rootfs.spdx.json` 单文件 | 自包含 | 有 |

本版本实际：格式 `SPDX-2.2`，打包形态 `tar.gz`，文档形态 `spdx2-index`。

语义差异（不能直接比大小）：

- 3.1/4.0/5.0 的镜像文档是**索引**：`packages` 只有 1 个 image 包，组件靠
  `externalDocumentRefs` + `CONTAINS` 指向 `deploy/spdx/<ver>/` 下的 per-recipe 文档，
  照抄 `packages` 会得到「1 个包」的假象，必须聚合后再比；
- 6.0 的 `software_Package` 把构建期元素也算进去，数字天然比 2.2 的聚合值大，
  两版包数不能当回归指标；
- PURL 只有 6.0 默认产出（`SPDX_PACKAGE_URL`），2.2 的 per-recipe 文档没有 purl，
  所以前三版 PURL 非空率是 0%，这是能力差异不是采集失败；
- 3.0.1 的 VEX 由 `security_Vex*` 关系元素承载（`SPDX_INCLUDE_VEX`），2.2 没有对应表达；
- 5.0 的镜像级 SBOM 是归档，要解压后才能当输入用，6.0 是可直接喂工具的单文件。

## 降级清单

无（本版本合规相关能力全部按标准实现）

## 验收结论

**PASS**

- [x] SBOM 已产出并可解析
- [x] SBOM 外部引用全部对位（索引型必检）
- [x] CVE 清单已产出（采集工具可随版本分叉）
- [x] FOSS 批量扫描有结果
- [x] FOSS 覆盖率 > 0
- [ ] PURL 非空率 >= 90%（CRA 漏洞匹配前提，观测项）
