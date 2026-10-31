# 只为 3.1（dunfell）的 create-spdx 回移版本补许可证文本。
#
# 现象：dunfell 3.1.33 的 create-spdx-2.2.bbclass 不会把 `GPLv2+` 归一成
# `GPL-2.0-or-later`，而是直接拿 `GPL-2+` 去 COMMON_LICENSE_DIR 找文件：
#
#   ERROR: strace-5.5-r0 do_create_spdx: Cannot find any text for license GPL-2+
#
# 而 common-licenses 里只有 `GPL-2.0`，没有 `GPL-2+`，于是 do_create_spdx 直接
# 失败，镜像级 SBOM 也就没有。4.0+ 的类会归一，不受影响。
#
# 做法：在 do_create_spdx 之前，按本 recipe 的 LICENSE 里带 `+` 的 id 生成别名
# 文件（`GPL-2+` → 复制 `GPL-2.0` 的正文），并把目录挂到 LICENSE_PATH ——
# create-spdx-2.2 依次搜 COMMON_LICENSE_DIR 与 LICENSE_PATH（源码见
# meta/classes/create-spdx-2.2.bbclass 的 get_license_text）。
#
# 为什么不用 NO_GENERIC_LICENSE：那要逐 recipe 手写文件名，232 处 `+` 许可证
# 写法覆盖不过来；这里对任意 `<base>+` 都能落到某个已存在的基础许可证上。
#
# 只影响 SBOM 的许可证正文，不改 LICENSE 取值，也不改打包结果。

YP_LEGACY_LICENSE_DIR ??= "${TOPDIR}/yp-legacy-licenses"

# 目录必须在解析期就存在：dunfell 的 license.bbclass 会用 os.listdir 遍历
# LICENSE_PATH 求 AVAILABLE_LICENSES，目录不存在直接
# `Unable to parse Var <AVAILABLE_LICENSES[:=]>`（实测踩过一次）。
# 用 `:=` 的立即展开在这里执行一次 makedirs，比匿名函数更早。
YP_LEGACY_LICENSE_INIT := "${@os.makedirs(d.getVar('YP_LEGACY_LICENSE_DIR'), exist_ok=True) or ''}"

LICENSE_PATH += "${YP_LEGACY_LICENSE_DIR}"

python yp_alias_spdx_licenses() {
    import os
    import re
    import shutil

    common = d.getVar("COMMON_LICENSE_DIR")
    dest = d.getVar("YP_LEGACY_LICENSE_DIR")
    license = d.getVar("LICENSE") or ""
    if not common or not dest:
        return

    os.makedirs(dest, exist_ok=True)
    # LICENSE 里的运算符是 & | ( )，其余才是 id
    for token in re.split(r"[&|()]", license):
        token = token.strip()
        if not token.endswith("+"):
            continue
        base = token[:-1]
        for candidate in (base, base + ".0", base + "-only"):
            source = os.path.join(common, candidate)
            if not os.path.exists(source):
                continue
            target = os.path.join(dest, token)
            if not os.path.exists(target):
                shutil.copyfile(source, target)
                bb.note("yp-spdx: %s 的许可证正文取自 %s" % (token, candidate))
            break
}

do_create_spdx[prefuncs] += "yp_alias_spdx_licenses"
