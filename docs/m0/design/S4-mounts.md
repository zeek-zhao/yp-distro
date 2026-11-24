# YP-M0-DES-004 · S4 下载与缓存分卷挂载设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-004 |
| 版本 | v1.0 |
| 状态 | Approved（见 YP-M0-RV-004） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-25 |
| 覆盖需求 | B-05（下载目录挂载）、B-06（缓存目录挂载）、B-04（普通用户构建，属主对齐） |
| 关联问题 | RV-010 F-03（旧证据错配，判据 3/4 悬空） |
| 关联变更 | YP-M0-CHG-002（阈值与挂载布局契约） |
| 关联设计 | DES-002（DL_DIR/SSTATE_DIR 指向 /work/downloads、/work/sstate）、DES-003（jenkins UID/GID） |

## 1. 目的与边界

- **目的**：把 `DL_DIR` 与 `SSTATE_DIR` 落成两个独立、跨容器存活、可单独清空的宿主目录卷，使「删容器后下载仍在」「缓存可独立清」「错属主被拒绝」成为可复现的验收事实。
- **不做的事**：不做实际 bitbake 构建（S5）；不改 `docker/entrypoint.sh` 的身份校验逻辑（DES-003 已定，改动须走 CHG）；不把 `--volumes-from` 当正式路径（那是 S7 的验证手段）；不引入远程缓存服务器。

## 2. 输入

| 输入 | 值 | 来源 |
|---|---|---|
| 容器内挂载点 | `/work/downloads`、`/work/sstate` | DES-002 §3.3（`DL_DIR`/`SSTATE_DIR` 变量值）、DES-003 §3.4 |
| 容器内构建用户 | `jenkins`，UID/GID 默认 `1000:1000` | DES-003 / Dockerfile `ARG JENKINS_UID/JENKINS_GID` |
| 集中化数字常量 | `JENKINS_UID`、`JENKINS_GID`、`MIN_FREE_BYTES` | `scripts/cache/threshold.conf`（CHG-002） |
| builder 镜像 | `ghcr.io/zeek-zhao/yp-builder:wrynose-m0` | S3/S7 已验证资产 |
| 旧证据缺口 | S7 `--volumes-from` 只证明属主对齐，不证明跨容器留存 | RV-010 F-03 / acceptance 判据 3/4 |

## 3. 设计

### 3.1 两个卷的生命周期

| 卷 | 容器挂载点 | 生命周期 | 清空后果 |
|---|---|---|---|
| downloads | `/work/downloads` | 跨容器、跨多次构建长期保留；容器只是消费者，删容器不删数据 | 下次构建需重新联网下载，属可恢复代价 |
| sstate | `/work/sstate` | 同上，但可**独立**清空以强制重算任务（S5 缓存命中验收用） | 命中率归零、构建变慢，但结果正确 |

两者与镜像、容器均解耦：换镜像、删容器不影响卷内容；换卷只需改运行时 `-v` 参数，不重建镜像。

### 3.2 目录布局与卷标识

每个卷根目录写入一个标识文件 `.yp-volume`（只在缺失时创建，不覆盖已有内容）：

```text
type=downloads|sstate
created_at=<ISO-8601 UTC>
owner=yp-m0
schema=1
```

`type` 用于识别「挂错卷」（把 downloads 挂到 sstate 挂载点）；`created_at` 仅作审计信息，不参与判定。标识文件缺失或 `type` 不符，preflight 一律拒绝（视为未初始化或挂错卷），避免静默在空卷上构建。

### 3.3 属主对齐

- 宿主目录属主必须为 `JENKINS_UID:JENKINS_GID`（默认 `1000:1000`，集中定义在 `threshold.conf`），与 builder 镜像内 jenkins 对齐。
- `bootstrap.sh` 负责 `chown`；`preflight.sh` **只读**校验 `stat -c %u`，不符打印修复命令并 `exit 2`，绝不偷偷 chown。
- 若镜像用 `--build-arg JENKINS_UID=<n>` 改变 UID，必须同步 `threshold.conf` 的 `JENKINS_UID`（契约，见 CHG-002）；否则 preflight 与镜像不一致。

### 3.4 宿主目录不存在 / 卷被清空的处理决策

| 场景 | preflight 行为 | 决策理由 |
|---|---|---|
| 目录不存在 | `exit 1`，提示先跑 `bootstrap.sh` | 未初始化属异常，不能靠构建时的 mkdir 掩盖 |
| 目录存在但 `.yp-volume` 缺失或 `type` 不符 | `exit 1`，提示挂错卷或重新 bootstrap | 防止挂空卷却误以为有缓存（RV-010 F-03 的教训） |
| 卷内其他内容被清空但标识仍在 | 允许继续（视为用户**主动**清空缓存） | 主动清空是 S5 的合法操作；被动丢标识才拒绝 |
| 属主不符 | `exit 2` + 修复命令 | 对齐 DES-003 entrypoint 的硬校验 |
| 可用空间不足 | `exit 3` + 阈值与实测值 | 提前拒绝，避免构建中途磁盘写满 |

### 3.5 空间阈值

- 最小可用空间 `MIN_FREE_BYTES` 定义在 `threshold.conf`（默认 10 GiB），遵守约束 8（数字常量唯一定义处）。
- `preflight.sh` 对每个卷用 `df -PB1` 取所在文件系统可用字节数，低于阈值 `exit 3`，打印阈值与实测值。
- 验收时通过 `--min-free-bytes` 传入一个超大值模拟空间不足，避免真的填满磁盘。

### 3.6 换卷不重建镜像

`bootstrap.sh` 对任意路径初始化并输出可直接复制的挂载片段：

```text
MOUNTS=-v /abs/path/downloads:/work/downloads -v /abs/path/sstate:/work/sstate
```

切换卷只需把新路径传给 `bootstrap.sh`/`preflight.sh` 并替换 `docker run -v`，镜像与容器定义不变。`--start` 可选拉起一个命名持久容器（已存在则跳过，保证幂等）；默认不拉起，与交接验收命令一致。

### 3.7 幂等性

`bootstrap.sh` 重复执行：`mkdir -p` 不报错、已有 `.yp-volume` 不覆盖、属主已正确则不重复 chown、自检 preflight 失败才退出。已有下载内容绝不被清空或覆盖。

## 4. 失败模式与可检测信号

| 失败模式 | 可检测信号 | 处理 |
|---|---|---|
| 卷目录不存在 | `preflight` exit 1 + `NOT_FOUND` | 先跑 `bootstrap.sh` |
| 挂错卷 / 标识缺失 | `preflight` exit 1 + `BAD_VOLUME` | 用正确路径重新 bootstrap |
| 属主不符 | `preflight` exit 2 + `BAD_OWNER` + FIX 命令 | `chown -R <uid>:<gid> <dir>` 或重跑 bootstrap |
| 空间不足 | `preflight` exit 3 + 阈值/实测 | 清理或换更大卷 |
| 重复 bootstrap 覆盖缓存 | 第二次执行后 `.probe` 仍在 | 幂等设计：只补缺失，不清空 |
| 删容器后数据丢失 | 新容器 `cat .probe` 失败 | 卷是宿主 `-v` 挂载，不随容器删除 |

## 5. 验收命令（用户指定：验收在 Docker 环境执行）

> 说明：`preflight.sh`/`bootstrap.sh` 是纯 bash + coreutils 脚本，宿主运行**不需要安装 kas/bitbake 等工具**；容器内写入/读取与持久化验证全部在 builder 容器内执行。

```bash
# 0) 准备空目录
rm -rf /tmp/yp-dl /tmp/yp-st

# 1) 未初始化目录必须被拒绝
bash scripts/preflight.sh --downloads /tmp/yp-dl --sstate /tmp/yp-st; echo "UNINIT_EXIT=$?"

# 2) bootstrap 初始化，连续跑两次验证幂等
bash scripts/bootstrap.sh --downloads /tmp/yp-dl --sstate /tmp/yp-st
bash scripts/bootstrap.sh --downloads /tmp/yp-dl --sstate /tmp/yp-st
bash scripts/preflight.sh --downloads /tmp/yp-dl --sstate /tmp/yp-st; echo "PREFLIGHT=$?"

# 3) 容器内写入（含幂等探针，第二次 bootstrap 后仍在）
docker run --rm -v /tmp/yp-dl:/work/downloads -v /tmp/yp-st:/work/sstate \
  ghcr.io/zeek-zhao/yp-builder:wrynose-m0 \
  bash -c 'echo probe > /work/downloads/.probe && echo WRITE_OK'
cat /tmp/yp-dl/.probe   # 期望：probe（证明第二次 bootstrap 未清空）

# 4) 删容器后用全新容器验证数据仍在
docker run --rm -v /tmp/yp-dl:/work/downloads -v /tmp/yp-st:/work/sstate \
  ghcr.io/zeek-zhao/yp-builder:wrynose-m0 \
  bash -c 'cat /work/downloads/.probe && echo PERSIST_OK'

# 5) 空间不足（传超大阈值模拟，属主此时仍正确）
bash scripts/preflight.sh --downloads /tmp/yp-dl --sstate /tmp/yp-st \
  --min-free-bytes 999999999999999; echo "LOW_SPACE_EXIT=$?"

# 6) 错属主必须拒绝
chown -R root:root /tmp/yp-dl
bash scripts/preflight.sh --downloads /tmp/yp-dl --sstate /tmp/yp-st; echo "BAD_OWNER_EXIT=$?"
```

**期望**：`UNINIT_EXIT=1`、`PREFLIGHT=0`、`WRITE_OK`、`probe`、`PERSIST_OK`、`LOW_SPACE_EXIT=3`、`BAD_OWNER_EXIT=2`。

## 6. 回滚

- 删除 `scripts/preflight.sh`、`scripts/bootstrap.sh`，还原 `scripts/cache/threshold.conf` 中 CHG-002 新增的三行；文档状态回退到 DES-004 v1.0 之前。
- 本阶段不触碰镜像、kas 配置与缓存切分脚本，回滚无跨阶段影响。已创建的宿主测试目录可 `rm -rf /tmp/yp-dl /tmp/yp-st` 清除。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-25 | 初稿：两卷生命周期、属主对齐、标识与退出码契约、验收命令 | zeek.zhao |
