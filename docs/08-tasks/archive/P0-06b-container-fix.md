# P0-06b · container.sh 修正卡（嵌套路径 / dry-run 可 grep / passwd 注入）

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-06b` |
| 里程碑 | `v0.1.0` |
| 分支 | `feat/P0-06-container-sh`（**继续用现有分支**，不要新开） |
| 关联 Issue | #10 / #16（修正卡，同 P0-03b 的做法） |
| 依赖 | P0-06 已产出 `scripts/container.sh` 等 7 文件（未提交） |
| 预计改动文件 | `scripts/container.sh`、`tests/bats/03_container.bats`、`docs/03-build/container.md` |

## 背景（P0-06 验收实测，3 个真缺陷）

WorkBuddy 独立验收（在**宿主**上 `bash scripts/container.sh` 与在 **dev 容器内** `bash scripts/dev.sh bats tests/bats/`）结果不一致，定位到三条：

1. **嵌套路径检查写错，导致容器内全红**：`scripts/container.sh:75` 有
   `[[ -d "${HOST_REPO_DIR}" ]] || die "仓库目录不存在：${HOST_REPO_DIR}"`。
   `HOST_REPO_DIR` 是**宿主**路径（dev.sh 通过 `-e WB_HOST_REPO_DIR=<宿主绝对路径>` 传进来），
   在 dev 容器里根本不存在 → 5 个 BATS 用例全红：
   ```
   not ok 2 all local release images pass container preflight
   # Last output: [ERROR] 仓库目录不存在：/home/jenkins/workspace/yocto
   ```
   你在宿主直接跑 `bats`（`WB_HOST_REPO_DIR` 未设 → 走 `${ROOT_DIR}`）所以没暴露。
   **本项目所有验收都必须经 `bash scripts/dev.sh ...` 进容器跑**，与 CI 环境一致。

2. **嵌套时把容器内路径当宿主路径挂载**：docker CLI / plugin 目录用
   `command -v docker` 得到的**容器内路径**（如 `/usr/local/bin/docker`）作为 `-v` 源，
   在宿主上该路径可能不存在 → docker 会在宿主创建同名空目录，污染宿主。
   这与 P0-03 踩过的「嵌套挂载成空目录」是同一类坑。

3. **`id -un` 无法解析**：构建机宿主 uid 是 **2000**，镜像内 `builder` 是 **1000**，
   `--user 2000:2000` 进容器后 `id -un` 输出 `id: cannot find name for user ID 2000`。
   Yocto/bitbake 依赖 `getpwuid` 的路径会因此出怪问题，必须让用户名可解析。

4. （附带）`--dry-run` 用 `printf ' \\\n    %q'` 把**每个参数拆成独立行**，导致
   `grep -- '--name yocto-scarthgap-general'` 匹配不到；任务卡原要求「一条命令里带换行缩进」，
   实际应改为**单行输出**（既好 grep 又好复制粘贴）。

## 要做的事

### 1. 修 `HOST_REPO_DIR` 的校验（`scripts/container.sh`）

```bash
# 现状（错误）：容器内 WB_HOST_REPO_DIR 是宿主路径，-d 必假
[[ -d "${HOST_REPO_DIR}" ]] || die "仓库目录不存在：${HOST_REPO_DIR}"

# 改为：
# - 绝对路径必须校验；
# - 路径存在性只校验「当前可见的仓库」ROOT_DIR；
# - 嵌套（WB_HOST_REPO_DIR 已设）时给一条 log_info 说明挂载源是宿主路径，不做 -d 检查
[[ "${HOST_REPO_DIR}" == /* ]] || die "WB_HOST_REPO_DIR 必须是绝对路径：${HOST_REPO_DIR}"
[[ -d "${ROOT_DIR}" ]] || die "仓库目录不存在：${ROOT_DIR}"
if [[ -n "${WB_HOST_REPO_DIR:-}" ]]; then
    log_info "嵌套模式：挂载源用宿主路径 ${HOST_REPO_DIR}"
fi
```

### 2. 嵌套时不挂宿主 docker 二进制/插件目录

```bash
# 只有在「宿主直跑」时才挂 docker CLI（嵌套时容器内路径 ≠ 宿主路径，会污染宿主）
if [[ -z "${WB_HOST_REPO_DIR:-}" ]]; then
    ... 现有的 host_docker / plugin_dir 挂载逻辑 ...
else
    log_info "嵌套模式：跳过 docker CLI 挂载（socket 已挂，容器内可直接用宿主 docker）"
fi
```

`socket` 挂载保持原样（嵌套时 `/var/run/docker.sock` 是同一个宿主 socket，安全）。

> 注意：release 构建镜像里**本来没有** docker CLI。嵌套场景下容器内确实没有 `docker` 命令，
> 这是预期（构建本身不需要 docker）；需要在 `docs/03-build/container.md` 写明。

### 3. 注入 passwd 条目，让 `id -un` 恒为 `builder`

起容器前（`--check`/`--dry-run` 不做，只有真要 run 时做）：

```bash
# 从镜像里取基线 passwd，追加一条映射到宿主 uid/gid 的 builder
passwd_file="${ROOT_DIR}/work/home/.passwd"
docker run --rm "${resolved_image}" cat /etc/passwd >"${passwd_file}.base"
grep -q "^builder:" "${passwd_file}.base" \
    || printf 'builder:x:%s:%s:builder:/home/builder:/bin/bash\n' "${host_uid}" "${host_gid}" >>"${passwd_file}.base"
mv "${passwd_file}.base" "${passwd_file}"
# 挂载：-v "${passwd_file}:/etc/passwd:ro"
```

要求：
- `work/home/` 目录必须先 `mkdir -p`（已存在）；
- 若镜像里已有 `builder` 条目但 uid 不同，**替换**该行而不是追加（保证 `id -un` = `builder`）；
- 文件权限 644，不影响宿主安全；
- `--dry-run` 输出里要能看到 `/etc/passwd` 这个挂载。

### 4. `--dry-run` 改为单行输出

```bash
printf 'docker'
printf ' %q' "${run_args[@]}" "${resolved_image}" "${command_args[@]:-bash}"
printf '\n'
```

即**一条命令一行**，`%q` 仍然逐参数转义（保证复制粘贴可用），但不再每个参数换行。
要求：`bash scripts/container.sh --release scarthgap --dry-run | grep -q -- '--name yocto-scarthgap-general'`
能匹配。

### 5. 同步 `tests/bats/03_container.bats`

- 用例 2/3/4/5/6 的失败根因是第 1 条，修完应自然变绿；
- 新增 1 个用例：`--dry-run` 输出含 `/etc/passwd`（passwd 注入生效）；
- 新增 1 个用例：`--dry-run` **单行**（`${#lines[@]} -eq 1`）；
- 用例必须能在 dev 容器内跑通（即 `bash scripts/dev.sh bats tests/bats/03_container.bats` 全绿）；
- 不要降低断言强度来凑绿：`id -u == 宿主 uid`、`--user` 不含 0、`DL_DIR`/`SSTATE_DIR` 在 `/work/work/` 下这几条必须保留。

### 6. `docs/03-build/container.md` 补两段

- **uid 与用户名**：宿主 uid（构建机上 2000）与镜像内 `builder`（1000）不同，靠 `/etc/passwd` 注入解决；`--check` 会打印宿主 uid/gid；
- **嵌套模式**：`WB_HOST_REPO_DIR` 的作用、容器内无 docker CLI 属预期、不要在容器内再起嵌套挂载。

## 不要做的事

- 不要改 `docker/*/Dockerfile`、`docker/common/install-yocto-deps.sh`；
- 不要改 `.github/workflows/*`；
- 不要动 `layers/meta-yp/`、`config/*.env`、`config/variants/*`；
- 不要新开分支（继续 `feat/P0-06-container-sh`）；
- 不要真跑 yocto 构建、不要 `docker pull`、不要 `docker system prune`。

## 验收标准（**全部经 dev.sh 进容器跑**，与 CI 一致）

```bash
# 1) 门禁
bash scripts/dev.sh bash scripts/ci/lint.sh
bash scripts/dev.sh bash scripts/ci/secret-scan.sh
bash scripts/dev.sh bats tests/bats/            # 期望 0 not ok、0 skip

# 2) 单独确认新用例全绿（这条是本次修正的核心）
bash scripts/dev.sh bats --print-output-on-failure tests/bats/03_container.bats

# 3) 嵌套模式（copilot 自身环境）：必须通
bash scripts/dev.sh bash scripts/container.sh --release wrynose --variant general --check

# 4) dry-run 单行且可 grep
n=$(bash scripts/dev.sh bash scripts/container.sh --release scarthgap --dry-run | wc -l)
[ "$n" -eq 1 ] || { echo "dry-run 必须单行，实际 $n 行"; exit 1; }
bash scripts/dev.sh bash scripts/container.sh --release scarthgap --dry-run | grep -q -- '--name yocto-scarthgap-general'
bash scripts/dev.sh bash scripts/container.sh --release scarthgap --dry-run | grep -q -- '/etc/passwd'

# 5) 真起容器：用户名可解析 + 非 root + uid 对齐
bash scripts/container.sh --release scarthgap --variant general -- bash -lc 'id -un; id -u'
#   期望两行：builder / 宿主 uid（构建机上为 2000）

# 6) 宿主上不许出现被 docker 误建的空目录
[ ! -d /usr/local/bin/docker ] || { echo "宿主 /usr/local/bin/docker 被误建为目录"; exit 1; }
```

- [ ] 上述命令全部 rc=0
- [ ] 空目录检查那条通过（宿主 `/usr/local/bin/docker` 不存在或仍是文件）
- [ ] `git status` 只包含本卡声明的 3 个文件 + P0-06 已产出的文件
- [ ] 在 **dev 容器内**跑的 BATS 全绿（这是本次唯一真正的验收环境）

## 参考

- `scripts/dev.sh` 的 `build_run_args()`：看 `-e WB_HOST_REPO_DIR` 与 `-v /var/run/docker.sock` 的写法
- `scripts/lib/common.sh` 的 `check_disk_watermark` / `resolve_all`（已复用，勿重写）
- 教训记录：P0-03 的「嵌套容器挂载成空目录」与本卡第 2 条同源
