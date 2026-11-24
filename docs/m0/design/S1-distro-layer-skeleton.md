# YP-M0-DES-001 · S1 发行版层骨架设计说明

| 项 | 值 |
|---|---|
| 文档编号 | YP-M0-DES-001 |
| 版本 | v1.0 |
| 状态 | Approved（见 YP-M0-RV-001） |
| 责任人 | zeek.zhao |
| 生效日期 | 2026-11-24 |
| 覆盖需求 | B-01、B-02（本步交付 kas 入口与层锁定所依赖的**发行版层载体**；kas 组合与 repos 版本锁定的完整实现在 DES-002） |
| 关联问题 | YP-M0-ISS-001（执行环境缺 kas/bitbake，验收命令无法实跑） |
| 关联决策 | YP-M0-ADR-001 |

## 1. 目的与边界

- **目的**：建立 `meta-yp-distro` 发行版层骨架，使 Yocto/bitbake 能识别本层并加载 `yp-wrynose` 发行版配置，为后续 S2（kas 入口与层锁定）提供可组合的层载体。
- **不做的事**：
  - 不做 BSP/机器适配、业务配方、镜像配方（属 S2 及以后）；
  - 不复制 main 分支的四版兼容层（`yp-compat.inc`）、CVE 离线库、eSDK workaround；
  - 不写 kas 文件、不锁定 repos commit（属 S2/DES-002）；
  - 不引入任何缓存服务器地址或 root 构建逻辑。

## 2. 输入

| 输入 | 来源 |
|---|---|
| PRD B 组 P0（B-01 至 B-07） | `yp-wrynose 发行版 PRD v0.1`（上游，仓库内以 m0-prompt 引用） |
| 上游发行版 | wrynose 单一发布系列（`LAYERSERIES_COMPAT` 仅此一个） |
| 前置 Step 产出 | S0 空分支、提示词、AI 入口（已完成，`088f346`） |
| 写法参考 | main 分支 `layers/meta-yp/conf/layer.conf`（**仅参考结构，不复制兼容层**） |

## 3. 设计

### 3.1 目录与文件

```text
meta-yp-distro/
  conf/
    layer.conf                 # 层注册、BBFILE_* 变量、LAYERSERIES_COMPAT
    distro/
      yp-wrynose.conf          # 发行版身份定义，require poky.conf
```

### 3.2 `layer.conf` 关键变量

| 变量 | 值 | 作用 |
|---|---|---|
| `BBPATH` | 追加 `${LAYERDIR}` | 让 bitbake 找到 classes/conf |
| `BBFILES` | 追加 `${LAYERDIR}/recipes-*/*.bb` 及 `.bbappend` | 预留配方扫描路径 |
| `BBFILE_COLLECTIONS` | `+= "meta-yp-distro"` | 层集合名 |
| `BBFILE_PATTERN_meta-yp-distro` | `^${LAYERDIR}/` | 配方归属判定 |
| `BBFILE_PRIORITY_meta-yp-distro` | `20` | 覆盖优先级 |
| `LAYERDEPENDS_meta-yp-distro` | `"core meta-poky"` | `yp-wrynose.conf` require 了 `conf/distro/poky.conf`，故显式依赖 |
| `LAYERSERIES_COMPAT_meta-yp-distro` | `"wrynose"` | **只兼容单一 wrynose 系列**，从根上杜绝多版本兼容层 |

### 3.3 `yp-wrynose.conf` 关键变量

| 变量 | 值 | 作用 |
|---|---|---|
| `require` | `conf/distro/poky.conf` | 继承 poky 发行版基线，不自行实现兼容层 |
| `DISTRO` | `"yp-wrynose"` | 发行版身份，供 kas `distro:` 字段加载 |
| `DISTRO_VERSION` | `"0.1.0"` | M0 骨架版本 |

### 3.4 执行顺序与接口

1. bitbake 依据 `BBLAYERS` 中的层路径读取 `conf/layer.conf`，注册 `meta-yp-distro` 集合；
2. kas 传入 `distro: yp-wrynose`，bitbake 按 `DISTRO` 变量加载 `conf/distro/yp-wrynose.conf`；
3. 该 conf `require conf/distro/poky.conf`，得到完整发行版基线；
4. 后续 S2 的 kas fragment 在此层之上叠加 edition/machine 配置。

### 3.5 关键取舍（详见 ADR-001）

- **采用**：`LAYERSERIES_COMPAT` 仅写 `wrynose`， distro conf 只 `require poky.conf`。
- **被否**：复制 main 的 `dunfell kirkstone scarthgap wrynose` 四值兼容串与 `yp-compat.inc`。理由：M0 只面向 wrynose 单一系列，多版本兼容层会引入大量与 M0 无关的分支逻辑，违反约束 4 且无法用 S1 验收命令覆盖。

## 4. 失败模式

| 失败 | 现象 | 检测方式 | 处理 |
|---|---|---|---|
| 层未被识别 | `bitbake-layers show-layers` 输出无 `meta-yp-distro` | 检查 `BBFILE_COLLECTIONS` / `BBFILE_PATTERN` 是否声明 | 补齐变量后重跑 show-layers |
| 层系列不兼容 | show-layers 标记层为 incompatible 或构建报 `incompatible` | 检查 `LAYERSERIES_COMPAT` 与上游 wrynose 系列字符串一致 | 对齐为 `wrynose` |
| distro conf 找不到基线 | 解析报 `Could not inherit`/`not found: conf/distro/poky.conf` | 检查 `LAYERDEPENDS` 含 `meta-poky`，且 poky.conf 路径正确 | 补 `meta-poky` 依赖 |
| 多版本兼容层混入 | `LAYERSERIES_COMPAT` 出现 wrynose 之外的系列 | `grep LAYERSERIES_COMPAT` 断言取值唯一 | 回退该行，开 ISS 单 |
| 执行环境缺工具 | `kas: command not found` / `bitbake-layers: command not found` | `command -v kas bitbake-layers` | 记 ISS-001，采用静态替代验证，实跑留待 CI/完整环境 |

## 5. 验收命令

```bash
# 主验收（需 bitbake / kas，当前执行环境缺失 → UNVERIFIED，见 ISS-001）
cd /workspace/yp-distro
bitbake-layers show-layers | grep meta-yp-distro     # 期望：输出含 meta-yp-distro 且非 incompatible
# S1 尚无 kas/yp.yml（属 S2），kas dump 的完整验收在 S2 执行；本步不伪造该结果。

# 静态替代验证（无需 bitbake，当前环境实跑，见 ISS-001 证据）
test -f meta-yp-distro/conf/layer.conf
test -f meta-yp-distro/conf/distro/yp-wrynose.conf
grep -q 'LAYERSERIES_COMPAT_meta-yp-distro = "wrynose"' meta-yp-distro/conf/layer.conf
! grep -qE 'LAYERSERIES_COMPAT.*(dunfell|kirkstone|scarthgap)' meta-yp-distro/conf/layer.conf
grep -q 'BBFILE_COLLECTIONS += "meta-yp-distro"' meta-yp-distro/conf/layer.conf
grep -q 'DISTRO = "yp-wrynose"' meta-yp-distro/conf/distro/yp-wrynose.conf
grep -q 'require conf/distro/poky.conf' meta-yp-distro/conf/distro/yp-wrynose.conf
```

**期望输出**：所有 `test`/`grep` 断言返回 0（静默通过）；主验收命令在具备工具的环境中应打印层名且不含 incompatible。

## 6. 回滚方式

- 单步回滚：`git revert <S1 提交 SHA>`（不 force push，用新提交修正）。
- 回滚后验证：`test ! -e meta-yp-distro/conf/layer.conf` 返回 0；`scripts/ai-entry.sh` 中 S1 状态回退为「待开始」。

## 7. 变更记录

| 版本 | 日期 | 变更 | 作者 |
|---|---|---|---|
| v1.0 | 2026-11-24 | 初稿：S1 发行版层骨架设计 | zeek.zhao |
