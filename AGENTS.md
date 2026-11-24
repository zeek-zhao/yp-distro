# AGENTS.md · AI 开发入口（唯一入口）

> 任何 AI 编码代理进入本仓库，**先读本文件**，再按「必读顺序」继续。不读本文件直接改代码视为违规。
> 人类协作规范见 `CONTRIBUTING.md`（合并后从 main 补齐）；本分支当前以文档先行推进 M0。

## 1. 三分钟上手

```bash
scripts/ai-entry.sh          # 打印当前里程碑、当前 Step、下一步命令、必读清单
scripts/ai-entry.sh --next   # 打印可直接粘贴给 AI 的单步提示词
```

## 2. 必读顺序（不可跳读）

| 顺序 | 文件 | 读它解决什么 |
|---|---|---|
| 1 | `AGENTS.md`（本文件） | 边界、入口、记录要求 |
| 2 | `README.md` | 项目目标与三步上手 |
| 3 | `docs/ai/m0-prompt.md` | M0 约束、Step 表、验收命令 |
| 4 | `docs/m0/plan.md` | 当前进度与下一步（唯一事实源） |
| 5 | `docs/m0/iso-mapping.md` | 记录怎么写、放哪里、对应哪条规范 |
| 6 | 当前 Step 对应的 `docs/m0/design/*.md` | 本步的设计与接口 |

## 3. 十条硬约束（摘要，全文见 m0-prompt）

1. 只在本分支工作，`main` 变更走 PR
2. 提交身份 `zeek-zhao`，禁止 AI 署名 trailer
3. 未实际执行不得声称成功，未验证写 `UNVERIFIED`
4. 主分支只作写法参考，禁止复制多版本兼容层
5. 不做 BSP / 业务 / OTA 服务
6. 禁止缓存服务器（远程 sstate、远程 hashserv）
7. 容器内禁止 root，固定 `jenkins` 用户
8. 切分阈值只在 `scripts/cache/threshold.conf` 定义
9. 一次一步，提交后停止等评审
10. 不新增 PRD 之外的需求，偏离记 `docs/m0/deviations.md`

## 4. 文档先行（Doc-First Gate）

**顺序是硬性的：文档 → 评审 → 实现 → 验证 → 记录。**

一个 Step 开工前，必须先有该 Step 的设计文档，且包含：目的、输入、接口与变量、失败模式、验收命令、回滚方式。没有设计文档的代码提交一律打回。

| 阶段 | 产物 | 编号 |
|---|---|---|
| 阶段计划 | `docs/m0/plan.md` | YP-M0-PLAN-001 |
| 设计 | `docs/m0/design/S<N>-*.md` | YP-M0-DES-0NN |
| 决策 | `docs/m0/adr/ADR-0NN.md` | YP-M0-ADR-0NN |
| 评审 | `docs/m0/reviews/RV-0NN.md` | YP-M0-RV-0NN |
| 问题 | `docs/m0/issues/ISS-0NN.md` | YP-M0-ISS-0NN |
| 变更 | `docs/m0/changes/CHG-0NN.md` | YP-M0-CHG-0NN |
| 验收 | `docs/m0/acceptance.md` | YP-M0-REC-001 |

模板在 `docs/m0/templates/`，复制后填写，不要自由发挥格式。

## 5. 问题与解决必须留痕

任何非预期现象（构建失败、脚本报错、镜像拉取失败、权限错误、性能异常）都必须开一张 `ISS-` 单，**先记录再修**。修复提交必须在信息里带 `Refs: YP-M0-ISS-0NN`。修完要有验证证据，不允许「改完看起来好了」就关单。字段与状态机见 `docs/m0/templates/issue.md`。

## 6. 提交与记录

```text
<type>(m0): <一句话动作>            # type: feat|chore|docs|ci|test|fix
Refs: YP-M0-DES-0NN                 # 关联设计
Refs: YP-M0-ISS-0NN                 # 如修复问题，必带
Doc: docs/m0/design/S<N>-xxx.md     # 本提交的文档出处
```

## 7. 分工：谁写代码，谁审记录

- 代码由外部 AI 执行方写；本仓库的记录质量与结论一致性由文档维护方核对，口径见 `docs/m0/handoff.md`。
- 每个 Step 交付必须包含：设计、四问评审、代码、命令真实输出、问题单（如有）、变更单（如有）。
- 结论缺证据 = 打回；记录缺失 = 打回，不代补。

## 8. 完成后必须回报的六件事

改动的文件清单、执行的命令清单、已验证项、未验证项及原因、新增的记录编号、下一步建议。
