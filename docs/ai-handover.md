# AI 协作交接文档

> 给 AI 协作者（agent / coding assistant）的作业手册：本仓库欢迎 AI 参与产出，
> 但**提交责任与署名只能是人类**（CONTRIBUTING.md）。本文写的是 AI 视角的
> 环境事实、禁区、验证方法与决策边界。人类视角的交接见
> [`handover.md`](handover.md)；待办见 [`backlog.md`](backlog.md)。
>
> 最后更新：2026-11-04

## 一、你是谁、能做什么

| 项 | 边界 |
|---|---|
| 可以做 | 写码/文档/测试、跑构建与回归（本机构建机）、起机取证、查 issue 与回帖结论、开 issue、切分支提交并 push |
| 需要人类确认 | **合并 PR**、**打 tag / 建 Release**、**关里程碑**、**提交 #107 的 GitHub Support 工单**——这些是署名与对外动作，见 §三 |
| 禁止 | 见 §二 |

## 二、硬性禁区（违反 = CI 拒或留下永久痕迹）

1. **提交署名**：每条 commit 必须 `Signed-off-by: zeek.zhao <zeek.zhao@foxmail.com>`
   （DCO），author/committer 与之一致；**不得**出现
   `Co-authored-by: Copilot/Claude/…`、`Generated with …`、`🤖`——
   本地钩子 + CI `identity-guard` + GitHub ruleset 三层都会拒。
2. **不手改生成文件**：`docs/issues.md`（`scripts/plan-sync.sh` 生成，改了 CI
   plan-sync 会红）、`docs/tokens.html` 与 `metrics/token-usage.tsv`（`wf3 tokens`
   副产物，提交前 `git checkout --` 还原）。
3. **不手工 `docker run` 跑 bitbake**：必须经 `scripts/container.sh`——它挂
   `/etc/passwd` **和** `/etc/group`，漏一个就是 `sstatesig` KeyError 被伪装成
   host contamination（#109 踩过）。qemu 取证同理由 `qemu.sh`/`boot-exec.sh`/
   `boot-time.sh` 进容器。
4. **不动 git 历史**：不 force push；改历史前先 `git bundle create --all` 备份。
5. **不提交凭据**：CI `secret-scan` 扫全部 tracked 文件；构建镜像与产物对外可见。
6. **回归前工作区必须干净**：脏树让 `SOURCE_FINGERPRINT` 不可复现，归档指纹失真。

## 三、需要人类拍板的事（AI 只准备材料）

| 事项 | AI 能做到哪一步 |
|---|---|
| 合并 PR（`main` 有 branch-guard，只认 PR 合并） | push 分支 + 保证 CI 全绿 + PR 描述完整 |
| 打 annotated tag `v1.0.0`、建 Release、关里程碑 | 按 `docs/plan/milestones.md`「收口动作」写好步骤清单 |
| #107 提交 GitHub Support 工单 | 英文措辞草稿已在 issue 回帖（2026-11-03） |
| 方向取舍（新里程碑、是否引入 meta-security 等新 layer） | 在 issue 里写方案 + 成本 + 三选一建议 |

## 四、环境事实（写死在机器上的，别再探索一遍）

- **构建机**：共享 Jenkins 节点，32 核，`work/` 在 3.7T 卷上；构建必须串行；
  低磁盘水位 `container.sh` 会阻断（`project.sh doctor` 可查）。
- **容器**：开发容器 `yocto-dev:local`（bats/shellcheck 等工具链）；
  每版构建容器 `ghcr.io/zeek-zhao/yp-distro/<release>:latest`（公开镜像）。
  `scripts/dev.sh` 在容器内会自动降级为本地执行（嵌套安全）。
- **KVM**：容器透传 `/dev/kvm`，boot-time 默认 KVM 口径；TCG 数字不可比。
- **版本钉扎**：`config/<release>.env` 的 `POKY_TAG`（poky 单仓）或
  `OE_CORE/BITBAKE/META_YOCTO_TAG`（wrynose 三仓拆分，`REPO_MODE=split`）。
- **宿主侧脚本**：`build.sh`/`qemu.sh`/`report.sh`/`boot-time.sh`/
  `release-check.sh`/`deploy-guard.sh` 在宿主跑（内部自己进容器）；
  `kas shell` 类一次性命令经 `project.sh shell` 进容器。

## 五、改完代码怎么验证（按层递进）

```bash
bash scripts/dev.sh bash scripts/ci/lint.sh          # L1：shellcheck/shfmt/hadolint/actionlint
bash scripts/dev.sh bash -lc 'cd /work && bats -r tests/bats'   # L1：全量 BATS（206 项，0 skip）
bash scripts/build.sh --release <r> --variant <v>    # L2：真构建（sstate 热时分钟级）
bash scripts/qemu.sh --release <r> --variant <v>     # L3：起机抓串口
bash scripts/release-check.sh                        # 全量回归（发版/点版本用）
bash scripts/deploy-guard.sh --all                   # 产物新鲜度（commit 后必跑）
```

CI 检查集 = lint + secret-scan + identity-guard + plan-sync + bats + 四版
release-matrix + branch-guard。**push 前先本地跑 L1**；CI 红过的两个已知坑：
`docs/issues.md` 过期（建/关 issue 后重跑 `scripts/plan-sync.sh`）与 shfmt
格式（写完跑 `shfmt -w`）。

## 六、高频坑速查（全部真实踩过，细节在引用处）

| 症状 | 原因 | 处置 |
|---|---|---|
| do_rootfs 目录属性冲突 | deploy 里新旧 rpm 混存（内容级污染） | 查 rpm 元数据确认；`cleansstate <pn>` 清除；指纹门禁拦不住这类（见 #114 边界） |
| commit 后 guard 全红 | 指纹含 scripts/config，提交即变 | 重跑 `build.sh`/`release-check.sh` 刷新盖章 |
| 起机进的不是预期镜像 | experiment overlay 残留 `qb_default_fstype/bios` | 查 qemuboot.conf；不留 overlay 产物在 deploy |
| 内核裁剪不生效 | KERNEL_FEATURES 的 scc 后合并覆盖 fragment | bbappend 里同步 `.replace` 摘 scc（#72） |
| dm 表 EINVAL / 设备建不出 | salt 必需 / 长度单位是 512 扇区 / hash_start=1 | 照抄 `docs/qa/security/dm-verity-feasibility.md` 的表 |
| 3.1 上配置静默失效 | 变量级冒号 override 3.1 不认 | python `__anonymous` 门控补下划线版（任务级冒号两版都认） |

## 七、当前在途状态（2026-11-04）

- **PR #113**（`fix/boot-time-marks-and-dunfell-rootfs` 分支）：29+ commit，
  CI ALL-GREEN，关闭 16 个 issue（含 #115/#116），**等人类合并**。
- 合并后动作：`backlog.md` P0——tag `v1.0.0`、Release、关里程碑。
- 开放 issue 仅剩 #107（工单草稿在帖）。
