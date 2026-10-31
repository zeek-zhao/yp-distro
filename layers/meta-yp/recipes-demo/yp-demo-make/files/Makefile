# 交叉编译变量由 bitbake 经 oe_runmake 传入（CC/CFLAGS/LDFLAGS），
# 不要在 Makefile 里写死 gcc / -O2，否则破坏 DEBUG_BUILD 与 -D_FORTIFY_SOURCE。
TARGET = yp-demo-make
SRC = demo.c

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(SRC) -o $(TARGET) $(LDFLAGS)

clean:
	rm -f $(TARGET)

.PHONY: clean
