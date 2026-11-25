# YP-M0-DES-007 · S7 预热镜像发布设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-007 |
| 版本 | v1.2 |
| 状态 | Approved（见 YP-M0-RV-007、YP-M0-CHG-007、YP-M0-CHG-010） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-24 |
| 覆盖需求 | B-08（预热镜像分发） |
| 关联问题 | YP-M0-ISS-004（PAT 缺 write:packages）、YP-M0-ISS-016（GITHUB_TOKEN 写包被拒 → CHG-010） |
| 关联决策 | YP-M0-ADR-002（方案 A：不带 PR 的孤立分支）；YP-M0-CHG-007（触发契约：dispatch + 受限 push）；YP-M0-CHG-010（发布凭据契约：具名 PAT secret） |

## 1. 目的与边界

- **目的**：用 GitHub Actions 的具名 secret `GHCR_PAT`（具备 `write:packages`，CHG-010）自动构建并发布 `yp-builder` 与缓存数据镜像到 GHCR，公共仓库可匿名拉取，使「只装 Docker 的机器拉镜像即可构建」成立。
- **不做的事**：
  - 不做实际 bitbake 构建产物（S5）；不在 workflow 内跑完整构建；
  - 不入库任何密钥/token（iso-mapping 第 7 节）；凭据只通过加密的 Actions secret `GHCR_PAT` 注入（CHG-010），不写进仓库或 git 历史；
  - 不向 main 开 PR（方案 A）；触发采用 CHG-007 的双通道：`workflow_dispatch`（并入 main 后可用）+ 本分支受限 `push`（CHG-007 实证可用）。孤立分支上 dispatch API 不可用 ≠ CI 完全阻断。

## 2. 输入

| 输入 | 来源 |
|---|---|
| Dockerfile | `docker/Dockerfile`（S3，DES-003） |
| 缓存数据镜像 | `docker/cache.Dockerfile`（DES-006 产出，本步一并发布） |
| 发布权限 | Actions 加密 secret `GHCR_PAT`（`write:packages`）+ `permissions: packages: write`（CHG-010；token 不入库） |
| 触发方式 | `workflow_dispatch` + 受限 `push`（CHG-007；`feat-m0-kas-bootstrap`，paths = `docker/**`、`scripts/cache/**`、`kas/**`） |
| 仓库可见性 | public，GHCR 包继承为可匿名拉取（实测验证） |

## 3. 设计

### 3.1 Workflow 文件

```text
.github/workflows/m0.yml
  on:
    workflow_dispatch:            # 并入 main 后可用
    push:                         # CHG-007：本分支实测可用
      branches: [feat-m0-kas-bootstrap]
      paths: [docker/**, scripts/cache/**, kas/**]
  permissions: contents: read, packages: write
  jobs:
    publish-builder:   # 构建 yp-builder:wrynose-m0 并 push GHCR
    publish-cache:     # 构建 yp-cache:wrynose-m0 并 push GHCR（缓存数据镜像）
```

### 3.2 发布与拉取流程

1. 本分支由受限 `push`（改动 `docker/**`、`scripts/cache/**`、`kas/**`）触发；`workflow_dispatch` 用具备 `repo`/`workflow` 范围的 PAT 可在孤立分支触发（CHG-010 v1.1，run `45606593806`/`45607197090` 实证），匿名或低权限 token 下返回不可用（ISS-005）；并入 main 后可用默认 token 触发；
2. Actions 用 `docker/login-action` + `secrets.GHCR_PAT`（用户名 `${{ env.OWNER }}`）登录 `ghcr.io`（CHG-010）；
3. `docker/build-push-action` 构建两个镜像并 push：
   - `ghcr.io/zeek-zhao/yp-builder:wrynose-m0`
   - `ghcr.io/zeek-zhao/yp-cache:wrynose-m0`
4. 本地删除镜像后，匿名 `docker pull`（不登录）验证公共可拉取。

### 3.3 镜像标签规则

| 镜像 | 标签 | 说明 |
|---|---|---|
| yp-builder | `wrynose-m0` | 构建环境（DES-003） |
| yp-cache | `wrynose-m0` | 下载/缓存预热数据（DES-006） |

### 3.4 关键取舍

- **采用** 具名 secret `GHCR_PAT`：ISS-016 证实孤立分支上 `GITHUB_TOKEN` 即使声明 `packages: write` 仍被 GHCR 拒绝 `write_package`；现由维护者提供具备 `write:packages` 的 PAT，以 Actions 加密 secret 注入。
- **被否**：把 token 明文写进仓库或 git 历史——违反 iso-mapping 第 7 节；CHG-010 只使用加密 secret，`git grep` 必须无 token 字面量。
- **历史记录**：ISS-004 阶段的旧 PAT 缺 `write:packages`，当时改用 `GITHUB_TOKEN`；run `45601074345` 证明该选择在孤立分支上不成立，故以 CHG-010 纠正。

## 4. 失败模式

| 失败 | 现象 | 检测方式 | 处理 |
|---|---|---|---|
| packages 写权限不足 | push 报 `denied` | workflow 日志 | 确认 `permissions: packages: write` 已声明 |
| workflow 未触发 | `gh run list` 无记录 | 列运行记录 | 区分两种入口：dispatch 404（ISS-005）只能用 push；push 无 run 则检查分支名与 paths 是否命中（CHG-007） |
| 构建失败 | job 红 | 日志 | 按 Dockerfile 报错修，不注释检查 |
| 包私有不可匿名拉 | 匿名 pull 报 denied | 匿名 docker pull | 检查仓库/包可见性设置 |
| 标签冲突/覆盖 | 旧 tag 未更新 | digest 对比 | push 显式 tag，保证 latest 语义 |

## 5. 验收命令

```bash
# 触发自动发布（本分支用 push；dispatch 在孤立分支不可用，ISS-005/CHG-007）
git push origin feat-m0-kas-bootstrap   # 提交需命中 docker/**、scripts/cache/** 或 kas/**
# 并入 main 后： gh workflow run m0.yml --ref main
gh run watch --exit-status            # 期望：job 成功；缺 S5 载荷时按 T3 明示 ::error 失败

# 匿名拉取（公共仓库，不登录）
docker logout ghcr.io
docker rmi ghcr.io/zeek-zhao/yp-builder:wrynose-m0 ghcr.io/zeek-zhao/yp-cache:wrynose-m0 2>/dev/null || true
docker pull ghcr.io/zeek-zhao/yp-builder:wrynose-m0   # 期望：拉取成功
docker pull ghcr.io/zeek-zhao/yp-cache:wrynose-m0     # 期望：拉取成功

# 使用
docker run --rm ghcr.io/zeek-zhao/yp-builder:wrynose-m0 whoami   # jenkins
```

## 6. 回滚方式

- 单步回滚：`git revert <提交 SHA>`；GHCR 包可在包设置中删除特定 tag。
- 回滚后验证：匿名 `docker pull` 该 tag 应失败或回到旧 digest。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-24 | 初稿：GITHUB_TOKEN 自动发布 + 匿名拉取 | zeek.zhao |
| v1.1 | 2026-11-25 | CHG-007：触发契约改为 dispatch + 受限 push；区分 dispatch 不可用与 CI 全部阻断；补 T3 载荷失败口径 | zeek.zhao |
| v1.2 | 2026-11-25 | CHG-010/ISS-016：发布凭据改为具名 PAT secret `GHCR_PAT`；`GITHUB_TOKEN` 写包被拒的事实归档，token 不入库 | zeek.zhao |
