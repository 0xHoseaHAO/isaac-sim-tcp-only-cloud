CC ?= gcc
CFLAGS ?= -shared -fPIC
LDFLAGS ?= -ldl

libnvenc_fix.so: nvenc_fix.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

.PHONY: clean
clean:
	rm -f libnvenc_fix.so
