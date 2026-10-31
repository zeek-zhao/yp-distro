# #56 四版切 systemd + 裁剪 DISTRO_FEATURES

## 元信息

| 项 | 值 |
|---|---|
| 任务 ID | `56-systemd-and-distro-features` |
| 里程碑 | `v0.3.0` |
| 分支 | `feat/56-systemd`（从 `dev` 切出） |
| 关联 Issue | #56 |
| 依赖 | 无（这是 v0.3.0 第一张卡） |
| 预计改动文件 | `layers/meta-yp/conf/distro/yp.conf`、`layers/meta-yp/conf/distro/include/yp-common.inc`、`docs/distro-features.md`（新建）、`tests/bats/12_distro.bats`（新建） |

---

## 背景

`layers/meta-yp/conf/distro/yp.conf` 第一行是 `require conf/distro/poky.conf`，`yp-compat.inc` 里写明「保留 poky 的 `DISTRO_FEATURES` / `IMAGE_FEATURES` 基线与 `INIT_MANAGER` 不动」。所以四版实际都跑 **sysvinit**。

但需求 §4.2 的 variant 矩阵 `init` 一行写的是 **systemd** —— 当前实现从未符合过需求。本卡补齐，并且把 `DISTRO_FEATURES` 里 QEMU 用不上的特性裁掉。

**必须分两阶段做**：阶段 A 切 systemd（往 features 里**加** `systemd`/`usrmerge`），阶段 B 裁特性（往里**删** `x11`/`wayland`）。合并成一步会互相污染，出错时无法定位是哪一半的问题。

---

## 阶段 A：四版切 systemd

### A1 已知事实（不要重新调研，直接用）

四版都有 `INIT_MANAGER` 机制，定义在 `meta/conf/distro/defaultsetup.conf`：

```bitbake
INIT_MANAGER ??= "none"
require conf/distro/include/init-manager-${INIT_MANAGER}.inc
```

四份 `init-manager-systemd.inc` 内容**不同**（已逐版确认）：

| 版本 | append 语法 | `usrmerge` | `BACKFILL_CONSIDERED` | `initscripts` | `dev_manager` | `ROOT_HOME` |
|---|---|---|---|---|---|---|
| 3.1 dunfell | `_append` | **不加** | `_append = " sysvinit"` | `systemd-compat-units` | **未设** | **未设** |
| 4.0 kirkstone | `:append` | **不加** | `:append = " sysvinit"` | `systemd-compat-units` | `systemd` | **未设** |
| 5.0 scarthgap | `:append` | 加 | `:append = " sysvinit"` | `systemd-compat-units` | `systemd` | `/root` |
| 6.0 wrynose | `:append` | 加 | **整行已删除** | **空串 `""`** | `systemd` | `/root` |

本卡已定的两个取舍，**不要再改**：

1. **不强行给 3.1/4.0 加 `usrmerge`**。3.1 上 `usrmerge` 要配合 `CONVERSION_CMD` 与大量 QA 调整，成本远高于收益，它只影响 `/bin` 是实体还是软链。差异写进 `docs/syntax-matrix.md`（若该文件不存在则新建）。
2. **3.1 的 `VIRTUAL-RUNTIME_dev_manager` 空缺失不预先补**，先实测 `systemd-udevd` 有没有起来，再决定补不补。

### A2 改动

`layers/meta-yp/conf/distro/yp.conf`，**在现有第一行 `require conf/distro/poky.conf` 之前**插入：

```bitbake
# ---- init 系统：四版统一 systemd（需求 §4.2）----
# 必须在 require poky.conf 之前：defaultsetup.conf 里的 `INIT_MANAGER ??= "none"`
# 会在 require 时立即消费并 require 对应的 init-manager-*.inc。
# 写在之后不会报错，但完全无效 —— 镜像里 init 仍是 busybox，
# 而 bitbake -e 看起来「INIT_MANAGER=systemd」，属于静默失败。
INIT_MANAGER = "systemd"

require conf/distro/poky.conf
```

**不要**用 `DISTRO_FEATURES:append = " systemd"` 替代：那只是把字符串塞进 features，不会设 `VIRTUAL-RUNTIME_init_manager`，结果同上。

### A3 阶段 A 验收（必须全绿）

```bash
# A-1 四版 INIT_MANAGER 都解析为 systemd（解析期即可）
for r in dunfell kirkstone scarthgap wrynose; do
  printf '%-12s ' "$r"
  ( cd work/kas-$r-custom && kas shell -c "bitbake -e yp-image" 2>/dev/null \
    | grep -E '^INIT_MANAGER=' | head -1 )
done
# 期望：四行都是 INIT_MANAGER="systemd"

# A-2 init provider 指向 systemd
cd work/kas-wrynose-custom && kas shell -c "bitbake -e yp-image" \
  | grep -E '^VIRTUAL-RUNTIME_init_manager='
# 期望：VIRTUAL-RUNTIME_init_manager="systemd"

# A-3 真构建 + 真起机（-n 不算），确认镜像里真的是 systemd
bash scripts/build.sh --release wrynose --variant custom
bash scripts/qemu.sh --release wrynose --variant custom --detach
# 串口日志里必须有 systemd 的 "Reached target" 行
grep -c 'Reached target' work/artifacts/wrynose/custom/qemu-serial.log
```

- [ ] A-1 四版全为 `INIT_MANAGER="systemd"`
- [ ] A-2 `VIRTUAL-RUNTIME_init_manager="systemd"`
- [ ] A-3 wrynose 真起机，`grep -c 'Reached target'` ≥ 1
- [ ] 3.1 也真起机一次，`ps | grep -c systemd-udevd` 的结论写进 `docs/distro-features.md`

---

## 阶段 B：裁 DISTRO_FEATURES

### B1 先 dump 实际值

```bash
cd work/kas-wrynose-custom
kas shell -c "bitbake -e yp-image" | grep -E '^DISTRO_FEATURES=' | fold -w 120
```

### B2 产出 `docs/distro-features.md`

三列表格：`feature | 决定（留/删/待定） | 理由`。

理由必须具体到「删了谁会省掉什么」（例如「`x11` 会拉入 libx11/libxcb/xauth 与 xserver 相关脚本，QEMU 无图形需求」），**不接受「用不上」四个字**。除表格外，另加一节记录 A1 表格里的四版 inc 差异。

### B3 落地删除项

写进 `layers/meta-yp/conf/distro/include/yp-common.inc`。**两种分隔符各写一行**（3.1 只认 `_`，4.0+ 只认 `:`）：

```bitbake
DISTRO_FEATURES:remove = "x11 wayland opengl 3g bluetooth nfs zeroconf"
DISTRO_FEATURES_remove = "x11 wayland opengl 3g bluetooth nfs zeroconf"
```

**禁止**直接 `DISTRO_FEATURES = "..."` 重写：那会把 poky 与 machine 追加的条目一起抹掉，包括刚加进去的 `systemd`。

### B4 保留项确认

切到 systemd 后 **`sysvinit` 不再是保留项**（它的位置由 `DISTRO_FEATURES_BACKFILL_CONSIDERED` 接管，3.1~5.0 有、6.0 已删该变量）。真正必须保留：`ipv4` `ipv6` `pci` `usbhost` `rtc` `ext2` `systemd`。

`ldconfig` 不要随手删（有 recipe 依赖 `ld.so.conf`）；`ipv6` 单列评估（影响 busybox 网络工具与 `network` 脚本分支）。

### B5 新增 `tests/bats/12_distro.bats`

**双向断言**：
1. 删除项确实不在 `DISTRO_FEATURES` 里
2. `systemd` 在
3. `sysvinit` **不在**
4. `yp.conf` 里 `INIT_MANAGER = "systemd"` 出现在 `require conf/distro/poky.conf` **之前**（用 awk 比较行号，防止有人把顺序改回去）
5. `yp-common.inc` 里 `remove` 两种分隔符都在

BATS 写法参照 `tests/bats/04_layer.bats` 与 `setup.bash` 的既有约定，不要自创 helper。

### B6 阶段 B 验收

```bash
# B-1 删除项确实不在
cd work/kas-wrynose-custom && kas shell -c "bitbake -e yp-image" \
  | grep '^DISTRO_FEATURES=' | grep -qwE 'x11|wayland|opengl|3g|bluetooth|nfs|zeroconf' \
  && echo "FAIL: 仍有残留" || echo "PASS"

# B-2 systemd 在、sysvinit 不在
cd work/kas-wrynose-custom && kas shell -c "bitbake -e yp-image" \
  | grep '^DISTRO_FEATURES=' > /tmp/df.txt
grep -qw systemd /tmp/df.txt  && echo "PASS systemd 在"
grep -qw sysvinit /tmp/df.txt && echo "FAIL sysvinit 仍在" || echo "PASS sysvinit 已移除"

# B-3 BATS
bash scripts/dev.sh bash -lc 'cd /work && bats -r tests/bats/12_distro.bats'

# B-4 镜像仍能起机
bash scripts/build.sh --release wrynose --variant custom

# B-5 全量 L1 不能因为本卡变红
bash scripts/dev.sh scripts/report.sh --release wrynose --variant custom
```

- [ ] B-1 PASS
- [ ] B-2 `systemd` 在、`sysvinit` 不在
- [ ] `bats -r tests/bats/12_distro.bats` 全过
- [ ] `docs/distro-features.md` 每条都有具体理由
- [ ] 文档写「删」的项在 `yp-common.inc` 里确实删了（不一致算未完成）
- [ ] `report.sh` 不因此出现新的失败项

---

## 执行边界（先读这一节）

你在容器内执行，**没有 docker socket**（`scripts/build.sh` 会被嵌套 docker guard 拒绝），也没有 HOSTTOOLS。所以：

**你负责的（必须做完）**

1. 改 `layers/meta-yp/conf/distro/yp.conf` 与 `include/yp-common.inc`
2. 新建 `docs/distro-features.md`、`docs/syntax-matrix.md`（若不存在）、`tests/bats/12_distro.bats`
3. 解析级验证：A-1 / A-2 / B-1 / B-2（`kas shell -c "bitbake -e ..."` 在容器内可跑）
4. BATS：`bats -r tests/bats/12_distro.bats`
5. 全量 L1：`bash scripts/report.sh --release wrynose --variant custom`（只读 `work/`，不构建）

**不要尝试的（会被拦，纯浪费时间）**

- `scripts/build.sh` / `scripts/qemu.sh` 任何形态 —— 真构建与起机属 L3，由人在宿主触发
- `docker` 任何命令

**遇到需要真构建的验收项**（A-3、B-4，以及 A3 里 3.1 的 `systemd-udevd` 实测）：**不要跳过，也不要假装通过**。在回复末尾单列一节：

```
## 待人工验证（L3）
- A-3 wrynose 真起机 + grep 'Reached target'
- A-3 3.1 起机 + ps | grep -c systemd-udevd
- B-4 改完 features 后镜像仍能起机
```

然后继续把其余部分做完。**解析级全绿 + 文档齐 + BATS 过**，本卡在你这侧就算完成。

---

## 不要做的事

- **不要改 `work/` 下的 poky / openembedded-core**：那是 kas 检出的上游仓库，下次 `kas build` 会被覆盖，且污染 `SOURCE_FINGERPRINT`。所有改动只落 `layers/meta-yp/`、`tests/bats/`、`docs/`。
- **不要动 `INIT_MANAGER` 之外的东西**：不改 `IMAGE_FEATURES`、不改 `ROOT_HOME`、不引入外部 `meta-systemd` 之类层。
- **不要改 `config/features.txt`**：这是能力矩阵，由报告链路管，本卡只影响 `DISTRO_FEATURES`。
- **不要顺手统一四版的 append 语法**：`_append`/`:append` 的差异是 3.1 的硬限制，不是笔误。
- **不要在阶段 A 未全绿时开始阶段 B**：两个阶段的验收指标相反，混做会得出错误结论。

## 参考

- `work/kas-dunfell-custom/poky/meta/conf/distro/defaultsetup.conf` 第 26-27 行（`INIT_MANAGER ??= "none"` 与 require）
- 四版 `init-manager-systemd.inc`（6.0 在 `work/kas-wrynose-custom/openembedded-core/meta/...`，其余在 `work/kas-<rel>-custom/poky/meta/...`）
- `layers/meta-yp/conf/distro/include/yp-compat.inc`（既有分隔符约定，含已知使用点清单）
- 需求 §4.2（`init = systemd` 的原始出处）
- `P3-产品化路线图.md` D4 / D6b / D15
