# P1-02b 修正：features 五列引发的旧断言 + 产物校验和路径 + zst 产物用例

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P1-02b` |
| 里程碑 | `v0.2.0` |
| 分支 | `feat/P1-02-qa-report`（**当前分支，直接改**，不要 switch/create） |
| 关联 Issue | `#18` |
| 依赖 | `P1-02`（已在当前工作区，未提交） |
| 预计改动文件 | `tests/bats/05_kas.bats`、`scripts/report.sh`、`tests/bats/06_report.bats`、`docs/qa/README.md` |

## 背景

`P1-02` 把 `config/features.txt` 从 4 列改成 5 列（新增 `status`）。上一轮任务卡里写了「不动 `05_kas.bats`」，但该文件里有两处断言精确匹配 4 列格式，因此全量 BATS 现在有 **2 个 not ok**：

```
05_kas.bats line 138: grep -q '^kas-layer | all | tests/bats/05_kas.bats | kas$'
05_kas.bats (kas feature and BATS tag registration match) 同上
```

这是任务卡的范围错误，不是实现错误。本卡修掉它，并顺带修 3 个实现层面的问题。

## 要做的事

### 1. 修 `tests/bats/05_kas.bats` 的两处断言（必须）

两处 `grep -q '^kas-layer | all | tests/bats/05_kas.bats | kas$'` 都改成匹配 5 列：

```
'^kas-layer | all | tests/bats/05_kas.bats | kas | ok$'
```

**只改这两行**，不要改 `05_kas.bats` 里的其它用例。

### 2. `artifacts.sha256` 用仓库相对路径（必须）

现在 `scripts/report.sh` 写 `artifacts.sha256` 时直接 `sha256sum -- "${artifact_path}"`，落盘是 `/home/jenkins/workspace/yocto/work/...` 这样的**绝对路径**。这个文件要入库，绝对路径既泄露执行机路径也不可复现。

改成写相对仓库根的路径：复用已有的 `relative_path()`，即

```
<sha256>  work/kas-wrynose-general/build/tmp/deploy/images/qemux86-64/core-image-minimal-qemux86-64.rootfs.ext4.zst
```

提示：`sha256sum` 输出是 `<hash>  <path>`（两个空格），手工拼装时保持这个格式（`printf '%s  %s\n' "$(artifact_sha256 "$f")" "$(relative_path "$f")"`），不要破坏 `sha256sum -c` 的可解析性。

同时把「构建产物」节里那行说明改成与实际一致：`- 全部产物 sha256: 见 `artifacts.sha256`（同目录，路径相对仓库根）`。

### 3. `06_report.bats` 补一条 `.zst` 产物用例（必须）

**实测事实**：wrynose（6.0）的 `meta/conf/machine/include/qemu.inc` 里是 `IMAGE_FSTYPES += "tar.zst ext4.zst"`，所以真实 deploy 产物是

- `core-image-minimal-qemux86-64.rootfs.ext4.zst`
- `core-image-minimal-qemux86-64.rootfs.tar.zst`

现有用例只造了 `.rootfs.ext4` / `.rootfs.tar.bz2`，没覆盖真实形态。新增一条 `# bats test_tags=report` 用例：

```bash
@test "artifact primary prefers zstd ext4 and list keeps zstd tarballs" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy-zst"
    mkdir -p "${deploy_dir}"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.ext4.zst"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.tar.zst"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.manifest"

    run artifact_primary "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *".rootfs.ext4.zst" ]]

    run artifact_list "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *".rootfs.ext4.zst"* ]]
    [[ "${output}" == *".rootfs.tar.zst"* ]]
    [[ "${output}" != *".manifest" ]]
}
```

如果 `artifact_primary` / `artifact_list` 在这个用例下不成立，**改 `scripts/lib/artifacts.sh` 让它成立**（真实产物形态优先），不要改用例去迁就实现。

### 4. `docs/qa/README.md` 补「降级项实测依据」小节（必须）

降级清单不能只有结论没有证据。在 README 末尾加一节，列出三条可复核的依据（下面是我在 wrynose checkout 上实测到的原文，照抄即可）：

```markdown
## 降级项实测依据（wrynose = yocto-6.0.4）

| aspect | 实测依据 |
|---|---|
| `spdx-format` | `image_types_spdx.bbclass` 已不存在；`meta/classes/` 下只剩 `create-spdx.bbclass`、`create-spdx-3.0.bbclass`，`meta/classes-recipe/` 下是 `create-spdx-image-3.0.bbclass`、`create-spdx-sdk-3.0.bbclass` → 只能产出 SPDX 3.0 SBOM |
| `cve-tool` | `cve-check.bbclass` 已不存在；`meta/classes-recipe/sbom-cve-check.bbclass` 存在 |
| `distro-backfill` | `meta/conf/bitbake.conf` 里只剩墓碑声明：`BB_RENAMED_VARIABLES[DISTRO_FEATURES_BACKFILL] = "is obsolete, add all default features to DISTRO_FEATURES_DEFAULTS"` |
```

### 5. 报告标题（必须）

`report.sh` 现在生成的标题是 `# BATS QA Report`，但它已经不止 BATS 了（含构建产物、QEMU 串口、降级清单）。改成 `# QA Report`，并在标题下第一行加一条 `- Kind: ` 字段，值为 `bats+build`（正常模式）或 `render-only`（`--render-only`）。不要动其它已有一行字段的格式。

## 不要做的事

- 不要改 `config/features.txt` 的列结构、不要改 `config/degraded.txt` 的内容。
- 不要动 `01_dockerfile.bats` / `02_workflows.bats` / `03_container.bats` / `04_layer.bats` / `99_coverage.bats`。
- 不要跑真实构建、不要碰 `work/` 下任何东西（那里有正在跑的构建）。
- 不要改 `report.sh --print-fingerprint`。
- 不要 `git commit`。

## 验收标准

```bash
# 1. 静态检查
bash scripts/dev.sh shfmt -d -i 4 -ci scripts/ tests/
bash scripts/dev.sh shellcheck -S warning scripts/*.sh scripts/lib/*.sh

# 2. 全量 BATS：必须 0 not ok（改动前是 88 ok / 2 not ok）
bash scripts/dev.sh bats -r tests/bats/

# 3. 05_kas 那两处断言真的被修了
grep -c "kas-layer | all | tests/bats/05_kas.bats | kas | ok" tests/bats/05_kas.bats   # == 2

# 4. zst 产物用例存在且通过
bash scripts/dev.sh bats --filter-tags report tests/bats/

# 5. render 报告含新标题与新字段
bash scripts/dev.sh bash scripts/report.sh --release wrynose --variant general --render-only
head -3 docs/qa/wrynose/*-render.md
grep -q '^# QA Report' docs/qa/wrynose/*-render.md
grep -q '^- Kind: `render-only`' docs/qa/wrynose/*-render.md
```

- [ ] 上述命令全部退出码 0
- [ ] 全量 BATS 0 not ok，skip 只出现在 `require_*` 相关用例
- [ ] `05_kas.bats` 只改那两行断言（`git diff tests/bats/05_kas.bats` 只能看到 2 行改动）
- [ ] `git status --porcelain` 只包含本卡「预计改动文件」
