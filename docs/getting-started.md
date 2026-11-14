# 新手上手指南

> 从零到第一次跑通完整回归的路径。读完本页（约 15 分钟）+ 动手跑完四个阶段
> （约半天，多数时间在等构建），你就能独立在这个工程上干活。
>
> 术语：release = Yocto 版本（dunfell 3.1 … wrynose 6.0）；
> variant = `general`（贴近上游默认）/ `custom`（独立 distro `yp` + 自有镜像）。
>
> **现行保障范围只有 wrynose 6.0**（单一事实源 `config/supported-releases.txt`）；
> 下文部分示例沿用 scarthgap 参数写法，把 `--release` 换成 `wrynose` 即可。

## 0. 前置条件

- Linux 主机（构建机基准 Ubuntu 24.04）+ **Docker**（构建全部在容器里）
- `work/` 所在盘 ≥ 80 GB（共享 Jenkins 节点的话确认磁盘水位）
- git 身份：`user.name`/`user.email` 与你要署名的身份一致（DCO 要求）
- 对 Yocto 的最低要求：知道 bitbake 是什么即可，其余本仓库已封装

## 1. 十分钟体验（不构建，只验环境）

```bash
git clone git@github.com:zeek-zhao/yp-distro.git && cd yp-distro
./project.sh hooks            # 启用提交钩子（commit-msg 校验）
bash scripts/dev.sh --build   # 构建开发容器 yocto-dev:local（一次性，约 10 分钟）
bash scripts/dev.sh bash scripts/ci/lint.sh    # L1 四段 lint
bash scripts/dev.sh bash -lc 'cd /work && bats -r tests/bats'   # 全量 BATS（206 项）
./project.sh doctor           # 8 个 release×variant 组合解析 + 磁盘水位
./project.sh config wrynose   # 看某个 release 的生效配置
```

全绿说明环境就绪。这一步不需要网络大流量，也不碰 Yocto 上游。

## 2. 第一次真构建（约 30–60 分钟，sstate 热时更短）

```bash
bash scripts/build.sh --release scarthgap --variant custom     # 最小镜像
bash scripts/qemu.sh --release scarthgap --variant custom      # headless 起机，抓串口日志
bash scripts/report.sh scarthgap --variant custom              # 全量 bats + 渲染归档
```

产物与证据：
- 镜像：`work/kas-scarthgap-custom/build/tmp/deploy/images/qemux86-64/`
- 串口日志：`work/artifacts/scarthgap/custom/qemu-serial.log`
- 归档报告：`docs/qa/wrynose/`（自动按「日期-指纹」命名）

**看什么**：报告末尾的 BATS 表（应 0 失败 0 跳过）+ 串口段是否命中 `login:`。

## 3. 日常开发循环

1. 先在 GitHub 开 issue（缺陷/功能都先开）
2. `git checkout -b fix/<ID>-<slug>`（从 main 切）
3. 改代码 → `bash scripts/dev.sh bash scripts/ci/lint.sh` → 跑相关 bats
4. `git commit -s`（Conventional Commits + DCO；**禁 AI 署名**，钩子会拒）
5. push + 开 PR（目标 main）→ CI 全绿 → 人工合并

改了 `layers/`、`config/`、`scripts/` 之后 commit，构建产物会因指纹变化被
`deploy-guard` 判 stale——这是正常保护，重跑 `build.sh`/`release-check.sh` 刷新即可。

## 4. 常用入口速查

| 想做什么 | 命令 |
|---|---|
| 全量回归（发版/点版本） | `bash scripts/release-check.sh` |
| 起机三段测量 | `bash scripts/boot-time.sh --release wrynose --variant custom --image minimal --runs 3` |
| 构建产物新鲜度 | `bash scripts/deploy-guard.sh --all` |
| 某次 kas 一次性命令 | `./project.sh shell --release wrynose --variant custom -- bash -c '...'` |
| 换实验开关（rootfs 格式等） | kas build 时叠加 `kas/features/*.yml`，见各文件头注释 |

## 5. 必读的三份文档（按顺序）

1. [`docs/point-releases.md`](point-releases.md) —— 点版本跟进流程（这是本仓库的
   「例行公事」；TAG 钉三处，漏一处会被门禁拦）
2. [`docs/handover.md`](handover.md) —— 已验证结论与排查方法论（别重复烧时间）
3. [`docs/knowledge-base.md`](knowledge-base.md) —— 工程规范（KB-01~32）：
   踩坑的规范条款都在这里，写代码前扫一遍 A/C/F 三组
4. [`docs/ai-handover.md`](ai-handover.md) —— 若你用 AI 协作，这是硬性禁区与
   验证手册；没有 AI 也值得一读（坑速查表是共用的）

## 6. 新手最容易踩的三个坑

1. **commit 后 guard 全红** —— 指纹含 scripts/config，提交即变，重跑构建刷新，
   不是坏了
2. **起机进的不是预期镜像** —— experiment overlay（`kas/features/*.yml`）构建后
   会残留 `qemuboot.conf` 字段；跑完实验把对应镜像重新默认构建一次
3. **报告里 205/206** —— 先看是不是 `05_kas` 的漂移测试或 `07_cache` 的降级
   断言：这两处跟着活文件走，红往往是「真实变化被测试预期过时」而非代码坏了

## 7. 更多深入

- 启动优化全部数据与结论：`docs/boot-optimization.md` + `docs/qa/boot-baseline.md`
- 安全基线（dm-verity）：`docs/qa/security/`
- 合规（SBOM/CVE/FOSS）：`docs/compliance.md`
- 四版语法差异：`docs/syntax-matrix.md`
