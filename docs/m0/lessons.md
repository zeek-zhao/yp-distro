# 经验台账（Lessons Learned）

> 只收录**可复用**的一条经验，来源必须是已关闭的 `ISS-` 单。不写「注意细心」这类无法执行的话。

| # | 经验（一条可执行动作） | 来源 ISS | 生效日期 |
|---|---|---|---|
| 1 | 开工前用 `command -v` 探测验收命令的运行时依赖，缺失即开 ISS 单并用静态断言过渡，不伪造「通过」结论 | YP-M0-ISS-001 | 2026-11-24 |
| 2 | 开里程碑分支前先用 `git merge-base <base> HEAD` 确认与 base 有共同祖先；「孤立分支」与「向 base 开 PR」不可兼得，须在设计阶段用 ADR 裁决分支策略 | YP-M0-ISS-002 | 2026-11-24 |
| 3 | 写 Dockerfile 创建固定 UID/GID 用户前，先用 `getent passwd/group` 检查官方基础镜像的占用，并做幂等删除或 `-o` 回退 | YP-M0-ISS-003 | 2026-11-24 |
| 4 | 发布镜像到 GHCR 前先用 `gh api /user/packages?package_type=container` 与 GHCR token scope 探测权限，区分 git push 与 package push 两套 scope | YP-M0-ISS-004 | 2026-11-24 |
| 5 | GHCR 包可见性无 REST/GraphQL API 可改，PAT 推送默认 private；要匿名拉取须用 Actions GITHUB_TOKEN（包自动链接仓库继承可见性）或网页手动改 public | YP-M0-ISS-005 | 2026-11-24 |
| 6 | 数据卷镜像的目录属主必须与消费者镜像的运行 UID 对齐，并在 `--volumes-from` 组合场景验收，不能只测各自单独使用 | YP-M0-ISS-006 | 2026-11-24 |
| 7 | 镜像的「完成」结论必须检查实际载荷：只含目录布局的空壳镜像不得标为「预热缓存完成」；发布后用 `docker run ... find/ls` 确认数据文件存在再下结论 | RV-010 F-02 | 2026-11-25 |
| 8 | 进入构建环境先读 `/sys/fs/cgroup/memory.max` 与 `cpu.max` 取真实配额，`free`/`nproc` 只作参考；按「限额GB ≈ 线程数 × 单任务峰值」设 `BB_NUMBER_THREADS`/`PARALLEL_MAKE`，OOM 看 `memory.events.oom_kill` 而非猜「偶发失败」 | YP-M0-ISS-011 | 2026-11-25 |
| 9 | `kas dump` 通过不等于 `kas build` 能跑：新 repo 先确认是否真 layer（工具仓库如 bitbake 须显式 `layers` 排除），`LAYERDEPENDS` 必须按上游 `layer.conf` 的 `BBFILE_COLLECTIONS` 实际值写（目录名 ≠ collection 名），并在 S2 做最小构建冒烟 | YP-M0-ISS-008 / ISS-009 | 2026-11-25 |
| 10 | 容器内 cgroup 显示 `max`/32 核可能是 user namespace 假象：判断真实上限要看 `--privileged --cgroupns=host -v /sys/fs/cgroup:/host:ro` 的宿主根 `cpu.max`/`memory.max`；若容器 uid 映射到非宿主 0（看 `/proc/self/uid_map` 与 `/proc/1/ns/user` owner），则无真 `cap_sys_admin`，`nsenter -t 1 -U/-C/-a`、`--cpus`/`--memory` 配额都会被父级硬顶吸收，提配无解时按真实配额调参而非反复重试 | YP-M0-ISS-011（补充调查） | 2026-11-25 |
