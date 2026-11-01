# 第三方组件声明 / Third-Party Notices

本仓库**自身**的源码（脚本、配置、layer 元数据、文档、CI 定义）以 MIT 许可发布，
全文见 [`LICENSE`](LICENSE)。

但「用本仓库构建出来的东西」与「本仓库的运行环境」都包含第三方组件，
它们的许可**不是** MIT，也不受上面那份 MIT 许可覆盖。本节按分发形态分别说明。

## 1. Yocto 构建产物（`yp-image` 及 SDK）

`scripts/build.sh` / `scripts/image.sh` 产出的 rootfs、SDK、eSDK 是**聚合发行版**，
其中绝大多数二进制来自 Yocto Project / OpenEmbedded 元数据所描述的上游项目，
许可覆盖 GPL-2.0-only、GPL-3.0-only、LGPL-2.1-only、MIT、BSD-3-Clause、Apache-2.0 等。

- **逐包清单与许可证**：每次合规构建会产出 SPDX SBOM 与 FOSS 扫描结果，
  归档在 `docs/qa/<release>/compliance-<date>-<sha>[-<variant>].md`，
  原始 SBOM 落在构建机的 `work/artifacts/<release>/<variant>/sbom/`。
  这些是分发时必须随附的证据。
- **对应源码**：GPL/LGPL 组件的源码通过 SBOM 中每个包的 `externalRefs`
  （`PACKAGE-MANAGER` / `DOWNLOAD-LOCATION`）定位到上游；Yocto 自身元数据从
  `kas/targets/*.yml` 锁定的 revision 取得。
- 本仓库**不分发** Poky、meta-openembedded 或任何上游源码树；
  它们在构建时由 `kas` 按锁定 revision 拉取。

## 2. 构建环境容器镜像（`ghcr.io/zeek-zhao/yp-distro/*`）

四个镜像（`dunfell` / `kirkstone` / `scarthgap` / `wrynose`）以 Ubuntu
官方镜像为基础（20.04 / 22.04 / 24.04），叠加 Yocto 依赖包与 lint 工具。
因此镜像内含大量 GPL/LGPL 组件，其许可与 MIT 无关。

| 项 | 说明 |
|---|---|
| 基础层 | `ubuntu:20.04` / `ubuntu:22.04` / `ubuntu:24.04`，见 `docker/*/Dockerfile` |
| 基础层许可 | Ubuntu 各包的许可见其 `/usr/share/doc/<pkg>/copyright` |
| 基础层对应源码 | <https://archive.ubuntu.com/ubuntu/>（按 `deb-src` 索引取得） |
| 镜像内新增包 | `docker/common/install-yocto-deps.sh`、`install-linters.sh` 全量列出 |
| 镜像自身许可 | `org.opencontainers.image.licenses=MIT`（指本仓库构建脚本部分） |

> 镜像 tag 为不可变的 `sha-<7位>` 时，镜像与提交一一对应，便于满足
> 「分发二进制时提供对应源码」的义务。可变的 `latest` / `<series>` tag
> 不适合作为合规基准。

## 3. 开发容器（`yocto-dev:local`）

`docker/dev/Dockerfile`，同样基于 `ubuntu:24.04`。许可关系同第 2 节。
该镜像只在本地构建（不推 GHCR），不构成对外分发。

## 4. 本仓库未内联（vendored）第三方源码

仓库内所有 `SRC_URI = "file://..."` 的源码（`layers/meta-yp/recipes-*/.../files/`）
都是本项目自有的示例代码（demo 服务、systemd unit、构建脚本），以 MIT 发布。
本仓库不包含任何第三方项目的源码副本。

## 5. 报告问题

若认为本仓库或某个发布镜像遗漏了应有的第三方声明，请开 issue 并注明
组件名与镜像 tag。
