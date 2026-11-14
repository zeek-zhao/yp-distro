# P0-02 BATS 骨架 + 报告机制 + 覆盖元测试

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `P0-02` |
| 里程碑 | `v0.1.0` |
| 依赖 | `P0-01`（已完成，提交 `2d313dc`） |
| 预计改动文件 | `tests/bats/setup.bash`、`tests/bats/00_project.bats`、`tests/bats/99_coverage.bats`、`scripts/report.sh`、`config/features.txt`、`project.sh`、`Makefile`、`.gitignore` |

## 背景

需求 §6（BATS 组织）、§6.1（features.txt 粒度）、§6.2（报告三层）、§6.3（门禁规则）、§6.4（变更驱动新鲜度）。

本任务建立**测试与报告的骨架**，让 `project.sh test` / `project.sh report` 从占位变成可用。
真实构建类测试（`02_source` / `03_build` / `04_qemu`）**不在本任务范围**，它们要等 `source.sh` / `build.sh` 存在。

**本任务必须修正 P0-01 遗留的错误**：`config/features.txt` 现有的第 4 列是「阶段」（`P0`），需求 §6.1 要求的是 **bats tag**。

## 关键约定（照抄，不要自己去翻文档）

**features.txt 格式（需求 §6.1，四列，`|` 分隔，`#` 开头为注释）**

```
# feature_id | 适用 release | bats 文件 | bats tag
entry-unified | all | tests/bats/00_project.bats | entry
```

- 第 2 列：`all` 或逗号分隔的 release 名（`dunfell,kirkstone`）
- 第 4 列：bats tag 标识符，与 `.bats` 文件里的 `# bats test_tags=<tag>` 对应

**报告三层（需求 §6.2）**

1. 机器可读：`reports/bats-<release>-<variant>-<date>.xml`（junit）
2. 人可读：终端汇总表（版本、用例数、通过、失败、跳过、耗时）
3. 归档：`docs/qa/<release>/<date>-<sha>.md`

**源码指纹（需求 §6.4）**

```
git rev-parse HEAD:config HEAD:docker HEAD:scripts HEAD:layers
```
四者拼接后再算一次 SHA-256（`git rev-parse` 输出逐行，取每行短 SHA 拼字符串，再 `sha256sum`），记作 `SOURCE_FINGERPRINT`。
`docker/` 与 `layers/` 在 P0 阶段可能存在但为空，脚本必须容忍 `git rev-parse` 对不存在路径报错（用 `|| true` 并跳过该段）。

**skip 白名单（需求 §6.3）**
只允许三类，且必须写明原因：需要 Docker、需要构建产物、需要构建机。
白名单外的 skip 一律视为失败。`setup.bash` 提供三个 helper（见下），不允许在用例里手写裸 `skip`。

## 要做的事

### 1. `tests/bats/setup.bash`

- `ROOT_DIR` 由脚本自身位置推导（`BASH_SOURCE` 所在目录向上两级），**不依赖调用者 cwd**
- 加载 `scripts/lib/log.sh` 与 `scripts/lib/common.sh`（复用 P0-01 的 `load_release` / `resolve_all`）
- `project()`：包装 `"${ROOT_DIR}/project.sh"`，便于 `run project config --release dunfell`
- 三个 skip helper，**只在条件不满足时 skip，并输出固定格式的原因**：
  - `require_docker` → `skip "需要 Docker：docker daemon 不可达"`
  - `require_build_artifact <path>` → 文件不存在时 `skip "需要构建产物：<path> 缺失"`
  - `require_build_host` → 主机名与 `YP_BUILD_HOST` 不符时 `skip "需要构建机：…"`
- `bats_version_info()`：打印 bats 版本与 ROOT_DIR（调试用）

### 2. `tests/bats/00_project.bats`

全部用例加 `# bats test_tags=entry`（每个 `@test` 上方一行）。至少覆盖：

| # | 用例 | 断言要点 |
|---|---|---|
| 1 | 四份 release 配置可加载且 tag 正确 | 逐行比对四个 `RELEASE REPO_MODE TAG` 三元组 |
| 2 | `project.sh --help` 退出码 0 且列出全部子命令 | 输出含 `config` / `doctor` / `test` / `report` |
| 3 | `project.sh config --release wrynose --variant custom --machine qemux86-64` | 输出含 `DISTRO=zeek-distro`、`IMAGE=core-image-zeek`、`REPO_MODE=split` |
| 4 | **负例**：`project.sh config --release bogus` 非 0 退出 | `$status -ne 0` 且 stderr 非空 |
| 5 | `project.sh doctor` 输出 8 个组合 | 匹配 `^(dunfell|kirkstone|scarthgap|wrynose) ` 的行数 = 8 |
| 6 | **负例**：未实现子命令 `project.sh build` 退出码 2 | `$status -eq 2` |
| 7 | `config/*.env` 里没有 `export` | 所有 `config/**/*.env` 中 `^export` 计数为 0 |

### 3. `tests/bats/99_coverage.bats`

**不加 `test_tags`**（它是元测试，不是能力用例）。四个校验：

1. **文件存在**：`features.txt` 每行第 3 列指向的文件必须存在；
2. **tag 有对应用例**：该文件里必须出现 `# bats test_tags=.*<tag>`（tag 来自第 4 列），否则失败并指出缺哪个 tag；
3. **反向无遗漏**：`tests/bats/*.bats` 中除 `99_coverage.bats` 外，每个文件至少被 `features.txt` 引用一次，否则失败（防止加了测试却没登记能力）；
4. **格式合法**：每行必须正好 4 个 `|` 分隔字段（注释行与空行跳过），第 2 列只能是 `all` 或已知 release 名。

失败信息必须包含**行号与原文**，便于定位。

### 4. `scripts/report.sh`

- 用法：`scripts/report.sh <release|all> [--variant V]`
- **另须支持 `scripts/report.sh --print-fingerprint`**：只打印 `SOURCE_FINGERPRINT` 一行后退出 0（不跑测试、不写文件）。这是验收与 CI 检查指纹的入口，必须实现。
- 行为：
  1. 跑 `bats --formatter junit --output reports/` 生成 junit（文件名 `bats-<release>-<variant>-<YYYYmmdd>.xml`）
  2. 终端打印汇总表（`TAP` 之外的统计从 bats 输出解析，或直接统计 junit 里的 `tests/failures/skipped` 属性）
  3. 写 `docs/qa/<release>/<date>-<sha>.md`，含：release / variant / commit / tag / **SOURCE_FINGERPRINT** / 执行机 hostname / 起止时间 / 用例数（通过/失败/跳过）/ 失败清单。
     镜像 digest 与产物 SHA-256 在 P0 阶段**没有**，字段写 `n/a（P0 未实现）`，不要留空、不要编造。
- 任一步失败即非 0 退出。

### 5. `project.sh` 接上 `test` 与 `report`（替换占位 `exit 2`）

- `project.sh test [--release R] [--variant V]`：容器内跑 `bats tests/bats/`，透传 `-r` 目录，退出码即 bats 退出码
- `project.sh report [--release R] [--variant V]`：转调 `scripts/report.sh`
- 其余子命令（`image` / `source` / `build` / `qemu` / `review` / `e2e`）**保持占位 `exit 2` 不动**

### 6. `Makefile` 增 `test` / `report` target，`.gitignore` 增 `reports/`（若尚未包含）

### 7. `config/features.txt` 重写

按新四列格式，**只列当前真正有测试覆盖的能力**（P0-02 之后只有 `entry-unified` 一项是真实覆盖的）：

```
# feature_id | 适用 release | bats 文件 | bats tag
entry-unified | all | tests/bats/00_project.bats | entry
```

> 不要为了「看起来完整」把 `02_source` / `01_dockerfile` / `ci-l1-l2` 等写进去——那些测试文件还不存在，`99_coverage.bats` 会直接失败。**未实现的能力不进 features.txt，随实现它的任务卡一起加。**

## 不要做的事

- **不要创建** `02_source.bats` / `03_build.bats` / `04_qemu.bats` / `05_review.bats` / `06_variant.bats` / `07_sdk.bats` / `08_compliance.bats` / `01_dockerfile.bats` / `01_docker_image.bats` —— 它们依赖尚未存在的 `source.sh` / `build.sh` / `docker/`
- **不要写** `scripts/source.sh` / `build.sh` / `container.sh`
- **不要改** `config/*.env`、`config/variants/`、`config/machines/`、`scripts/lib/`、`scripts/dev.sh`、`scripts/wf3.sh`、`docs/08-tasks/`、`meta-zeek/`
- **不要引入新的测试框架**（不用 pytest / shunit2 / 自研 runner），只用已装的 bats 1.14
- **不要在用例里手写裸 `skip`**，只能用 `setup.bash` 的三个 helper
- 不要 `git commit`

## 验收标准

全部在 dev 容器内可执行（`scripts/dev.sh` 已支持容器内直通）：

```bash
# 1. 静态检查零告警
bash scripts/dev.sh shellcheck -S warning tests/bats/setup.bash scripts/report.sh project.sh
bash scripts/dev.sh shfmt -d -i 4 -ci tests/bats/ scripts/report.sh project.sh

# 2. 全部用例通过，且一条不 skip
bash scripts/dev.sh bats tests/bats/
# 期望：00_project.bats 7 个用例全 pass，99_coverage.bats 4 个用例全 pass
# 期望：输出不含 "skipped"

# 3. junit 报告生成
bash scripts/dev.sh ./project.sh test --release wrynose --variant general
ls reports/bats-wrynose-general-*.xml
# 期望：文件存在，且能 grep 到 <testsuite
# 注意：必须写 ./project.sh，不能写裸 project.sh —— dev.sh 容器内直通是 exec "$@"，
#       裸命令不在 PATH 会报 `exec: "project.sh": executable file not found in $PATH`

# 4. 归档报告生成
bash scripts/dev.sh ./project.sh report --release wrynose --variant general
ls docs/qa/wrynose/*.md
# 期望：存在，且含 SOURCE_FINGERPRINT / commit / 用例统计 三段

# 5. 指纹随源码变化（负向验证）
F1=$(bash scripts/dev.sh bash scripts/report.sh --print-fingerprint)
echo "# fingerprint probe" >> config/scarthgap.env
F2=$(bash scripts/dev.sh bash scripts/report.sh --print-fingerprint)
git checkout -- config/scarthgap.env
F3=$(bash scripts/dev.sh bash scripts/report.sh --print-fingerprint)
echo "F1=$F1"; echo "F2=$F2"; echo "F3=$F3"
# 期望：F1 != F2，且 F1 == F3（改回原样后指纹复原），三者均为 64 位十六进制

# 6. 元测试真的会拦（负向验证，两条）
# 6a. 删掉 features.txt 的一行 → 99_coverage 必须失败
cp config/features.txt /tmp/features.bak
sed -i '/entry-unified/d' config/features.txt
bash scripts/dev.sh bats tests/bats/99_coverage.bats; echo "exit=$?"
cp /tmp/features.bak config/features.txt
# 期望：exit 非 0
# 6b. 去掉 00_project.bats 里的 test_tags → 99_coverage 必须失败
cp tests/bats/00_project.bats /tmp/p.bak
sed -i '/test_tags=entry/d' tests/bats/00_project.bats
bash scripts/dev.sh bats tests/bats/99_coverage.bats; echo "exit=$?"
cp /tmp/p.bak tests/bats/00_project.bats
# 期望：exit 非 0

# 7. 还原后全绿（证明 6 的破坏已复原）
bash scripts/dev.sh bats tests/bats/ && git status --short
# 期望：全 pass；git status 只含本任务声明的文件
```

- [ ] 上述 7 组命令全部符合期望
- [ ] `git status --short` 只出现「预计改动文件」里的文件
- [ ] `grep -c '^skip\|[[:space:]]skip ' tests/bats/*.bats` 为 0（用例里没有裸 skip）

## 参考

- 参考工程 `D:\zeek\work\repo\project\poky\tests\bats\setup.bash`（`_detect_poky_root` 的 ROOT_DIR 推导写法、`require_qemu_ssh` 这类 skip helper 的风格）
- 参考工程 `D:\zeek\work\repo\project\poky\tests\bats\00_regression.bats`（用例组织方式）
- 需求 `40-项目/YP/Yocto-多版本工程需求.md` §6 全节
