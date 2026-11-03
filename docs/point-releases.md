# LTS 点版本跟进流程

> 本项目对受支持的 Yocto LTS 做点版本（x.y.z）跟进：只跟 **wrynose 6.0** 与
> **scarthgap 5.0** 两个 LTS；kirkstone/dunfell 已 EOL（D12 冻结口径），不跟。
>
> 节奏与日期看 [Yocto Releases wiki](https://wiki.yoctoproject.org/wiki/Releases)
> 与 [endoflife.date/yocto](https://endoflife.date/yocto)——每半年一个大版本，
> LTS 每隔几周出一个点版本（如 2026-12-07 的 6.0.x / 5.0.x）。

## 为什么要跟点版本

点版本只包含安全与缺陷修复（CVE backport、构建修复），不改 API。跟进它们：

- CVE 扫描链（`scripts/cve-db.sh`）的「已修补」口径才成立——不升级，扫描器
  会一直报上游已修的 CVE；
- CRA（EU《网络弹性法案》）第 14 条自 2026-09 生效，安全更新能力是合规硬要求
  （全面执行日 2027-12-11）；本项目作为发行版工程样例，点版本跟进就是它的
  「安全更新流程」本身。

## 版本钉扎在哪

| release | 文件 | 变量 |
|---|---|---|
| dunfell / kirkstone / scarthgap | `config/<release>.env` | `POKY_TAG`（如 `yocto-5.0.20`）|
| wrynose | `config/wrynose.env` | `OE_CORE_TAG` / `BITBAKE_TAG` / `META_YOCTO_TAG`（三仓拆分，`REPO_MODE=split`）|

`kas` 在 checkout 时按这些 TAG 取源码；`EXPECT_SHA` 是人读的辅助字段（脚本当前
不校验它），升级 TAG 时顺手更新。

## 点版本跟进步骤

1. **发现**：上游发布点版本（wiki 公告 / mailing list）。
2. **升级钉扎**：改 `config/<release>.env` 的 TAG（wrynose 改三个）+
   `EXPECT_SHA`（新 tag 的 commit，`git ls-remote <repo> refs/tags/<tag>` 可查）。
3. **全量回归**：
   ```bash
   bash scripts/release-check.sh                       # 两 LTS × 两 variant
   ```
   失败项看 `/tmp/release-check-*.log`；全绿后 8 份归档已刷新（report.sh
   按「日期-指纹」落 `docs/qa/<release>/`，旧指纹归档按「删旧再渲」纪律删除）。
4. **提交**：TAG bump + 新归档一个 commit（Conventional Commits：
   `chore(release): 跟进 yocto-5.0.21 / yocto-6.0.5`）。
5. **出问题怎么办**：点版本回归若红，先看是上游修复暴露了我们的既有问题
   （如 #109 的 0700 污染被新 dnf 行为放大）还是上游回归——前者修自己，
   后者可暂缓 TAG 并在上游 issue 跟进；`docs/point-releases.md` 不记个案。

## 边界

- EOL 版本不跟（kirkstone 2026-04 / dunfell 2024-04 已停）；它们的 TAG 只在
  语法对照（#84）与 D12 冻结口径下使用。
- 点版本升级不跨大版本：跨大版本（如 6.0 → 6.1）是里程碑级工作，不是本流程。
- qemuarm64 维度：`release-check.sh --machine qemuarm64`（#27 验证过的两组合：
  scarthgap/wrynose × general）——作为可选抽查，不进默认回归。
