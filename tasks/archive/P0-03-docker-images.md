# P0-03 构建镜像（4 份 Dockerfile + 共享安装脚本 + 镜像入口）

## 目标

交付 4 个**构建镜像**（跑 bitbake 用），以及它们的共享安装脚本、入口脚本和静态门禁测试。

这是 P0 出口条件「GHCR 4 镜像可拉」的直接前置。**本卡不推 GHCR**（L2 workflow 属 P0-04），
本卡只保证：Dockerfile 正确、静态门禁通过、镜像能本地构建成功、镜像内工具齐全且非 root。

## 背景约束（必须遵守，不要自己发挥）

- 仓库根 = `/work`（WF3 容器内）或 `/home/jenkins/workspace/yocto`（宿主）。所有命令用相对仓库根的路径。
- **开发镜像 `docker/dev/` 已存在**，它是「跑 lint/BATS/AI CLI」的，**本卡不要改它**。
  本卡新增的是 4 个**构建镜像**，跑 bitbake 用。两者严格分工，别合并。
- 已有约定（沿用，不要另起一套）：
  - `.hadolint.yaml` 已存在（ignored: DL3008/DL3013/DL3059/DL3016，failure-threshold: warning）
  - `scripts/lib/log.sh` 提供 `log` / `warn` / `die`；`scripts/lib/common.sh` 提供 `load_release` / `work_dir` 等
  - 入口 `project.sh`，已有子命令 `config` `doctor` `test` `report`，其余是 `exit 2` 占位
  - `config/<release>.env` 的 schema 见下（**不要改字段名，不要新增字段**）
- 每份 Dockerfile 的 base 由需求锁定，**不许改**：
  | release | base |
  |---|---|
  | dunfell | `ubuntu:20.04` |
  | kirkstone | `ubuntu:22.04` |
  | scarthgap | `ubuntu:24.04` |
  | wrynose | `ubuntu:24.04` |

## 交付物 1：`docker/common/install-yocto-deps.sh`

**唯一真本的安装脚本**，被 4 份 Dockerfile `COPY` 进去执行。它必须自己处理 3 个 Ubuntu 版本差异。

以 root 运行。入参全部用环境变量（Dockerfile 用 `ARG`+`ENV` 传），**不要用位置参数**：

| 变量 | 默认值 | 说明 |
|---|---|---|
| `APT_MIRROR` | `cn.archive.ubuntu.com` | 拼接成 `http://${APT_MIRROR}/ubuntu` |
| `SDL_PKG` | 必填 | `libsdl1.2-dev` 或 `libsdl2-dev` |
| `EXTRA_PKGS` | 空 | 空格分隔的额外包，可空 |
| `UBUNTU_VERSION` | 必填 | `20.04` / `22.04` / `24.04`，仅用于日志与指纹 |
| `BUILD_USER` | `builder` | 非 root 用户名 |
| `BUILD_UID` | `1000` | |
| `BUILD_GID` | `1000` | |
| `SHELLCHECK_VERSION` | `0.9.0` | 与 dev 镜像保持一致 |
| `SHFMT_VERSION` | `3.14.1` | |
| `BATS_VERSION` | `1.14.0` | |
| `GH_DL` | `https://github.com` | |

**三段必须做的处理（都有实测依据，照做）**：

1. **apt 源改写要分两种格式**
   - `20.04` / `22.04`：只有 `/etc/apt/sources.list`（一行式 `deb http://archive.ubuntu.com/ubuntu/ focal main ...`）
   - `24.04`：`/etc/apt/sources.list` 是空壳，真源在 `/etc/apt/sources.list.d/ubuntu.sources`（deb822 格式 `URIs: http://archive.ubuntu.com/ubuntu/`）
   - 两种都要改写：`http://archive.ubuntu.com/ubuntu` → `http://${APT_MIRROR}/ubuntu`，`http://security.ubuntu.com/ubuntu` → 同。
     判定方式：`if [ -f /etc/apt/sources.list.d/ubuntu.sources ]` 则改 deb822，否则改 sources.list；**两个文件存在就都改，不要 if/else 二选一**。
   - 实测 `cn.archive.ubuntu.com` 对 focal/jammy/noble 全部返回 200（有一次 302 跳转，apt/curl 均能跟随），可用。

2. **包集合按版本裁剪**（已实测包名可用性，别写错）
   - 基础集合（三版本都有）：
     `gawk wget git diffstat unzip texinfo gcc build-essential chrpath socat cpio python3 python3-pip python3-pexpect xz-utils debianutils iputils-ping python3-git python3-jinja2 python3-subunit zstd liblz4-tool file locales`
   - `SDL_PKG` 按 release 传（dunfell/kirkstone → `libsdl1.2-dev`，scarthgap/wrynose → `libsdl2-dev`）
   - `rpcsvc-proto` **只有 jammy/noble 有，focal 没有** → 只能通过 `EXTRA_PKGS` 由 scarthgap 传入，**不要写进基础集合**
   - `pylint3` **三个版本都装不上**（focal candidate none / jammy、noble 无此包）→ **不要装**
   - 装包用 `--no-install-recommends`，装完 `apt-get clean && rm -rf /var/lib/apt/lists/*`

3. **建非 root 用户并处理 uid 冲突**
   - 与 `docker/dev/Dockerfile` / `scripts/dev.sh` 同一套逻辑：先看 `${BUILD_UID}` 是否已被占用（`getent passwd "${BUILD_UID}"`），
     被占用就复用那个用户名的组与用户（只补 `/work` 属主），否则新建。
   - `/work` 目录 `chown ${BUILD_UID}:${BUILD_GID}`，`WORKDIR` 由 Dockerfile 设。
   - **不要**给 sudo（构建不是交互场景）。

4. `locale-gen en_US.UTF-8` + `update-locale LANG=en_US.UTF-8`（20.04 也要过；`locales` 已在基础集合里）

5. 装三个工程工具（GitHub release 直连，实测 1.3~2.3s 可用；全部 pin 版本）：
   - `shellcheck-v${SHELLCHECK_VERSION}.linux.x86_64.tar.xz` → `/usr/local/bin/shellcheck`
   - `shfmt_v${SHFMT_VERSION}_linux_amd64` → `/usr/local/bin/shfmt`
   - `bats-core/archive/refs/tags/v${BATS_VERSION}.tar.gz` → `./install.sh /usr/local`

6. 脚本末尾打印指纹（供 `01_docker_image.bats` 断言），格式固定：
   ```
   === image fingerprint ===
   ubuntu=<UBUNTU_VERSION>
   user=<BUILD_USER> uid=<BUILD_UID>
   shellcheck=<ver>
   shfmt=<ver>
   bats=<ver>
   sdl=<SDL_PKG>
   ```

**硬要求**：脚本必须 `shellcheck` 零告警（L1 会跑），`shfmt -i 4 -ci` 无改动，
`#!/usr/bin/env bash` + `set -euo pipefail`。

## 交付物 2：4 份 `docker/<release>/Dockerfile`

薄壳，只做参数与元数据，逻辑全在 install 脚本里。每份结构固定：

```dockerfile
# syntax=docker/dockerfile:1.7
FROM ubuntu:20.04                      # ← 按上表，不许用 latest / 不许省略 tag

ARG APT_MIRROR=cn.archive.ubuntu.com
ARG BUILD_UID=1000
ARG BUILD_GID=1000
ARG BUILD_USER=builder

# 版本专用差异
ENV YOCTO_RELEASE=dunfell \
    YOCTO_SERIES=3.1 \
    UBUNTU_VERSION=20.04 \
    SDL_PKG=libsdl1.2-dev \
    EXTRA_PKGS="" \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="yocto-dunfell" \
      org.opencontainers.image.source="https://github.com/zeek-zhao/yp-distro" \
      org.opencontainers.image.description="Yocto 3.1 (dunfell) build image on Ubuntu 20.04" \
      org.opencontainers.image.licenses="MIT"

COPY docker/common/install-yocto-deps.sh /tmp/install-yocto-deps.sh
RUN bash /tmp/install-yocto-deps.sh && rm -f /tmp/install-yocto-deps.sh

USER ${BUILD_USER}
WORKDIR /work
CMD ["bash"]
```

四份的差异只有：`FROM`、`YOCTO_RELEASE`、`YOCTO_SERIES`、`UBUNTU_VERSION`、`SDL_PKG`、`EXTRA_PKGS`、`LABEL`。

| release | SERIES | SDL_PKG | EXTRA_PKGS |
|---|---|---|---|
| dunfell | 3.1 | `libsdl1.2-dev` | 空 |
| kirkstone | 4.0 | `libsdl1.2-dev` | 空 |
| scarthgap | 5.0 | `libsdl2-dev` | `rpcsvc-proto` |
| wrynose | 6.0 | `libsdl2-dev` | 空 |

**构建 context 是仓库根**（因为 `COPY docker/common/...`），入口脚本会自动处理，不要写成 `docker/<release>` 作 context。

## 交付物 3：`scripts/image.sh`

```
scripts/image.sh build <release>      # docker build，tag = ghcr.io/zeek-zhao/yp-distro/<release>:local
scripts/image.sh verify <release>     # 起容器做工具断言（见下）
scripts/image.sh list                 # 列出 4 个 local 镜像
scripts/image.sh push <release> <tag> # docker tag + push 到 ghcr.io（本卡不调用，留好）
```

要求：
- 复用 `scripts/lib/log.sh` 的 `log`/`warn`/`die`；`set -euo pipefail`；shellcheck 零告警
- `build`：`docker build -f docker/<release>/Dockerfile -t <tag> --build-arg APT_MIRROR=... .`（context 用脚本自身推出的仓库根，不要依赖 `pwd`）
- `verify`：`docker run --rm <tag> bash -c '...'` 断言并打印
  1. `id -u` != 0
  2. `bats --version` / `shellcheck --version` / `shfmt --version` 可执行
  3. `locale charmap` 输出 `UTF-8`
  4. 无凭据文件：`ls /work /home/*/.ssh /root/.ssh /root/.netrc /root/.docker/config.json` 均不存在（`/work` 空目录除外）
  5. `ENV` 里的 `YOCTO_RELEASE` 与参数一致
- **未知 release 必须 `die` 且退出码 ≠ 0**
- 镜像名统一 `ghcr.io/zeek-zhao/yp-distro/<release>`（本地 tag 用 `:local`，避免误推）

## 交付物 4：`project.sh` 增 `image` 子命令

把现有的 `image)` 占位（`exit 2`）改成真实现，**只转发不重写逻辑**：

```bash
image)
    # --release <r> 必填；--build / --verify / --list 选一个，缺省 --build
    bash "${ROOT_DIR}/scripts/image.sh" ...
    ;;
```

- `./project.sh image --release wrynose` → 构建
- `./project.sh image --release wrynose --verify` → 校验
- `./project.sh image --list` → 列表
- `--release` 缺省或非法 → 非 0 退出 + 用法提示
- `project.sh --help` 的输出要包含 `image`（现有 BATS 已断言 help 含 config/doctor，别破坏）

## 交付物 5：`tests/bats/01_dockerfile.bats`（L1 静态门禁，**不需要 docker**）

沿用 `tests/bats/00_project.bats` 的风格：`source "${BATS_TEST_DIRNAME}/setup.bash"`，每个用例打 `# bats test_tags=dockerfile`。
全部用 `run` + 断言，**不许真的 docker build**。至少这 8 个用例：

1. `hadolint` 4 份 Dockerfile 全部 exit 0
2. 每份 `FROM ubuntu:<期望版本>` 与矩阵一致（4 份逐个断言，用循环 + 表驱动）
3. 基础镜像不许带 `:latest`，也不许省略 tag（`FROM ubuntu` 或 `FROM ubuntu:latest` 都要失败）
4. 每份都 `COPY docker/common/install-yocto-deps.sh`
5. 每份都有 `USER` 且不是 `root`（`grep -q '^USER ' && ! grep -q '^USER root'`）
6. 每份都有 `org.opencontainers.image.source` 与 `org.opencontainers.image.title` 两个 LABEL
7. `docker/common/install-yocto-deps.sh` 通过 `shellcheck` 且通过 `shfmt -d -i 4 -ci`
8. **负例**：临时把一份 Dockerfile 的 `FROM` 改成 `ubuntu:latest`，第 2、3 号用例必须失败（用 `setup`/`teardown` 备份还原，或用临时副本 + 提取断言函数对临时文件跑，**不要留脏文件**）

## 交付物 6：`config/features.txt` 增两行

格式严格照现有：`feature_id | 适用 release | bats 文件 | bats tag`，`|` 两侧各一个空格。

```
docker-images | all | tests/bats/01_dockerfile.bats | dockerfile
image-helper | all | tests/bats/99_coverage.bats | coverage
```

> 第二行如果要触发元测试，需在 `99_coverage.bats` 里已有对应 tag 的用例；**若现有元测试不接受该行，就只加第一行**，不要改元测试逻辑。

## 验收标准（由派单方执行，你不需要跑 docker build）

```bash
# 1. hadolint 4 份全过
cd /work && for r in dunfell kirkstone scarthgap wrynose; do hadolint "docker/$r/Dockerfile" || echo "FAIL $r"; done

# 2. 静态门禁 BATS 全绿
bash scripts/dev.sh bats tests/bats/01_dockerfile.bats

# 3. 全量 BATS 不许退化
bash scripts/dev.sh bats tests/bats/

# 4. 静态检查
bash scripts/dev.sh shellcheck scripts/image.sh docker/common/install-yocto-deps.sh
bash scripts/dev.sh shfmt -d -i 4 -ci scripts/image.sh docker/common/install-yocto-deps.sh

# 5. 入口可用
bash scripts/dev.sh ./project.sh image --list
bash scripts/dev.sh ./project.sh --help | grep -q image

# 6. 负例：非法 release 必须非 0
bash scripts/dev.sh ./project.sh image --release nosuch; echo "exit=$?"   # 期望非 0

# 7. 真构建（派单方执行，两端 base 各一，覆盖 20.04 与 24.04 两条路）
bash scripts/dev.sh ./project.sh image --release dunfell
bash scripts/dev.sh ./project.sh image --release wrynose
bash scripts/dev.sh ./project.sh image --release dunfell --verify
bash scripts/dev.sh ./project.sh image --release wrynose --verify
```

## 禁止事项

- **不要 `docker build`**（耗时长，派单方执行）；你只保证 hadolint + BATS + shellcheck/shfmt 全绿
- 不要改 `docker/dev/Dockerfile`、`scripts/dev.sh`、`scripts/wf3.sh`、`config/*.env` 的字段
- 不要推 GHCR、不要碰 GitHub Actions
- 不要动 `meta-zeek/`（属 P0-05）
- 不要装 `pylint3`、不要把 `rpcsvc-proto` 写进基础包集合（focal 没有，会构建失败）
- 不要在镜像里放任何凭据/私钥（GHCR 将设为 public，见需求 C24）

## 完成后

在工作区留下改动即可，不要 commit、不要 push（由派单方验收后提交）。
最后用一句话汇报：改了哪些文件、hadolint/BATS/shellcheck/shfmt 各自结果。
