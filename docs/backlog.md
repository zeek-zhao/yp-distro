# 待办清单（backlog）

> 按「先做哪件」排序，优先级只是建议。做完一项就把本页对应行勾掉并挪进
> 「已完成」；新想法先进 [issues](https://github.com/zeek-zhao/yp-distro/issues)
> 再落到这里。最后更新：2026-11-04

## P0 · 收口（不依赖任何前置，只差人工动作）

| 事项 | 说明 | 依赖 |
|---|---|---|
| [ ] 合并 PR #113 | v0.5/v0.6/v0.7 出口条件 + v1.0.0 回归归档 + 14 个 issue 自动关闭。CI 全绿 | 人工确认 |
| [ ] 打 tag `v1.0.0` + 建 Release | 合并后在 `main` 上打 annotated tag（`zeek.zhao <zeek.zhao@foxmail.com>`），Release 页引用 `docs/qa/20261104-*` 归档；关四个里程碑 | 合并 |
| [ ] #107 GitHub Support 工单 | 英文措辞草稿已在 issue 回帖；需仓库所有者账号提交 | 人工 |

## P1 · 活发行版的例行义务（有明确时间窗）

| 事项 | 说明 | 时间窗 |
|---|---|---|
| [ ] wrynose/scarthgap 点版本跟进 | 流程见 [`docs/point-releases.md`](point-releases.md)：bump TAG → `release-check.sh` → 归档提交 | **2026-12-07** 上游点版本发布后 |
| [ ] CVE 扫描例行化 | `scripts/cve-db.sh` 目前手工触发；点版本流程跑的时候顺带跑并归档结论 | 与上一条合并执行 |

## P2 · 安全深化（CRA 驱动，方向已验证）

| 事项 | 说明 | 前置 |
|---|---|---|
| [ ] #116 dm-verity 生产化评估 | spike 已证可行；评估两条集成路线的成本：自建 `cryptsetup-native` vs 引入 `meta-security`（`dm-verity-img.bbclass` 官方路线，要评估四版兼容成本） | 无 |
| [ ] 只读根的可写目录方案 | dm-verity 根是只读的：/var 等 overlay 到独立分区/tmpfs；与 #74「维持 ext4」的取舍要重新权衡（安全场景 vs 可写场景可并存为两种镜像形态） | dm-verity 集成 |
| [ ] 签名链设计 | root hash 走 cmdline 明文防盘上篡改、不防整镜像替换。设计题：ARM 走 FIT+U-Boot 校验 / x86 QEMU 走 UEFI SB（OVMF）——与现有 QFW 链的关系要先画图 | 签名方案讨论 |
| [ ] guard 内容级扫描 | #114 已知盲区：指纹匹配但 deploy 内容被旧 sstate 污染（#109 型）。可选门禁：rpm 元数据逐包扫 0700（约 3 分钟/组合），挂进 release-check 的 `--deep` 开关 | 无 |

## P3 · 测试面与矩阵扩展

| 事项 | 说明 |
|---|---|
| [ ] qemuarm64 常态化抽查 | `release-check.sh --machine qemuarm64`（#27 验证过的 scarthgap/wrynose × general）；建议每个点版本窗口顺带跑一次 |
| [ ] ptest 运行时测试 | 上游 runtime testing 的主路径；挑 3–5 个关键包（busybox/python3/openssl）先接，产出进回归报告 |
| [ ] boot 基线扩到 base/full 的 systemd-analyze | minimal/base 串口 root 无空密码（`empty-root-password` 只开 full），两层采不到 analyze；若需要完整三段，给 base 开 `empty-root-password` 并更新 degraded.txt |

## 已完成（2026-11 本轮，供对照）

- [x] #109 dunfell do_rootfs 冲突（sstate 污染，cleansstate 解决）
- [x] #110 boot-time 测量链修复（set -e 静默打断）
- [x] #72–#75 启动优化 + 三版移植（boot-baseline §6–§10）
- [x] #73 ttyS1 mask 三版落地
- [x] #78 服务数×耗时（均摊 134ms/unit）
- [x] #80–#84 v0.7.0 5.0 对齐与四版语法闭合
- [x] #85 四版全量回归归档（两轮刷新，最终 `20261104-ad7c52d*`）
- [x] #114 deploy 指纹门禁（release-check 全程把关）
- [x] #115 点版本跟进流程（release-check.sh + 文档 + 首跑）
- [x] #116 dm-verity 可行性验证（起机 + 篡改检出证据）
