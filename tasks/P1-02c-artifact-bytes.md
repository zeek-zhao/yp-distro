# P1-02c 修正：产物字节数取符号链接目标 + 排除 qemuboot.conf

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P1-02c` |
| 里程碑 | `v0.2.0` |
| 分支 | `feat/P1-02-qa-report`（**当前分支，直接改**） |
| 关联 Issue | `#18` |
| 依赖 | `P1-02` / `P1-02b`（已提交 `ffd4db3`） |
| 预计改动文件 | `scripts/lib/artifacts.sh`、`tests/bats/06_report.bats` |

## 背景

wrynose 真构建跑通后（4630/4630 全过），`scripts/report.sh` 生成的报告里出现：

```
- Artifact: `core-image-minimal-qemux86-64.rootfs.ext4.zst`
- Artifact bytes: `60`
```

但该文件实际是 **20 MB**。原因是 deploy 目录里 `core-image-minimal-qemux86-64.rootfs.ext4.zst` 是一个**符号链接**（指向 `...-20261028155200.ext4.zst`），而 `artifact_bytes()` 用的是 `stat -c %s`（不跟随链接），返回的是**链接本身的长度 60 字节**。

同样，`artifacts.sha256` 里混进了 `core-image-minimal-qemux86-64.rootfs.qemuboot.conf`——那是 qemu 启动配置，不是镜像产物。

SHA-256 是对的（`sha256sum` 默认跟随链接），所以只有字节数错、以及产物清单多一项。

## 要做的事

### 1. `artifact_bytes` 跟随符号链接

把 `stat -c %s -- "$1"` 改成 `stat -Lc %s -- "$1"`（`-L` = dereference）。保持函数签名与失败语义不变（文件不存在 return 1）。

### 2. 把 `*.qemuboot.conf` 排除出产物清单

`artifact_list()` 和 `artifact_primary()` 的排除条件里加上 `*.qemuboot.conf`。现有排除是 `.manifest` / `.testdata.json` / `.spdx.*` / `.json`，在同样两处（list 与 primary 的兜底分支）各补一条。

### 3. `06_report.bats` 补两条用例

**a) 符号链接的字节数**（防回归）：

```bash
# bats test_tags=report
@test "artifact bytes follows symlinks in deploy dir" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy-link"
    mkdir -p "${deploy_dir}"
    head -c 4096 /dev/zero >"${deploy_dir}/core-image-minimal-qemux86-64.rootfs-1.ext4.zst"
    ln -s core-image-minimal-qemux86-64.rootfs-1.ext4.zst \
        "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.ext4.zst"

    run artifact_primary "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    run artifact_bytes "${output}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "4096" ]
}
```

**b) `qemuboot.conf` 不算产物**：

```bash
# bats test_tags=report
@test "artifact list excludes qemuboot.conf" {
    local deploy_dir="${BATS_TEST_TMPDIR}/deploy-qb"
    mkdir -p "${deploy_dir}"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.ext4.zst"
    touch "${deploy_dir}/core-image-minimal-qemux86-64.rootfs.qemuboot.conf"

    run artifact_list "${deploy_dir}" core-image-minimal qemux86-64
    [ "${status}" -eq 0 ]
    [[ "${output}" == *".rootfs.ext4.zst"* ]]
    [[ "${output}" != *".qemuboot.conf"* ]]
}
```

## 不要做的事

- 不要动 `scripts/report.sh`（渲染逻辑没问题）、不要动 `config/`、不要动其它 `.bats`。
- 不要跑真实构建、不要删 `work/` 下的产物与串口日志（那是验收证据）。
- 不要重新生成 `docs/qa/` 下的报告（WorkBuddy 拿到修复后会统一重跑）。
- 不要 `git commit`。

## 验收标准

```bash
bash scripts/dev.sh shfmt -d -i 4 -ci scripts/ tests/
bash scripts/dev.sh shellcheck -S warning scripts/*.sh scripts/lib/*.sh
bash scripts/dev.sh bats -r tests/bats/
bash scripts/dev.sh bats --filter-tags report tests/bats/
```

- [ ] 上述命令全部退出码 0；全量 BATS 从 91 增加到 **93 ok / 0 not ok**
- [ ] `git status --porcelain` 只包含本卡「预计改动文件」
- [ ] `git diff scripts/lib/artifacts.sh` 里能看到 `-Lc` 与 `qemuboot.conf` 两处
