# YP-M0-DES-003 · S3 Ubuntu 容器镜像（jenkins 用户）设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-003 |
| 版本 | v1.0 |
| 状态 | Approved（见 YP-M0-RV-003） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-24 |
| 覆盖需求 | B-03（Ubuntu 容器环境）、B-04（普通用户构建） |
| 关联问题 | YP-M0-ISS-003（ubuntu:24.04 默认 UID/GID 1000 冲突，已修复） |
| 关联决策 | YP-M0-ADR-003（基础镜像版本） |

## 1. 目的与边界

- **目的**：提供可复现的 Ubuntu 构建容器镜像，内含 Yocto 官方要求的主机依赖与 kas，容器内以固定非 root 用户 `jenkins` 执行构建，UID/GID 可通过 build-arg 配置以匹配挂载目录属主。
- **不做的事**：
  - 不做 BSP/业务/镜像配方；不做实际 bitbake 构建（属 S5）；
  - 不做下载/缓存卷挂载逻辑（属 S4，本步仅在 entrypoint 预留校验接口）；
  - 不复制 main 的四版 Dockerfile 兼容层与 linters 安装脚本；
  - 不引入缓存服务器地址、不内置任何密钥/token。

## 2. 输入

| 输入 | 来源与依据 |
|---|---|
| 基础镜像版本 | Yocto 6.0 官方文档 `system-requirements.html` 支持矩阵列出 **Ubuntu 24.04 (LTS)**；沙箱宿主为 Ubuntu 24.04.3 LTS，二者一致 |
| 主机依赖包 | Yocto 6.0 官方 `1.4.1 Ubuntu and Debian` 段落给出的 apt 包列表 |
| 附加依赖 | `python3-websockets`（官方注明除 Ubuntu 22.04/Debian 11 外必装）、`pipx` + `kas`（kas 官方推荐安装方式） |
| locale | 官方要求 `en_US.UTF-8` 可用 |
| 前置产出 | S1 `meta-yp-distro` 层骨架（DES-001） |
| 写法参考 | main 分支 `docker/wrynose/Dockerfile`（仅参考分层组织，不复制兼容层） |

## 3. 设计

### 3.1 文件

```text
docker/
  Dockerfile      # 镜像定义
  entrypoint.sh   # 启动时校验 uid 与挂载点属主
  README.md       # 构建与运行说明
```

### 3.2 基础镜像与版本锁定

- `FROM ubuntu:24.04`：与宿主一致且为 Yocto 6.0 官方支持版本（ADR-003）。
- `ARG JENKINS_UID=1000`、`ARG JENKINS_GID=1000`：用 build-arg 创建 `jenkins`，默认 1000:1000，避免与挂载目录属主冲突。

### 3.3 分层顺序（减少层失效）

1. 设置 `DEBIAN_FRONTEND=noninteractive`、apt 源；
2. 安装官方 Yocto 依赖包 + `pipx` + `python3-websockets` + `locales`，生成 `en_US.UTF-8`，清理 apt 缓存；
3. `pipx install kas`（kas 官方推荐，隔离依赖）；
4. 创建 `jenkins` 用户/组（UID/GID 来自 build-arg），建立工作目录；
5. 拷入 `entrypoint.sh` 并设可执行；
6. `USER jenkins`、`WORKDIR`、ENTRYPOINT。

### 3.4 用户与权限（约束 7）

- 容器内默认用户固定为 `jenkins`，禁止 root 构建：`USER jenkins`。
- `entrypoint.sh` 启动时校验：当前 `id -u` 是否等于 `jenkins` 的 UID；若挂载点（`/work/downloads`、`/work/sstate`，由 S4 定义）存在且属主 UID 不匹配，打印修复命令并 `exit 1`，不允许带错属主继续。
- 本步不真正挂载卷，校验逻辑对「目录不存在」情况跳过，保证镜像单独可启动。

### 3.5 关键取舍（ADR-003）

- **采用** `ubuntu:24.04`：官方支持 + 与宿主一致，可复现。
- **被否**：`ubuntu:22.04`（虽也支持，但与宿主版本不一致，增加变量）；main 的多版本 Dockerfile（与 M0 单一系列目标不符）。

## 4. 失败模式

| 失败 | 现象 | 检测方式 | 处理 |
|---|---|---|---|
| 基础镜像版本不受支持 | 构建时 bitbake 报主机发行版不支持 | 对照官方支持矩阵（DES 第 2 节已锁定 24.04） | 升级基础镜像版本并走 CHG |
| apt 依赖缺失 | `kas build` 早期报缺命令 | `docker run ... sh -c 'for c in ...; do command -v; done'` | 补进 Dockerfile apt 行 |
| root 构建 | `whoami` 返回 root | `docker run --rm <img> whoami` | 检查 `USER jenkins` 是否被覆盖 |
| UID/GID 不匹配 | 挂载目录写入 Permission denied | entrypoint 校验输出 + `stat -c %u` | 用 build-arg 对齐 UID/GID |
| kas 安装失败/版本不符 | `kas --version` 报错 | `docker run --rm <img> kas --version` | 检查 pipx install 步骤与 PATH |
| locale 缺失 | bitbake 报编码错误 | `locale --all-locales | grep -i en_US.utf8` | 确认 Dockerfile 生成 en_US.UTF-8 |

## 5. 验收命令

```bash
# 构建（需 Docker 守护进程）
docker build --build-arg JENKINS_UID=1000 --build-arg JENKINS_GID=1000 \
  -t yp-builder:wrynose-m0 docker/

# 身份为 jenkins，非 root
docker run --rm yp-builder:wrynose-m0 whoami                 # 期望：jenkins
docker run --rm yp-builder:wrynose-m0 id -u                  # 期望：1000

# build-arg 生效
docker build --build-arg JENKINS_UID=2000 --build-arg JENKINS_GID=2000 \
  -t yp-builder:wrynose-m0-uid2000 docker/
docker run --rm yp-builder:wrynose-m0-uid2000 id -u          # 期望：2000

# 工具链与 locale
docker run --rm yp-builder:wrynose-m0 kas --version          # 期望：kas 版本输出
docker run --rm yp-builder:wrynose-m0 locale --all-locales | grep -i en_US.utf8

# entrypoint 校验：属主不符时非零退出（构造错误属主挂载）
mkdir -p /tmp/dl-bad && chown 12345:12345 /tmp/dl-bad
docker run --rm -v /tmp/dl-bad:/work/downloads yp-builder:wrynose-m0 true  # 期望：exit 1
```

**期望输出**：`whoami`=jenkins、`id -u`=1000（默认）/2000（build-arg）、`kas --version` 有输出、locale 匹配、属主不符时 exit 1。

## 6. 回滚方式

- 单步回滚：`git revert <S3 提交 SHA>`；删除本地镜像 `docker rmi yp-builder:wrynose-m0`。
- 回滚后验证：`test ! -e docker/Dockerfile` 返回 0；`ai-entry.sh` 中 S3 状态回退为「待开始」。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-24 | 初稿：Ubuntu 24.04 + jenkins 容器镜像设计 | zeek.zhao |
