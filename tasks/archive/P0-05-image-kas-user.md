# P0-05 镜像补齐 kas + 构建用户归一

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-05` |
| 里程碑 | `v0.1.0` |
| 分支 | `feat/P0-05-image-kas-user`（从 `dev` 切出） |
| 关联 Issue | `#14`（缺 kas/repo）、`#15`（用户不一致） |
| 依赖 | 无（P0-03 镜像已就绪） |
| 预计改动文件 | `docker/common/install-yocto-deps.sh`、`docker/{dunfell,kirkstone,scarthgap,wrynose}/Dockerfile`、`scripts/image.sh`、`tests/bats/01_dockerfile.bats`、`docs/branching.md` 不动 |

## 背景

2026-10-28 在构建机上实测 4 个已发布镜像，发现两个真缺陷（证据见 Issue #14 / #15）：

```
dunfell    py3=3.8.10  user=builder uid=1000   kas-MISS repo-MISS
kirkstone  py3=3.10.12 user=builder uid=1000   kas-MISS repo-MISS
scarthgap  py3=3.12.3  user=ubuntu  uid=1000   kas-MISS repo-MISS   ← 用户不一致
wrynose    py3=3.12.3  user=ubuntu  uid=1000   kas-MISS repo-MISS   ← 用户不一致
```

P1 全部工作依赖 `kas build`（决策 C36–C40），镜像里没有 kas → P1 第一步就崩；
构建用户名不一致 → 后续 `scripts/container.sh` 按固定用户名做属主/`--user` 会踩权限坑。

## 要做的事

### 1. `docker/common/install-yocto-deps.sh` 安装 kas

- 追加 `kas` 安装，版本**锁死 4.6**（`kas==4.6`，与 `docs/kas.md` 设计一致）；
- **必须 root 装到 `/usr/local/bin`**：非 root 会落 `~/.local/bin` 且不在 PATH，
  导致镜像内 `kas` 找不到；
- Ubuntu 24.04（scarthgap/wrynose）需 `pip3 install --break-system-packages`；
  20.04/22.04 走普通 `pip3 install`（**不要**无条件加该 flag，老 pip 不认）；
- 安装后立即自检：`kas --version` 必须输出 `4.6.x`，否则脚本 `exit 1`；
- 网络：`PIP_INDEX_URL` 已可覆盖（沿用现有约定），默认留清华源。

### 2. `repo` 工具：本次**不装**，但要留下可选项和结论

- 决策：kas 的 `repos:` map 已能表达 wrynose 三仓库拆分（C40），不依赖 Google `repo`；
- 因此默认**不安装** `repo`（避免依赖 storage.googleapis.com 外网可用性）；
- 但加环境变量开关 `INSTALL_REPO=1` 时安装（`curl` 官方脚本到 `/usr/local/bin/repo`，
  `chmod +x`），并在脚本 `--help` 与注释里说明这是可选；
- 在 `docs/kas.md`（若不存在则先不建）或 `install-yocto-deps.sh` 顶部注释里写明
  「构建链路不依赖 repo，原因：kas repos map」。

### 3. 构建用户归一为 `builder`

- 目标：**4 个镜像 `id -un` 必须都是 `builder`**，UID 仍为 1000；
- 24.04 系（scarthgap/wrynose）当前解析成 `ubuntu`，说明 `USER builder` 没生效。
  修法：显式建 `builder`（uid 1000 已被 `ubuntu` 占用时用
  `useradd --non-unique --uid 1000 --create-home builder`），再 `USER builder`；
- 20.04/22.04 保持现状（已是 `builder`），但确认 4 份 Dockerfile 的 `USER` 指令
  **字面一致**（全部 `USER builder`）。

### 4. `scripts/image.sh verify` 加强断言

- 新增：`kas --version` 能跑且以 `4.6.` 开头（4 个镜像逐个断言）；
- 新增：`id -un` 必须等于 `builder`；
- 保留现有断言（非 root / 工具链 / UTF-8 / 无私钥）；
- **断言必须真会红**：这些断言是上一轮的盲区（缺 kas 时 verify 仍全绿），
  写完要自己负向验证（见验收最后一条）。

## 不要做的事

- 不要改 `docker/dev/Dockerfile`（开发镜像已有 copilot/工具链，动它会牵动 `.devhome` 凭证）；
- 不要升级基础镜像版本（dunfell 20.04 / kirkstone 22.04 / scarthgap+wrynose 24.04 是刻意的）；
- 不要动 `kas/`（P1 才落地）、不要改 `config/*.env` 的版本锁；
- 不要在镜像里放任何凭据；不要往 `scripts/ci/lint.sh` 的扫描范围外新增顶层脚本。

## 验收标准

```bash
# 1) 4 镜像重建（会用到缓存，只多一层 pip 安装）
bash scripts/dev.sh bash scripts/image.sh build

# 2) verify 全过（含新增 kas / 用户名断言）
bash scripts/dev.sh bash scripts/image.sh verify

# 3) 逐镜像直测
for r in dunfell kirkstone scarthgap wrynose; do
  docker run --rm "ghcr.io/zeek-zhao/yp-distro/$r:local" bash -lc 'kas --version | head -1; id -un'
done

# 4) 用户必须唯一且为 builder
for r in dunfell kirkstone scarthgap wrynose; do
  docker run --rm "ghcr.io/zeek-zhao/yp-distro/$r:local" id -un
done | sort -u | grep -qx builder

# 5) 静态门禁
bash scripts/dev.sh bash scripts/ci/lint.sh
bash scripts/dev.sh bats tests/bats/

# 6) 负向验证（必须做，用来证明断言不是摆设）
#    临时把 wrynose 镜像的 kas 隐藏（如 docker run 里 PATH 去掉 /usr/local/bin），
#    确认 image.sh verify 的 kas 断言会失败；验证完恢复正常状态
```

- [ ] `bash scripts/image.sh build` 4 镜像全部成功
- [ ] `bash scripts/image.sh verify` 全过，输出含 kas 与用户名断言
- [ ] 4 镜像 `kas --version` 均以 `4.6.` 开头
- [ ] `id -un | sort -u` 结果唯一且为 `builder`
- [ ] `scripts/ci/lint.sh` 四段 ok（11 files / 11 files / 5 files / 3 workflows 不变）
- [ ] `bats tests/bats/` 零 skip 全绿（当前基线 **32 用例**，可新增但不可减少）
- [ ] `tests/bats/01_dockerfile.bats` 新增用例：4 份 Dockerfile 的 `USER` 指令字面一致
- [ ] 负向验证记录写进 PR 描述（哪个断言、怎么造的、失败输出是什么）
- [ ] `git status` 只包含本卡声明的文件

## 参考

- Issue #14 / #15 里有实测输出与背景
- `docker/common/install-yocto-deps.sh` 现有的 `APT_MIRROR` / `PIP_INDEX_URL` 约定
- `scripts/image.sh` 现有 verify 的断言写法（逐路径显式检查，不用 nullglob）
