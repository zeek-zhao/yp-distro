# 任务卡 P1-07：报告新增「跨版本差异」节（Issue #19 验收项）

## 背景

Issue #19（scarthgap 全链路实跑）的验收里有一条：

> [ ] 与 wrynose 报告的差异段非空（**跨版本差异必须显式记录，不许复制粘贴**）

现在 `scripts/report.sh` 没有这一节。scarthgap(5.0) 的真构建正在 215 上跑（预计 4551 任务），跑完就要出报告，所以这一节现在补。

## 已实测的差异事实（不要重新怀疑，可直接用）

在 215 上直接读两份已检出的源码（`work/kas-scarthgap-general/poky` 与 `work/kas-wrynose-general/openembedded-core`）得到：

| aspect | scarthgap 5.0 | wrynose 6.0 |
|---|---|---|
| `DISTRO_VERSION` | `5.0.20` | `6.0.4` |
| SPDX class | `create-spdx-2.2.bbclass` + `create-spdx-3.0.bbclass` 都在 | 只有 `create-spdx-3.0.bbclass`（2.2 被删） |
| `SPDX_VERSION` 取值 | `"2.2"` 与 `"3.0.1"` | 只有 `"3.0.1"` |
| CVE class | `meta/classes/cve-check.bbclass` | `sbom-cve-check-*.bbclass`（`cve-check` 已不存在） |
| `DISTRO_FEATURES_BACKFILL` | 真实生效：`bitbake.conf` 里 `= "pulseaudio sysvinit gobject-introspection-data ldconfig"` | 只剩改名墓碑：`BB_RENAMED_VARIABLES[DISTRO_FEATURES_BACKFILL] = "is obsolete…"` |
| 内核 recipe | `linux-yocto_6.6.bb` | `linux-yocto_6.18.bb` |
| GCC | `GCCVERSION ?= "13.%"` | `GCCVERSION ?= "15.%"` |
| `IMAGE_FSTYPES`（`qemu.inc`） | `tar.bz2 ext4` | `tar.zst ext4.zst` |

（wrynose 的 `DISTRO_VERSION` 我没直接从同一路径取到 —— 它是三仓库拆分，`meta-poky` 在 `meta-yocto` 仓库里。
按 `config/wrynose.env` 的版本锁 `yocto-6.0.4`，值就是 `6.0.4`。如果你能顺手核实一下更好，核实不了就用 `6.0.4`。）

## 要做的

### 1. 新增 `config/crossdiff.txt`（唯一真本）

格式：`aspect | <release>=<取值> | <release>=<取值>`（release 列按需增减，只填**已经真跑过**的版本）。

```
# 跨版本差异真本。每行：aspect | <release>=<取值> | ...
# 取值必须是可核验的事实（源码路径/变量值），不要写主观描述。
# 只有真跑过的版本才填；新增版本时同步加列。
distro-version | scarthgap=5.0.20 | wrynose=6.0.4
spdx-format | scarthgap=2.2 + 3.0.1 | wrynose=3.0.1 only
cve-class | scarthgap=cve-check | wrynose=sbom-cve-check
distro-backfill | scarthgap=生效（pulseaudio sysvinit gobject-introspection-data ldconfig） | wrynose=仅改名墓碑
kernel | scarthgap=linux-yocto 6.6 | wrynose=linux-yocto 6.18
gcc | scarthgap=13.% | wrynose=15.%
image-fstypes | scarthgap=tar.bz2 ext4 | wrynose=tar.zst ext4.zst
```

注意取值里**不要出现 `|`**（列分隔符）。

### 2. `scripts/report.sh`：新增「## 跨版本差异」节

放在「## 降级清单」之后。内容规则：

- 遍历 `config/crossdiff.txt` 的每一行；
- 输出一个表格：第一列 `` `aspect` ``，后面**每个其它 release 一列**（即：当前 release 自己 + 对比方）。建议格式：
  `| aspect | 本版本(wrynose) | scarthgap |` —— 只要能让读者看出"我 vs 别人"的差异即可；
- 若 `crossdiff.txt` 里只有当前 release 一列（还没别的版本真跑过）→ 该节写一行
  `n/a（尚无其它版本归档，无可比对象）`，**不要**因此新增 degraded 项；
- 缺失/无归档时同样写 `n/a`，不写 failed。

### 3. 新增 `tests/bats/08_crossdiff.bats`

打 `# bats test_tags=crossdiff`。至少 4 个用例：

1. **格式校验**：`config/crossdiff.txt` 每行至少 3 列；第 2 列起必须是 `<合法release>=<非空取值>`；aspect 不重复。
   合法 release 取自 `config/*.env`（dunfell/kirkstone/scarthgap/wrynose）。
2. **反向**：临时目录里造一份坏文件（例如某行只有 2 列、或 release 名非法、或取值含 `|`），校验函数必须报错。
   **临时目录必须建在 `<repo>/work/` 下**（容器里 `/tmp` 不共享，这个坑以前踩过）。
3. **报告含该节且非空**：用真实 `config/crossdiff.txt` 渲染 wrynose 报告（`--render-only`），断言含 `## 跨版本差异`，且表格行数 == `crossdiff.txt` 的有效行数。
4. **不许复制粘贴（可执行化）**：渲染 wrynose 报告后，断言「wrynose 列」与「scarthgap 列」**至少有一行取值不同**。
   这条正是 Issue #19 「不许复制粘贴」那条验收的可执行版本 —— 请在用例上方注释写明。

### 4. `config/features.txt` 增一行

```
cross-version-diff | all | tests/bats/08_crossdiff.bats | crossdiff | ok
```

（`99_coverage.bats` 有一条「every non-meta BATS file is referenced by a feature」的用例，不加这行会红。注意第 5 列是 `ok` 不是 `degraded`。）

### 5. `docs/qa/README.md`

补一句说明：跨版本差异的真本是 `config/crossdiff.txt`，报告只做呈现。

## 明确不要做

- 不要改 `scripts/build.sh`、`kas/base.yml`
- 不要改 `config/degraded.txt`、不要新增 degraded 项
- 不要动 `docs/qa/wrynose/` 下已归档的报告文件
- 不要跑真构建（scarthgap 正在跑，别干扰）
- 不要用完整模式跑 `report.sh` 做验证（会递归跑 BATS）—— 一律 `--render-only`

## 验收（容器内，全部 rc=0）

```bash
cd /home/jenkins/workspace/yocto

bash scripts/dev.sh shfmt -d -i 4 -ci scripts/ tests/
bash scripts/dev.sh shellcheck -S warning scripts/*.sh scripts/lib/*.sh
bash scripts/dev.sh bats -r tests/bats/                 # 必须 >= 102 ok，0 not ok，0 skip
bash scripts/dev.sh bats --filter-tags crossdiff tests/bats/
bash scripts/dev.sh bash scripts/report.sh --release wrynose --variant general --render-only
grep -A6 '## 跨版本差异' docs/qa/wrynose/*-render.md
```

**渲染产生的 `*-render.md` 必须删掉。**
另外 `docs/qa/wrynose/artifacts.sha256` 是 #18 的归档存证，跑 `report.sh` 会重写它的头部 commit 注释 ——
验收完 `git checkout -- docs/qa/wrynose/artifacts.sha256` 恢复（已知缺陷，见 Issue #41，本卡不修）。

## 提交

- 分支 `feat/P1-07-crossdiff`（从 `dev` 切，我会先切好；若你发现不在该分支，停下手上的活先告诉我）
- 提交信息注明 `Refs #19`
- 不要 push / 开 PR
