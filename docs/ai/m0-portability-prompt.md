# yp-distro 换机可交付性改造 · AI 提示词

> 版本 v1.0 · 2026-11-25
> 适用分支：`feat-m0-kas-bootstrap`（HEAD `8530465`）
> 用途：把"换一台新机器能稳定跑完 M0"从口头知识变成仓库里的可交付能力，交给外部 AI 编码代理执行。

## 三条必须先知道的事实

- **归档是两层结构**：全量 tar 的顶层是 `downloads.tar` 与 `sstate.tar`，不是 `downloads/`、`sstate/`；恢复必须外层解一次、内层再各解一次。
- **校验对象是重组后的 tar**：`cache-full.sha256` 里的 `1c8126d4…` 对应 11,153,397,760 B 的重组 tar，不是单个分片。
- **provenance 必须静态**：`gate.sh` 的 G2 会把 `gen-meta.sh` 输出与 `docker/cache-meta.json` 逐字比对，任何时间戳都会让门禁变红。

## 使用方法

1. 把下面代码块整段复制给 AI，不要删减；它是自包含的，AI 只需要仓库访问权。
2. 要求它按 T1→T7 逐项做、每项提交后停下等你确认，避免一次性大改。
3. 它交付后，你在新机器上按 `docs/runbook-new-machine.md` 从零跑一遍，作为最终验收。

## 提示词全文（整段复制）

```text
仓库 https://github.com/zeek-zhao/yp-distro，分支 feat-m0-kas-bootstrap（HEAD 8530465）。
先读 AGENTS.md、docs/ai/m0-prompt.md、docs/m0/plan.md、docs/m0/acceptance.md、docs/m0/traceability.md、docs/m0/changes/CHG-012.md、docs/m0/issues/ISS-019.md、ISS-020.md、scripts/cache/*.sh、scripts/bootstrap.sh、scripts/preflight.sh。

背景：M0 已收口（判据 1-8 全通过，gate/publish 绿）。现在的目标不是继续做 M0，而是把“换一台新机器能稳定跑完 M0”变成可交付能力。当前缺口已核实如下，全部要修：
1) README 状态表过期（S1/S2/S4/S5/S8/S9 还写“待开始”），三步上手写的是宿主机 kas build（宿主机没有 kas），镜像地址还是 <owner> 占位。
2) 没有换机 runbook：磁盘/内存/网络要求、11 GiB 全量缓存怎么取、8 个 release 分片怎么重组校验、怎么解包到两个卷，全都没有。
3) UID 硬编码：bootstrap 无条件 chown 到 1000，preflight 用当前用户判可写；新机用户 UID≠1000 时流程自锁（chown 需 sudo，chown 完自己反而不可写）。
4) 缓存无 provenance：cache-meta.json 只有布局和阈值，没有 edition/machine/kas commit/生成时间；note 还写着 “Baseline layout only”（已过期）。
5) 全量分片清单不持久：release 只有 8 个 cache-full.part-NN + cache-full.sha256，没有 slice manifest；GHCR 全量分片消费所需的 manifest 只在 CI artifact（会过期）。CHG-012 承诺的 yp-cache:wrynose-m0-full 镜像实际不存在。
6) split.sh 无每片大小断言，ISS-019 这类问题只能在 merge 阶段才暴露。

重要事实（不要重新推断，按这个实现）：
- pack.sh 产出的外层 tar 顶层是两个内层归档：downloads.tar 与 sstate.tar，不是 downloads/、sstate/。恢复必须两步解包：外层解出两个内层 tar，再各自 -C <父目录> 解出 downloads/、sstate/。
- release m0-s5-payload-full：资产 cache-full.part-00..07（每个 1572864000 B，最后一个 143339520 B），加 cache-full.sha256（内容格式为 <sha256>  cache-full.tar，哈希 1c8126d4b1c57d5dc5a4f772617cd74dacbeab475d79e8ce2ee49bbcea1be624，对应重组后的 tar 11,153,397,760 B）。
- 全量切片：2 片，8,589,934,592 + 2,563,463,168 B；GHCR tag wrynose-m0-full-part-00/01，digest 分别为 sha256:f1404012... 与 sha256:899af6fa...，匿名可拉。
- builder 镜像 ghcr.io/zeek-zhao/yp-builder:wrynose-m0 匿名可拉，kas 5.5，用户 jenkins/1000。
- scripts/gate.sh 的 G2 会把 gen-meta.sh 输出与 docker/cache-meta.json 逐字比对。因此 provenance 不能用时间戳动态生成，必须放静态文件再由 gen-meta 合并，否则门禁必红。

按 T1→T7 顺序做，一次一件事，每件先文档后代码，涉及契约变更先出 CHG，做完提交并停下等我确认。

T1 README 与 runbook（文档）
1.1 重写 README：状态表与 docs/m0/plan.md 完全一致（全部完成/验收 Final）；三步上手改为容器内执行：
    docker pull ghcr.io/zeek-zhao/yp-builder:wrynose-m0
    bash scripts/bootstrap.sh --downloads ./downloads --sstate ./sstate
    docker run --rm -v "$PWD/downloads:/work/downloads" -v "$PWD/sstate:/work/sstate" ghcr.io/zeek-zhao/yp-builder:wrynose-m0 kas build kas/yp.yml:editions/prod.yml
    写明需要先取缓存（指向 runbook），不要再出现 <owner> 占位。
1.2 新增 docs/runbook-new-machine.md，必须包含：
    a) 机器要求表：Ubuntu 24.04、Docker >=24、CPU/内存建议（>=8 核 / >=16 GB，32 GB 推荐）、磁盘预算（缓存 11.15 GB + tar 11.15 GB + 分片 11.15 GB + build tmp，建议 >=200 GB 空闲）、出网需求（ghcr.io、git.openembedded.org、git.yoctoproject.org、api.github.com）。
    b) 从零到构建成功的完整命令序列，每条带期望输出：clone → verify-env.sh → 拉镜像 → bootstrap → fetch-cache.sh（release 模式）→ preflight → 容器内 kas build → 产物核对（file/ls -lh）→ 二次构建命中率检查（grep "from sstate" cooker log）。
    c) 缓存恢复的两步解包说明（外层 tar 含 downloads.tar/sstate.tar），并给出 tar -tf 预期输出。
    d) 磁盘/内存不足、UID 不一致、GHCR 拉取 401、sstate 命中率低 四类故障的判定与处理。
    e) 明确写出“首次构建预期时长”（引用 RV-005：ci 7096s、prod 10253s）与“第二次预期 200-300s 量级”，避免误以为卡死。
1.3 新增 docs/m0/reviews/RV-013.md 记录本轮交付物与验证边界（编号先查是否占用）。

T2 scripts/verify-env.sh（只读检查，不改任何东西）
参数：--downloads <dir> --sstate <dir> [--min-disk-gb 200] [--skip-network]
检查项与退出码：
  0 全通过；1 致命（docker 不可用/磁盘不足/网络不通/镜像不可拉）；2 警告（内存 <16 GB、UID≠1000 需重建镜像）
必须检查并逐项打印 PASS/WARN/FAIL：docker version 与 daemon 可用、磁盘空闲、物理内存、CPU 核数、当前 uid/gid、editions 符号链接存在且指向 kas/editions、threshold.conf 存在、匿名拉取 builder 镜像（registry token + tags list，失败即 FAIL）、目标目录所在卷空间、网络可达（curl -I 到三个域名，超时 10s）。
禁止 chown、禁止创建目录、禁止拉镜像（只做 registry API 探测，不 docker pull 11 GB 的东西）。

T3 scripts/cache/fetch-cache.sh（核心）
两种模式，必须都实现：
  --mode release：按 manifest 从 GitHub release 下载 cache-full.part-NN 与 cache-full.sha256，逐片校验大小与拼接顺序，cat 重组为 tar，用 sha256 文件校验（期望 1c8126d4...），然后两步解包到 --downloads 与 --sstate 的父目录。
  --mode ghcr：docker pull wrynose-m0-full-part-NN，docker cp 取出分片，用 --manifest <path> 指定的 manifest 调用现成 merge.sh 校验合并（缺片/哈希不符必须 exit 1），再解包。
参数：--dest-parent <dir>（其下生成 downloads/ 与 sstate/）、--work <dir>（下载/重组临时区）、--release-tag、--parts、--force、--keep。
硬性要求：
  a) 幂等：目标目录非空且无 --force 时拒绝覆盖并打印提示；
  b) 校验失败必须 exit 1，且不允许部分解包后留下半成品（先解到临时目录，校验通过再 mv）；
  c) 不把 token 写进脚本；公开仓库用匿名下载；如需要鉴权，只读环境变量 GH_TOKEN；
  d) 支持 --dry-run：只打印将要下载的资产 URL、大小、校验期望值，不实际下载（供无网/小磁盘环境自测）。
自测要求：用样本 release m0-s5-payload-sample（18 MB，sha256 ca3063ab1d164b4c7556896507912a5a23bd4ccab341b924d57615704028cf1d）跑通下载→校验→两步解包→目录结构断言；不要在本机下载 11 GB 全量包，全量路径标 UNVERIFIED 并说明原因。

T4 UID 参数化
4.1 bootstrap.sh / preflight.sh 增加 --uid <n>、--gid <n>，默认取当前用户 id -u/id -g；保留 JENKINS_UID/JENKINS_GID 作为镜像默认与文档默认（当前用户为 1000 时行为与 M0 验收命令完全一致）。
4.2 当目标 UID 与当前 UID 不一致时，脚本必须明确报错并给出两条路径：用 sudo 执行，或 docker build --build-arg JENKINS_UID=$(id -u) --build-arg JENKINS_GID=$(id -g) -t yp-builder:local docker/ 后设置 YP_BUILDER_IMAGE=yp-builder:local；禁止静默 chown 到不可写状态。
4.3 preflight 增加一项检查：目录属主 == 目标 UID 且当前用户可写；两者不一致时给出具体修复命令（exit 2）。
4.4 更新 runbook 的 UID 章节与 bootstrap 的 usage 文本。

T5 provenance 与清单持久化
5.1 新增静态文件 docker/cache-provenance.json（提交入库，不由时间戳生成），字段至少：edition=ci、machine=qemux86-64、distro=yp-wrynose、distro_version、kas repo commits（4 个 SHA，从 kas/base.yml 抄）、payload_sha256=1c8126d4...、payload_bytes=11153397760、file_counts（downloads/sstate 各多少）、created_at（固定字符串，取生成日）、source="S5 full build"。
5.2 gen-meta.sh 读取该静态文件并合并进输出（缺文件则报错），保持输出确定性（同样输入逐字相同），确保 gate.sh G2 仍能通过。
5.3 修正 cache-meta 里过期的 note（"Baseline layout only" 改为"真实 S5 载荷；分片分发见 ADR-005/CHG-012/CHG-013"）。
5.4 slice manifest 持久化：提供 scripts/cache/publish-manifest.sh（或在 runbook 中给命令），把 manifest.json 作为 release 资产 cache-full.manifest.json 上传到 m0-s5-payload-full；若当前无可用凭据，脚本必须能 --dry-run 并明确提示需要 GH_TOKEN，不得伪造成功。

T6 split.sh 加每片大小断言
每片 dd 之后立即断言 stat -c %s == min(MAX, total - idx*MAX)，不符则打印期望/实际并 exit 1；保持阈值只来自 threshold.conf；用 20 MiB + YP_SPLIT_MAX_BYTES=4194304 回归，断言 5 片且末片 1048576 B。

T7 CHG-012 收口（契约修正）
全量镜像 yp-cache:wrynose-m0-full 实际未产出（GHCR 只有 full-part-00/01）。二选一，并在 CHG-013 中记录理由：
  方案 A（推荐，省 11 GB 存储）：改为“全量数据以 release 归档 + 两片 GHCR 分片分发，不发布单一大镜像”，同步修改 CHG-012 的契约描述与 acceptance 措辞；
  方案 B：补发布该镜像（需 >=11 GB 临时空间与推送时间），发布后补 digest 证据。
无论选哪个，都要保证 CHG-012/acceptance/runbook 三处对“全量数据如何分发”的描述一致。

全局红线
- 只用 zeek.zhao <zeek.zhao@foxmail.com> 提交，禁止 AI 署名 trailer；仓库内不得出现任何 token。
- 没真实执行的命令不许写“通过”；跑不了的写 UNVERIFIED + 缺哪条命令、缺什么环境。
- 阈值只在 scripts/cache/threshold.conf；不得为测试方便调小阈值后忘了改回。
- 不修改 M0 已 Final 的判据结论；新增证据以 RV-013/CHG-013 追加，不改写历史 RV/ISS。
- 不引入缓存服务器、不 root 构建、不新增外部依赖（除 bash/python3/docker/curl 外）。
- 非预期现象先开 ISS-021 起，贴证据才关单。

完成判据（四条同时满足）
1) 本地 bash scripts/gate.sh = GATE_PASS 且 bash scripts/check-vars.sh = VARS_OK（新增脚本后仍绿）；
2) fetch-cache.sh --mode release --dry-run 与样本 release 全链路实跑通过（贴输出）；
3) verify-env.sh 在本机跑出可解释的 FAIL/WARN（本机无 docker 属预期，贴输出），不出现脚本崩溃；
4) runbook 从“只有 Docker 的新机器”视角逐步可执行，每条命令有期望输出；无法在本机验证的（11 GB 全量恢复、真实构建、新机 UID 场景）明确标 UNVERIFIED 并写清验证方法。

每个 T 结束回报六项：改动文件、执行命令（含失败）、已验证项（贴输出行）、未验证项及原因、新增记录编号、下一步建议。
```

## 交付后你要做的三件事

1. 在没有历史缓存的新机器上，按 runbook 从 clone 跑到出镜像，记录每步实际耗时。
2. 核对两处硬指标：`fetch-cache` 重组后的 tar sha256 是否为 `1c8126d4…`；二次构建的 `from sstate` 命中行数与 RV-005 的 99% 是否同量级。
3. 若新机 UID 不是 1000，专门走一次"重建镜像 + `--uid/--gid`"路径，确认不再出现"chown 完自己不可写"。
