include cpp-hello.inc
PROVIDES += "virtual/cpp-hello"
# RPROVIDES 不能用 virtual/ 前缀（6.0 QA virtual-slash）；
# IMAGE_INSTALL 的 "virtual/cpp-hello" 由 build 期 PROVIDES 解析。