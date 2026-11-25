# YP-M0-DES-008 · S6/S7 接线与结论降级设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-008 |
| 版本 | v1.0 |
| 状态 | Approved（见 YP-M0-RV-008） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-25 |
| 覆盖需求 | B-09、B-10、判据 7 |
| 关联决策 | YP-M0-ADR-005（分片发布，方案 1：每片 tag） |
| 关联变更 | YP-M0-CHG-006 |
| 关联审计项 | RV-010 F-02/F-05/F-07/F-11 |

## 1. 目的与边界

- **目的**：把 S6 已产出的缓存切分能力接入 S7 发布链路，收口判据 7；修正三处审计缺陷（写死字节数、阈值可绕过、空壳镜像结论虚高）。
- **不做的事**：
  - 不做实际远程推送验证（孤立分支不可 dispatch，L-01；本阶段只做本地脚本链路 + workflow 接线）；
  - 不引入缓存服务器（约束 6）；
  - 不把空壳镜像结论升级为「预热完成」（F-02 红线）。

## 2. 输入

| 输入 | 来源 |
|---|---|
| 阈值常量 | `scripts/cache/threshold.conf`（唯一源，约束 8） |
| 打包/切分/合并脚本 | `scripts/cache/pack.sh` / `split.sh` / `merge.sh`（DES-006） |
| 发布决策 | ADR-005 方案 1（每片一个 tag） |
| 发布 workflow | `.github/workflows/m0.yml`（DES-007） |

## 3. 设计

### 3.1 gen-meta.sh（F-05）

- 新增 `scripts/cache/gen-meta.sh`：source `threshold.conf`，输出与 `docker/cache-meta.json` 同结构的 JSON，`slice_max_bytes`/`upload_timeout_sec` 取自常量而非写死。
- CI 与发布前调用它生成元数据；验收通过「改阈值→重新生成→数值变化」证明来源唯一。

### 3.2 split.sh 接口收紧（F-11 + 约束 8）

- 删除 `--max-bytes` CLI 参数；改为读取环境变量 `YP_SPLIT_MAX_BYTES`，若设置则打印 `WARN: 使用非标准切片阈值，仅用于测试` 后使用，否则用 `threshold.conf` 的 `SLICE_MAX_BYTES`。
- 不再生成 `SHA256SUMS.slice`（每片 sha256 已在 manifest.json）；若输出目录存在旧 `SHA256SUMS.slice` 则先删除。
- manifest.json 新增 `source_sha256`（源 tar 的 sha256）。

### 3.3 merge.sh 比对增强

- 在现有「缺片 exit 1 / 逐片 sha256 匹配」基础上，合并后若 manifest 含 `source_sha256`，比对合并结果与源 sha256，不符则 exit 1。
- 无 `SHA256SUMS.slice` 时不再报缺失（该文件已由 CHG-006 删除）。

### 3.4 发布 workflow 串联（F-07）

在 `.github/workflows/m0.yml` 新增 `publish-cache-slices` job（沿用 `workflow_dispatch` + GITHUB_TOKEN）：

```text
checkout → 准备缓存源（downloads/sstate）→ pack.sh → gen-meta.sh
→ split.sh → docker build+push 每片为 yp-cache:wrynose-m0-part-NN
→ 上传 manifest.json 为 release 附件 → 记录每片 digest 到 job summary
```

- 缓存源来自 checkout 后的缓存目录；若不存在则 job 明确失败并说明「需 S5 产物」，不伪造推送。
- 受 L-01 约束，孤立分支 workflow 不可 dispatch，本次只完成接线交付，端到端触发标 UNVERIFIED。

### 3.5 空壳镜像结论降级（F-02）

- `docker/cache.Dockerfile` 与 `docker/cache-meta.json` 的注释/note 明确「仅布局基线，真实数据由 S5 产物经 pack.sh 提供」。
- `README.md` 的 S7 行由「完成（公共 GHCR 匿名拉取验证通过）」改为「基线镜像分发已验证；真实缓存载荷待 S5 产物」。
- `traceability.md` B-08 → 「基线已验证 / 载荷待 S5」。

## 4. 失败模式

| 失败 | 现象 | 检测方式 | 处理 |
|---|---|---|---|
| 阈值被 CLI 绕过 | split 用非 8GB 阈值 | `grep -- --max-bytes split.sh` 无命中 | 只留环境变量 + WARN |
| cache-meta 数值写死 | grep 到 8589934592 | `grep -R 8589934592` 仅 threshold.conf | gen-meta 从常量生成 |
| 缺片仍可合并 | merge 输出成功 | 移走一片跑 merge | exit 1（已实现，回归验证） |
| 合并 sha256 不符 | 合并结果≠源 | manifest source_sha256 比对 | exit 1 |
| 空壳镜像被称预热完成 | 文档写「预热完成」 | grep README/traceability | 降级为「基线已验证」 |

## 5. 验收命令

```bash
# 阈值唯一性（脚本源码范围；cache-meta.json 是 gen-meta 生成产物，必然含数值，不纳入此断言）
grep -R "8589934592" scripts/ | grep -v threshold.conf   # 期望：无输出

# 打包-生成元数据-切分-合并闭环
bash scripts/cache/pack.sh --src /tmp/yp-dl --src /tmp/yp-st --out /tmp/yp-cache.tar
bash scripts/cache/gen-meta.sh > /tmp/cache-meta.json && cat /tmp/cache-meta.json
bash scripts/cache/split.sh --in /tmp/yp-cache.tar --out /tmp/slices
bash scripts/cache/merge.sh --in /tmp/slices --out /tmp/merged.tar
sha256sum /tmp/yp-cache.tar /tmp/merged.tar   # 两者一致

# 缺片拒绝
mv /tmp/slices/cache.slice.01 /tmp/ ; bash scripts/cache/merge.sh --in /tmp/slices --out /tmp/x.tar; echo "MISSING_EXIT=$?"

# 阈值变化时 gen-meta 数值随之变化（临时改阈值→生成→比对→还原）
```

期望：两 sha256 相同；`MISSING_EXIT=1`；cache-meta 数值来自 threshold.conf；改阈值后数值变化。

## 6. 回滚方式

- `git revert <提交 SHA>`；删除 gen-meta.sh、恢复 split.sh 的 `--max-bytes` 与 SHA256SUMS.slice、恢复 workflow 到两 job。
- 回滚后验证：`grep -- --max-bytes scripts/cache/split.sh` 有命中、`gen-meta.sh` 不存在、判据 7 回退 UNVERIFIED。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-25 | 初稿：S6/S7 接线、ADR-005 方案 1、F-02/F-05/F-07/F-11 修正 | zeek.zhao |
