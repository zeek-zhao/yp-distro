# YP-M0-DES-007 · S7 预热镜像发布设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-007 |
| 版本 | v1.0 |
| 状态 | Approved（见 YP-M0-RV-007） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-24 |
| 覆盖需求 | B-08（预热镜像分发） |
| 关联问题 | YP-M0-ISS-004（PAT 缺 write:packages，改用 Actions GITHUB_TOKEN） |
| 关联决策 | YP-M0-ADR-002（方案 A：CI 用 workflow_dispatch） |

## 1. 目的与边界

- **目的**：用 GitHub Actions 的 `GITHUB_TOKEN`（具备 `packages: write`）自动构建并发布 `yp-builder` 与缓存数据镜像到 GHCR，公共仓库可匿名拉取，使「只装 Docker 的机器拉镜像即可构建」成立。
- **不做的事**：
  - 不做实际 bitbake 构建产物（S5）；不在 workflow 内跑完整构建；
  - 不入库任何密钥/token（iso-mapping 第 7 节）；只用 Actions 内置 `secrets.GITHUB_TOKEN`；
  - 不向 main 开 PR（方案 A）；workflow 由 `workflow_dispatch` 手动触发。

## 2. 输入

| 输入 | 来源 |
|---|---|
| Dockerfile | `docker/Dockerfile`（S3，DES-003） |
| 缓存数据镜像 | `docker/cache.Dockerfile`（DES-006 产出，本步一并发布） |
| 发布权限 | Actions `GITHUB_TOKEN` + `permissions: packages: write`（**不依赖用户 PAT**） |
| 触发方式 | `workflow_dispatch`（方案 A / ADR-002） |
| 仓库可见性 | public，GHCR 包继承为可匿名拉取（实测验证） |

## 3. 设计

### 3.1 Workflow 文件

```text
.github/workflows/m0.yml
  on: workflow_dispatch
  permissions: contents: read, packages: write
  jobs:
    publish-builder:   # 构建 yp-builder:wrynose-m0 并 push GHCR
    publish-cache:     # 构建 yp-cache:wrynose-m0 并 push GHCR（缓存数据镜像）
```

### 3.2 发布与拉取流程

1. `gh workflow run m0.yml --ref feat-m0-kas-bootstrap` 触发；
2. Actions 用 `docker/login-action` + `secrets.GITHUB_TOKEN` 登录 `ghcr.io`；
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

- **采用** `GITHUB_TOKEN`：ISS-004 证实用户 PAT 缺 `write:packages`；Actions token 由平台注入、无需入库、权限可控。
- **被否**：把 PAT 写进 secrets 或明文——违反 iso-mapping 第 7 节；且 PAT 权限不足。

## 4. 失败模式

| 失败 | 现象 | 检测方式 | 处理 |
|---|---|---|---|
| packages 写权限不足 | push 报 `denied` | workflow 日志 | 确认 `permissions: packages: write` 已声明 |
| workflow 未触发 | `gh run list` 无记录 | 列运行记录 | 确认 --ref 指向本分支、文件已 push |
| 构建失败 | job 红 | 日志 | 按 Dockerfile 报错修，不注释检查 |
| 包私有不可匿名拉 | 匿名 pull 报 denied | 匿名 docker pull | 检查仓库/包可见性设置 |
| 标签冲突/覆盖 | 旧 tag 未更新 | digest 对比 | push 显式 tag，保证 latest 语义 |

## 5. 验收命令

```bash
# 触发自动发布
gh workflow run m0.yml --ref feat-m0-kas-bootstrap
gh run watch --exit-status            # 期望：两个 job 成功

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
