# P0-04 GitHub Actions（L1 静态门禁 + L2 镜像推 GHCR + 免登录拉取验证）

## 目标

把仓库的**校验流水线**从"人工在构建机上敲命令"搬到 GitHub Actions，并交付 P0 的出口条件：
`ghcr.io/zeek-zhao/yp-distro/<release>` 4 个镜像**免登录可拉**（需求 C24）。

本卡只写"能被本地静态验证"的东西：工具链安装脚本、lint 脚本、3 个 workflow、BATS 静态门禁、文档。
**真正的镜像推送与 public 设置由派单方在 GitHub 侧执行**，你不需要、也不允许碰 GitHub 仓库设置。

## 背景约束（必须遵守，不要自己发挥）

- 仓库根 = `/work`（WF3 容器内，你的工作目录）或 `/home/jenkins/workspace/yocto`（宿主）。所有路径相对仓库根，**不要写死任何绝对路径**。
- 你已经在 `yocto-dev:local` 容器内（`id -u` = 2000，`$HOME=/home/jenkins`，`/work` 是仓库）。容器内已有：`shellcheck 0.9.0`、`shfmt 3.14.1`、`bats 1.14.0`、`hadolint 2.15.1`、`python3`、`curl`、`xz`、`unzip`、`git`。**没有 `actionlint`**，需要靠本卡的 `scripts/ci/install-tools.sh` 装。
- `scripts/dev.sh` 有直通判断：容器内调用 `bash scripts/dev.sh <cmd>` 就是本地 exec。因此任务卡里的验收命令在容器内和宿主上都通用。
- 已有的东西（沿用，不要另起一套）：
  - `scripts/lib/log.sh`：`log_info` / `log_warn` / `log_error` / `die`
  - `scripts/lib/common.sh`：`load_release` / `resolve_all` / `check_disk_watermark`
  - `.hadolint.yaml`（ignored: DL3008/DL3013/DL3059/DL3016，failure-threshold: warning）
  - `.editorconfig`（缩进 4 空格、`shfmt -i 4 -ci` 风格）
  - BATS 风格见 `tests/bats/00_project.bats`：`source "${BATS_TEST_DIRNAME}/setup.bash"`，每个用例打 `# bats test_tags=<tag>`
  - `config/features.txt` 四列：`feature_id | 适用 release | bats 文件 | bats tag`
  - `tests/bats/99_coverage.bats` 会强制校验：新增的**非 meta 的 BATS 文件必须被 features.txt 引用**，且 tag 必须在该文件里真实出现。所以 02 号文件**必须**登记 feature 并打对 tag，否则全量 BATS 会红。
- GitHub 仓库：`zeek-zhao/yp-distro`，**私有**。默认分支 `main`。
- **凭据铁律**：workflow 里只允许用 `secrets.GITHUB_TOKEN`（GitHub 自动注入）。**任何地方都不许出现 PAT / `ghp_` / `github_pat_`**，也不许往仓库写 `.env`、私钥、token 文件。GHCR 推送用 `GITHUB_TOKEN` + `permissions: packages: write` 就够，不需要个人令牌。
- **CI 的网络位置是 GitHub 托管 runner（境外）**，所以构建镜像时必须把 `APT_MIRROR` 覆盖成 `archive.ubuntu.com`（Dockerfile 默认值是 `cn.archive.ubuntu.com`，那是给构建机用的）。

## 交付物 0：遗留脚本隔离（先做这一步）

`scripts/` 下混着 5 个从本地参考工程拷来的**遗留脚本**，它们在 `105c582 feat: init` 一次性提交进来，`shellcheck`（15 处告警）和 `shfmt`（522 行 diff）都不合规，会直接把 L1 打死。仓库里**没有任何东西引用它们**（已核实：只有 `.devhome/` 和 `logs/` 里的历史会话日志提到，都是未跟踪目录）。

用 `git mv` 原样搬到 `reference/legacy/` 隔离：

```
git mv scripts/yocto.sh              reference/legacy/yocto.sh
git mv scripts/kernel.sh             reference/legacy/kernel.sh
git mv scripts/sample.sh             reference/legacy/sample.sh
git mv scripts/foss                  reference/legacy/foss
git mv scripts/Dockerfile            reference/legacy/Dockerfile
```

新增 `reference/README.md`（10 行以内）说明：本目录是本地参考工程 `D:\zeek\work\repo\project\poky` 的拷贝，仅作参考，**不参与 lint、不参与流水线、不保证可运行**；`scripts/` 下只允许放本工程自己的、lint 零告警的脚本。

**要求**：`git mv` 只搬不改内容（`git status` 里必须是 `renamed:` 而不是 `deleted + added`）。

做完这一步，`scripts/` 下所有 `*.sh` 才能做到 shellcheck / shfmt 双零。当前已核实：排除这 5 个后，`scripts/*.sh` + `scripts/lib/*.sh` 的 shellcheck 与 shfmt 都是 rc=0。

## 交付物 1：`scripts/ci/install-tools.sh`

**CI 与本地共用的唯一工具链安装器**（把版本写死在这里，workflow 里不许再出现版本号）。

```
scripts/ci/install-tools.sh [--prefix DIR] [--only tool1,tool2] [--print-env]
```

| 项 | 要求 |
|---|---|
| `--prefix` | 默认：`/usr/local` 可写就用它，否则 `$HOME/.local`。二进制装到 `<prefix>/bin` |
| `--only` | 逗号分隔，只装指定工具（调试用） |
| `--print-env` | 只打印 `export PATH="<prefix>/bin:$PATH"` 后退出，方便 `eval` |
| `GH_DL` | 环境变量覆盖，默认 `https://github.com`（构建机出网走 GitHub release 直连，实测可用） |

固定版本（**不要改成 latest，不要自动升级**）：

| tool | 版本 | 下载源（相对 `${GH_DL}`） | 落地 |
|---|---|---|---|
| shellcheck | `0.9.0` | `/koalaman/shellcheck/releases/download/v0.9.0/shellcheck-v0.9.0.linux.x86_64.tar.xz` | `<prefix>/bin/shellcheck` |
| shfmt | `3.14.1` | `/mvdan/sh/releases/download/v3.14.1/shfmt_v3.14.1_linux_amd64` | `<prefix>/bin/shfmt` |
| bats | `1.14.0` | `/bats-core/bats-core/archive/refs/tags/v1.14.0.tar.gz` → `./install.sh <prefix>` | `<prefix>/bin/bats` |
| hadolint | `2.15.1` | `/hadolint/hadolint/releases/download/v2.15.1/hadolint-Linux-x86_64` | `<prefix>/bin/hadolint` |
| actionlint | `1.7.7` | `/rhysd/actionlint/releases/download/v1.7.7/actionlint_1.7.7_linux_amd64.tar.gz` | `<prefix>/bin/actionlint` |

实现要求：
- `#!/usr/bin/env bash` + `set -euo pipefail`；复用 `scripts/lib/log.sh` 的 `log_info` / `log_warn` / `die`
- **幂等**：先探测已装版本（`<prefix>/bin/<tool>` 优先，其次 `PATH`），版本一致就 `log_info "skip <tool> <ver> (already)"` 跳过；不一致才下载覆盖
- 下载到 `mktemp -d` 里做，装完删临时目录；**不要往仓库里落中间文件**
- 不 `sudo`。`<prefix>` 不可写 → `die "prefix 不可写：<prefix>（换个 --prefix 或加权限）"`
- 全是 x86_64：先判断 `uname -m` = `x86_64`，否则 `die`
- 结束时打印指纹块（供 BATS 断言，格式固定）：
  ```
  === toolchain ===
  prefix=<prefix>
  shellcheck=0.9.0
  shfmt=3.14.1
  bats=1.14.0
  hadolint=2.15.1
  actionlint=1.7.7
  ```
- `shellcheck -S warning` 零告警、`shfmt -d -i 4 -ci` 无改动

## 交付物 2：`scripts/ci/lint.sh`

**L1 静态门禁的唯一真本**，`make lint` 和 CI 都调它。不依赖 docker daemon。

```
scripts/ci/lint.sh [--skip hadolint,actionlint]
```

四段，每段先打 `log_info` 头，失败不中断（跑完再汇总），任何一段失败 → 退出码 1：

1. **shellcheck**：`shellcheck -S warning` 作用于 `git ls-files` 里所有 `scripts/**/*.sh` 和 `tests/bats/*.bash`（用 `git ls-files -z` ＋ `xargs -0`，**不要用 `$(...)` 展开**，路径带空格会炸）
2. **shfmt**：`shfmt -d -i 4 -ci` 作用于同一集合（`-d` 有 diff 即失败）
3. **hadolint**：`docker/dev/Dockerfile` + `docker/<release>/Dockerfile` ×4（用 `docker/*/Dockerfile` glob，不要写死 release）
4. **actionlint**：`.github/workflows/*.yml`

末尾汇总：
```
=== lint summary ===
shellcheck  ok    (N files)
shfmt       ok    (N files)
hadolint    ok    (5 files)
actionlint  ok    (3 workflows)
```
失败段显示 `FAIL` 并把前 20 行输出打出来。

工具缺失时 `die "找不到 <tool>，先跑 scripts/ci/install-tools.sh --prefix \$HOME/.local"`（**不许静默 skip**）。

## 交付物 3：`scripts/ci/secret-scan.sh`

轻量凭据扫描（`make secret-scan` 与 CI 都调它）。只扫 **`git ls-files` 跟踪的文件**，跳过 `.devhome/`、`reference/legacy/` 与二进制（用 `grep -I` 即可）。

必须命中的模式（命中即失败，输出 `file:line: <pattern-id>`）：

| id | 正则 |
|---|---|
| `gh-token` | `ghp_[A-Za-z0-9]{36}` |
| `gh-fine-grained` | `github_pat_[A-Za-z0-9_]{22,}` |
| `aws-key` | `AKIA[0-9A-Z]{16}` |
| `private-key` | `-----BEGIN [A-Z ]*PRIVATE KEY-----` |
| `slack-token` | `xox[baprs]-[A-Za-z0-9-]{10,}` |
| `generic-sk` | `sk-[A-Za-z0-9]{32,}` |

- 命中 0 条时输出 `secret-scan: clean (N files scanned)` 并 exit 0
- 允许清单：`scripts/ci/secret-scan.allow`（可选文件），每行 `path | pattern-id | reason`；**只有在确实误报时才加，且必须写理由**
- 脚本自身与 BATS 里若要用假 token 演示，必须写成拼接形式（如 `ghp_` + `xxx`），**不要真的写一串像 token 的字面量**
- `shellcheck` 零告警、`shfmt -d -i 4 -ci` 无改动

## 交付物 4：`.github/workflows/ci.yml`

```yaml
name: ci
on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
permissions:
  contents: read
```

3 个 job，全部 `runs-on: ubuntu-24.04`（**不许 `-latest`**，不许 ubuntu-22.04）：

1. `lint`（`timeout-minutes: 15`）：checkout → `bash scripts/ci/install-tools.sh --prefix "$RUNNER_TEMP/tools"` → `export PATH="$RUNNER_TEMP/tools/bin:$PATH"` → `bash scripts/ci/lint.sh`
2. `bats`（`timeout-minutes: 20`）：checkout → 同上装工具 → `bash scripts/report.sh all` → `actions/upload-artifact@v4`（`if: always()`）上传 `reports/` 与 `docs/qa/`，`name: bats-report`，`retention-days: 14`
3. `secret-scan`（`timeout-minutes: 10`）：checkout → `bash scripts/ci/secret-scan.sh`

硬要求：
- 每个 job 都要 `timeout-minutes`；**不要**在这里 `docker build`（L1 不构建镜像）
- action 引用固定主版本（`actions/checkout@v4` 这种），**不许 `@main` / `@master`**
- 全部步骤 `run:` 用 bash（runner 默认就是），需要 `set -euo pipefail` 的地方显式写

## 交付物 5：`.github/workflows/images.yml`

L2：4 镜像矩阵构建并推 GHCR。

```yaml
name: images
on:
  push:
    branches: [main]
    paths:
      - "docker/**"
      - "scripts/image.sh"
      - "scripts/ci/**"
      - ".github/workflows/images.yml"
  workflow_dispatch:
concurrency:
  group: images-${{ github.ref }}
  cancel-in-progress: false        # 构建贵，不要互相打断
permissions:
  contents: read
  packages: write
```

matrix（`strategy.fail-fast: false`，4 个 include，`series` 与 Dockerfile 里的 `YOCTO_SERIES` 一致）：

| release | series |
|---|---|
| dunfell | "3.1" |
| kirkstone | "4.0" |
| scarthgap | "5.0" |
| wrynose | "6.0" |

job `build`（`timeout-minutes: 60`）步骤顺序固定：
1. `actions/checkout@v4`
2. `docker/setup-buildx-action@v3`
3. `docker/login-action@v3`：`registry: ghcr.io`，`username: ${{ github.actor }}`，`password: ${{ secrets.GITHUB_TOKEN }}`
4. 计算短 SHA（`id: meta`）：`echo "short_sha=${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"`
5. `docker/build-push-action@v6`：
   - `context: .`（**不是** `docker/<release>`，Dockerfile 要 `COPY docker/common/...`）
   - `file: docker/${{ matrix.release }}/Dockerfile`
   - `push: true`
   - `build-args: APT_MIRROR=archive.ubuntu.com`（境外 runner，见背景约束）
   - `tags`：
     ```
     ghcr.io/zeek-zhao/yp-distro/${{ matrix.release }}:sha-${{ steps.meta.outputs.short_sha }}
     ghcr.io/zeek-zhao/yp-distro/${{ matrix.release }}:${{ matrix.series }}
     ghcr.io/zeek-zhao/yp-distro/${{ matrix.release }}:latest
     ```
   - `labels`：`org.opencontainers.image.source=https://github.com/zeek-zhao/yp-distro`、`org.opencontainers.image.revision=${{ github.sha }}`、`org.opencontainers.image.version=${{ matrix.series }}`
   - `cache-from: type=gha,scope=${{ matrix.release }}` / `cache-to: type=gha,mode=max,scope=${{ matrix.release }}`

**不许**出现 `pull_request` 触发（PR 上不推镜像，也不给 PR 写 packages 权限）。

## 交付物 6：`.github/workflows/pull-check.yml`

P0 出口的**验收器**：不登录 GHCR，匿名拉 4 个镜像并跑断言。

```yaml
name: pull-check
on:
  workflow_dispatch:
    inputs:
      tag:
        description: "要验证的镜像 tag"
        default: latest
  schedule:
    - cron: "0 22 * * 0"     # 每周一 06:00 (CST)
permissions:
  contents: read
```

job `pull`（`timeout-minutes: 30`，matrix 4 个 release，`fail-fast: false`），**只有一个 step**，且这个 step 里：
- 里**绝对不能**有 `docker/login-action` / `docker login` / `GITHUB_TOKEN`（免登录是这条流水线的全部意义，BATS 会断言这一点）
- 执行内容：
  ```bash
  set -euo pipefail
  img="ghcr.io/zeek-zhao/yp-distro/${{ matrix.release }}:${{ inputs.tag || 'latest' }}"
  docker pull "$img"
  docker run --rm "$img" bash -c '
    set -euo pipefail
    test "$(id -u)" -ne 0
    test "${YOCTO_RELEASE}" = "'"${{ matrix.release }}"'"
    shellcheck --version | grep -q 0.9.0
    shfmt --version
    bats --version
    test "$(locale charmap)" = UTF-8
    printf "pulled release=%s user=%s uid=%s\n" "${YOCTO_RELEASE}" "$(id -un)" "$(id -u)"
  '
  ```

## 交付物 7：`tests/bats/02_workflows.bats`

纯静态，**不需要网络、不需要 docker、不许 skip**。沿用 `00_project.bats` 风格（`source setup.bash` + `run` + 断言）。首个用例前定义：

```bash
setup() {
    source "${BATS_TEST_DIRNAME}/setup.bash"
    WF_DIR="${ROOT_DIR}/.github/workflows"
    CI_YML="${WF_DIR}/ci.yml"
    IMG_YML="${WF_DIR}/images.yml"
    PULL_YML="${WF_DIR}/pull-check.yml"
}
```

11 个用例，每个都打 `# bats test_tags=ci`（tag 必须与 `config/features.txt` 登记的一致）：

1. 三个 workflow 文件存在且非空
2. `actionlint` 对 `.github/workflows/*.yml` 全部 exit 0 —— `actionlint` 的定位链：`command -v actionlint` → `${HOME}/.local/bin/actionlint`，都没有就 `fail "先跑 scripts/ci/install-tools.sh --prefix $HOME/.local"`（**是 fail 不是 skip**）
3. `images.yml` 的 matrix release 集合 == `docker/*/Dockerfile` 的目录名集合 == `config/*.env` 的 basename 集合；且每个 release 的 `series` 与 `docker/<release>/Dockerfile` 里的 `YOCTO_SERIES=<x>` 一致（**这条是防漂移的关键**）
4. `images.yml` 用 `secrets.GITHUB_TOKEN`，且整个 `.github/` 里不含 `ghp_` / `github_pat_` / `PERSONAL_ACCESS`
5. `images.yml` 有 `packages: write`，且 `push: true`，且 `context: .` + `file: docker/...Dockerfile` 都在
6. `ci.yml` 不构建镜像：不含 `build-push-action`，不含 `docker build`
7. `pull-check.yml` 不登录：不含 `login-action`、不含 `docker login`、不含 `GITHUB_TOKEN`
8. 三个 workflow 的 `runs-on` 全是 `ubuntu-24.04`，且全文不含 `ubuntu-latest`
9. 所有 `uses:` 都钉在 `@v<数字>`（正则 `@v[0-9]+$`），不许 `@main` / `@master` / 裸 badge 之类
10. `scripts/ci/install-tools.sh --help` exit 0，输出里含 5 个工具名与 `--prefix`
11. `bash scripts/ci/secret-scan.sh` 在当前仓库 exit 0

## 交付物 8：`config/features.txt` + `Makefile`

`config/features.txt` 追加一行（四列格式严格照现有，`|` 两侧各一个空格）：
```
ci-workflows | all | tests/bats/02_workflows.bats | ci
```

`Makefile`：`help` 的 `Targets:` 行补上 `lint secret-scan ci-tools`，并新增三个 target（**只转发，不写逻辑**）：
```make
lint:
	bash scripts/ci/lint.sh
secret-scan:
	bash scripts/ci/secret-scan.sh
ci-tools:
	bash scripts/ci/install-tools.sh
```
`.PHONY` 同步补上。

## 交付物 9：`docs/06-process/ci.md`

一页纸，中文，覆盖：
1. 三层流水线（L1 门禁 / L2 镜像 / L3 真实构建在构建机）各自落在哪、谁触发
2. 三个 workflow 的触发条件、产物、耗时预期
3. GHCR 命名与 tag 约定（`sha-<7>` 不可变、`<series>` 浮动、`latest`）
4. **首次推送后把包设为 public 的操作**：Web 路径（Package settings → Change visibility）与 API 路径
   （`PATCH /user/packages/container/yocto%2F<release>`，body `{"visibility":"public"}`）。
   强调包名带斜杠，URL 里必须编码成 `yocto%2Fdunfell`，否则 404
5. 本地等价命令：`make ci-tools` / `make lint` / `make secret-scan` / `bash scripts/dev.sh bats tests/bats`
6. 常见故障：匿名 pull 403（包还是 private）、`APT_MIRROR` 没覆盖导致境外构建卡死、`actionlint` 缺失

## 验收标准

全部在仓库根执行。前 8 条你自己必须跑绿（容器内直接跑即可）：

```bash
# 1. 工具链安装器（幂等 + 可指定 prefix）
bash scripts/ci/install-tools.sh --prefix "$HOME/.local"
bash scripts/ci/install-tools.sh --prefix "$HOME/.local"     # 第二次必须全部 skip
"$HOME/.local/bin/actionlint" --version

# 2. L1 静态门禁（四段全绿）
export PATH="$HOME/.local/bin:$PATH"
bash scripts/ci/lint.sh

# 3. 凭据扫描
bash scripts/ci/secret-scan.sh

# 4. 新增的静态门禁 BATS（11 用例零 skip）
bats tests/bats/02_workflows.bats

# 5. 全量 BATS 不许退化（原来 11 用例全绿，现在应为 22 用例左右全绿，0 skip）
bats -r tests/bats

# 6. 入口不退化
./project.sh --help
make -n lint
make -n secret-scan

# 7. 遗留脚本是 rename 不是删+增
git status --porcelain | grep -c '^R'   # 期望 5（或至少 5）

# 8. 没有脏文件
git status --porcelain | grep -v -E '^(R|A|M)' || echo "clean"
```

派单方另外执行（你不用做，也做不了）：
- 真推 GHCR（`images.yml` 在 main 上跑）→ 4 个包设为 public → `pull-check.yml` 免登录拉通
- 把 `docs/qa/all/*.md` 与 `reports/*.xml` 作为 CI artifact 下载核对

## 禁止事项

- **不要 commit、不要 push、不要建 tag**（派单方验收后提交）
- **不要动 GitHub 仓库设置**（分支保护、Actions 策略、package 可见性都不要碰），不要 `gh` 登录任何账号
- **不要往仓库写任何凭据**，不要新建 `.env` / 私钥 / token 文件
- **不要 `docker build`、不要 `docker pull`、不要推 GHCR**
- 不要改 `docker/dev/Dockerfile`、`docker/<release>/Dockerfile`、`docker/common/install-yocto-deps.sh`、`scripts/dev.sh`、`scripts/image.sh`、`scripts/wf3.sh`、`config/*.env` 的字段
- 不要改 `tests/bats/99_coverage.bats` 的逻辑来绕过它（它对 features.txt 的校验是正确的，要让新文件合规，不是改校验）
- 不要动 `meta-zeek/`（属 P0-05）
- 不要往 `scripts/` 里新增其他东西，也不要"顺手"美化 `reference/legacy/`（那是死的参考件）
- 不要引入新依赖（不需要 `yamllint`、不需要 `pre-commit`、不需要 Node）

## 完成后

工作区留改动即可。最后用一句话汇报：改了/加了哪些文件、`lint.sh` 四段各自结果、`02_workflows.bats` 与全量 BATS 的用例数与 skip 数。

## 参考

- 现有 BATS 风格：`tests/bats/00_project.bats`、`tests/bats/01_dockerfile.bats`、`tests/bats/setup.bash`
- 报告生成器（CI 的 bats job 要调）：`scripts/report.sh`（`bash scripts/report.sh all`）
- 镜像构建入口（L2 与之等价，不要重写）：`scripts/image.sh`
- 需求文档 §7（路线图）、§6（测试报告）、C24（GHCR public）：只在 OB 里，不在仓库内，本卡已把结论内联，**不要去找**
