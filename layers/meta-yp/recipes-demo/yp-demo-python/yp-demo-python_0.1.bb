SUMMARY = "YP Python demo service"
DESCRIPTION = "Minimal Python demo managed by systemd; PEP 517 on 4.0+, setup.py on 3.1."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Python 构建 class 在 3.1 与 4.0+ 不同名（setuptools3 / python_setuptools_build_meta），
# 由 yp-python-build.bbclass 按 class 文件实际位置判别，配方侧不写版本判断。
inherit yp-python-build yp-service

# pyproject.toml（4.0+ 的 PEP 517 后端）与 setup.py（3.1 的 setuptools3）同时提供：
# 两个后端各读各的，互不干扰；少一个就会在对应版本上直接失败。
SRC_URI = "file://pyproject.toml file://setup.py file://yp_demo_py.py file://yp-demo-python.service"
S = "${YP_SRC_DIR}"

# 3.1 只认下划线语法，4.0+ 只认冒号语法。两行都写，未命中的那行是惰性变量
# （与 yp-service.bbclass 处理 SYSTEMD_SERVICE 的手法一致）。
RDEPENDS:${PN} += "python3-core python3-json"
RDEPENDS_${PN} += "python3-core python3-json"

yp_demo_python_install_script() {
	install -d ${D}${bindir}
	install -m 0755 ${S}/yp_demo_py.py ${D}${bindir}/yp-demo-python
}

do_install:append() {
	yp_demo_python_install_script
}

# 「3.1 上还要额外执行的函数名」，由 yp-service.bbclass 统一拼进
