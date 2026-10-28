include cpp-hello.inc

do_compile:append() {
    ${CC} helloworld.c -o helloworld1
}
# 先定义 PACKAGES
PACKAGES =+ "${PN}-cus"
# CUS_DIR 已经是完整路径
CUS_DIR = "/${PN}-cus"

do_install:append() {
    install -d ${D}${bindir}
    install -m 0755 helloworld ${D}${bindir}
    
    # 创建完整路径
    install -d ${D}${CUS_DIR}${bindir}
    install -m 0755 helloworld1 ${D}${CUS_DIR}${bindir}
}

FILES:${PN} = "${bindir}/helloworld"
FILES:${PN}-cus = "${CUS_DIR}${bindir}/helloworld1"
SUMMARY:${PN}-cus = "cus program for helloworld"

PROVIDES += "virtual/cpp-hello"
# RPROVIDES 不能用 virtual/ 前缀（6.0 QA virtual-slash）；
# IMAGE_INSTALL 的 "virtual/cpp-hello" 由 build 期 PROVIDES 解析。