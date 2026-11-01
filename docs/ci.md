# CI 与 GHCR

| 层级 / 位置 | 触发者与条件 | 产物与预计耗时 |
|---|---|---|
| L1：GitHub 托管 runner，`ci.yml` | main push、所有 PR、手动 | lint、凭据扫描、身份门禁、问题清单校验、BATS（含 4 版本矩阵）；约 5–20 分钟 |
| L2：GitHub 托管 runner，`images.yml` | main 上 docker、image.sh、scripts/ci 或本 workflow 变更；手动 | 4 个 GHCR 镜像，GHA 分 release 缓存；约 10–60 分钟 |
| 出口验收：GitHub 托管 runner，`pull-check.yml` | main push、手动指定 tag、每周一北京时间 06:00 | 匿名拉取并断言非 root、release、工具链、UTF-8；约 2–15 分钟 |
| L3：构建机构建节点 | 派单方按真实构建任务触发 | Yocto 构建及运行产物，**不在 GitHub 托管 runner 构建** |

所有 job 使用 ubuntu-24.04 并设超时。
`ci.yml` 的 BATS job 无论成败上传 `bats-report`，含 `reports/` 和 `docs/qa/`，保留 14 天。
工具版本只由 `scripts/ci/install-tools.sh` 管理；workflow 不重复维护工具版本。

## ci.yml 的 job 构成

| job | 做什么 | 失败了说明什么 |
|---|---|---|
| `lint` | shellcheck / shfmt / hadolint / actionlint | 代码风格或 Dockerfile/workflow 有实质问题 |
| `bats` | 拉齐 4 个发行版镜像后跑全量 BATS，再执行 skip 门禁 | 有回归，或有用例被悄悄跳过 |
| `bats-release-matrix` | 按 4 个发行版各跑一遍 BATS | 某个 release 的配置分支坏了 |
| `secret-scan` | 扫描跟踪文件里的凭据形态 | 可能提交了密钥 |
| `identity-guard` | **全历史**校验身份、内部信息、AI 署名 | 历史里混进了不该有的东西 |
| `plan-sync` | 校验 `docs/issues.md` 与线上 issue 一致 | 文档漂移了，跑 `scripts/plan-sync.sh` |
| `branch-guard` | 校验 `main` 的 push 来自 PR | 有人直推了 main（ruleset 的备份） |

### 为什么 BATS job 要先拉镜像

`03_container.bats` 的容器用例需要本地有发行版镜像，此前在 CI 上恒 skip——
镜像明明就公开在 GHCR 上，这是纯资源妥协。仓库转公开后 runner 不再限量，
所以先 `docker pull` 四个镜像，让这些用例真跑。
`scripts/ci/skip-gate.sh` 兜底：跳过数超过上限就让 job 红，避免「悄悄跳过」再发生。

### 为什么 L3 不进 CI

bitbake 是 2184 个 task 量级，标准 runner 只有 2 核 7GB，Yocto 的 OOM 边界就在
附近；4 个版本串行还会撞 6 小时 job 上限。真构建留在构建机上跑，CI 只做静态
与轻量回归——**「配方能 parse」和「配方能 build」之间隔着一次真构建**，
这个缺口由 `docs/qa/` 的归档和发布前的人工验收补上，不假装 CI 覆盖了它。


## 镜像约定与首次公开

命名为 `ghcr.io/zeek-zhao/yp-distro/<release>`，release 为 dunfell、kirkstone、scarthgap、wrynose。
`sha-<7 位提交 SHA>` 作为不可变引用使用（不覆盖已有提交的镜像）；`<series>`（3.1 / 4.0 / 5.0 / 6.0）和 `latest` 随构建浮动。
GHCR 本身不强制 tag 不可变；需要严格可复现时记录镜像 digest。
推送只使用自动注入的 `GITHUB_TOKEN` 和 `packages: write`。

**首次推送后由派单方逐个把 4 个包设为 public，CI 本身不修改任何仓库或包设置。**

只能走 Web UI —— **REST API 没有"修改包可见性"的端点**（2026-10-28 实测：
`PATCH /user/packages/container/yp-distro%2F<release>` 恒返回 404，官方文档里包相关端点只有
GET / DELETE / POST restore，无 PATCH / PUT）。所以个人令牌无论什么 scope 都改不了可见性。

直达链接（包名含斜杠，URL 里编码成 `%2F`）：

```
https://github.com/users/zeek-zhao/packages/container/yp-distro%2Fdunfell/settings
https://github.com/users/zeek-zhao/packages/container/yp-distro%2Fkirkstone/settings
https://github.com/users/zeek-zhao/packages/container/yp-distro%2Fscarthgap/settings
https://github.com/users/zeek-zhao/packages/container/yp-distro%2Fwrynose/settings
```

页面底部 Danger Zone → Change visibility → Public → 输入包名确认。
改完用 `pull-check.yml` 或匿名 `docker manifest inspect` 复核（private 时返回 `unauthorized`）。
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
lint 检查全部跟踪的 shell 脚本（`*.sh` 递归，含 `docker/common/` 与 `scripts/ci/`）、5 个 Dockerfile 和 workflow。
凭据扫描只检查跟踪文本，排除 `.devhome/` 和二进制；
确有误报才在可选的 `scripts/ci/secret-scan.allow` 写 `path | pattern-id | reason`。

## 常见故障

- 匿名 pull 返回 403：检查四个包是否仍为 private；由派单方公开后重跑验收。
- 境外镜像构建卡在 apt：确认 `build-args` 覆盖 `APT_MIRROR=archive.ubuntu.com`，不要沿用构建机的国内源。
- 找不到 actionlint：运行安装器并将对应 `<prefix>/bin` 加到 PATH；静态 BATS 不会跳过此项。

  四个 release 构建镜像与 dev 镜像自 #46 起已在 `/usr/local/bin` 内置
  shellcheck / shfmt / bats / hadolint / actionlint（构建日志里有
  `=== linter fingerprint ===` 一行可核对版本），只有直接在宿主跑门禁才需要
  自己装。之前 release 镜像缺后两个，归档报告只能临时补装、结果不可复现。
