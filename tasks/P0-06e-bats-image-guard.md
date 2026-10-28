# P0-06e · 03_container.bats 镜像缺席时显式 skip（CI 红 → 绿）

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-06e` |
| 分支 | `feat/P0-06-container-sh`（继续用） |
| 关联 Issue | #10 |
| 改动文件 | `tests/bats/03_container.bats`（**只改这一个文件**） |

## 问题（CI 实测）

PR #31 的 `ci` run 在 GitHub 托管 runner 上 `bats` job 红：

```
| Release | Tests | Passed | Failed | Skipped | Duration |
| all     |    46 |     36 |     10 |      0 |      3s   |
##[error]Process completed with exit code 1.
```

10 个失败全部来自 `tests/bats/03_container.bats`：runner 上**没有** `ghcr.io/zeek-zhao/yocto/<release>:local|latest` 镜像
（那是 215 本地构建的产物，CI 里只有 `images.yml` 在 main 上推镜像）。而 215 上 46/46 全绿。

也就是说：测试把「机器上已构建过 4 个镜像」当成了隐含前提，CI 环境没有 → 必红。
`scripts/container.sh` 的实现是对的（镜像缺席时报错并提示 `scripts/image.sh build`），**不要改实现**。

## 改法（加一个 skip 守卫）

在 `tests/bats/03_container.bats` 顶部（`setup()` 附近）加：

```bash
CONTAINER_SCRIPT="${BATS_TEST_DIRNAME}/../../scripts/container.sh"

# 镜像名与 scripts/container.sh 的 image_name() 保持一致
release_image() {
    printf 'ghcr.io/zeek-zhao/yocto/%s' "$1"
}

# 该环境没有可用镜像时跳过（CI runner 常态）；本地/215 构建过镜像则会真跑
require_release_image() {
    local release="$1"
    if docker image inspect "$(release_image "${release}"):local" >/dev/null 2>&1 ||
        docker image inspect "$(release_image "${release}"):latest" >/dev/null 2>&1; then
        return 0
    fi
    skip "release image not available in this environment: ${release}（CI runner 常态；215 上应真跑）"
}
```

然后在**每个需要真实镜像的用例**开头调用 `require_release_image <release>`：

- `--check` 的 4 个 release 循环 → 每个 release 前调用；
- 真起容器的用例（`id -un` / `id -u`）→ 调用 `require_release_image scarthgap`；
- 水位负向用例如果先解析镜像，也加；
- **纯参数校验类**用例（`--help`、未知 release、相对路径拒绝、单行 dry-run、嵌套 dry-run）**不要**加 skip——它们不碰镜像。

> 注意：`--dry-run` 目前也会解析镜像，如果它在无镜像环境非 0 退出，则同样需要守卫；
> **以实测为准**：先跑 `docker` 环境无镜像的等效验证（见验收第 3 条）。

再补 1 个用例，证明守卫本身有效：

```bash
@test "image guard skips when the release image is absent" {
    run require_release_image does-not-exist
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"skip"* || "${output}" == *"not available"* ]]
}
```
（`skip` 在子 shell 里返回 0 且带 skip 标记，用 `run` 断言它确实走了 skip 分支。）

## 不要做的事

- 不改 `scripts/container.sh`、`scripts/dev.sh`、`docs/`、`config/`；
- 不删任何用例、不降低任何断言；
- 不要为了凑绿把 `--check` 的 4 个 release 减成 1 个；
- 不新开分支。

## 验收标准

```bash
# 1) 215 上有 4 个镜像 → 期望 0 not ok、0 skip（新加的守卫不被触发）
bash scripts/dev.sh bats --print-output-on-failure tests/bats/03_container.bats
bash scripts/dev.sh bats tests/bats/

# 2) 门禁
bash scripts/dev.sh bash scripts/ci/lint.sh
bash scripts/dev.sh bash scripts/ci/secret-scan.sh

# 3) 模拟"无镜像环境"：把镜像临时藏起来验证 skip 生效（不要删镜像，用 tag 重命名后还原）
img=ghcr.io/zeek-zhao/yocto/scarthgap
had_local=0; had_latest=0
docker image inspect "${img}:local"  >/dev/null 2>&1 && { had_local=1;  docker tag "${img}:local"  "${img}:tmp-local";  docker rmi "${img}:local"  >/dev/null; }
docker image inspect "${img}:latest" >/dev/null 2>&1 && { had_latest=1; docker tag "${img}:latest" "${img}:tmp-latest"; docker rmi "${img}:latest" >/dev/null; }
bash scripts/dev.sh bats --print-output-on-failure tests/bats/03_container.bats || true
[ $had_local  -eq 1 ] && docker tag "${img}:tmp-local"  "${img}:local"
[ $had_latest -eq 1 ] && docker tag "${img}:tmp-latest" "${img}:latest"
```

- [ ] 第 1 条：0 not ok、**0 skip**（215 有镜像，守卫不触发）
- [ ] 第 3 条：镜像缺席时相关用例显示 `# skip`，且**没有** `not ok`
- [ ] 镜像已还原（`docker image inspect ghcr.io/zeek-zhao/yocto/scarthgap:local` 成功）
- [ ] `git diff --stat` 只含 `tests/bats/03_container.bats`

## 背景（为什么允许 skip）

CI runner 上没有 215 的本地构建产物，镜像只在 `images.yml`（main 分支）用 GHCR 推。
本地/build 机上 4 个镜像都在，验收要求 0 skip；CI 上容器运行时用例 skip 属预期，
但**纯逻辑用例（参数校验、dry-run 组装、水位门禁）必须在 CI 上真跑**，不能被 skip 掩盖。
