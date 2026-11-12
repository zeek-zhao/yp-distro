> **历史记录（#135，2026-11-12）**：本文件是 normative 规范，条目编号（KB-xx）
> 仍可继续引用；但部分条目的实测背景来自四版保障时期。现行保障范围只有
> wrynose 6.0（`config/supported-releases.txt`），文中涉及「四版受保」的表述
> 以现行范围为准。正文按历史原样保留。

# 知识库与工程规范（Knowledge Base）

> **本文件是 normative reference（规范）**：条目编号（KB-xx）可被 issue、PR、
> commit message 与其他文档直接引用。全部条目来自本仓库真实发生过的问题与
> 真机验证——每条都有「现象 → 根因 → 规范条款 → 参考」。
>
> 修订纪律：与代码实际行为冲突时，**以代码为准**并当场回改本条目；
> 新增条目必须带可复现的证据（issue/归档/日志路径）。
>
> 最后更新：2026-11-05。条目数：32，分八组。

---

## A. BitBake 与跨版本语法

### KB-01 · 变量级 override 两个版本家族互斥
- **现象**：3.1（dunfell）上 `SRC_URI:append` 静默失效；4.0+ 上写 `SRC_URI_append`
  是**致命解析错误**（data_smart「old override syntax」），且报错会挂到所有求值
  同名变量的 recipe 上（连上游 base-files/systemd 一起红）。
- **根因**：bitbake 2.x 只认冒号；3.1 的 bitbake 不解析冒号 override。
- **规范**：
  1. 4.0+ 一律冒号；3.1 的变量级补丁只能经 `python __anonymous` 按
     `LAYERSERIES_CORENAMES` 动态 `setVar` 下划线版。
  2. 顶层的冒号版在 3.1 会被**静默丢弃**——「不报错 ≠ 不生效」，写完必须验证副作用。
- **参考**：`docs/syntax-matrix.md` A 组；issue #21；`layers/meta-yp/conf/distro/yp-common.inc`

### KB-02 · 任务级 append 冒号四版通用
- **现象**：曾以为「3.1 不认冒号」推广到函数，给每个 `do_install:append` 再补一份
  `do_install_append`，结果同一函数被调两次（症状 `xxx: not found` exit 127）。
- **规范**：`do_x:append()` 函数语法 3.1 也认，四版统一只留冒号一份；
  绝不并列下划线版本。取证方式：`bitbake -c install -f <recipe>` 后看生成的
  `do_install` 是否含目标调用——比读版本号可靠。
- **参考**：`layers/meta-yp/classes/yp-service.bbclass` 尾注；`docs/syntax-matrix.md`

### KB-03 · 自定义任务不经 pseudo
- **现象**：用独立任务 + `addtask` 做 install 逻辑，装出的文件属主是宿主 uid，
  `do_package_qa` 判 host-user-contaminated。
- **规范**：install 逻辑必须挂在 `do_install`（含 append）上以借 pseudo 的
  fake root；不要为绕过语法差异改用 addtask。
- **参考**：`docs/handover.md` §二

### KB-04 · UNPACKDIR 是 6.0 特有
- **现象**：5.0 及更早写 `S = "${UNPACKDIR}"`，`S` 停在字面量，报
  `Directory name ... contains unexpanded bitbake variable`——极易误判成别的问题。
- **规范**：跨版本配方统一用 `YP_SRC_DIR ?= "${@d.getVar('UNPACKDIR') or d.getVar('WORKDIR')}"`
  （meta-yp 的兜底变量），不直接写两套 S。
- **参考**：`layers/meta-yp/classes/yp-service.bbclass`；`docs/syntax-matrix.md`

### KB-05 · usrmerge 从 5.0 开始 → unit 目录路径分两族
- **结论**：`systemd_system_unitdir` 在 3.1/4.0 = `/lib/systemd/system`，
  5.0/6.0 = `/usr/lib/systemd/system`（rpm 包内路径 + 真机 FragmentPath 双证据）。
- **规范**：涉及绝对路径的脚本/文档不要写死 unit 目录，引用该变量；
  与 usrmerge 行为联动理解。
- **参考**：`docs/syntax-matrix.md`（含取证方法）；#80/#82

### KB-06 · cargo.bbclass 4.0 才有；3.1 摘包必须双管齐下
- **规范**：3.1 屏蔽 Rust 配方 = `BBMASK`（kas/releases/dunfell.yml）**加**
  镜像层 `YP_DEMO_RUST=""` 摘包——只做其一必挂（ParseError 或 Nothing RPROVIDES）。
- **参考**：`docs/syntax-matrix.md`；`kas/releases/dunfell.yml`

### KB-07 · kas 的 local.conf 先于 distro conf 解析
- **现象**：kas `local_conf_header` 里 `IMAGE_FSTYPES = "squashfs"` 被 distro 的
  append 盖回去，最终值 `squashfs tar.zst ext4.zst`。
- **规范**：需要「一次只出一种」时必须配 `:remove`（finalize 阶段晚于一切
  append）；`QB_DEFAULT_FSTYPE` 同理（qemuboot.bbclass 默认 `ext4.zst`）。
- **参考**：`kas/features/rootfs-squashfs.yml`；#74

---

## B. 版本锁与点版本

### KB-08 · release TAG 钉在三处，缺一即漂
- **规范**：点版本 bump 必须三处同改：
  ① `kas/releases/<release>.yml` 的 `repos.<repo>.tag`（kas 实际消费）；
  ② `kas/targets/<release>-{custom,general}.lock.yml` 的 `commit`（复现锁，
  **优先级高于 tag**——漏改则 kas 仍 checkout 旧 commit）；
  ③ `config/<release>.env` 的 `*_TAG` + `EXPECT_SHA`（人读口径）。
- **拦截信号**（各自独立）：①漏 → `kas-verify` 报 `repos.poky.tag '旧' != '新'`；
  ②漏 → kas 报 `Provided tag does not match provided commit`；
  每层门禁都按设计工作，红 = 提示你漏了哪处。
- **参考**：`docs/point-releases.md`；#115 首演实证（2026-11-05）

### KB-09 · 浅克隆没有新 tag，kas 不补 fetch
- **现象**：`KAS_CLONE_DEPTH=1` 的旧克隆里没有新 tag，kas 报
  `Tag "x.y.z" cannot be found in repository "poky"`。
- **规范**：删 KAS_WORK_DIR 下对应 repo 目录让 kas 在新 tag 重克隆；
  sstate/downloads 在 KAS_WORK_DIR 之外，不受影响。
- **参考**：`docs/point-releases.md`

### KB-10 · EOL 版本只冻结不跟进
- **规范**：点版本跟进只覆盖受支持 LTS（wrynose/scarthgap）；kirkstone/dunfell
  的 TAG 只为语法对照与 D12 冻结口径服务，安全更新不跟随。
- **参考**：`docs/point-releases.md`；`docs/plan/milestones.md`

---

## C. 内核

### KB-11 · KERNEL_FEATURES 的 scc 在 SRC_URI fragment **之后**合并
- **现象**：fragment 关掉的 `DEBUG_INFO` 被 `features/debug/debug-kernel.scc`
  重新打开，首版实验白测一次（靠 bzImage 体积对不上才发现）。
- **规范**：每启用一组内核裁剪，必须在 bbappend 里同步摘掉对应 KERNEL_FEATURES
  条目（当前三组：debug-kernel / nfsd-enable / sound）；两份文件的分组注释一一对应。
- **参考**：`layers/meta-yp/recipes-kernel/linux/linux-yocto_%.bbappend`；#72

### KB-12 · 裁内核 ≠ 快启动，只有「解压量」直接相关
- **结论**：三版一致（6.18/6.6/5.15）——裁调试设施（DWARF 段）是唯一有启动
  收益的项（kernel_ms -6~-9%）；文件系统/设备驱动惰性初始化，裁掉只减体积。
- **规范**：内核优化的「收益与代价」表必须以 boot-baseline 的实测为准；
  声称启动收益前先看该选项是否在启动路径上。
- **参考**：`docs/qa/boot-baseline.md` §6/§10；`docs/boot-optimization.md`

### KB-13 · bzImage 压缩用宿主命令
- **现象**：`CONFIG_KERNEL_LZ4/ZSTD` 构建报 `lz4: not found`（do_compile）。
- **规范**：bbappend 加 `DEPENDS += "lz4-native zstd-native"`；压缩算法三选一
  在 KVM 下启动时间等价，定稿 ZSTD（体积最小）。
- **参考**：#72；`yp-minimal.cfg` 压缩段

### KB-14 · defconfig 的「保留清单」要核实不要假设
- **现象**：fragment 注释声称保留 SQUASHFS，实测 defconfig 里该选项**根本没开**
  （连 `=m` 都不是）——squashfs 起机 `error -19` panic。
- **规范**：依赖某内核选项前，先查 `package/boot/config-<ver>` 实际值；
  fragment 里显式打开所需选项并注明来源。

---

## D. dm-verity 与安全

### KB-15 · dm-verity 表的三条硬规则
- **规范**（全来自实测，照抄即通）：
  1. `salt` 是内核 verity 表第 10 个**必需**参数，缺了报
     `Not enough arguments (-EINVAL)`；
  2. dm 表长度单位是 **512 字节扇区**（= 数据块数 × 8），传块数报
     `len not aligned to h/w logical block size` → 队列建立失败；
  3. `hash_start` 指树的起始块：cryptsetup 在块 0 写 superblock，
     **必须传 1**，传 0 报 `metadata block 0 is corrupted`。
- **参考**：`docs/qa/security/dm-verity-feasibility.md`；#116

### KB-16 · dm-verity 的保护边界要说清
- **结论**：root hash 走 cmdline 明文——防盘上篡改/持久化后门（篡改被逐块
  检出），**不防整镜像替换**。完整闭环需要签名链。
- **规范**：对外表述 dm-verity 能力时必须带此边界；签名链是前置设计项（#118）。
- **参考**：`docs/qa/security/dm-verity-production-assessment.md`

### KB-17 · dm-verity 集成走综合路线
- **决策**：路线一（meta-security + meta-oe，initramfs 挂根）用于 5.0；
  路线二（自持 cmdline 建表，无 initramfs）用于 6.0——上游 meta-security 无
  6.0 分支（master 已指向 blacksail），且路线二保持启动测量口径不变。
- **参考**：`docs/qa/security/dm-verity-production-assessment.md`；#117

---

## E. systemd 与启动测量

### KB-18 · 测量链的收尾段也要守护
- **现象**：`set -e` 恢复后 `kill <已退出的writer>` 非零 → 脚本在写结果之前
  静默 exit 1（marks 里明明有 login，json 永远不出）。
- **规范**：任何「可能合法失败」的清理动作（kill/awk/可选文件读）必须
  `|| true` 或吞错返回空，失败判定统一收口到调用方的显式检查。
- **参考**：#110；`scripts/lib/boot-marks.sh`

### KB-19 · systemd-analyze 的 blame 时长不可相加
- **结论**：blame 是每个 unit 各自的激活耗时，并行时重叠——只用于排序，
  不用于统计；真正决定 login 时刻的是 `critical-chain`。
- **规范**：优化取舍只看 critical-chain；不在链上的 unit 砍了墙钟不变。
- **参考**：`docs/qa/boot-baseline.md` §7；#73

### KB-20 · 5.0+ 的 userspace 瓶颈是 udev 冷插排空
- **结论**：`dev-ttyS0/vda.device` 要 ~6-8s 才 active（settle 语义），login 等
  最慢的设备事件；继续压它靠减少设备事件（内核裁剪）而非改 systemd。
- **规范**：遇到「启动慢」先跑 `critical-chain` 定位链尾，再决定动哪里；
  已落地的措施见 boot-optimization 的「到此为止」一节。
- **参考**：`docs/qa/boot-baseline.md` §7；#73

### KB-21 · runqemu 串口布局四版一致：ttyS1 是 null 口
- **规范**：`serial-getty@ttyS1` 在所有版本 mask（`YP_MASK_UNITS`，distro 层
  postprocess，/dev/null 链接）；mask 而非删文件（unit 属 systemd 包）。
- **参考**：`layers/meta-yp/conf/distro/include/yp-common.inc`；#73

### KB-22 · U-Boot QFW bootmeth 需要 2024.07+
- **结论**：u-boot 2024.01（5.0）没有 `BOOTMETH_QFW`——U-Boot 本体能起但
  引导不了 `-kernel` 传入的 bzImage；6.0 的 2026.01 defconfig 自带
  CMD_QFW+BOOTSTD_FULL。
- **规范**：5.0 的启动基线按 `-kernel` 直启口径（bootloader 段 n/a，
  degraded.txt 登记）；不 hand-roll `qfw+zboot` bootcmd（两版链语义会分叉）。
- **参考**：#81；`config/degraded.txt`（uboot-qfw-chain）

### KB-23 · 6.0 把 debug-tweaks 拆成了三个正交项
- **结论**：串口空密码登录只需要 `empty-root-password`；`allow-empty-password`
  只管 sshd；`allow-root-login` 本来就没禁。选错会静默失效。
- **规范**：三层镜像中 `empty-root-password` 只开 full 层（有意为之的降级，
  degraded.txt 登记）；新增版本若同样拆分，逐项核对而非沿用旧名。
- **参考**：`layers/meta-yp/recipes-core/images/yp-image.bb`；#59/#110

### KB-24 · busybox 工具链的参数形态
- **规范**：镜像内的 busybox `head` 不认 `-15` 旧式参数（要 `-n 15`）；
  boot-exec 下发长命令时避免参数落在串口折行处。
- **参考**：#73 排障记录

---

## F. QA / 门禁 / 流程

### KB-25 · do_rootfs 目录属性冲突 → 先查 rpm 元数据
- **现象**：`file X conflicts between attempted installs of A and B`——A/B 两包
  同路径 `(mode,owner,group)` 不一致。
- **规范**：docker 内 `rpm -qp --qf` 逐包比对冲突路径三元组，**先定位脏包再
  怀疑配方**；本仓库两次事故（#109 及其复发）全是 11-01 实验期的旧 rpm。
- **参考**：#109；`docs/handover.md` §三

### KB-26 · 内容级污染只能 cleansstate 清除
- **现象**：强制重跑 do_install 后 do_rootfs 全绿，几小时后同款污染又出现——
  旧哈希的 sstate 归档把污染带回来（restore 连 mtime 一起还原）。
- **规范**：`bitbake -c cleansstate <pn>` 是唯一可靠清除；重跑任务会被旧哈希
  归档复活。指纹门禁拦不住这类（内容级 vs 指纹级），内容扫描是 backlog #119。
- **参考**：#109/#114/#85

### KB-27 · deploy 指纹门禁的语义与边界
- **规范**：`commit` 之后构建产物必然被判 stale——重跑 `build.sh`/`release-check.sh`
  刷新盖章，这是保护不是故障。**已知盲区**：指纹匹配但内容被旧 sstate 污染
  （KB-26），deep 扫描是 #119。
- **参考**：#114；`scripts/deploy-guard.sh` 头注

### KB-28 · 归档纪律：删旧再渲、一档一指纹
- **规范**：报告按「日期-指纹」命名，一次渲染对应一次真构建；重渲前删旧档；
  归档里的 commit/fingerprint 是**当时**的值，不回填。
- **参考**：`docs/qa/boot-baseline.md` 头注；#85

### KB-29 · bats 的用例输出不进 CI console
- **规范**：CI bats 走 JUnit formatter，失败细节在 XML（workflow artifact）里；
  排障从 artifact 的 `<failure>` 取断言位置，用 fixture 在本地复现。
  测试要诊断输出时打印到 fd3 或主动 echo。
- **参考**：`scripts/report.sh` 注释；CI 排障记录（#114 连带）

### KB-30 · CI runner 磁盘水位是间歇性红的来源
- **现象**：与提交无关，doctor/dry-run/preflight 类用例（全部走
  `check_disk_watermark`）间歇集体红。
- **根因**：GitHub runner 根盘基线 ~70%，job 内拉镜像后间歇越过 85% 阈值；
  runner 磁盘规格本身不一致（runner-images #14492）。
- **规范**：CI 的 bats 两个 job 已设 `WATERMARK_PCT=95`；本地无此问题
  （构建机 69%）。新增 CI job 用到容器/disk 检查时同步设置。
- **参考**：actions/runner-images#14492；ci.yml 同名 env

---

## G. 流程与合规

### KB-31 · 一切对外发布走「issue → PR → squash 合并 → tag/Release」
- **规范**：main 有 branch-guard，只认 PR 合并；squash 为主（历史惯例）；
  合并后 tag 用 annotated（zeek.zhao 签名身份）、Release 页引用 docs/qa 归档；
  关里程碑是发版动作的一部分。
- **参考**：`docs/branching.md`；`docs/plan/milestones.md` 收口动作；v1.0.0 实录

### KB-32 · 合规产物链是 CRA 的地基
- **现状**：SPDX 2.2（3.1–5.0）/ 3.0.1（6.0）、cve-check / sbom-cve-check、
  FOSS 扫描、THIRD_PARTY_NOTICES。
- **规范**：发布前必跑合规采集并归档；CRA 第 14 条（2026-09 生效）与
  2027-12 全面执行的差距（VEX、shipping-accurate SBOM 校验）在 backlog 管理。
- **参考**：`docs/compliance.md`；EC CRA 页面（见参考清单）

---

## 参考清单（外部）

| 类别 | 链接 |
|---|---|
| 上游发布与节奏 | [Yocto Releases wiki](https://wiki.yoctoproject.org/wiki/Releases) · [yoctoproject.org/development/releases](https://www.yoctoproject.org/development/releases) · [endoflife.date/yocto](https://endoflife.date/yocto) |
| wrynose 6.0 LTS | [发布公告（2026-05-13）](https://www.yoctoproject.org/blog/2026/05/13/yocto-project-6-0-wrynose-is-here) |
| dm-verity | 内核文档 `Documentation/device-mapper/dm-verity.rst`；[meta-security dm-verity-img.bbclass](https://git.yoctoproject.org/meta-security/plain/classes/dm-verity-img.bbclass) |
| cryptsetup/veritysetup | [meta-oe recipes-crypto](https://git.openembedded.org/meta-openembedded/plain/meta-oe/recipes-crypto/cryptsetup/)（oe-core/meta-security 均不带） |
| U-Boot QFW bootmeth | [v2024.01 qemu-x86_64_defconfig](https://raw.githubusercontent.com/u-boot/u-boot/v2024.01/configs/qemu-x86_64_defconfig)（无 BOOTMETH_QFW）vs v2026.01 |
| EU CRA | [欧委会 CRA 页面](https://digital-strategy.ec.europa.eu/en/policies/cyber-resilience-act) · [Finite State SBOM 指南](https://finitestate.io/blog/eu-cra-sbom-technical-documentation-guide) · [Cybeats CRA 要求](https://www.cybeats.com/eu-cra-sbom-requirements) |
| GitHub runner | [runner-images #14492（磁盘不一致）](https://github.com/actions/runner-images/issues/14492) · [Ubuntu2404-Readme](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md) · [清盘策略](https://www.geraldonit.com/mastering-disk-space-on-github-actions-runners-a-deep-dive-into-cleanup-strategies-for-x64-and-arm64-runners) |
| 内部关联 | `docs/syntax-matrix.md`（四版语法）· `docs/handover.md`（结论索引）· `docs/qa/`（全部归档）· 各 issue 正文 |
