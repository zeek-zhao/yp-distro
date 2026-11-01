CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra

# 字符串宏必须在本层加引号，配方只负责传裸值。
# 若在配方的 CFLAGS 里写 -DYP_VERSION=\"0.3.0\"，这个 token 要经过
# recipe → make → sh → gcc 四层，每过多一层就吃掉一层反斜杠：一层不够，
# gcc 收到 -DYP_VERSION=0.3.0（too many decimal points in number）且
# -DYP_BUILD=yp-qemux86-64 被当成表达式；多写几层又会变成 stray '\'。
# 单引号包双引号是唯一不经额外转义的写法。
YP_VERSION ?= 0.1
YP_BUILD ?= unknown
YP_MACHINE ?= unknown
CPPFLAGS += -DYP_VERSION='"$(YP_VERSION)"' \
            -DYP_BUILD='"$(YP_BUILD)"' \
            -DYP_MACHINE='"$(YP_MACHINE)"'

yp-statusd: statusd.c
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LDFLAGS) -o $@ $<

.PHONY: clean
clean:
	rm -f yp-statusd
