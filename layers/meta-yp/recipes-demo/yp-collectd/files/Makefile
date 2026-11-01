CC ?= cc
CFLAGS ?= -O2
LDFLAGS ?=

.PHONY: all clean

all: yp-collectd

yp-collectd: collectd.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

clean:
	rm -f yp-collectd
