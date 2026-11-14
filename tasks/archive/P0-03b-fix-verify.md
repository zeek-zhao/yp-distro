# P0-03b 修正：镜像非 root 用户解析 + verify 断言

## 背景（真构建暴露的缺陷，已实测）

P0-03 的静态门禁全绿，但**真构建 + 起容器**暴露两个缺陷：

1. **`wrynose`（ubuntu:24.04）容器起不来**：
   `docker: Error response from daemon: unable to find user builder: no matching entries in passwd file`
   原因：24.04 镜像里 **uid 1000 已被 `ubuntu` 用户占用**。`install-yocto-deps.sh` 的「uid 已被占用」分支只复用了占用者并 chown，**没有建出 `builder`**；而 Dockerfile 写死 `USER builder` → 解析失败。
   20.04 / 22.04 上 1000 空闲，所以 dunfell 没暴露（dunfell 镜像已验证能起来）。
2. **`scripts/image.sh verify` 的凭据检查是死逻辑**：
   用了 `shopt -s nullglob` + 数组 `credentials=(/home/*/.ssh /root/.ssh /root/.netrc /root/.docker/config.json)`。
   nullglob **只丢弃含通配符且未匹配的词**，那三个裸路径不管存在与否都会留在数组里 → 数组永远非空 → dunfell 实测 `verify rc=1`（假警报，镜像其实是干净的）。
3. `image --list` 把 `docker images` 的表头打了 4 次（每个 release 一次）。

## 要改的（三处，别扩大范围）

### 1. `docker/common/install-yocto-deps.sh` — 保证 `BUILD_USER` 一定存在

**不变式**：容器里必须存在名为 `${BUILD_USER}` 的 passwd 条目，且其 uid = `BUILD_UID`。
`/work` 的属主 uid 必须是 `BUILD_UID`。

三种情况分别处理：

- **uid 未被占用**：`useradd --uid "${BUILD_UID}" --gid "<gid>" --create-home --shell /bin/bash "${BUILD_USER}"`
- **uid 已被别的用户名占用**（如 24.04 的 `ubuntu`）：沿用占用者的 gid，另外建出 `BUILD_USER` 作为**同 uid 的别名**：
  `useradd --uid "${BUILD_UID}" --non-unique --gid "<占用者的 gid>" --create-home --shell /bin/bash "${BUILD_USER}"`
  （`--non-unique` 允许同 uid 多用户名；构建镜像里两个名字指向同一 uid 无害，且保证 `USER builder` 可解析）
- **`BUILD_USER` 已存在但 uid ≠ `BUILD_UID`**：`die`（配置冲突，不要静默改 uid）

`/work` 一律 `chown "${BUILD_UID}:<实际 gid>" /work`。

指纹段末尾追加两行（便于排查 uid 冲突，供 `verify` 观察）：
```
resolved_user=<getent passwd ${BUILD_UID} 的第一个名字>
resolved_gid=<getent group 该 uid 的主组 gid>
```
（保留原有的 `user=${BUILD_USER} uid=${BUILD_UID}` 那一行不动）

### 2. `scripts/image.sh` — `verify` 的凭据检查改成逐项 `-e` 判断

替换掉数组 + nullglob 的写法：

```bash
found=0
for p in /home/*/.ssh /root/.ssh /root/.netrc /root/.docker/config.json; do
    if [ -e "${p}" ]; then
        printf 'Credential path exists: %s\n' "${p}" >&2
        found=1
    fi
done
[ "${found}" -eq 0 ] || exit 1
```

保留 `shopt -s nullglob`（让裸通配 `/home/*/.ssh` 未匹配时被跳过），裸路径靠 `[ -e ]` 过滤。
`test "${YOCTO_RELEASE}" = "$1"` 那段保持不变。

### 3. `scripts/image.sh` — `list` 只打一次表头

现在每个 release 调一次 `docker images`，表头重复 4 次。改成**一次**命令取全量再按 4 个 release 过滤：

```bash
docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' | grep -E '/yocto/(dunfell|kirkstone|scarthgap|wrynose)$' || true
```
无镜像时打印 `(无本地构建镜像)`，退出码仍为 0。

## 验收标准

```bash
# 1. 静态检查
bash scripts/dev.sh shellcheck scripts/image.sh docker/common/install-yocto-deps.sh
bash scripts/dev.sh shfmt -d -i 4 -ci scripts/image.sh docker/common/install-yocto-deps.sh

# 2. 静态门禁不许退化
bash scripts/dev.sh bats tests/bats/01_dockerfile.bats

# 3. list 表头只出现一次（当前应为 0 次镜像 + 1 次表头或无输出）
bash scripts/dev.sh ./project.sh image --list
```

## 禁止事项

- **不要 `docker build`**（由派单方重建 4 个镜像验证）
- 不要改 4 份 Dockerfile（问题在安装脚本，不在 Dockerfile）
- 不要改 `docker/dev/`、`scripts/dev.sh`、`scripts/wf3.sh`、`config/*.env`
- 不要 commit / push

## 完成后

一句话汇报：改了哪几个文件、三组验收结果。特别说明 24.04 的 uid 冲突分支你用了什么写法。
