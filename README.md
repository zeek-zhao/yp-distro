# yp-distro · M0（kas bootstrap）

本分支为 **M0 里程碑专用孤立分支**，与 `main` 不共享历史。`main` 仅作写法参考：kas 文件结构、Docker 分层、GitHub Actions 组织；本分支不复制其四版兼容层与全量测试套件。

## 目标

只装 Docker 的机器，拉取预置镜像后一条命令产出 prod 镜像；下载目录与缓存目录以挂载复用；缓存可打包、可切分、可恢复；无缓存服务器、无 root 构建。

## AI 与人类协作者的入口

```bash
scripts/ai-entry.sh          # 当前 Step + 必读清单 + 下一步
scripts/ai-entry.sh --next   # 可直接粘贴给 AI 的单步提示词
```

**文档先行**：每个 Step 先写设计（`docs/m0/design/`）并过四问评审（`docs/m0/reviews/`），再写代码；遇到的问题先开 `docs/m0/issues/` 单，再修；阈值与契约变更先开 `docs/m0/changes/` 单。记录规范见 [`docs/m0/iso-mapping.md`](docs/m0/iso-mapping.md)。进度以 [`docs/m0/plan.md`](docs/m0/plan.md) 为唯一事实源。

## 三步上手（S9 后可用）

```bash
# 1. 拉镜像
docker pull ghcr.io/<owner>/yp-builder:wrynose-m0

# 2. 建挂载目录
scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate

# 3. 构建
kas build kas/yp.yml:edition/prod.yml:machine/qemux86-64.yml
```

## 现状

| Step | 内容 | 状态 |
|---|---|---|
| S0 | 空分支与实施提示词 | 已完成 |
| S1 | 发行版层骨架 | 待开始 |
| S2 | kas 入口与层锁定 | 待开始 |
| S3 | Ubuntu 容器镜像（jenkins 用户） | 已完成 |
| S4 | 下载与缓存分卷挂载 | 待开始 |
| S5 | 首次构建 | 待开始 |
| S6 | 缓存打包与切分（阈值 80%） | 完成 |
| S7 | 缓存分片发布到容器仓库 | 基线镜像分发已验证（公共 GHCR 匿名拉取）；真实缓存载荷以 S5 产物为准（F-02 结论降级）；分片接线见 ADR-005 / DES-008 |
| S8 | PR 门禁 | 待开始 |
| S9 | 验收与文档 | 待开始 |

执行规则见 [`docs/ai/m0-prompt.md`](docs/ai/m0-prompt.md)。
