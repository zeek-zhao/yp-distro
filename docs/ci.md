# CI 与 GHCR

| 层级 / 位置 | 触发者与条件 | 产物与预计耗时 |
|---|---|---|
| L1：GitHub 托管 runner，`ci.yml` | main push、所有 PR、手动 | lint、凭据扫描、BATS；约 2–10 分钟 |
| L2：GitHub 托管 runner，`images.yml` | main 上 docker、image.sh、scripts/ci 或本 workflow 变更；手动 | 4 个 GHCR 镜像，GHA 分 release 缓存；约 10–60 分钟 |
| 出口验收：GitHub 托管 runner，`pull-check.yml` | 手动指定 tag；每周一北京时间 06:00 | 匿名拉取并断言非 root、release、工具链、UTF-8；约 2–15 分钟 |
| L3：215 构建节点 | 派单方按真实构建任务触发 | Yocto 构建及运行产物，不在 GitHub 托管 runner 构建 |

所有 job 使用 ubuntu-24.04 并设超时；L1 不依赖 Docker daemon。
`ci.yml` 的 BATS job 无论成败上传 `bats-report`，含 `reports/` 和 `docs/qa/`，保留 14 天。
工具版本只由 `scripts/ci/install-tools.sh` 管理；workflow 不重复维护工具版本。

## 镜像约定与首次公开

命名为 `ghcr.io/zeek-zhao/yocto/<release>`，release 为 dunfell、kirkstone、scarthgap、wrynose。
`sha-<7 位提交 SHA>` 作为不可变引用使用（不覆盖已有提交的镜像）；`<series>`（3.1 / 4.0 / 5.0 / 6.0）和 `latest` 随构建浮动。
GHCR 本身不强制 tag 不可变；需要严格可复现时记录镜像 digest。
推送只使用自动注入的 `GITHUB_TOKEN` 和 `packages: write`。

**首次推送后由派单方逐个把 4 个包设为 public，本卡不修改任何仓库或包设置。**
Web：个人主页 Packages → 对应包 → Package settings → Change visibility → Public。
API 路径：`PATCH /user/packages/container/yocto%2F<release>`，body 为 `{"visibility":"public"}`，
由具备包管理权限的派单方执行；若服务端不支持该修改接口，以 Web 为准。
包名包含斜杠，URL 必须编码，例如 `yocto%2Fdunfell`；未编码会 404。
私有仓库不等于包必须私有；公开后手动运行 `pull-check` 验证 C24，不做任何登录。

## 本地等价命令

```bash
make ci-tools
# 默认选可写的系统前缀，否则使用用户前缀；必要时显式指定：
bash scripts/ci/install-tools.sh --prefix "$HOME/.local"
eval "$(bash scripts/ci/install-tools.sh --prefix "$HOME/.local" --print-env)"
make lint
make secret-scan
bash scripts/dev.sh bats tests/bats
```

`--only actionlint` 可单独安装；`GH_DL` 可覆盖 GitHub 下载地址。
lint 只检查跟踪的工程脚本、5 个 Dockerfile 和 workflow；遗留参考文件不参与。
凭据扫描只检查跟踪文本，排除 `.devhome/`、`reference/legacy/` 和二进制；
确有误报才在可选的 `scripts/ci/secret-scan.allow` 写 `path | pattern-id | reason`。

## 常见故障

- 匿名 pull 返回 403：检查四个包是否仍为 private；由派单方公开后重跑验收。
- 境外镜像构建卡在 apt：确认 `build-args` 覆盖 `APT_MIRROR=archive.ubuntu.com`，不要沿用 215 的国内源。
- 找不到 actionlint：运行安装器并将对应 `<prefix>/bin` 加到 PATH；静态 BATS 不会跳过此项。
