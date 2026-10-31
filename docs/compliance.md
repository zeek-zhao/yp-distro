# 开源合规证据采集（SBOM / CVE / FOSS）

一个入口做三件事：`scripts/compliance.sh`。它只做**采集**，不做构建；
采集结果落 `work/artifacts/<release>/<variant>/compliance.json`，
再由 `scripts/report.sh --compliance` 渲染成
`docs/qa/<release>/compliance-<date>-<sha>[-<variant>].md`。

## 1. 为什么是「采集 + 渲染」两段

主报告（`<date>-<sha>.md`）已经被 150+ 例 BATS 与 `99_coverage.bats` 校验，
往里塞 SBOM 包数、许可证分布、FOSS 逐包表格会让任何一次格式调整都连带打断
主报告用例。所以合规证据走**独立归档**，只共享同一套路径规则。

采集与渲染分开的第二个理由：采集很贵（6.0 的 CVE 要 4 GB 离线库、FOSS 要
ScanCode 扫源码包），渲染很便宜。改版式时只需要 `report.sh --compliance`
重渲，不用重跑采集。

## 2. 三件采集的口径

| 项 | 3.1 dunfell | 4.0 kirkstone | 5.0 scarthgap | 6.0 wrynose |
|---|---|---|---|---|
| SBOM | `create-spdx`（2.2） | 同左（2.2） | 默认已开（2.2） | 默认已开（3.0.1） |
| CVE | 构建期 `cve-check` | 同左 | 同左 | 构建后 `sbom-cve-check` CLI |
| FOSS | ScanCode 批量（构建后） | 同左 | 同左 | 同左 |

三条与直觉相反的实测事实（都在 215 上真跑过）：

1. **5.0 的 `create-spdx` 是默认打开的**。`deploy/spdx/2.2/` 下有 3.6 万个
   per-recipe SBOM，镜像级 SBOM 只有一个 `<image>-<machine>.rootfs.spdx.tar.zst`
   （归档，不是散文件）。所以对 5.0 来说 `--spdx` 是幂等的，加上不会有副作用。
2. **6.0 的镜像级 SBOM 不在 `deploy/spdx/`**。那里是
   `spdx/3.0.1/<ns>/by-spdxid-hash/...` 的逐包文档，喂给 CVE 工具会报
   `SpdxDocument does not contain an Sbom node`。真正的 SBOM 是
   `deploy/images/<machine>/<image>-<machine>.rootfs.spdx.json`。
3. **四版的镜像级 SBOM 四种形态**，靠候选列表 + 解包统一，不按 release 分支：

   | release | 形态 | 包内文件名 |
   |---|---|---|
   | dunfell 3.1.33 | `<image>-<machine>.spdx.tar.gz` | `<image>-<ts>.spdx.json`（**没有** `.rootfs` 中缀） |
   | kirkstone 4.0.35 | `<image>-<machine>.spdx.json` 单文件 | — |
   | scarthgap 5.0.20 | `<image>-<machine>.rootfs.spdx.tar.zst` | `<image>.rootfs-<ts>.spdx.json` |
   | wrynose 6.0.4 | `<image>-<machine>.rootfs.spdx.json` 单文件 | — |

   解包出来的那份落到 `work/artifacts/.../sbom/`，归档里记录的 SHA-256
   是**解出来的那份**，不是压缩包本身。

## 3. CVE：采集分叉、报告归一

6.0 没有 `cve-check.bbclass`，改用构建后 CLI：

```bash
sbom-cve-check --databases-dir work/cve-cache/sbom \
  --sbom-type spdx3 --sbom-path <rootfs SBOM> \
  --disable-auto-updates --offline-mode \
  --set-db-cfg cvelist disabled=true \
  --export-type yocto-cve-check-manifest --export-path <manifest>
```

- `--export-type yocto-cve-check-manifest` 产出的字段与前三版 `cve-check`
  完全一致（`package[].issue[].status` = `Unpatched|Patched|Ignored`），
  所以统计逻辑不需要分叉，报告可以并排看。
- `--offline-mode` 是「全程没联网」的机器化证据：开了它任何 clone/fetch
  直接失败，能跑通就说明只读了 `work/cve-cache/sbom/nvd-fkie`。
- 只留 nvd-fkie 一个库（`--set-db-cfg cvelist disabled=true`）：CVE 编号、
  CVSS、CPE 匹配它都含，cvelist 是 CNA 侧补充。省 4.3 GB 与一次全量 clone。
- 工具版本固定在 `YP_SBOM_CVE_CHECK_VERSION`（默认 1.3.5），
  `pip3 install --target work/tools/sbom-cve-check-<ver>`。不用 venv：
  215 的 python 缺 `ensurepip`，`python3 -m venv` 建不出来。

3.1/4.0/5.0 读构建期清单，两级来源：

1. 优先 `<image>-<machine>.rootfs.json` / `<image>-<machine>.json`（镜像级清单）；
2. 没有就聚合 `deploy/cve/<recipe>_cve.json`，并按 `<image>.rootfs.manifest`
   过滤成「镜像内软件包」口径 —— 否则 native 包会把数字抬高一个量级，
   与 6.0 不可比。过滤后一个都对不上时退回全量，并在报告里标
   `统计口径 = all-recipes`，不留「看起来正常」的假数字。

VEX 只有 5.0/6.0 有（`vex.bbclass`），且与 `cve-check` 互斥。本项目选择
保留 `cve-check`（四版口径统一优先），所以在 3.1/4.0 的「未修复」里会有
一些实际已被 `CVE_STATUS` 忽略的项 —— 报告里标注，不当回归。

## 4. FOSS：构建后批量，覆盖率如实记账

- 扫描在**构建容器内**进行：ScanCode 的 venv 里 python 是容器解释器的软链
  （3.1 py3.8 / 4.0 py3.10 / 5.0+ py3.12），搬到宿主直接报废。
- 输入优先 `work/downloads`（有 `SRC_URI` 归档的上游源码）。`file://` 与
  git 源的包不在其中，**缺口按包名如实记账**，不做静默补齐。
- 每包四件：`<pkg>.json` / `.csv` / `.spdx` / `.html`；`.html` 体积大，
  只留前 3 个。汇总在 `foss-summary.json`。
- `--foss-limit` 默认 20（0 = 不限）。1397 个源码包全扫是小时级，
  默认值是「先跑通闭环」，不是「扫完就合规」。覆盖率会写进报告，
  一眼能看出这是抽样。
- `--ignore` 不忽略 `temp/` 之类：这里扫的是解包后的上游源码树，不存在
  recipe 的 `S=${WORKDIR}` 问题（那个坑属于 #28 的 recipe 内扫描）。

## 5. 报告结构

`compliance-<date>-<sha>[-<variant>].md` 五节：

| 节 | 内容 |
|---|---|
| SBOM | 格式、文件、体积、SHA-256、打包形态、包/文件元素、PURL 非空率、VEX、许可证 top |
| CVE | 采集工具、清单、包数、未修复/已修复/忽略、数据源与库版本、统计口径 |
| FOSS | 工具、已扫/镜像内包数、覆盖率、文件数、许可证分布、逐包明细（前 25） |
| 格式差异 | 四版 SPDX 形态对照 + 本版本实际情况 + 语义差异说明 |
| 降级清单 | 只列合规相关项（`spdx-format` / `cve-tool` / `foss-scan`） |

验收门（不通过则退出码非零）：SBOM 可解析、CVE 有清单、FOSS 有结果、
FOSS 覆盖率 > 0。PURL 非空率 >= 90% 作为**观测项**列出，不设门 ——
CRA 语境下它决定漏洞匹配是否有效，但本项目当前只做「有就行」。

## 6. 与 CRA 的关系（留钩子，不实现）

`51-工作/compliance/CRA-Yocto多版本方案.md` 的两条钩子已经落在数据里：

1. **VEX**：6.0 的 `SPDX_INCLUDE_VEX` 让 SBOM 带
   `security_Vex{Fixed,NotAffected}VulnAssessmentRelationship`，
   报告里直接出计数。5.0 若改走 `vex.bbclass` 也能出，但不能与 `cve-check` 同开。
2. **PURL 非空率**：报告单独成行。`Version=git` 会让 CVE 匹配失效，
   这个比值就是它的量化。

未做的部分：SBOM → CVE 关联的持续监测、CVD 政策、24/72 小时值班 ——
这些是流程而不是构建产物，超出本工程范围。

## 7. 已知限制

- 6.0 的 CVE 只覆盖镜像 SBOM 里能关联到的包；`SBOM_CVE_CHECK_SCAN_SCOPE`
  保持默认 `target`，与前三版「只扫镜像内容」对齐。
- FOSS 许可证分布按 `license_expression` 计检出次数，不是按文件数加权，
  也没有做许可证兼容性判定。
- 3.1/4.0 的 `--spdx` 是真正新增的任务量（每 recipe 一个 `do_create_spdx`），
  首次开启会明显拉长构建时间，sstate 命中后回到正常水平。
- **3.1 的 SPDX 需要一份许可证别名补丁**（`yp-spdx-legacy-license.bbclass`）：
  dunfell 的 create-spdx 回移版本不把 `GPLv2+` 归一成 `GPL-2.0-or-later`，
  直接拿 `GPL-2+` 去 `common-licenses` 找文件，找不到就
  `Cannot find any text for license GPL-2+` 让 `do_create_spdx` 失败
  （实测 strace 是第一个）。类里按 recipe 的 `LICENSE` 生成 `<base>+` 的别名
  正文并挂到 `LICENSE_PATH`，4.0+ 上是空操作。SBOM 里那些包的许可证正文
  因此是「基础许可证的正文 + 原始 `+` 声明」，语义正确。
- 覆盖率的分子是「解包成功且 ScanCode 产出 json 的包数」，解包失败算失败，
  记在 `failed` 里，不进分子。
