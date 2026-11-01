# 交叉编译变量由 bitbake 经 oe_runmake 传入（CC/CFLAGS/LDFLAGS），
# 不要在 Makefile 里写死 gcc / -O2，否则破坏 DEBUG_BUILD 与 -D_FORTIFY_SOURCE。
TARGET = yp-demo-make
SRC = demo.c

# 字符串宏在本层加引号，配方只传裸值（原因见 yp-statusd/files/Makefile）。
YP_DEMO_VARIANT ?= make
CPPFLAGS += -DYP_DEMO_VARIANT='"$(YP_DEMO_VARIANT)"'

$(TARGET): $(SRC)
	$(CC) $(CPPFLAGS) $(CFLAGS) $(SRC) -o $(TARGET) $(LDFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: clean
