# 贡献指南

本仓库以 MIT 许可发布，欢迎 issue 与 PR。合并进 `main` 的提交会进入发布历史，
因此对提交信息与签名有硬性要求。

## 1. 先开 issue 再动代码

- 缺陷 → 开 issue，附 release（`dunfell`/`kirkstone`/`scarthgap`/`wrynose`）、
  machine、以及能复现的最小命令。
- 功能 → 开 issue 说明动机与影响面。较大的改动请先在 issue 里对齐方向，
  避免 PR 返工。
- 开放中的工作与阶段目标见 [`docs/06-process/roadmap.md`](docs/06-process/roadmap.md)。

## 2. 提交身份与 DCO

每次提交必须带开发者原创声明（[DCO 1.1](https://developercertificate.org/)）：

```
Signed-off-by: Your Name <you@example.com>
```

`git commit -s` 会自动加。姓名与邮箱需与提交的 author 一致。

仓库维护者的提交统一使用 `zeek.zhao <zeek.zhao@foxmail.com>`；
如果你在本地启用了仓库自带的钩子，非该身份的提交只会提示、不会阻断，
但 CI 会校验「历史里不得再出现维护者的历史工作邮箱」（详见
`.github/workflows/ci.yml` 的 `identity-guard`）。

启用钩子（一次性）：

```bash
git config core.hooksPath .githooks
```

## 3. 提交信息格式

Conventional Commits：

```
<type>(<scope>): <摘要>

<正文，可选：为什么这么改、试过什么、放弃了什么>

Signed-off-by: Your Name <you@example.com>
```

`type` ∈ `feat` `fix` `docs` `test` `chore` `refactor` `perf` `ci`。
`scope` 用受影响的目录或组件名，如 `recipes-demo`、`boot-exec`、`compliance`。

**不允许** AI 协作者 trailer（`Co-authored-by: Copilot/Claude/GPT/...`）
与 AI 生成声明（`Generated with ...`）。本仓库的钩子会直接拒绝这两类内容。
AI 可以参与产出，但提交责任与署名只能是人类。

## 4. 分支与 PR

分支模型见 [`docs/06-process/branching.md`](docs/06-process/branching.md)。要点：

- 从 `dev` 切出短生命周期分支：`feat/<slug>` / `fix/<slug>` / `docs/<slug>`
- PR 目标为 `dev`；阶段收口时才 `dev` → `main`
- PR 描述里贴出验证命令与结果，CI 必须绿

`main` 上的提交必须能关联到 PR（`branch-guard` 会校验）。

## 5. 提交前本地自检

```bash
bash scripts/dev.sh --build                  # 建/更新开发容器
bash scripts/dev.sh bash scripts/ci/lint.sh  # shellcheck / shfmt / hadolint / actionlint
bash scripts/dev.sh bats tests/bats/         # BATS 全量
bash scripts/ci/secret-scan.sh               # 密文扫描
```

四项与 CI 一致。BATS 要求零 skip。

## 6. 改动 recipe 时的额外要求

- 新增/修改 recipe 后跑一次真构建（至少本机支持的 release），并把 release 与
  结果写进 PR 描述。纯静态检查不足以发现 `file://` 路径、`S`/`UNPACKDIR`
  这类只在解析期报错的问题。
- 涉及许可证字段的改动，同步更新 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
