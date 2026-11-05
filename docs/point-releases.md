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

| release | 钉扎点①（kas 实际消费） | 钉扎点②（kas 复现锁） | 钉扎点③（config，人读辅助）|
|---|---|---|---|
| dunfell / kirkstone / scarthgap | `kas/releases/<release>.yml` 的 `repos.poky.tag` | `kas/targets/<release>-{custom,general}.lock.yml` 的 `commit` | `config/<release>.env` 的 `POKY_TAG` + `EXPECT_SHA` |
| wrynose | `kas/releases/wrynose.yml` 的三个 `tag:` | `kas/targets/wrynose-*.lock.yml` 的三个 `commit` | `config/wrynose.env` 的三个 `*_TAG` |

**三处都要改**（lock 是每 target 一份，scarthgap 就是 2 份）：
1. 只改 config 不改 yml → `kas-verify` 漂移门禁拦下（`repos.poky.tag '旧' != '新'`，
   2026-11-05 首演实证）
2. yml+config 改了但 lock 没改 → kas 仍 checkout 旧 commit（lock 的 commit 优先），
   或报 `Provided tag does not match provided commit`
3. 另外 `build.sh` 用 `KAS_CLONE_DEPTH=1` 浅克隆，旧克隆里没有新 tag 时 kas 也不
   会补 fetch（报 `Tag cannot be found`）——删 KAS_WORK_DIR 下对应 repo 目录让
   kas 在新 tag 重克隆，sstate/downloads 在外不受影响

`kas` 在 checkout 时按这些 TAG 取源码；`EXPECT_SHA` 是人读的辅助字段（脚本当前
不校验它），升级 TAG 时顺手更新。

## 点版本跟进步骤

1. **发现**：上游发布点版本（wiki 公告 / mailing list）。
2. **升级钉扎（两处）**：改 `kas/releases/<release>.yml` 的 `repos.poky.tag`
   （wrynose 是三个 repos 的 `tag:`），**同时**改 `config/<release>.env` 的
   TAG + `EXPECT_SHA`（新 tag 的 commit，`git ls-remote <repo> refs/tags/<tag>`
   可查）。漏改任何一处，`kas-verify` 或 doctor 的口径对不上都会拦下。
3. **浅克隆坑**：`build.sh` 用 `KAS_CLONE_DEPTH=1` 克隆上游——旧克隆里没有新
   tag，kas 会报 `Tag "x.y.z" cannot be found in repository "poky"`（不会自动
   补 fetch）。处置：删掉 KAS_WORK_DIR 下对应 repo 目录（如
   `work/kas-scarthgap-custom/poky`）让 kas 在新 tag 重克隆；sstate/downloads
   都在外面，不受影响。
4. **全量回归**：
   ```bash
   bash scripts/release-check.sh                       # 两 LTS × 两 variant
   ```
   失败项看 `/tmp/release-check-*.log`；全绿后 8 份归档已刷新（report.sh
   按「日期-指纹」落 `docs/qa/<release>/`，旧指纹归档按「删旧再渲」纪律删除）。
5. **提交**：TAG bump + 新归档一个 commit（Conventional Commits：
   `chore(release): 跟进 yocto-5.0.21 / yocto-6.0.5`）。
6. **出问题怎么办**：点版本回归若红，先看是上游修复暴露了我们的既有问题
   （如 #109 的 0700 污染被新 dnf 行为放大）还是上游回归——前者修自己，
   后者可暂缓 TAG 并在上游 issue 跟进；`docs/point-releases.md` 不记个案。

## 边界

- EOL 版本不跟（kirkstone 2026-04 / dunfell 2024-04 已停）；它们的 TAG 只在
  语法对照（#84）与 D12 冻结口径下使用。
- 点版本升级不跨大版本：跨大版本（如 6.0 → 6.1）是里程碑级工作，不是本流程。
- qemuarm64 维度：`release-check.sh --machine qemuarm64`（#27 验证过的两组合：
  scarthgap/wrynose × general）——作为可选抽查，不进默认回归。
