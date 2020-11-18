#
# Licence: GPL
# Created: 2020-10-23 17:37:20+02:00
# Main authors:
#     - Jérôme Pouiller <jerome.pouiller@silabs.com>
#
CFLAGS += -Wall
PREFIX = /usr/local

all: tunslip6

tunslip6: tunslip6.o tools-utils.o

%.o: %.c
	$(COMPILE.c) -MMD -c -o $@ $<

clean:
	$(RM) *.o *.d

distclean: clean
	$(RM) tunslip6

install:
	install -s -D -m 755 tunslip6 $(DESTDIR)$(PREFIX)/bin

include $(wildcard *.d)
