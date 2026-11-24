# 经验台账（Lessons Learned）

> 只收录**可复用**的一条经验，来源必须是已关闭的 `ISS-` 单。不写「注意细心」这类无法执行的话。

| # | 经验（一条可执行动作） | 来源 ISS | 生效日期 |
|---|---|---|---|
| 1 | 开工前用 `command -v` 探测验收命令的运行时依赖，缺失即开 ISS 单并用静态断言过渡，不伪造「通过」结论 | YP-M0-ISS-001 | 2026-11-24 |
| 2 | 写 Dockerfile 创建固定 UID/GID 用户前，先用 `getent passwd/group` 检查官方基础镜像的占用，并做幂等删除或 `-o` 回退 | YP-M0-ISS-003 | 2026-11-24 |
| 3 | 发布镜像到 GHCR 前先用 `gh api /user/packages?package_type=container` 与 GHCR token scope 探测权限，区分 git push 与 package push 两套 scope | YP-M0-ISS-004 | 2026-11-24 |
| 4 | GHCR 包可见性无 REST/GraphQL API 可改，PAT 推送默认 private；要匿名拉取须用 Actions GITHUB_TOKEN（包自动链接仓库继承可见性）或网页手动改 public | YP-M0-ISS-005 | 2026-11-24 |
| 5 | 数据卷镜像的目录属主必须与消费者镜像的运行 UID 对齐，并在 `--volumes-from` 组合场景验收，不能只测各自单独使用 | YP-M0-ISS-006 | 2026-11-24 |
