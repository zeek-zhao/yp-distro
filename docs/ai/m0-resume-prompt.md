# M0 续做提示词（依据 YP-M0-RV-010 审计）

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-AI-002 |
| 版本 | v1.0 |
| 状态 | Approved |
| 适用对象 | 外部 AI 编码代理（代码执行方） |
| 基准提交 | 分支 `feat-m0-kas-bootstrap` @ `242c88f` |
| 前置阅读 | `AGENTS.md` → `docs/ai/m0-prompt.md` → `docs/m0/plan.md` → `docs/m0/handoff.md` → `docs/m0/reviews/RV-010.md` |

> 用法：把文末「§12 直接粘贴版」整段发给 AI。**一次只做一 Stage，做完提交并停下等核对**，不要一口气推完。

---

## 1. 你现在接手的状态（事实，不要重新推断）

| 项 | 事实 |
|---|---|
| 分支 | `feat-m0-kas-bootstrap`（孤立分支，与 `main` 无共同祖先；按 YP-M0-ADR-002 方案 A，不开 PR） |
| 已提交 Step | S0、S1、S3（S6/S7 为部分完成） |
| 未开始 Step | **S2（kas 入口）、S4（分卷挂载）、S5（首次构建）、S8（门禁）、S9（变量索引）** |
| 缺口文件 | `kas/` 整个目录、`scripts/bootstrap.sh`、`scripts/preflight.sh`、`docs/m0/variable-index.md` |
| B 组需求 | 已验证 3 条（B-03、B-04、B-08）；进行中 2 条（B-01、B-02）；未开始 7 条 |
| 审计结论 | 有条件通过：**顺序倒置**，S6/S7 走在 S2/S4/S5 前面，导致判据 1/3/4/6 悬空 |

审计报告 `docs/m0/reviews/RV-010.md` 里列了 11 条发现（F-01…F-11），本轮就是按它收口。**先读它，再动手。**

---

## 2. 本轮目标（按顺序，不可跳）

| Stage | 内容 | 消化审计项 | 结束标志 |
|---|---|---|---|
| A | 记录一致性修正 | F-04、F-08、F-09、F-10 | 文档无自相矛盾，lessons 有内容 |
| B | **S2 kas 入口与层锁定** | F-01、F-06 | 两次 `kas dump` 一致，判据 6 由 UNVERIFIED → 通过 |
| C | **S4 下载/缓存分卷挂载** | F-03 | 删容器重建后下载仍在，判据 3/4 有真实证据 |
| D | **S5 首次构建与缓存命中** | 判据 1、B-12、B-13 | 产出镜像 + 两次耗时 + 命中率 |
| E | S6/S7 接线与结论降级修正 | F-02、F-05、F-07 | 分片进发布链路，判据 7 通过 |
| F | S8 门禁 + S9 变量索引与验收 | 判据 8 | 验收表 1–8 行全部有结论 |

**硬性顺序**：A→B→C→D→E→F。**B 不完成，不许碰 C/D**（没有 kas 入口，S4/S5 的"构建"没有执行入口，做了也是空中楼阁）。

---

## 3. 全局约束（与 AGENTS.md 一致，违反即打回）

1. 只在 `feat-m0-kas-bootstrap` 工作；不开 PR（ADR-002 方案 A）。
2. 提交身份只用 `zeek.zhao <zeek.zhao@foxmail.com>`；**禁止** `Co-Authored-By`、`Signed-off-by: AI` 之类署名。
3. **没跑过的命令不许写「通过」**；跑不了就写 `UNVERIFIED` + 原因。这是本项目的头号红线。
4. 主分支只当写法参考，禁止整段复制，禁止引入多版本兼容层。
5. 不做 BSP、业务功能、OTA 服务、包管理器扩展。
6. 禁止任何远程缓存服务器（`SSTATE_MIRRORS`、远程 `BB_HASHSERVE`、远程 hash-equivalence）。
7. 构建容器内禁止 root；固定 `jenkins` 用户；UID 通过 build-arg 可配。
8. 数字常量只允许出现在 `scripts/cache/threshold.conf`（当前 `SLICE_MAX_BYTES=8589934592`、`UPLOAD_TIMEOUT_SEC=480`，即 GHCR 限制的 80%）。
9. 一次一个 Stage，提交后停。
10. 不新增 PRD 之外的需求；确实需要偏离，先写 `docs/m0/deviations.md`。

---

## 4. 每个 Stage 的通用流程（照抄，不要自创）

```text
1) 先写/更新设计文档 docs/m0/design/S<N>-*.md
   必含：目的、输入、接口与变量、失败模式（可检测）、验收命令（可执行）、回滚方式
2) 若涉及契约（阈值、镜像 tag、目录布局、kas 结构）→ 先写 ADR 或 CHG，状态 Approved 才实现
3) 实现代码
4) 真实执行验收命令，保存输出到 docs/m0/reviews/ 或提交信息中引用
5) 遇到非预期现象 → 先开 ISS 单再修；修完贴验证输出才可 Close
6) 更新 plan.md 状态、traceability.md 对应行、acceptance.md 对应判据
7) 提交，信息格式见 §9
8) 停下，回报 §10 六件事
```

---

## 5. Stage A · 记录一致性修正（预计 1 个提交，纯文档）

逐条处理：

| 审计项 | 动作 |
|---|---|
| F-04 | `acceptance.md` 判据 7、8 已填 `UNVERIFIED`（已由核对方补），你需在 E、F 阶段完成后回填真实结论 |
| F-08 | `plan.md` S0 提交号与 B-09/B-10 设计引用已由核对方修正；你需保证后续每次状态变更同步 `traceability.md`，并恢复 S8 的正确名称「PR 门禁」 |
| F-09 | 补齐历史 docs 提交缺的 `Doc:` 说明——不改历史提交，改为在 `plan.md` 顶部「记录补链」小节列明哪次提交缺 Doc 路径及其对应文档 |
| F-10 | `lessons.md` 至少补 6 条：对应 ISS-001…ISS-006 各一行「下次如何避免」，另加 RV-010 F-02「空壳镜像不能当预热缓存」一条 |
| F-03/F-02 | 在 `acceptance.md` 把判据 3、4、5 的结论临时改回 `UNVERIFIED`，备注「待 S4/S5 重验」，避免带病结论流入下一里程碑 |

验收：`grep -rn "已验证" docs/m0/traceability.md` 的每一行都能在 `acceptance.md` 找到对应判据且证据路径存在。

---

## 6. Stage B · S2 kas 入口与层锁定（本轮核心）

### 6.1 先写 `docs/m0/design/S2-kas-entry.md`（编号 YP-M0-DES-002）

必须回答：kas 版本怎么锁、repos 怎么 pin commit、edition 怎么分层、machine 放哪、`kas dump` 为什么应稳定、不同 edition 的差异边界。

### 6.2 目录与文件（硬性）

```text
kas/
├── yp.yml                     # 顶层：include base + 默认 edition + machine
├── base.yml                   # 通用：distro=yp-wrynose、机器无关变量、repos 定义（全部 commit pin）
├── machines/qemux86-64.yml    # 唯一 machine：qemux86-64，无 BSP 代码
└── editions/
    ├── dev.yml                # 开发：可调试、保留符号、不裁体积
    ├── prod.yml               # 生产：image 精简、只读根（后续里程碑）
    ├── dev-kernel.yml         # 内核/驱动开发：独立内核 recipe 覆盖点、menuconfig 片段
    └── ci.yml                  # CI：最小构建、缓存命中优先
```

### 6.3 实现要点

1. **kas 版本固定**：`Dockerfile` 中 `pipx install kas` 改为精确版本（与 `kas --version` 输出一致，写进 DES-002 与 `docs/m0/variable-index.md`），并加一行注释说明锁定原因（F-06）。
2. **repos 全部 pin commit**：`base.yml` 中每个仓库（`poky`、`meta-openembedded`、`meta-yp-distro` 及其依赖）都必须有 `commit:` 或 `tag:`+`commit:`，禁止 `branch:` 裸引用。取值用 `git ls-remote <repo> refs/heads/wrynose` 拿到的实际 SHA，写进设计文档。
3. **`meta-yp-distro` 走本地路径**：`repo: meta-yp-distro`（相对路径），不要写绝对路径，保证换机器可用。
4. **变量归口**：所有可在 edition 覆盖的变量（`DISTRO_FEATURES`、`PACKAGE_CLASSES`、`INIT_MANAGER`、`DL_DIR`、`SSTATE_DIR`）只在 `base.yml` 定义默认、edition 只写差异，禁止三处各写一遍。
5. **`DL_DIR`/`SSTATE_DIR` 指向 `/work/downloads`、`/work/sstate`**，与 S4 的挂载点对齐（此处只写变量，不写挂载逻辑）。
6. **不加缓存服务器**：确认产物中无 `SSTATE_MIRRORS`，`BB_HASHSERVE` 保持 `auto` 本地模式。
7. **不加 `bitbake-setup`**（kas 独占，用户已拍板）。

### 6.4 验收命令（必须真实执行并贴输出）

```bash
kas --version
# 两次 dump 必须无差异
kas dump kas/yp.yml:editions/prod.yml > /tmp/yp-dump-1.yml
kas dump kas/yp.yml:editions/prod.yml > /tmp/yp-dump-2.yml
diff -u /tmp/yp-dump-1.yml /tmp/yp-dump-2.yml && echo DUMP_STABLE
# 每个 repo 都必须有 commit pin
grep -c 'commit:' kas/base.yml
# 四个 edition 均可解析
for e in dev prod dev-kernel ci; do kas dump kas/yp.yml:editions/$e.yml >/dev/null && echo "EDITION_OK $e"; done
# 层锁定仍然单值
grep 'LAYERSERIES_COMPAT' meta-yp-distro/conf/layer.conf
```

期望：`DUMP_STABLE`、四个 `EDITION_OK`、`LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"` 单值。

### 6.5 收尾

- `acceptance.md` 判据 6：`UNVERIFIED` → `通过`，证据栏贴上述命令与输出摘行。
- `traceability.md` B-01、B-02 → `已验证`；B-07（不依赖缓存服务器）证据补 `grep -rn "SSTATE_MIRRORS\|BB_HASHSERVE" kas/ meta-yp-distro/` 无命中。
- `plan.md` S2 → `完成`。

---

## 7. Stage C · S4 下载与缓存分卷挂载

### 7.1 先写 `docs/m0/design/S4-mounts.md`（YP-M0-DES-004）

必须写清：两个卷的生命周期、属主如何对齐、宿主目录不存在时怎么办、卷被清空时构建应该失败还是重建、如何在不重建镜像的前提下换卷。

### 7.2 交付文件

```text
scripts/preflight.sh   # 只做检查，不改数据：目录存在性、属主、可写、剩余空间、卷标识文件
scripts/bootstrap.sh   # 初始化：创建目录、写卷标识、chown、首次拉起构建容器（幂等，可重复执行）
```

### 7.3 实现要点

1. `preflight.sh` 退出码语义：`0` 可继续；`2` 属主不符（打印修复命令）；`3` 空间不足（给出阈值与实测值）；`1` 其他错误。**只读检查，禁止偷偷 chown。**
2. `bootstrap.sh` 必须幂等：重复执行不覆盖已有下载内容，只补缺失。
3. 两个卷分别挂载：`-v <host>/downloads:/work/downloads`、`-v <host>/sstate:/work/sstate`，**不要**用 `--volumes-from` 作为正式路径（那是 S7 的验证手段）。
4. 卷内放一个标识文件（如 `/work/downloads/.yp-volume`，内容含卷类型与创建时间），便于 `preflight` 判断"挂错卷"。
5. 不修改 `entrypoint.sh` 的身份校验逻辑；如必须改，走 CHG。

### 7.4 验收命令（重点是"删容器重建后仍在"）

```bash
bash scripts/preflight.sh --downloads /tmp/yp-dl --sstate /tmp/yp-st; echo "PREFLIGHT=$?"
bash scripts/bootstrap.sh --downloads /tmp/yp-dl --sstate /tmp/yp-st
docker run --rm -v /tmp/yp-dl:/work/downloads -v /tmp/yp-st:/work/sstate yp-builder:wrynose-m0 \
  bash -c 'echo probe > /work/downloads/.probe && echo WRITE_OK'
docker rm -f yp-m0-probe 2>/dev/null || true
# 新容器（全新，不复用上一个）验证数据还在
docker run --rm -v /tmp/yp-dl:/work/downloads -v /tmp/yp-st:/work/sstate yp-builder:wrynose-m0 \
  bash -c 'cat /work/downloads/.probe && echo PERSIST_OK'
# 错属主必须拒绝
chown -R root:root /tmp/yp-dl && bash scripts/preflight.sh --downloads /tmp/yp-dl --sstate /tmp/yp-st; echo "BAD_OWNER_EXIT=$?"
```

期望：`PREFLIGHT=0`、`WRITE_OK`、`PERSIST_OK`、`BAD_OWNER_EXIT=2`。

### 7.5 收尾

判据 3、4 才可由 `UNVERIFIED` → `通过`，证据贴上面四行输出；`traceability.md` B-05、B-06 → `已验证`。

---

## 8. Stage D · S5 首次构建与缓存命中

### 8.1 前置

S2、S4 已完成，`kas build` 能跑通；`DL_DIR`/`SSTATE_DIR` 已指向挂载卷。

### 8.2 做什么

1. 第一次构建（卷留空）：记录 wall time、产物路径、镜像大小。
2. 清 `build/` 但**保留** `downloads/` 与 `sstate/`，第二次构建：记录 wall time 与复用情况。
3. 计算命中率：从 `build/tmp/log/cooker/qemux86-64/console-latest.log`（或 `bitbake` 输出）统计 `from sstate` / `Reusing` 行数 ÷ 总任务数，写进 `docs/m0/reviews/RV-0NN.md`，**贴原始行，不要只写百分比**。
4. 产出 `core-image-minimal`（或 prod 目标），给出镜像路径与 `file` 输出。

### 8.3 验收命令

```bash
time kas build kas/yp.yml:editions/ci.yml        # 第一次，卷空
grep -c "from sstate" build/tmp/log/cooker/qemux86-64/console-latest.log || true
time kas build kas/yp.yml:editions/ci.yml        # 第二次，复用缓存
ls -lh build/tmp/deploy/images/qemux86-64/
```

期望：第二次显著快于第一次；命中率有原始计数；产物存在且可 `file` 识别。

### 8.4 收尾

判据 1 → 通过；B-12、B-13 → 已验证（B-13 离线复用以"第二次构建不再访问网络"的证据：`grep -c "Fetching"` 为 0 或贴 no-network 运行方式）。

---

## 9. Stage E · S6/S7 接线与结论降级修正

### 9.1 先写 ADR（必做）

分片如何以镜像形式发布是**契约变更**，先在 `docs/m0/adr/ADR-004.md` 二选一并给理由：

- **方案 1**：每片一个独立镜像 tag（`yp-cache:wrynose-m0-part-00` …），清单 `manifest.json` 作为 release 附件；
- **方案 2**：分片作为 OCI artifact（`oras push`），单一引用 + 清单。

写完 Approved 才改 workflow。

### 9.2 实现要点

1. `cache-meta.json` 不再写死字节数：新增 `scripts/cache/gen-meta.sh`，从 `threshold.conf` 读取后生成，CI 调用它（F-05）。
2. `split.sh` 删除 `--max-bytes` 覆盖参数（测试需要时用环境变量 `YP_SPLIT_MAX_BYTES` 并打印 WARN），并清理 `SHA256SUMS.slice` 残留（F-11）。
3. 发布 workflow 串联：`pack.sh` → `split.sh` → 上传各片与 `manifest.json` → 记录 digest。
4. **空壳镜像不许再叫"预热缓存"**（F-02）：`cache.Dockerfile` 里若仍是基线布局，注释与 README 必须写明"仅布局基线，真实数据由 S5 产物提供"；S7 的结论降级为「基线镜像分发已验证，真实缓存载荷待 S5 产物」。
5. 下载侧校验脚本：拉取后 `merge.sh` + 比对 `manifest.json` 的源 sha256；缺片必须 `exit 1`。

### 9.3 验收命令

```bash
bash scripts/cache/pack.sh --src /tmp/yp-dl --src /tmp/yp-st --out /tmp/yp-cache.tar
bash scripts/cache/gen-meta.sh > /tmp/cache-meta.json && cat /tmp/cache-meta.json
bash scripts/cache/split.sh --in /tmp/yp-cache.tar --out /tmp/slices
# 匿名拉取 + 合并 + 比对
docker pull ghcr.io/zeek-zhao/yp-cache:wrynose-m0-part-00
bash scripts/cache/merge.sh --in /tmp/slices --out /tmp/merged.tar
sha256sum /tmp/yp-cache.tar /tmp/merged.tar
mv /tmp/slices/cache.slice.01 /tmp/ ; bash scripts/cache/merge.sh --in /tmp/slices --out /tmp/x.tar; echo "MISSING_EXIT=$?"
```

期望：两个 sha256 相同；`MISSING_EXIT=1`；`cache-meta.json` 的数值来自 `threshold.conf`（改阈值后重新生成数值随之变化即可证明）。

### 9.4 收尾

判据 7 → 通过；B-09、B-10 → 已验证；B-08 状态改为「基线已验证 / 载荷待 S5」。

---

## 10. Stage F · S8 门禁 + S9 变量索引与验收

### 10.1 S8

`plan.md` 恢复名称为「PR 门禁」；方案 A 下用 `workflow_dispatch` + 分支 push 触发，内容至少包含：

- `bash -n` 全部脚本
- 阈值唯一性检查：`grep -rn "8589934592\|8G" scripts/ docker/ .github/` 仅命中 `threshold.conf`
- 缓存服务器检查：`grep -rn "SSTATE_MIRRORS\|hashserv"` 仅命中文档禁令
- 提交身份检查：`git log --format=%ae` 无 AI 署名
- 文档一致性：`traceability.md` 每条状态都有 `acceptance.md` 对应行

不跑 bitbake（耗时与配额），构建验证由人工或独立 workflow 承担。

### 10.2 S9

产出 `docs/m0/variable-index.md`：至少 20 个关键变量（`MACHINE`、`DISTRO`、`DL_DIR`、`SSTATE_DIR`、`SSTATE_MIRRORS`、`BB_HASHSERVE`、`INIT_MANAGER`、`DISTRO_FEATURES`、`PACKAGE_CLASSES`、`IMAGE_FSTYPES`、`KERNEL_*` 覆盖点…），每条写：默认值、定义文件、可覆盖层、手改检测命令。

判据 8（手改配置可发现）在此闭环：给出检测脚本与一次"故意手改→被检出"的样例输出。

### 10.3 验收表收口

`acceptance.md` 判据 1–8 全部有结论，且每个"通过"都有命令或产物路径；`lessons.md` 有内容；`plan.md` 全 Step 状态与 `traceability.md` 一致。

---

## 11. 提交格式（缺字段一律打回）

```text
<type>(m0): <一句话动作>
Refs: YP-M0-DES-0NN          # 本提交实现的设计
Refs: YP-M0-ISS-0NN          # 修问题必带
Refs: YP-M0-CHG-0NN          # 动契约必带
Doc: docs/m0/design/S<N>-xxx.md
```

---

## 12. 回报（每个 Stage 结束都要给这六项）

1. 改动文件清单（新增/修改分开）
2. 执行过的命令清单（含失败过的）
3. 已验证项（贴关键输出行）
4. 未验证项及原因
5. 新增记录编号（DES/ISS/CHG/RV）
6. 下一步建议

**不许写"已完成"三个字代替证据。**

---

## 13. 直接粘贴版（发给 AI 的完整提示词）

```text
你在仓库 https://github.com/zeek-zhao/yp-distro 的分支 feat-m0-kas-bootstrap 上继续 M0 实施。
先按顺序读完：AGENTS.md、docs/ai/m0-prompt.md、docs/m0/plan.md、docs/m0/handoff.md、docs/m0/reviews/RV-010.md、docs/ai/m0-resume-prompt.md。

现状：S0/S1/S3 完成，S6/S7 部分完成；S2/S4/S5/S8/S9 未开始。RV-010 审计结论是"有条件通过"，因为顺序倒置，判据 1/3/4/6 悬空。

本轮按 Stage 逐个做，一次只做一个 Stage，做完提交并停下等我确认：
- Stage A 记录修正：lessons.md 补 7 条；acceptance 判据 3/4/5 临时改回 UNVERIFIED 并注明待重验；plan 增加"记录补链"小节。
- Stage B（核心）S2 kas 入口：新建 kas/yp.yml、kas/base.yml、kas/machines/qemux86-64.yml、kas/editions/{dev,prod,dev-kernel,ci}.yml；所有 repos 必须 pin 实际 commit SHA（用 git ls-remote 取）；Dockerfile 把 kas 版本固定；DL_DIR/SSTATE_DIR 指向 /work/{downloads,sstate}；不引入缓存服务器与 bitbake-setup。验收：kas --version、两次 kas dump 用 diff 断言无差异、四个 edition 均可解析、LAYERSERIES_COMPAT 单值。完成后把判据 6 置为通过并贴输出。
- Stage C S4 挂载：交付 scripts/preflight.sh（只读检查，属主不符 exit 2、空间不足 exit 3）与 scripts/bootstrap.sh（幂等）；两个卷分别 -v 挂载，不用 --volumes-from 作正式路径。验收必须包含"删掉容器后新容器里数据仍在"和"错属主被拒绝"的真实输出，然后才把判据 3/4 改回通过。
- Stage D S5 首次构建：第一次空卷构建、清 build 保留 downloads/sstate 后第二次构建，记录两次 wall time、产物路径，并从 cooker log 统计 from sstate 复用行数写进 RV 记录；据此把判据 1 与 B-12/B-13 置为已验证。
- Stage E S6/S7 接线：先写 ADR-004 选"每片一个镜像 tag"或"oras OCI artifact"；cache-meta.json 改为由 scripts/cache/gen-meta.sh 从 threshold.conf 生成；split.sh 去掉 --max-bytes 覆盖并清理 SHA256SUMS.slice；发布流程串 pack→split→上传→记录 digest；空壳镜像的注释与结论降级为"仅布局基线"。验收：合并后 sha256 与源一致、缺片 exit 1。
- Stage F S8/S9：写分支 push 触发的门禁 workflow（脚本语法、阈值唯一、无缓存服务器、提交身份、文档一致性，不跑 bitbake）；产出 docs/m0/variable-index.md，并给出"故意手改被检出"的样例；最后把 acceptance 判据 1–8 全部收口。

硬约束：只用 zeek.zhao <zeek.zhao@foxmail.com> 提交，不允许任何 AI 署名；没跑过的命令不许写"通过"，跑不了写 UNVERIFIED 并说明原因；阈值只在 scripts/cache/threshold.conf；容器内禁止 root；禁止远程 sstate/hashserv；不开 PR；不新增 PRD 外需求；遇到任何非预期现象先开 ISS 单再修，修完贴验证输出才关单。

提交格式：
<type>(m0): 一句话动作
Refs: YP-M0-DES-0NN / YP-M0-ISS-0NN / YP-M0-CHG-0NN
Doc: docs/m0/design/S<N>-xxx.md

每个 Stage 结束回报六项：改动文件清单、执行命令清单（含失败的）、已验证项（贴输出行）、未验证项及原因、新增记录编号、下一步建议。
```
