# M0 实施提示词（交给 AI 编码代理执行）

> 本文件是提示词本体，不是说明文档。用法见文末「两版可直接粘贴的提示词」。
> 上游输入：`yp-wrynose 发行版 PRD v0.1`（M0 里程碑 + B 组需求）。本文件把该 PRD 收敛成可执行、可验收的 M0 任务。

---

## 一、角色与硬约束

**角色**：你是 CI/CD 与嵌入式发行版工程师，交付物必须可构建、可验证、可复现。

**不可协商的约束**（违反任一条即停止并报告）：

| # | 约束 |
|---|---|
| 1 | 只在 `feat-m0-kas-bootstrap` 分支工作；任何 `main` 变更走 PR，禁止直接 push `main` |
| 2 | 提交身份 `zeek-zhao <GitHub noreply 邮箱>`；提交信息**不得**出现 AI 署名、Co-authored-by、Generated with 等 trailer |
| 3 | 每条「构建成功 / 测试通过」的结论，必须来自你实际执行的命令输出；未执行就写 `UNVERIFIED`，不得推断 |
| 4 | 主分支只作参考：允许借鉴 kas 文件写法、Dockerfile 分层、GitHub Actions 结构；**禁止**复制四版兼容层（dunfell/kirkstone/scarthgap）、BATS 全量套件、CVE 离线库逻辑、多 release 分支判断 |
| 5 | 不引入 BSP 硬件适配、不写业务应用、不实现 OTA 服务；发行版只做策略、容器、缓存与验证 |
| 6 | 不设缓存服务器：禁止出现远程 sstate、远程 hash equivalence 地址、任何自建服务端 |
| 7 | 容器内构建禁止 root；固定 `jenkins` 用户，UID/GID 可配 |
| 8 | 缓存切片阈值集中定义一处（默认单层 8 GB、上传 8 分钟，即 GitHub 容器仓库 10 GB / 10 分钟限制的 80%），禁止散落在脚本里 |
| 9 | 一次只推进一个 Step，提交后停止，等人评审再继续；不得一次性重写多个 Step |
| 10 | 不新增需求。PRD 里没有的能力不实现；确有必要的偏离，写进 `docs/m0/deviations.md` 并说明理由 |

---

## 二、M0 的目标与范围

**一句话目标**：新人只装 Docker，拉取预置镜像后一条 `kas build` 产出 prod 镜像；下载目录与缓存目录以挂载方式复用；缓存可打包、可切分、可恢复；全流程无缓存服务器、无 root 构建。

**范围内**：PRD B 组 P0（B-01 至 B-07）及其必要支撑（B-08、B-09、B-10、B-12、B-13 的脚本与流程骨架）。
**范围外**：D 组开发者平台、K 组内核开发、P 组启动性能、E 组安全合规（这些属于 M1 之后）。

| M0 判据 | 验收方式 |
|---|---|
| 容器内一条命令出 prod 镜像 | `kas build` 实跑，记录耗时与产物路径 |
| 构建身份为 jenkins | 容器内 `whoami`、产物属主 |
| 下载目录跨容器留存 | 删除容器后重建，`DL_DIR` 内容仍在，第二次不再下载 |
| 缓存目录独立可清 | 清缓存不影响下载目录；清理后仅重跑受影响任务 |
| 无缓存服务器依赖 | 全仓库 grep 无远程缓存地址；空缓存也能完成构建 |
| 分层锁定可复现 | 两次 `kas dump` 层清单与 commit 完全一致 |
| 超限切分可用 | 构造超阈值缓存，自动切片并恢复为一致内容 |
| 手改配置可发现 | 非 kas 来源的配置变更被检测并报出差异 |

---

## 三、GitHub 工作流

1. **起点是空分支**：本分支为孤立分支（orphan），与 `main` 不共享历史；`main` 只用于对照阅读。
2. **分支命名**：`feat-m0-kas-bootstrap`；后续子任务如需并行，用 `feat-m0-<子主题>`，例如 `feat-m0-cache-split`。
3. **提交粒度**：一个 Step 一个提交，提交信息 `<type>(m0): <动作>`，type 取 `feat|chore|docs|ci|test`。示例：`feat(m0): add kas entry with locked layers`。
4. **PR 流程**：S0 完成后立即开 draft PR（标题 `M0: kas bootstrap + containerized cache`），每个 Step 推送后 draft 自动更新 CI；S9 完成后转 ready，squash merge。
5. **CI 触发**：PR 触发 `.github/workflows/m0.yml`；未自动触发时用 workflow dispatch 指定分支。
6. **失败处理**：CI 红先修 CI，不得注释掉检查项绕过；确需临时跳过，需在 PR 描述写明原因与恢复计划。

---

## 四、M0 结束时的目标文件树

```text
README.md                         # 三步上手：拉镜像 / 建目录 / kas build
.gitignore
docs/
  ai/m0-prompt.md                 # 本文件
  m0/acceptance.md                # 验收记录（含实跑输出摘要）
  m0/variable-index.md            # M0 变量索引（DISTRO_*、DL_DIR、SSTATE_DIR 等）
  m0/deviations.md                # 偏离记录（无偏离可缺省）
meta-yp-distro/
  conf/layer.conf                 # LAYERSERIES_COMPAT = wrynose
  conf/distro/yp-wrynose.conf     # DISTRO、EDITION 派生、基础策略
  README.md
kas/
  yp.yml                          # 唯一入口
  base.yml                        # repos + bblayers + 缓存的 local_conf_header
  distro/yp-wrynose.yml
  edition/{dev,prod,sec,dev-kernel}.yml
  machine/qemux86-64.yml          # 参考用最小机器，真实机器由 BSP 提供
docker/
  Dockerfile                      # Ubuntu LTS + kas + 构建依赖 + jenkins 用户
  entrypoint.sh                   # 建挂载点、切用户、透传命令
  README.md
scripts/
  bootstrap.sh                    # 建下载/缓存目录、预检、起容器
  preflight.sh                    # 挂载点与权限检查
  cache/threshold.conf            # 唯一切分阈值常量
  cache/pack.sh  unpack.sh  split.sh  merge.sh
.github/workflows/
  m0.yml                          # PR 门禁
  cache-image.yml                 # 手动发布预热镜像到容器仓库（含切片）
```

---

## 五、分步实施（每步单独提交，提交后停止）

| Step | 动作 | 主要产出 | 验收命令（必须实跑） | 停止条件 |
|---|---|---|---|---|
| **S0** | 空分支初始化 | `README.md`、本提示词、`.gitignore` | `git rev-list --max-parents=0 HEAD` 只返回 1 个无父提交 | 分支已建、可 push、PR 已开 draft |
| **S1** | 发行版层骨架 | `meta-yp-distro/conf/layer.conf`、`conf/distro/yp-wrynose.conf` | `bitbake-layers show-layers` 列出该层；`kas dump` 解析无报错 | 层能被 bitbake 解析，不依赖任何 BSP |
| **S2** | kas 入口与层锁定 | `kas/yp.yml`、`base.yml`、`distro/*`、`edition/*`、`machine/qemux86-64.yml` | `kas dump kas/yp.yml:edition/prod.yml` 两次输出层清单与 commit 完全一致 | 四个 edition 均可解析；`DISTRO` 正确 |
| **S3** | 容器镜像 | `docker/Dockerfile`、`entrypoint.sh` | `docker build` 成功；`docker run --rm <img> whoami` 返回 `jenkins`；`--build-arg UID=1000` 生效 | 构建依赖齐备；镜像内可直接跑 kas |
| **S4** | 下载与缓存挂载 | `scripts/bootstrap.sh`、`preflight.sh`、目录约定 | 预检脚本对缺失/只读挂载返回非零；容器删除重建后下载目录内容仍在 | 两个挂载点分属不同目录，互不影响 |
| **S5** | 首次构建 | 无新代码，验证 S1–S4 组合 | `kas build` 产出镜像；第二次构建命中 sstate，耗时显著下降；记录两次耗时与命中率 | 产物路径固定，日志留档 |
| **S6** | 缓存打包与切分 | `scripts/cache/*`、`threshold.conf` | 构造超阈值缓存：切片数量正确、`merge` 后逐文件 sha256 与原始一致；人为删一片时拒绝恢复 | 阈值只从 `threshold.conf` 读取 |
| **S7** | 预热镜像发布 | `cache-image.yml` | 手动 dispatch 发布到容器仓库指定 tag；分片以多镜像上传；再次拉取可恢复 | 公开仓库不写入任何密钥；用内置 token |
| **S8** | PR 门禁 | `m0.yml` | 故意改坏一处（如 `kas dump` 不一致、Dockerfile lint 失败）观察 CI 变红，再修好 | 门禁至少覆盖 kas 解析、镜像构建、挂载预检 |
| **S9** | 验收与文档 | `acceptance.md`、`variable-index.md` | 按 README 三步在新容器中跑通；逐条勾选第二节判据表 | 判据表全部有实跑证据或明确 `UNVERIFIED` |

**顺序不可压缩**：S1、S2 未稳定前不做 S3；S3、S4 未稳定前不做 S5。先让「入口能解析」，再让「环境能跑」，最后才是「缓存与分发」。

---

## 六、关键实现要求（写进代码，不靠口头约定）

| 主题 | 要求 |
|---|---|
| kas 组合 | `yp.yml` 只做 include；edition、machine、性能档、内核档都是可叠加 fragment；不允许在 fragment 里写机器名判断 |
| 层锁定 | `base.yml` 的 `repos` 全部写 `commit` 或 `tag`，禁止 `branch` 浮动；上游层固定到 wrynose 发布 tag |
| 缓存变量 | `DL_DIR` 与 `SSTATE_DIR` 分别指向两个不同挂载点，路径由环境变量注入，默认值写在 `base.yml` |
| 用户与权限 | `jenkins` 用户在 Dockerfile 内固定，UID/GID 用 build-arg 覆盖；entrypoint 校验 uid 与挂载点属主一致，不一致直接失败并给出修复命令 |
| 阈值常量 | `threshold.conf` 只有两项：单层上限 8 GB、上传上限 8 分钟，并注明「= 仓库限制的 80%」 |
| 切片格式 | 分片目录含 `manifest.json`（片序号、字节数、sha256、总片数）与 `SHA256SUMS`；恢复时先验清单再拼 |
| 无服务器 | 不得引入 sstate 镜像 URL、hashserv 远程地址；本地 hash equivalence 若启用，仅 `auto` 模式 |
| 日志可核对 | 每次构建输出一行结构化摘要：edition、machine、commit、耗时、sstate 命中、缓存体积 |

---

## 七、两版可直接粘贴的提示词

**长版（开工时一次性交给 AI）**

```text
读 docs/ai/m0-prompt.md，严格按其中约束与 Step 表执行 M0。
当前只做 S0，其余 Step 等我逐条指令。
规则：一次一步；每步一个提交；不得推断构建成功，未跑就写 UNVERIFIED；
不得复制 main 的四版兼容层与 BATS 全量；不引入缓存服务器；容器内禁止 root。
完成后输出：改了哪些文件、跑了哪些命令、哪些已验证、哪些未验证、下一步建议。
```

**单步版（逐条推进时用）**

```text
继续 M0：实现 Step S<N>（<动作>）。
只做该 Step 的产出文件与验收命令；跑完命令后停下等我评审。
若验收命令无法在当前环境执行，明确说明缺什么前置条件，并给出可执行的替代验证方式，不得跳过。
```

---

## 八、失败与回滚

- **构建失败**：先读 `log.do_*`，按最小改动修；不得通过关闭检查、删除 recipe、放宽策略绕过。
- **缓存恢复失败**：优先怀疑清单与片序，其次怀疑存储层；保留原始缓存现场，不覆盖。
- **门禁误报**：修正门禁规则本身，并补一个能重现误报的最小用例。
- **回滚**：单个 Step 用 `git revert`；不 force push 分支，用新提交修正。

---

## 九、M0 完成检查清单

- [ ] 空分支可 push，draft PR 已开
- [ ] `kas dump` 两次输出一致，层全部锁定
- [ ] 容器内 `whoami` 为 `jenkins`，产物属主正确
- [ ] 下载目录与缓存目录分卷挂载，均可独立清理
- [ ] 空缓存可完成构建；预热缓存后命中率有记录
- [ ] 超阈值缓存可切片、可恢复、缺片即停
- [ ] 预热镜像可从容器仓库拉取，公开仓库无密钥
- [ ] PR 门禁覆盖 kas 解析、镜像构建、挂载预检
- [ ] `acceptance.md` 每条判据有实跑证据或 `UNVERIFIED`
- [ ] `variable-index.md` 覆盖 M0 全部 `DISTRO_*` 与环境变量
