# YP-M0-DES-006 · S6 缓存打包与切分设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-006 |
| 版本 | v1.0 |
| 状态 | Approved（见 YP-M0-RV-006） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-24 |
| 覆盖需求 | B-09（超限切分）、B-10（分片完整性校验） |
| 关联问题 | — |
| 关联决策 | — |

## 1. 目的与边界

- **目的**：把下载目录（`DL_DIR`）与状态缓存（`SSTATE_DIR`）打包成可分片的缓存数据，支持超大缓存自动切片、完整性校验与可恢复，供预热镜像发布（S7）使用。
- **不做的事**：
  - 不做实际 bitbake 构建；不引入缓存服务器（约束 6）；
  - 不在本步发布镜像（属 S7）；只产出可打包的缓存目录与切片工具；
  - 不复制 main 的 CVE 离线库或全量 BATS。

## 2. 输入

| 输入 | 来源 |
|---|---|
| 阈值 | `scripts/cache/threshold.conf`：单层 8 GB、上传 8 分钟（= 仓库限制 80%） |
| 缓存源 | 本机 `downloads/` 与 `sstate/` 目录（`.gitignore` 已忽略，不入库） |
| 切片格式 | `manifest.json`（序号、字节数、sha256、总片数）+ `SHA256SUMS` |

## 3. 设计

### 3.1 文件

```text
scripts/cache/
  threshold.conf   # 仅两项：SLICE_MAX_BYTES=8589934592 (8GB)、UPLOAD_TIMEOUT_SEC=480 (8分钟)
  pack.sh          # 把 downloads+sstate 打包成单一 tar + manifest + SHA256SUMS
  split.sh         # 按 threshold 把 tar 切成 <8GB 分片，生成 manifest.json
  merge.sh         # 校验 manifest/SHA256SUMS 后合并分片，sha256 一致才通过
  unpack.sh        # 把合并后的 tar 解包到目标 downloads/sstate 目录
```

### 3.2 阈值常量（约束 8：唯一定义处）

```bash
# threshold.conf
SLICE_MAX_BYTES=8589934592    # 8 GiB = GHCR 单层 10 GB 的 80%
UPLOAD_TIMEOUT_SEC=480        # 8 分钟 = 仓库上传超时 10 分钟的 80%
```

### 3.3 流程

1. `pack.sh`：tar 打包 downloads/ 与 sstate/ → `cache.tar`；计算 sha256 写入 `SHA256SUMS`；
2. `split.sh`：按 `SLICE_MAX_BYTES` 切分 `cache.tar` → `cache.slice.00`...；`manifest.json` 记录每片序号/字节数/sha256/总片数；
3. `merge.sh`：先验 `manifest.json` 与 `SHA256SUMS` 齐全、每片 sha256 匹配，缺片直接拒绝（exit 1）；全部通过才按序合并，最终 sha256 与原始一致；
4. `unpack.sh`：解包到目标目录。

### 3.4 失败模式与处理见第 4 节。

## 4. 失败模式

| 失败 | 现象 | 检测方式 | 处理 |
|---|---|---|---|
| 缓存超过单片阈值 | 单片 >8GB | `stat -c %s` 对比 threshold | 自动切分（split.sh） |
| 缺片 | 某 slice 文件不存在 | manifest 校验 | merge.sh exit 1，拒绝恢复 |
| sha256 不一致 | 校验失败 | `sha256sum -c` | 拒绝合并，保留现场不覆盖 |
| 阈值被多处定义 | grep 到多处数字 | `grep -R 8589934592` 仅一处 | 收敛到 threshold.conf |
| 缓存服务器地址混入 | 出现远程 sstate URL | grep 远程地址 | 移除（约束 6） |

## 5. 验收命令

```bash
# 阈值唯一性
grep -R "8589934592" scripts/ | grep -v threshold.conf   # 期望：无输出

# 打包-切分-合并-校验闭环（用构造的小缓存验证流程）
bash scripts/cache/pack.sh   --src downloads --src sstate --out /tmp/cache.tar
bash scripts/cache/split.sh  --in /tmp/cache.tar --max-bytes "$(. scripts/cache/threshold.conf; echo $SLICE_MAX_BYTES)" --out /tmp/slices
bash scripts/cache/merge.sh  --in /tmp/slices --out /tmp/cache-restored.tar   # 缺片应 exit 1
sha256sum /tmp/cache.tar /tmp/cache-restored.tar   # 两者一致

# 无缓存服务器地址
grep -R "sstate-mirror\|hashserv" . --include="*.yml" --include="*.conf"   # 期望：无输出
```

## 6. 回滚方式

- 单步回滚：`git revert <提交 SHA>`；删除生成的切片与缓存 tar。
- 回滚后验证：脚本文件不存在、threshold.conf 无阈值定义。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-24 | 初稿：缓存打包/切分/合并/校验设计 | zeek.zhao |
