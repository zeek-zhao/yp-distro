# 合规证据报告

- Kind: `compliance`
- Release: `wrynose`
- Variant: `custom`
- Machine: `qemux86-64`
- Tag: `yocto-6.0.4`
- Commit: `3feb33e`
- Date: `20261031`

> 采集口径：SBOM 与 CVE 在构建期/构建后取，FOSS 是构建后对 `work/downloads`
> 的源码包做批量扫描。三者都不参与构建增量决策。

## SBOM

| 项 | 值 |
|---|---|
| 格式 | `SPDX-3.0.1` |
| 文件 | `work/kas-wrynose-custom/build/tmp/deploy/images/qemux86-64/yp-image-qemux86-64.rootfs.spdx.json` |
| 体积 | 6.4 MB（6737823 字节） |
| SHA-256 | `2c4f84176d5ceee2f86471a12071a6afe547e01ad06ca26b8634bec26465a794` |
| 打包形态 | `single-json` |
| 文档形态 | 自包含：单个 `@graph` 内同时含包与文件 |
| 包元素 | 574 |
| 文件元素 | 5123 |
| PURL 非空率 | 69.2%（397/574） |
| VEX | fixed 144 / not_affected 58 / vulnerability 202 |
| 许可证 top | `AFL-2.1 OR GPL-2.0-or-later` 1，`BSD-3-Clause AND BSD-1-Clause AND MIT AND BSD-2-Clause AND curl AND Apache-2.0` 1，`DocBook-XML` 1，`GPL-2.0-only AND bzip2-1.0.6` 1，`GPL-2.0-or-later AND MPL-2.0` 1，`LGPL-2.1-or-later AND GPL-2.0-or-later` 1，`LicenseRef-DocBook` 1，`bzip2-1.0.6` 1 |

## CVE

| 项 | 值 |
|---|---|
| 采集工具 | `sbom-cve-check` |
| 清单 | `work/artifacts/wrynose/custom/cve/yocto-cve-check-manifest.json` |
| 包数 | 102 |
| 未修复 / 已修复 / 忽略 | 318 / 16968 / 41 |
| 数据源 | `nvd-json-data-feeds (nvd-fkie)` |
| 库版本 | `f26b0edd41`（2026-10-30T15:06:24+00:00） |

6.0 没有 `cve-check.bbclass`，这里用构建后 CLI 扫镜像 SBOM 得到清单，
导出格式选 `yocto-cve-check-manifest`，与前三版 `cve-check` 的字段和
`status` 取值一致，所以统计口径可以并排看。扫描时开了 `--offline-mode`：
它会让任何 clone/fetch 直接失败，能跑通即证明全程只读本地库。

## FOSS

| 项 | 值 |
|---|---|
| 工具 | `scancode-toolkit` |
| 源码来源 | `work/downloads` |
| 镜像内软件包 | 187 |
| 本次已扫 | 10（上限 10） |
| 覆盖率 | 5.3% |
| 扫描文件数 | 28418 |
| 产物 | `work/artifacts/wrynose/custom/foss/`（每包 json/csv/spdx，前 3 个另有 html） |

许可证表达式分布（按检出次数）：

`bsd-new` 24，`bzip2-libbzip-2010` 4，`curl` 8，`fsf-free` 19，`fsf-unlimited-no-warranty` 6，`gpl-1.0-plus` 27，`gpl-2.0` 30，`gpl-2.0-plus` 36，`gpl-2.0-plus WITH autoconf-simple-exception-2.0` 7，`lgpl-2.0-plus` 5

| 包 | 源码包 | 文件数 | 清晰度 | 主要许可证 |
|---|---|---:|---:|---|
| `busybox` | `work/downloads/busybox-1.31.1.tar.bz2` | 2786 | 100 | bsd-new、bzip2-libbzip-2010、gpl-1.0-plus |
| `curl` | `work/downloads/curl-7.69.1.tar.bz2` | 3249 | 80 | apache-2.0 AND zlib、bsd-new、curl |
| `dropbear` | `work/downloads/dropbear-2019.78.tar.bz2` | 1038 | 80 | bsd-new、bsd-simplified、fsf-free |
| `kbd` | `work/downloads/kbd-2.2.0.tar.xz` | 1208 | 90 | free-unknown、fsf-free、gpl-1.0-plus |
| `kmod` | `work/downloads/kmod-34.2.tar.xz` | 703 | 100 | fsf-free、fsf-unlimited-no-warranty、gpl-2.0 |
| `libxml2` | `work/downloads/libxml2-2.12.10.tar.xz` | 4172 | 80 | fsf-free、fsf-unlimited-no-warranty、gfdl-1.1-plus |
| `nettle` | `work/downloads/nettle-3.10.2.tar.gz` | 974 | 90 | ((gpl-2.0-plus OR gpl-3.0-plus) AND other-permissive AND public-domain) AND public-domain、(lgpl-3.0-plus OR gpl-2.0-plus) AND public-domain、fsf-free |
| `openssl` | `work/downloads/openssl-1.1.1w.tar.gz` | 3265 | 80 | (mit AND apache-2.0) AND openssl-ssleay、bsd-simplified、gpl-2.0-plus OR artistic-2.0 |
| `shadow` | `work/downloads/shadow-4.11.1.tar.gz` | 1076 | 80 | bsd-new、free-unknown、fsf-free |
| `strace` | `work/downloads/strace-5.16.tar.xz` | 9947 | 90 | bsd-new、fsf-ap、gpl-1.0-plus |

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

本版本实际：格式 `SPDX-3.0.1`，打包形态 `single-json`，文档形态 `spdx3`。

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
