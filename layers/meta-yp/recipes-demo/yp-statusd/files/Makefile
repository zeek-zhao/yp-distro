CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra

yp-statusd: statusd.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $<

.PHONY: clean
clean:
	rm -f yp-statusd
