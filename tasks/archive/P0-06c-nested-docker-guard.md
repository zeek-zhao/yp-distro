# P0-06c · container.sh 末条修正（嵌套时禁用 docker CLI 兜底）

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-06c` |
| 分支 | `feat/P0-06-container-sh`（继续用，不新开） |
| 关联 Issue | #10 |
| 依赖 | P0-06 / P0-06b 已产出（未提交） |
| 改动文件 | `scripts/container.sh`（预计 4~6 行）；**其他文件不要动** |

## 唯一要修的问题

`scripts/container.sh` 约 139-152 行：

```bash
host_docker="${WB_HOST_DOCKER_BIN:-}"
if [[ -z "${host_docker}" ]]; then
    host_docker="$(command -v docker 2>/dev/null || true)"   # ← 嵌套模式下这里是「容器内」路径
fi
```

`scripts/dev.sh` 已经正确透传了两个宿主侧环境变量（本次已验证）：
`WB_HOST_REPO_DIR` / `WB_HOST_DOCKER_BIN` / `WB_HOST_DOCKER_PLUGIN_DIR`。

**问题**：在嵌套模式（`WB_HOST_REPO_DIR` 已设）下若 `WB_HOST_DOCKER_BIN` 缺失，代码会回落到
`command -v docker`，在 dev 容器里得到 `/usr/bin/docker`——那是**容器内路径**，作为 `-v` 源挂载
到宿主会失败或误建目录。同理 `plugin_dir` 的候选目录探测在嵌套下也不该兜底。

**实测红**（`bash scripts/dev.sh bats tests/bats/03_container.bats`）：

```
not ok 37 nested dry-run accepts an invisible host path without mounting docker binaries
# (in test file tests/bats/03_container.bats, line 74)
#   `[[ "${output}" != *"/usr/local/bin/docker"* ]]' failed
# Last output: ... -v /usr/bin/docker:/usr/local/bin/docker:ro -v /usr/libexec/docker/cli-plugins:/usr/local/lib/docker/cli-plugins:ro ...
```

## 改法

```bash
# 兜底只在「宿主直跑」时启用；嵌套模式必须由 dev.sh 显式透传宿主路径
if [[ -z "${host_docker}" && -z "${WB_HOST_REPO_DIR:-}" ]]; then
    host_docker="$(command -v docker 2>/dev/null || true)"
fi
```

`plugin_dir` 的候选目录探测同样加 `[[ -z "${WB_HOST_REPO_DIR:-}" ]]` 条件。

嵌套且两个变量都缺时，`log_info` 打一条「嵌套模式且未透传宿主 docker 路径，跳过 CLI 挂载」
（构建本身不需要 docker CLI，属预期）。

## 不要做的事

- 不要改测试用例的断言强度（`03_container.bats` 用例 37 已经是正确断言，**改实现、不要改测试**）；
- 不要改 `scripts/dev.sh`（它已经对了）；
- 不要动 `docs/`、`README.md`、`config/features.txt`；
- 不要新开分支、不要动 `layers/meta-yp/`、不要真跑构建。

## 验收标准（全部经 dev.sh 进容器）

```bash
bash scripts/dev.sh bats --print-output-on-failure tests/bats/03_container.bats   # 12/12 全绿
bash scripts/dev.sh bats tests/bats/                       # 0 not ok、0 skip
bash scripts/dev.sh bash scripts/ci/lint.sh                # 四段 ok
bash scripts/dev.sh bash scripts/ci/secret-scan.sh         # clean

# 嵌套 dry-run 不含容器内 docker 路径（这就是本卡的核心断言）
bash scripts/dev.sh bash scripts/container.sh --release scarthgap --dry-run > /tmp/d.txt
grep -q -- '--name yocto-scarthgap-general' /tmp/d.txt
grep -vq -- '/usr/bin/docker:/usr/local/bin/docker' /tmp/d.txt || { echo "嵌套时不应挂容器内 docker 路径"; exit 1; }
```

- [ ] 上述命令全部 rc=0
- [ ] `git status` 只有 `scripts/container.sh` 一个文件相对上一轮发生变化
- [ ] **不要**尝试删除宿主 `/usr/local/bin/docker`（那是 root 拥有的历史空目录，jenkins 无权删，
      与本卡无关；本卡只要求「不再新增此类挂载」）
