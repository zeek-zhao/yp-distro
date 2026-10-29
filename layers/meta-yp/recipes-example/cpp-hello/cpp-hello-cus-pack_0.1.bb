include cpp-hello.inc

# 这里刻意不写 do_compile:append() / do_install:append()：
# 3.1 只认 `_` 分隔符，冒号写法在 3.1 上会被解析成一个没人调用的函数名，静默失效。
# 直接重定义整个任务，四个版本语法完全一致。
do_compile() {
    ${CC} helloworld.c -o helloworld
    ${CC} helloworld.c -o helloworld1
}

CUS_DIR = "/${PN}-cus"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 helloworld ${D}${bindir}

    install -d ${D}${CUS_DIR}${bindir}
    install -m 0755 helloworld1 ${D}${CUS_DIR}${bindir}
}

# 多包拆分：主包保留默认 FILES（覆盖 ${bindir}），额外包单独声明。
PACKAGES =+ "${PN}-cus"

# 同样两种分隔符都写：3.1 读 `_`，4.0+ 读 `:`，未命中的那行是惰性变量。
FILES:${PN}-cus = "${CUS_DIR}${bindir}/helloworld1"
FILES_${PN}-cus = "${CUS_DIR}${bindir}/helloworld1"
SUMMARY:${PN}-cus = "cus program for helloworld"
SUMMARY_${PN}-cus = "cus program for helloworld"

PROVIDES += "virtual/cpp-hello"
# RPROVIDES 不能用 virtual/ 前缀（6.0 QA virtual-slash）；
# IMAGE_INSTALL 的 "virtual/cpp-hello" 由 build 期 PREFERRED_PROVIDER 解析。
