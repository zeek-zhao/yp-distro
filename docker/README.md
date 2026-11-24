# yp-builder 镜像（S3）

Yocto wrynose 构建容器：基于 Ubuntu 24.04（Yocto 6.0 官方支持，ADR-003），内置官方主机依赖与 kas，以非 root 的 `jenkins` 用户构建。

## 依据

- 基础镜像：`ubuntu:24.04`（与宿主 Ubuntu 24.04.3 一致）
- 依赖：Yocto 6.0 `ref-manual` 1.4.1 Ubuntu and Debian 包列表 + `python3-websockets` + `pipx install kas`
- 设计：`docs/m0/design/S3-container-image.md`（DES-003），评审 `docs/m0/reviews/RV-003.md`

## 构建

```bash
docker build \
  --build-arg JENKINS_UID=1000 --build-arg JENKINS_GID=1000 \
  -t yp-builder:wrynose-m0 docker/
```

UID/GID 应与宿主机挂载目录属主一致；不一致时容器启动会报错并给出修复命令。

## 运行（校验）

```bash
docker run --rm yp-builder:wrynose-m0 whoami          # jenkins
docker run --rm yp-builder:wrynose-m0 id -u           # 1000（默认）
docker run --rm yp-builder:wrynose-m0 kas --version   # kas 版本
```

## 挂载（S4 提供完整流程）

```bash
docker run --rm \
  -v "$PWD/downloads:/work/downloads" \
  -v "$PWD/sstate:/work/sstate" \
  yp-builder:wrynose-m0 kas --version
```

挂载源目录属主需与 `JENKINS_UID` 一致，否则 entrypoint 拒绝启动。
