# Python 构建 class 的跨版本兼容层。
#
# 3.1 与 4.0+ 的 Python 打包 class **不同名，也不同后端**：
#
#   dunfell 3.1 : setuptools3               （meta/classes/setuptools3.bbclass）
#                 只认 setup.py，走 `python3 setup.py build`，
#                 没有 PEP 517 / pyproject.toml 支持。
#   kirkstone+  : python_setuptools_build_meta（meta/classes-recipe/...）
#                 走 PEP 517，读 pyproject.toml 的 build-backend。
#
# 判别方式刻意用 **class 文件的实际位置**，不用版本号：backport 版
# （如 3.1 打了 python-setuptools 补丁的发行版）会让版本判断说谎，而
# 「class 文件在不在」是构建期的事实。
#
# 注意 4.0~5.0 的 classes 目录布局是 classes/ + classes-recipe/ 混存，
# 6.0 才统一到 classes-recipe/。所以这里**两个位置都要探**，只探
# classes-recipe/ 会在 kirkstone/scarthgap 上误判成 setuptools3。
YP_PYTHON_BUILD_CLASS = "${@ \
    'python_setuptools_build_meta' if any(os.path.exists(os.path.join(d.getVar('COREBASE'), p)) \
        for p in ('meta/classes-recipe/python_setuptools_build_meta.bbclass', \
                  'meta/classes/python_setuptools_build_meta.bbclass')) \
    else 'setuptools3'}"

inherit ${YP_PYTHON_BUILD_CLASS}
