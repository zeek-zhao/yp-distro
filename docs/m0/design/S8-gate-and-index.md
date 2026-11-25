# YP-M0-DES-009 · S8 门禁与 S9 变量索引设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-009 |
| 版本 | v1.1 |
| 状态 | Approved（见 YP-M0-RV-009、YP-M0-CHG-009） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-25 |
| 覆盖需求 | 判据 8（手改配置可发现）、门禁自动化 |
| 关联约束 | AGENTS.md §3 十条硬约束、RV-010 F-04/F-08 |

## 1. 目的与边界

- **目的**：建立提交前/推送时的自动门禁（S8），把十条硬约束中可机械检查的部分固化为脚本；产出变量索引（S9）使"手改配置可被发现"（判据 8）闭环。
- **不做的事**：
  - 门禁不跑 bitbake（耗时与 8GB 配额约束），构建验证由人工或独立 workflow 承担；
  - 不向 main 开 PR（方案 A / ADR-002）；门禁用 `workflow_dispatch` + 分支 push 触发。

## 2. 输入

| 输入 | 来源 |
|---|---|
| 十条硬约束 | AGENTS.md §3 / m0-prompt |
| 全部脚本 | `scripts/**/*.sh`（9 个） |
| 阈值唯一源 | `scripts/cache/threshold.conf` |
| 变量定义 | `kas/base.yml`、`kas/editions/*`、`kas/machines/*`、`meta-yp-distro/conf/*`、`scripts/build/measure.sh` |

## 3. 设计

### 3.1 门禁检查项（S8，五项）

| # | 检查 | 命令 | 通过条件 |
|---|---|---|---|
| G1 | 脚本语法 | `for f in $(find scripts -name '*.sh'); do bash -n "$f"; done` | 全部 rc=0 |
| G2 | 阈值唯一性 | 先 source `scripts/cache/threshold.conf`，再用 `${SLICE_MAX_BYTES}`/`${UPLOAD_TIMEOUT_SEC}` 拼 `grep -rnE` 模式扫描 `scripts/`、`.github/`；校验 `docker/cache-meta.json` 与 gen-meta 输出一致 | 数值字面量仅出现在 threshold.conf；`gate.sh`/`check-vars.sh` 不再含阈值数字、不再需要自我豁免；生成产物 cache-meta.json 数值与 gen-meta 一致（CHG-009） |
| G3 | 无缓存服务器 | `grep -rn "SSTATE_MIRRORS\|hashserv" scripts/ kas/ docker/ .github/` 后排除注释行 | 无非注释的真实远程配置（`SSTATE_MIRRORS =` 赋值、远程 hashserv URL）；允许 `BB_HASHSERVE = "auto"` 本地模式与说明性注释 |
| G4 | 提交身份无 AI 署名 | `git log --format=%ae` + `git log --format=%B \| grep -i co-authored` | 邮箱仅 zeek.zhao；无 AI trailer |
| G5 | 文档一致性 | traceability 每条状态在 acceptance 有对应判据、证据路径存在 | 逐行断言通过 |

门禁实现为 `scripts/gate.sh`（本地可复用）+ `.github/workflows/m0-gate.yml`（CI 触发），两者共用同一检查逻辑（workflow 调用 gate.sh），避免两处漂移。

### 3.2 变量索引（S9）

产出 `docs/m0/variable-index.md`，≥20 个关键变量，每条四要素：

| 要素 | 说明 |
|---|---|
| 默认值 | 从 base.yml / edition / distro conf / 脚本实际取值 |
| 定义文件 | 唯一定义处（归口） |
| 可覆盖层 | base < edition < 命令行；或只读不可覆盖 |
| 手改检测命令 | 一条可执行 grep/diff 断言，检出被改默认值 |

### 3.3 判据 8 检出机制

- 检测脚本 `scripts/check-vars.sh`：对每个关键变量，用 `grep` 比对"归口文件中的期望值"；值被改动或出现重复定义即报 `DRIFT` 并 exit 1。
- 检出样例：临时改一个变量默认值 → 运行 check-vars.sh → 报出漂移行 → 还原 → 再运行通过。贴真实输出于 RV-009。

## 4. 失败模式

| 失败 | 现象 | 检测方式 | 处理 |
|---|---|---|---|
| 脚本语法错误 | `bash -n` 非 0 | G1 | 修脚本，门禁阻断 |
| 阈值多处定义 | grep 命中非 threshold.conf | G2 | 收敛到唯一源 |
| 混入远程缓存服务器 | 出现 SSTATE_MIRRORS/远程 hashserv | G3 | 移除，门禁阻断 |
| AI 署名混入 | git log 命中 co-authored | G4 | 改写提交（本分支可 rebase） |
| 文档状态与判据不一致 | traceability 行无对应判据 | G5 | 补齐对应行 |
| 变量默认值被手改 | check-vars 报 DRIFT | §3.3 | 还原到归口值，门禁阻断 |

## 5. 验收命令

```bash
# S8 五项门禁（本地实跑）
bash scripts/gate.sh                       # 期望：GATE_PASS，五项全绿

# S9 判据 8 检出样例
bash scripts/check-vars.sh                 # 期望：VARS_OK
# 故意手改：把 base.yml 的 BB_NUMBER_THREADS 从 "4" 改成 "8"
sed -i 's/BB_NUMBER_THREADS = "4"/BB_NUMBER_THREADS = "8"/' kas/base.yml
bash scripts/check-vars.sh                 # 期望：DRIFT 检出，exit 1
# 还原
sed -i 's/BB_NUMBER_THREADS = "8"/BB_NUMBER_THREADS = "4"/' kas/base.yml
bash scripts/check-vars.sh                 # 期望：VARS_OK
```

期望：`GATE_PASS`；手改后 `DRIFT` + exit 1；还原后 `VARS_OK`。

## 6. 回滚方式

- `git revert <提交 SHA>`；删除 `scripts/gate.sh`、`scripts/check-vars.sh`、`.github/workflows/m0-gate.yml`、`docs/m0/variable-index.md`。
- 回滚后验证：门禁 workflow 不存在、判据 8 回退 UNVERIFIED。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-25 | 初稿：S8 五项门禁 + S9 变量索引 + 判据 8 检出机制 | zeek.zhao |
| v1.1 | 2026-11-25 | CHG-009：G2 数值来自 threshold.conf，去掉 gate.sh/check-vars.sh 自我豁免；check-vars 用变量拼期望串 | zeek.zhao |
