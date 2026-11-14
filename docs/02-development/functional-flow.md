# 功能性流程

> 本文件回答一个问题：**这个仓库从一份配置能产出什么，经过哪些环节，每一步留下什么证据。**
> 它只描述「能力」，不描述「怎么证明能力是对的」——后者在
> [`verification-flow.md`](../01-requirements/verification-flow.md)；为什么这样组织在
> [`engineering-overview.md`](../06-process/engineering-overview.md)。
>
> **保障范围（2026-11-09 决策）**：只保障 **wrynose 6.0**。3.1 / 4.0 / 5.0 的
> 配置与配方**冻结保留、退出保障**（能读、不再构建、不承诺可用），
> 待 6.0 达到五条完成门槛后再回移。详见 [`engineering-overview.md`](../06-process/engineering-overview.md) §2。
>
> 最后更新：2026-11-09

## 1. 主链路：从配置到可起机镜像

一条构建 = **一个 release × 一个 variant × 一个镜像层级**。三个维度都由 kas 组合决定，
产物落在 `work/kas-<release>-<variant>/deploy/`。

```mermaid
flowchart TD
    subgraph IN["输入（全部是文本，可 review）"]
        R["kas/releases/wrynose.yml<br/>发行版 + 层版本锁"]
        V["kas/variants/general.yml<br/>variants/custom.yml"]
        F["kas/features/*.yml<br/>可选开关（rootfs 格式 / 专项）"]
        L["layers/meta-yp/<br/>配方 + bbclass + 镜像定义"]
    end

    R --> K["kas 合并<br/>base + release + variant + features"]
    V --> K
    F --> K
    K --> B["scripts/container.sh<br/>起构建容器"]

    B --> BB["bitbake<br/>parse → fetch → compile → package → rootfs"]
    L --> BB

    BB --> P["工作区 package/<br/>按 PN 分目录的已安装文件树"]
    P --> I1["yp-image-minimal"]
    P --> I2["yp-image-base"]
    P --> I3["yp-image（full）"]

    I1 --> D["deploy/<br/>bzImage · rootfs · wic"]
    I2 --> D
    I3 --> D

    D --> Q["scripts/qemu.sh<br/>起机，等 login 提示"]
    Q --> RP["scripts/report.sh<br/>JUnit + 串口日志"]
    RP --> AR["docs/qa/{release}/{日期}-{sha}.md<br/>+ artifacts-{sha}.sha256"]
```

**这条链上有三个「必须同时存在」的约束**，不符合就是断链：

| 约束 | 破了会怎样 | 守在哪 |
|---|---|---|
| 容器必须同时挂 `/etc/passwd` 与 `/etc/group` | `sstatesig` 用 `grp.getgrgid()` 解析 gid，缺了报「doesn't match any user/group」，只在 `do_package` 真执行时炸 | `scripts/container.sh` |
| 镜像层级必须体积单调（minimal ⊂ base ⊂ full） | 分包了但没装进去，三层退化成同一层 | `12_distro.bats` 断言 |
| 源码根必须走 `YP_SRC_DIR` | 6.0 用 `UNPACKDIR`，3.1–5.0 没有该变量；写死任一个都会让另一侧停在字面量 | `yp-service.bbclass`；`15/16/17_syntax.bats` |

## 2. 组合矩阵：为什么是这三个维度

```mermaid
flowchart LR
    subgraph REL["release（发行版）"]
        R6["wrynose 6.0<br/>受保障"]
        R5["scarthgap 5.0<br/>冻结"]
        R4["kirkstone 4.0<br/>冻结"]
        R3["dunfell 3.1<br/>冻结"]
    end
    subgraph VAR["variant"]
        VG["general<br/>纯参考发行版"]
        VC["custom<br/>叠加 meta-yp 全部能力"]
    end
    subgraph IMG["镜像层级"]
        I1["minimal<br/>只够起机"]
        I2["base<br/>+ 服务与工具"]
        I3["full<br/>+ 六构建系统 demo"]
    end
    R6 --> VG & VC
    VG --> I1 & I2 & I3
    VC --> I1 & I2 & I3
```

- **release** 决定 Yocto 层版本（3.1/4.0/5.0/6.0），带来语法与 class 可用性差异。
- **variant** 决定是否叠 `meta-yp`。`general` 用来证明「meta-yp 可以被剥离」，
  `custom` 用来证明「叠上去也不破坏上游」。
- **镜像层级**用来证明分包设计成立，而不是一坨 full。

> `general` 这个 variant 的存在理由经常被误解成「省时间」。它不是——它是
> **可剥离性证据**：如果 meta-yp 只能整包用，这个仓库就只是个发行版，不是个可复用的层。

## 3. 能力分区：仓库里到底有什么

按能力域分成五组，每组标注**证据位置**。这一节是 `features.md` 的流程图版本，
区别是这里标出了模块之间的依赖。

```mermaid
flowchart TD
    subgraph BASE["A. 构建基础设施"]
        A1["容器化构建<br/>4 发行版镜像 + 1 开发镜像"]
        A2["kas 版本锁<br/>四版配置矩阵"]
        A3["BATS 门禁体系"]
        A4["QA 报告链<br/>build → qemu → report"]
    end

    subgraph DISTRO["B. 发行版能力"]
        B1["三层镜像<br/>minimal ⊂ base ⊂ full"]
        B2["systemd 作 init<br/>journald / 服务管理"]
        B3["品牌化<br/>release / hostname / motd"]
        B4["U-Boot 启动链<br/>x86 QFW"]
    end

    subgraph DEMO["C. 内容示例"]
        C1["六构建系统 demo<br/>make · cmake · autotools<br/>meson · python · rust · go"]
        C2["服务模板 yp-service.bbclass"]
        C3["yp-statusd<br/>/status 返回 JSON"]
        C4["yp-collectd<br/>周期性采集进 journald"]
    end

    subgraph PERF["D. 启动优化"]
        D1["内核裁剪 fragment<br/>kernel_ms -6~-9%"]
        D2["ZSTD 定稿<br/>bzImage -37.5%"]
        D3["serial-getty@ttyS1 mask"]
        D4["rootfs 格式实验开关<br/>squashfs / cpio"]
    end

    subgraph SEC["E. 安全"]
        E1["dm-verity 只读根<br/>cmdline 建表"]
        E2["篡改检出<br/>逐块比对"]
        E3["root hash 保护边界声明"]
    end

    A4 --> B1
    A1 --> B2
    A2 --> B3
    A2 --> B4
    B2 --> C3
    B2 --> C4
    C2 --> C3
    C2 --> C4
    B1 --> D1
    D4 --> E1
    E1 --> E2
    E2 --> E3
```

### 3.1 每组的入口、产物与证据

| 组 | 你能改什么（入口） | 产物 | 证据在哪 |
|---|---|---|---|
| A 构建基础设施 | `scripts/container.sh`、`kas/`、`tests/bats/` | 可复现构建容器、配置组合、门禁结果 | CI 九个检查；`docs/qa/` |
| B 发行版能力 | `layers/meta-yp/conf/`、`recipes-core/images/`、`yp-uboot.inc` | 三层镜像、systemd 单元、品牌文件 | `docs/qa/*/…md`；`12_distro.bats` |
| C 内容示例 | `recipes-demo/`、`classes/yp-service.bbclass` | 9 个 demo 包、`yp-statusd`/`yp-collectd` | `13/16/17_bats`；起机后 `/status` |
| D 启动优化 | 内核 `.cfg` fragment、`IMAGE_FSTYPES`、systemd mask | 更小的内核、ZSTD 镜像、启动耗时数据 | `docs/qa/boot-baseline.md`；`docs/02-development/boot-optimization.md` |
| E 安全 | `scripts/dm-verity.sh`、`kas/features/` | 带 verity 的镜像 + hash 设备 | `docs/qa/security/dm-verity-feasibility.md` |

## 4. 一次「加功能」要经过哪些环节

这是仓库最常发生的一种改动。图上每一个菱形都是一个**可能卡住的地方**，
卡住时的排查入口写在表里。

```mermaid
flowchart TD
    S["开 issue<br/>说明要做什么 + 验收标准"] --> A{"要改哪一层？"}

    A -->|"新配方"| R1["recipes-*/(包名)/(包名)_(版本).bb"]
    A -->|"改镜像内容"| R2["recipes-core/images/yp-image.bb"]
    A -->|"改 distro 行为"| R3["conf/distro/"]
    A -->|"只改命令/脚本"| R4["scripts/"]

    R1 --> C1{"源码根用 YP_SRC_DIR？"}
    C1 -->|"否"| X1["6.0 上 S 会停在字面量"]
    C1 -->|"是"| C2{"需要任务级 override？"}
    C2 -->|"是"| X2["统一写 do_xxx:append()<br/>四版都认，不要补下划线版"]
    C2 -->|"否"| C3{"要在 3.1 上也编？"}
    C3 -->|"是"| X3["变量级 override 要 python __anonymous 补<br/>但当前已退出保障，可不做"]
    C3 -->|"否"| T["改 tests/bats/ 加断言"]

    R2 --> T
    R3 --> T
    R4 --> T

    T --> L["本地 lint + bats"]
    L --> PR["开 PR"]
    PR --> CI["CI 九检查"]
    CI --> BL["构建机真构建<br/>build.sh + qemu.sh + report.sh"]
    BL --> AR["归档 docs/qa/"]
    AR --> MG["PR 合并"]
```

**对应的排查入口**（卡住时看这里，不要猜）：

| 卡在哪 | 第一件事 |
|---|---|
| 解析期报 `old override syntax` | 变量级用了冒号，或下划线版进了 4.0+ 的层 |
| 解析期报 `Could not inherit file classes/xxx.bbclass` | 该 class 在当前 release 不存在（如 3.1 无 `cargo.bbclass`） |
| `do_compile` 报 not found | 先确认是不是同一任务跑了两遍（冗余 override 补丁） |
| `do_package` 报 `doesn't match any user/group` | 容器没挂 `/etc/group` |
| `do_rootfs` 报目录属性冲突 | 先查包元数据，再怀疑配方；旧 sstate 只能 `cleansstate` |
| 起机后行为不对 | 先看串口日志是不是目标镜像（experiment overlay 会残留） |

## 5. 状态机：6.0 主线与冻结版本

```mermaid
stateDiagram-v2
    [*] --> Frozen: 3.1 / 4.0 / 5.0<br/>（已 EOL 或临近）
    [*] --> Active: 6.0 wrynose<br/>唯一受保障

    Active --> Deepening: 做深（smoke / 只读根 /var / 门禁）
    Deepening --> DoD: 五条门槛全过
    DoD --> Backport: 把能力回移到 5.0
    Backport --> Backport: 其余版本按需

    Frozen --> Backport: 只在回移阶段被唤醒
```

五条完成门槛（`DoD`）的原文在 [`engineering-overview.md`](../06-process/engineering-overview.md) §3。
**未达 `DoD` 之前不动 `Frozen` 里的任何东西**——这是这次范围决策的核心纪律，
理由不是「省事」，是「单点资源下同时保四版等于四版都不深」。

## 6. 明确不在图上的东西

画出来的图最容易被问「为什么没有 X」。这里先答：

| 不在图上 | 原因 |
|---|---|
| 真实硬件烧写 | 全部验证在 QEMU，未上过任何一块板；这是**主动声明**，不是遗漏 |
| arm64 / 其他架构 | 单架构策略，`qemuarm64` 暂停；扩架构会先暴露硬编码假设，不是加一行参数 |
| 增量 OTA / 镜像升级 | 无此能力。dm-verity 的只读根是「防篡改」，不是「可升级」 |
| 包管理源 / 在线安装 | 镜像内无 feed，`dnf`/`opkg` 只用于构建期装包 |
| 多用户 / 权限模型 | 默认 root，未做用户体系；服务以 root 跑 |
| 远程管理面 | 无 sshd 默认开启、无 agent、无上报 |

这六条是**边界声明**，写在这里比等评审者问出来强。技术分享场合尤其如此：
「清楚自己不是什么」比「声称什么都是」可信。

## 7. 相关文档

- 怎么证明上面每一步都对 → [`verification-flow.md`](../01-requirements/verification-flow.md)
- 为什么这样分层、为什么只保 6.0 → [`engineering-overview.md`](../06-process/engineering-overview.md)
- 四版语法差异（历史资产，保留） → [`syntax-matrix.md`](syntax-matrix.md)
- 服务怎么写 → [`adding-a-service.md`](adding-a-service.md)
- 启动链细节 → [`boot-chains.md`](boot-chains.md)
