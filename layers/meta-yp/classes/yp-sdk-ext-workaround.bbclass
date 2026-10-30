# dunfell (3.1) 的 oe.copy_buildsystem.copy_bitbake_and_layers() 只对两类层
# 算得出正确目标：COREBASE 树内的层，以及 COREBASE 的兄弟目录。本工程的
# layers/meta-yp 在构建树外四层：
#
#   <repo>/layers/meta-yp                    ← 层
#   <work>/kas-<release>-custom/poky         ← COREBASE
#
# 于是 relpath(layer, corebase) 得到 ../../../../layers/meta-yp，被拼成
#   poky/../../../../layers/meta-yp
# 写进 eSDK 的 conf/bblayers.conf 后，生成 filtered task list 时 bitbake 直接
#   ERROR: The following layer directories do not exist
# do_populate_sdk_ext 失败（SDK 本体是好的，只有 eSDK 挂）。
#
# 4.0 起这个函数被 write_sdk_bblayers() 重写、按层位置分三态处理，不再有这个
# 限制 —— 所以只有 dunfell 需要这个 workaround。判据用实现源码的特征串，比按
# 版本号猜更可靠（4.0+ 三份源码里这个串都是 0 命中）。
#
# 做法：在 COREBASE 旁边建一个指向真实层的软链，并**只对本任务**把 BBLAYERS
# 换成软链路径。这样 relpath(layer, corebase) 就是 `../meta-yp`，命中上游本来
# 支持的那个分支，eSDK 里得到
#   ${SDKBASEMETAPATH}/layers/poky/meta-yp     （文件也真被复制到那个位置）
# 真实构建用的 BBLAYERS 不动，其它任务不受影响。

python yp_sdk_ext_layer_relink() {
    import os

    corebase = os.path.abspath(d.getVar('COREBASE') or '')
    if not corebase or not os.path.isdir(corebase):
        return

    # 只在有该缺陷的实现上动手。
    impl = os.path.join(corebase, 'meta', 'lib', 'oe', 'copy_buildsystem.py')
    try:
        with open(impl, 'r') as f:
            if 'os.path.basename(corebase) + ' not in f.read():
                return
    except OSError:
        return

    layers = (d.getVar('BBLAYERS') or '').split()
    relinked = []
    changed = False
    for layer in layers:
        ap = os.path.abspath(layer)
        inside = ap == corebase or ap.startswith(corebase + os.sep)
        if not os.path.isdir(ap) or inside:
            relinked.append(layer)
            continue

        link = os.path.join(os.path.dirname(corebase), os.path.basename(ap))
        if os.path.abspath(link) == ap:
            relinked.append(layer)
            continue

        if os.path.islink(link):
            os.unlink(link)
        elif os.path.exists(link):
            # 同名真实目录占位：不动它，保持原行为并在日志里说清。
            bb.warn('yp-sdk-ext: %s 已存在且不是软链，%s 的 eSDK 仍然会失败'
                    % (link, ap))
            relinked.append(layer)
            continue

        os.symlink(ap, link)
        bb.note('yp-sdk-ext: %s -> %s（仅本任务的 BBLAYERS）' % (link, ap))
        relinked.append(link)
        changed = True

    if changed:
        d.setVar('BBLAYERS', ' '.join(relinked))
}

do_populate_sdk_ext[prefuncs] += "yp_sdk_ext_layer_relink"
