# P0-06d · 修 03_container.bats 的环境密闭性（仅 1 处）

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-06d` |
| 分支 | `feat/P0-06-container-sh`（继续用） |
| 关联 Issue | #10 |
| 改动文件 | `tests/bats/03_container.bats`（**只改 1 个用例，1~2 行**） |

## 问题

用例 `nested dry-run accepts an invisible host path without mounting docker binaries`（约 71-79 行）只
设了 `WB_HOST_REPO_DIR`，却断言输出里**没有** `/usr/local/bin/docker` 挂载。但它**没清掉**继承来的
`WB_HOST_DOCKER_BIN` / `WB_HOST_DOCKER_PLUGIN_DIR`：

- 在 CI（runner 上直接跑 `bats`）里这两个变量不存在 → 用例绿；
- 在 `scripts/dev.sh` 里跑时，`dev.sh` 必然会 `-e WB_HOST_DOCKER_BIN=<宿主 docker>` 透传 → 用例红：

```
not ok 37 nested dry-run accepts an invisible host path without mounting docker binaries
# (in test file tests/bats/03_container.bats, line 74)
#   `[[ "${output}" != *"/usr/local/bin/docker"* ]]' failed
```

即「同一份代码，CI 绿、WF3 派单环境红」——这正是本项目所有验收环境（`dev.sh`）都会撞上的坏测试。
根因是**用例不密闭**，不是实现有问题（实现已正确：显式透传时正常挂载，见用例 38）。

## 改法（只改这一处）

```bash
# 现在
run --separate-stderr env WB_HOST_REPO_DIR=/not-visible-on-purpose/yocto \
    bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run

# 改为（显式清掉宿主侧两个变量，模拟"dev.sh 未透传"场景）
run --separate-stderr env -u WB_HOST_DOCKER_BIN -u WB_HOST_DOCKER_PLUGIN_DIR \
    WB_HOST_REPO_DIR=/not-visible-on-purpose/yocto \
    bash "${CONTAINER_SCRIPT}" --release scarthgap --dry-run
```

**不许**改断言、不许删用例、不许改 `scripts/container.sh`。

## 不要做的事

- 不改其他任何用例（其他用例不涉及这两个变量的「缺席」断言）；
- 不改 `scripts/`、`docs/`、`config/`；
- 不新开分支；
- 不要删宿主 `/usr/local/bin/docker`（root 拥有，与本卡无关）。

## 验收标准（必须经 dev.sh 跑，这才是会被撞上的环境）

```bash
bash scripts/dev.sh bats --print-output-on-failure tests/bats/03_container.bats   # 13/13 全绿
bash scripts/dev.sh bats tests/bats/                                              # 0 not ok、0 skip
bash scripts/dev.sh bash scripts/ci/lint.sh                                       # 四段 ok
bash scripts/dev.sh bash scripts/ci/secret-scan.sh                                # clean
```

- [ ] 上述全部 rc=0（**关键是第一条**：上一轮就是它在 dev.sh 环境下红）
- [ ] `git diff --stat` 只含 `tests/bats/03_container.bats`
