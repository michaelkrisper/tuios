CFLAGS ?= -O2 -Wall -Wextra
PREFIX ?= $(HOME)/.local

all: swaybar-status

swaybar-status: src/swaybar-status.c
	$(CC) $(CFLAGS) -o $@ $<

TESTS = test_swaybar_status

test_swaybar_status: tests/test_swaybar_status.c src/swaybar-status.c tests/check.h
	$(CC) $(CFLAGS) -o $@ $<

test: $(TESTS)
	@for t in $(TESTS); do ./$$t || exit 1; done

# swaybar does not restart status_command by itself -- after copying, have it
# restarted via "swaymsg reload".
install: swaybar-status
	install -Dm755 swaybar-status $(PREFIX)/bin/swaybar-status
	-swaymsg reload

clean:
	rm -f swaybar-status $(TESTS)

.PHONY: all test install clean
