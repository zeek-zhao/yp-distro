# 任务卡 P1-05b：修正 Sstate hit 的字段语义（我的任务卡定义错了）

## 背景

P1-05 里我要求 `Sstate hit` 输出 `Current/Wanted (match%)`，这是**错的**。

bitbake 的 `Sstate summary` 真实语义（以 wrynose 真构建日志为例）：

```
Sstate summary: Wanted 209 Local 184 Mirrors 0 Missed 25 Current 2095 (88% match, 98% complete)
```

- `Wanted 209` = 本轮构建需要的 sstate 对象数
- `Local 184` = **本地缓存命中的数量**
- `Missed 25` = 未命中、需要重新构建的数量
- `Current 2095` = **sstate 缓存目录里现存对象总数**（不是命中数！）
- `88% match` = `Local / Wanted` = 184/209

所以按现写法会输出 `2095/209 (88%)` —— 分子是缓存总数，比值 1001%，语义荒谬。正确应输出 `184/209 (88%)`。

数据源是真实存在的：`work/logs/build-wrynose-general-resume.log` 里就有这一行（未经整理的旧命名，稍后我会按约定改名）。

## 要改的

### 1. `scripts/report.sh`

`Sstate hit` 的解析改成抓 `Local` 与 `Wanted`，输出 `Local/Wanted (match%)`。

当前（错误）实现：

```bash
sstate_value="$(sed -nE 's/.*Sstate summary: Wanted ([0-9]+) Local [0-9]+ Mirrors [0-9]+ Missed [0-9]+ Current ([0-9]+) \(([0-9]+)% match,.*/\2\/\1 (\3%)/p' "${build_log}" | tail -n 1)"
```

要求改成输出 `<Local>/<Wanted> (<match>%)`，例如 `184/209 (88%)`。

请在改动处加一行注释，写明 `Current` 是缓存总数、不能当命中数用（避免以后有人又改回去）。

### 2. `tests/bats/07_cache.bats`

用例 `report.sh renders latest build metrics and n/a without adding degraded items` 里构造的样例是：

```
Sstate summary: Wanted 50 Local 20 Mirrors 0 Missed 30 Current 40 (40% match, 0 missed)
```

断言要从 `Sstate hit: 40/50 (40%)` 改成 `Sstate hit: 20/50 (40%)`。

**并且**这个样例要特意保留 `Current(40) != Local(20)` 的特征 —— 这样如果有人再退回用 Current，用例就会红。请在该样例上方加注释说明这个设计意图。

### 3. `docs/03-build/kas.md`（P1-05 里新增的那 37 行）

若里面描述了 `Sstate hit` 的口径，同步改成 `本地命中 / 需要数`；没提到就不用改。

## 明确不要做

- 不要动 `scripts/build.sh`
- 不要动 `kas/base.yml`
- 不要改 `config/features.txt`、`config/degraded.txt`
- 不要跑 `report.sh` 的完整模式（会递归跑 BATS），验收只用 `--render-only`

## 验收（容器内，全部 rc=0）

```bash
cd /home/jenkins/workspace/yocto

bash scripts/dev.sh shfmt -d -i 4 -ci scripts/ tests/
bash scripts/dev.sh shellcheck -S warning scripts/*.sh scripts/lib/*.sh
bash scripts/dev.sh bats -r tests/bats/            # 仍须 102 ok，0 not ok，0 skip
bash scripts/dev.sh bats --filter-tags cache tests/bats/
```

额外自查（人工确认，写进你的总结）：

```bash
# 用真实日志验证口径
printf 'Sstate summary: Wanted 209 Local 184 Mirrors 0 Missed 25 Current 2095 (88%% match, 98%% complete)\n' \
  > work/logs/build-wrynose-general.log
bash scripts/dev.sh bash scripts/report.sh --release wrynose --variant general --render-only
grep 'Sstate hit' docs/qa/wrynose/*-render.md     # 必须是 184/209 (88%)
rm -f docs/qa/wrynose/*-render.md work/logs/build-wrynose-general.log
```

**渲染产生的 `*-render.md` 与临时日志必须删掉**，`git status` 要只剩你该改的文件。注意 `docs/qa/wrynose/artifacts.sha256` 是已归档存证，**不要改**（`git checkout --` 可恢复）。

## 提交

- 当前分支 `feat/P1-05-cache`（已切好，继续在上面提交）
- 提交信息注明 `Refs #23`
- 不要 push / 开 PR
