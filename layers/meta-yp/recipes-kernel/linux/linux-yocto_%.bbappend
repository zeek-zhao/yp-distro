# 6.0 内核裁剪 fragment（#72）——只在 wrynose 生效，其余版本内核一个字节都不动。
#
# FILESEXTRAPATHS 顶层的冒号版在 4.0+ 生效、3.1 静默丢弃：这只是把搜索路径加上，
# 没引用就不会有副作用；真正把 fragment 挂进 SRC_URI 的动作在下面的 python 门控里 ——
# 顶层直接写 SRC_URI:append 会同时命中 kirkstone/scarthgap，超出本实验的范围。
#
# 关键坑（首版 G1 白测一次的原因）：KERNEL_FEATURES 里的 scc 在 SRC_URI fragment
# **之后**合并，debug-kernel.scc 会把 fragment 关掉的 DEBUG_INFO 重新打开 —— 实测
# .config 里 DEBUG_INFO 回到 =y。所以每组裁剪必须在这里同步摘掉对应的
# KERNEL_FEATURES 条目（与 yp-minimal.cfg 的分组注释一一对应）：
#   G1 调试设施  ←→ features/debug/debug-kernel.scc
#   G2 文件系统  ←→ features/nfsd/nfsd-enable.scc
#   G3 设备      ←→ cfg/sound.scc
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-yocto:"

python __anonymous() {
    if "wrynose" not in (d.getVar("LAYERSERIES_CORENAMES") or "").split():
        return
    d.appendVar("SRC_URI", " file://yp-minimal.cfg")
    # 压缩算法实验（#72 第 4 组）：bzImage 的 lz4/zstd 压缩用的是**宿主**命令，
    # 构建容器里没有，缺了会在 do_compile 的 LZ4 步骤报 `lz4: not found`。
    d.appendVar("DEPENDS", " lz4-native zstd-native")
    d.setVar("KERNEL_FEATURES", (d.getVar("KERNEL_FEATURES") or "")
             .replace("features/debug/debug-kernel.scc", "")
             .replace("features/nfsd/nfsd-enable.scc", "")
             .replace("cfg/sound.scc", ""))
}
