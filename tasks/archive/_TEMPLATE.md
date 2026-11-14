# 任务卡模板

> 复制为 `tasks/<TASK-ID>.md`（如 `tasks/P0-02-bats-skeleton.md`）后填写。
> 任务卡是 WF3 的唯一输入：容器内的 Copilot CLI 读它干活，WorkBuddy 按它的
> 「验收标准」判定通过与否。**验收标准必须是可执行命令**，不能是主观描述。

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `<P0-02>` |
| 里程碑 | `v0.1.0` / `v0.2.0` / `v1.0.0` |
| 分支 | `feat/<TASK-ID>-<slug>`（从 `dev` 切出，见 `docs/branching.md`） |
| 关联 Issue | `#<n>` |
| 依赖 | 无 / `P0-01` 必须先完成 |
| 预计改动文件 | 列出明确路径，避免 AI 到处乱改 |

## 背景

一两句话说清"为什么做这个"。引用需求章节号（如"需求 §6.2"），不要复述整段需求。

## 要做的事

1. 具体到文件与函数，例如"新增 `tests/bats/02_source.bats`，含 3 个用例：…"
2. …

## 不要做的事

- 明确边界，例如"不要改 `docker/<release>/Dockerfile`"、"不要引入新依赖"。
- AI 最容易越界的地方要写死。

## 验收标准

每条都要能跑：

```bash
bash scripts/dev.sh shfmt -d -i 4 -ci scripts/
bash scripts/dev.sh shellcheck -S warning scripts/*.sh
bash scripts/dev.sh bats tests/bats/
```

- [ ] 上述命令全部退出码 0
- [ ] `git status` 只包含本任务声明的文件
- [ ] …

## 参考

指向仓库内或本地参考工程的具体文件，例如
`D:\zeek\work\repo\project\poky\tests\bats\setup.bash`（参考工程的 BATS 骨架）。
