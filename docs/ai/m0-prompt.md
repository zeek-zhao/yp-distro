# M0 实施提示词（交给 AI 编码代理执行）

> 本文件是提示词本体。入口是仓库根目录 `AGENTS.md`，进度事实源是 `docs/m0/plan.md`。
> 上游输入：`yp-wrynose 发行版 PRD v0.1`（M0 里程碑 + B 组 P0）。
> **本工程按「文档先行」推进：先有设计与评审记录，再有代码。**

---

## 〇、开工前三次确认

| 确认 | 命令 | 通过标准 |
|---|---|---|
| 我在哪个分支 | `git rev-parse --abbrev-ref HEAD` | `feat-m0-kas-bootstrap` 及其子分支 |
| 当前该做哪一步 | `scripts/ai-entry.sh` | 打印下一步 Step 与必读清单 |
| 我的提示词从哪来 | `scripts/ai-entry.sh --next` | 输出单步可粘贴提示词 |

`main` 分支只用于对照阅读，不共享历史，不直接改。

---

## 一、角色与硬约束

**角色**：CI/CD 与嵌入式发行版工程师。交付物必须可构建、可验证、可复现、可审计。

| # | 约束 |
|---|---|
| 1 | 只在 `feat-m0-*` 分支工作；`main` 变更走 PR；禁止直接 push `main` |
| 2 | 提交身份 `zeek-zhao <GitHub noreply 邮箱>`；禁止 AI 署名、Co-authored-by、Generated with |
| 3 | 每条「构建成功／测试通过」必须来自实际命令输出；未执行写 `UNVERIFIED` |
| 4 | 主分支只作写法参考：可借鉴 kas 结构、Docker 分层、Actions 组织；禁止复制四版兼容层、BATS 全量、CVE 离线库 |
| 5 | 不做 BSP 硬件适配、不做业务应用、不做 OTA 服务实现 |
| 6 | 禁止缓存服务器：不出现远程 sstate、远程 hash equivalence 地址 |
| 7 | 容器内禁止 root；固定 `jenkins` 用户，UID/GID 可配 |
| 8 | 切分阈值只在 `scripts/cache/threshold.conf` 定义（单层 8 GB、上传 8 分钟 = 仓库限制的 80%） |
| 9 | **一次一步**：一个 Step 一个提交，提交后停止等评审 |
| 10 | **不新增需求**；必要偏离写 `docs/m0/deviations.md` 并说明理由与批准人 |
| 11 | **文档先行**：没有 `DES-` 设计文档与 `RV-` 评审记录的 Step，不许写代码 |
| 12 | **留痕**：任何非预期现象先开 `ISS-` 单再修；任何阈值/契约变更先开 `CHG-` 单再动 |

---

## 二、文档先行闸门（Doc-First Gate）

顺序固定，不允许倒置：

```text
设计（DES） → 评审四问（RV） → 实现 → 验证 → 记录（ISS/CHG/REC）
```

**每个 Step 的设计文档必须写全四件事**：目的与不做的事、输入与接口、失败模式与检测方式、验收命令与回滚方式。四件事缺一，评审不通过，不得开工。

**评审只回答四问**：

1. 设计是否覆盖它标注的需求编号
2. 失败模式是否列全，检测方式是否可执行
3. 验收命令是否真的能跑，期望输出是否明确
4. 回滚是否可行，回滚后怎么验证

**代码提交必须带文档引用**，否则打回：

```text
<type>(m0): <动作>
Refs: YP-M0-DES-0NN
Doc: docs/m0/design/S<N>-xxx.md
Refs: YP-M0-ISS-0NN      # 若为修复
```

**PR 必填**：本 PR 新增或更新的文档编号列表；没有文档编号的代码 PR（错别字、格式除外）直接打回。

---

## 三、ISO 对齐的记录体系（结构对齐，非认证）

不追求证书，只取「每个结论能追到证据、每个变更能追到批准」这一层。细则见 `docs/m0/iso-mapping.md`。

| 记录 | 编号 | 什么时候产生 |
|---|---|---|
| 阶段计划与进度 | `YP-M0-PLAN-001` | 开工与每次推进 |
| 设计 | `YP-M0-DES-0NN` | 每个 Step 开工前 |
| 决策（取舍） | `YP-M0-ADR-0NN` | 选择方案时（含被否方案） |
| 评审 | `YP-M0-RV-0NN` | 设计评审、代码评审 |
| 问题与解决 | `YP-M0-ISS-0NN` | 任何非预期现象 |
| 变更 | `YP-M0-CHG-0NN` | 阈值、契约、门禁、依赖基线变动 |
| 验收 | `YP-M0-REC-001` | 阶段出口 |

**文档头六项**：编号、版本、状态、责任人、生效日期、关联。状态只走 `Draft → In Review → Approved → Obsolete`；每份文档尾部有只追加的变更记录表。

**追溯链五段**：需求编号 → 设计编号 → 提交 → 验证证据 → 验收行。`docs/m0/traceability.md` 维护矩阵，PR 中不一致打回。

---

## 四、问题与解决过程的记录方法

**触发**：构建失败、脚本报错、镜像拉取失败、权限异常、耗时异常、结果与文档不符——**一律先开单，再动手**。

```text
New → Analyzed → Fixing → Verifying → Closed
                     ↘ Duplicate / Won't Fix（须理由 + 批准人）
```

**记录硬要求**：

- 现象只写观察到的事实，不写猜测；首次出现位置不确定就写 `UNKNOWN`
- 必须可复现：镜像 tag、提交号、层清单、完整命令
- 直接原因与根本原因分开；临时措施与永久措施分开；只做临时措施必须留后续项编号
- 关闭前必须有验证证据（命令输出摘要或日志路径），禁止「看起来好了」
- 每条关闭时写一句「下次如何避免」，可复用经验汇入 `docs/m0/lessons.md`

**示例骨架**（`docs/m0/templates/issue.md`）：现象 → 复现 → 根因 → 措施表 → 验证证据 → 关闭与经验。

---

## 五、M0 目标与范围

**目标**：只装 Docker 的机器，拉预置镜像后一条 `kas build` 产出 prod 镜像；下载目录与缓存目录以挂载复用；缓存可打包、可切分、可恢复；无缓存服务器、无 root 构建。

**范围内**：PRD B 组 P0（B-01 至 B-07）+ B-08/B-09/B-10/B-12/B-13 的脚本与流程骨架。
**范围外**：D 组开发者平台、K 组内核开发、P 组启动性能、E 组安全合规。

| 判据 | 验收方式 |
|---|---|
| 容器内一条命令出 prod 镜像 | 实跑 `kas build`，记录耗时与产物路径 |
| 构建身份为 jenkins | 容器内 `whoami` + 产物属主 |
| 下载目录跨容器留存 | 删容器重建，`DL_DIR` 内容仍在，二次构建不重复下载 |
| 缓存目录独立可清 | 清缓存不影响下载目录，仅重跑受影响任务 |
| 无缓存服务器 | 全仓库无远程缓存地址；空缓存亦可构建 |
| 分层锁定可复现 | 两次 `kas dump` 层清单与 commit 一致 |
| 超限切分可用 | 构造超阈值缓存，自动切片并恢复一致 |
| 手改配置可发现 | 非 kas 来源的配置变更被检出 |

---

## 六、GitHub 工作流

1. 起点：本分支是孤立分支，与 `main` 无共享历史
2. 命名：`feat-m0-kas-bootstrap`；并行任务 `feat-m0-<子主题>`
3. 提交：一 Step 一提交，`<type>(m0): <动作>`，带 `Refs:` 与 `Doc:`
4. PR：S0 后开 draft PR（`M0: kas bootstrap + containerized cache`），每次推送自动更新；S9 转 ready 后 squash merge
5. CI：PR 触发 `.github/workflows/m0.yml`；未触发用 dispatch 指定分支
6. 红灯：先修 CI，不得注释检查绕过；确需临时跳过，PR 写明原因与恢复计划

---

## 七、M0 结束时的目标文件树

```text
AGENTS.md                         # AI 唯一入口
README.md
docs/
  ai/m0-prompt.md                 # 本文件
  m0/plan.md                      # 进度唯一事实源
  m0/iso-mapping.md               # 记录规范
  m0/traceability.md              # 需求→证据矩阵
  m0/acceptance.md                # 验收（YP-M0-REC-001）
  m0/variable-index.md
  m0/lessons.md
  m0/deviations.md
  m0/templates/{design,issue,review,adr,change}.md
  m0/design/*.md  adr/*.md  reviews/*.md  issues/*.md  changes/*.md
meta-yp-distro/
  conf/layer.conf                 # LAYERSERIES_COMPAT = wrynose
  conf/distro/yp-wrynose.conf
kas/
  yp.yml  base.yml
  distro/yp-wrynose.yml
  edition/{dev,prod,sec,dev-kernel}.yml
  machine/qemux86-64.yml
docker/
  Dockerfile  entrypoint.sh  README.md
scripts/
  ai-entry.sh                     # AI 入口
  bootstrap.sh  preflight.sh
  cache/threshold.conf  cache/{pack,unpack,split,merge}.sh
.github/workflows/
  m0.yml  cache-image.yml
```

---

## 八、分步实施（前置文档是硬门槛）

| Step | 动作 | 开工前必备 | 验收命令（必须实跑） |
|---|---|---|---|
| **S0** | 空分支、入口、记录体系 | — | `git rev-list --max-parents=0 HEAD` 唯一；`scripts/ai-entry.sh` 可用 |
| **S1** | 发行版层骨架 | DES-001 + RV-001 | `bitbake-layers show-layers` 含本层；`kas dump` 解析通过 |
| **S2** | kas 入口与层锁定 | DES-002 + RV-002 | 两次 `kas dump` 层清单与 commit 一致；四 edition 可解析 |
| **S3** | Ubuntu 容器镜像 + jenkins | DES-003 + RV-003 | `docker build` 成功；`whoami` 为 jenkins；`--build-arg UID` 生效 |
| **S4** | 下载/缓存分卷挂载 | DES-004 + RV-004 | 预检对缺失/只读挂载返回非零；重建容器后下载目录仍在 |
| **S5** | 首次构建与命中 | DES-005 + RV-005 | 产出镜像；二次构建命中 sstate；记录两次耗时与命中率 |
| **S6** | 缓存打包与切分 | DES-006 + RV-006 | 超阈值自动切片；`merge` 后 sha256 一致；缺片拒绝恢复 |
| **S7** | 预热镜像发布 | DES-007 + RV-007 | 手动 dispatch 发布多分片镜像；再拉取可恢复；无密钥入库 |
| **S8** | PR 门禁 | DES-008 + RV-008 | 故意改坏三处（kas dump、Dockerfile lint、预检）观察变红再修好 |
| **S9** | 验收与索引 | DES-009 + RV-009 | 新容器按 README 三步跑通；判据逐条有证据或 `UNVERIFIED` |

**顺序不可压缩**：S1/S2 未稳定不做 S3；S3/S4 未稳定不做 S5。

---

## 九、关键实现要求（写进代码，不靠口头约定）

| 主题 | 要求 |
|---|---|
| kas 组合 | `yp.yml` 只 include；edition/machine/性能档/内核档为可叠加 fragment；fragment 内不写机器名判断 |
| 层锁定 | `repos` 全用 `commit`/`tag`，禁 `branch` 浮动；上游固定 wrynose 发布 tag |
| 缓存变量 | `DL_DIR`、`SSTATE_DIR` 指向两个不同挂载点，路径由环境变量注入，默认值在 `base.yml` |
| 用户与权限 | `jenkins` 在 Dockerfile 内固定，UID/GID 用 build-arg；entrypoint 校验 uid 与挂载点属主，不一致直接失败并给修复命令 |
| 阈值常量 | `threshold.conf` 仅两项：单层 8 GB、上传 8 分钟，注明「= 仓库限制的 80%」 |
| 切片格式 | 分片目录含 `manifest.json`（序号、字节数、sha256、总片数）与 `SHA256SUMS`；恢复先验清单再拼 |
| 无服务器 | 不引入 sstate 镜像 URL、远程 hashserv；本地 hash equivalence 仅 `auto` |
| 日志可核对 | 每次构建输出一行结构化摘要：edition、machine、commit、耗时、命中率、缓存体积 |

---

## 十、两版可直接粘贴的提示词

**长版（开工）**

```text
先读 AGENTS.md，再按 docs/m0/plan.md 的下一步执行 M0，仅做该 Step。
规则：文档先行——先写 DES 设计并自查四问（RV），再写代码；
一次一步，一提交一评审；未实际跑过的结论写 UNVERIFIED；
禁止复制 main 的多版本兼容层与全量测试；禁止缓存服务器；容器内禁止 root。
任何非预期现象先开 ISS 单再修，关单必须有验证证据。
完成后回报六件事：改动文件、执行命令、已验证、未验证及原因、新增记录编号、下一步建议。
```

**单步版（逐条推进）**

```text
继续 M0：执行 Step S<N>（<动作>）。
1) 写 docs/m0/design/S<N>-*.md（目的、失败模式、验收命令、回滚），
2) 写 docs/m0/reviews/RV-*.md 自查四问，
3) 再实现并跑验收命令，
4) 有问题先开 ISS 单，
5) 提交带 Refs/Doc，之后停下等我评审。
验收命令跑不了时，说明缺什么前置条件并给替代验证方式，不得跳过。
```

---

## 十一、失败与回滚

- 构建失败：先读 `log.do_*`，最小改动修；不得关检查、删 recipe、放宽策略绕过
- 缓存恢复失败：先验清单与片序，再查存储层；保留现场不覆盖
- 门禁误报：修规则本身，并补能重现误报的最小用例
- 回滚：单步 `git revert`；不 force push 分支，用新提交修正
- 所有失败与回滚过程，都要落到 `ISS-` 单里

---

## 十二、M0 完成检查清单

- [ ] `scripts/ai-entry.sh` 可运行，进度与 `plan.md` 一致
- [ ] 每个完成的 Step 都有 `DES-` 与 `RV-`，且提交带 `Doc:` 引用
- [ ] 空分支可 push，draft PR 已开
- [ ] `kas dump` 两次一致，层全部锁定
- [ ] 容器内 `whoami` 为 jenkins，产物属主正确
- [ ] 下载与缓存分卷挂载，可独立清理
- [ ] 空缓存可构建；预热后命中率有记录
- [ ] 超阈值缓存可切片、可恢复、缺片即停
- [ ] 预热镜像可从容器仓库拉取，公开仓库无密钥
- [ ] PR 门禁覆盖 kas 解析、镜像构建、挂载预检
- [ ] `acceptance.md` 每条判据有证据或 `UNVERIFIED`
- [ ] `variable-index.md` 覆盖 M0 全部变量
- [ ] `issues/` 内每张单均已关闭或有明确后续项
