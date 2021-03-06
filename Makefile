# Metadata
METAPATH=$(abspath ./metadata.make)
-include $(METAPATH)
APPDATE=$(shell date -d "$$(stat --printf "%y" $(METAPATH))" "+%d %B %Y")
LONGEST_VALID_PASSPHRASE=1024
WARN_ON_MEMORY_LOCK_ERRORS=1
SETCAP_BINARY=1

# Paths
PREFIX=/usr/local
SRCDIR=$(abspath ./src)
INCDIR=$(abspath ./include)
MANDIR=$(abspath ./man)
SCRIPTDIR=$(abspath ./scripts)
DISTDIR=$(abspath ./dist)
BINPATH=$(DISTDIR)/bin/$(APPNAME)
M4VARSPATH=$(abspath ./variables.m4)

# Source files
SRCS=$(shell find $(SRCDIR) -name '*.c')
HEADERS=$(shell find $(INCDIR) -name '*.h')

# Derived filenames
OBJS=$(SRCS:.c=.o)
PREREQUISITES=$(SRCS:.c=.d)

# Compiler options
ifeq ($(origin CC),default)
CC=clang
endif
WARNINGFLAGS=-Wall -Wshadow -Wwrite-strings -Wmissing-prototypes -Wimplicit-fallthrough -pedantic -fstack-protector-all -fno-strict-aliasing
DEFINEFLAGS=-DAPPNAME=\"$(APPNAME)\" -DAPPVERSION=\"$(APPVERSION)\" -DLONGEST_VALID_PASSPHRASE=$(LONGEST_VALID_PASSPHRASE) -DWARN_ON_MEMORY_LOCK_ERRORS=$(WARN_ON_MEMORY_LOCK_ERRORS)
INCLUDEFLAGS=$(shell pkg-config --cflags libfido2 libcbor libsodium) -iquote $(INCDIR)
LDLIBS=$(shell pkg-config --libs libfido2 libcbor libsodium)

# Derived compiler options
CFLAGS:=$(INCLUDEFLAGS) $(DEFINEFLAGS) $(WARNINGFLAGS) $(CFLAGS)
LDFLAGS:=$(WARNINGFLAGS) $(DEFINEFLAGS) $(LDFLAGS)

# m4 preprocessor options
M4FLAGS=-Dm4_APPNAME="$(APPNAME)" -Dm4_APPVERSION="$(APPVERSION)" -Dm4_APPDATE="$(APPDATE)" -Dm4_LONGEST_VALID_PASSPHRASE=$(LONGEST_VALID_PASSPHRASE) -Dm4_WARN_ON_MEMORY_LOCK_ERRORS=$(WARN_ON_MEMORY_LOCK_ERRORS) --prefix-builtins $(M4VARSPATH)

# Release build targets
.PHONY: all
all: release initcpio bash-completion ssh-askpass

.PHONY: release
release: CFLAGS:=-O3 $(CFLAGS)
release: LDFLAGS:=-O3 -s $(LDFLAGS)
release: $(BINPATH) manpages

.PHONY: install
install: release
	install -g 0 -o 0 -p -m 0755 -D $(DISTDIR)/bin/$(APPNAME) $(DESTDIR)$(PREFIX)/bin/$(APPNAME)
	if [ "$(SETCAP_BINARY)" -ne 0 ]; then setcap cap_ipc_lock+ep $(DESTDIR)$(PREFIX)/bin/$(APPNAME); fi
	install -g 0 -o 0 -p -m 0644 -D $(DISTDIR)/share/man/man1/$(APPNAME).1.gz $(DESTDIR)$(PREFIX)/share/man/man1/$(APPNAME).1.gz
	if [ -f $(DISTDIR)/share/bash-completion/completions/$(APPNAME) ]; then install -g 0 -o 0 -p -m 0644 -D $(DISTDIR)/share/bash-completion/completions/$(APPNAME) $(DESTDIR)$(PREFIX)/share/bash-completion/completions/$(APPNAME); fi
	if [ -f $(DISTDIR)/lib/initcpio/install/$(APPNAME) ]; then install -g 0 -o 0 -p -m 0644 -D $(DISTDIR)/lib/initcpio/install/$(APPNAME) $(DESTDIR)$(PREFIX)/lib/initcpio/install/$(APPNAME); fi
	if [ -f $(DISTDIR)/lib/initcpio/hooks/$(APPNAME) ]; then install -g 0 -o 0 -p -m 0644 -D $(DISTDIR)/lib/initcpio/hooks/$(APPNAME) $(DESTDIR)$(PREFIX)/lib/initcpio/hooks/$(APPNAME); fi
	if [ -f $(DISTDIR)/bin/$(APPNAME)-add-luks-key ]; then install -g 0 -o 0 -p -m 0755 -D $(DISTDIR)/bin/$(APPNAME)-add-luks-key $(DESTDIR)$(PREFIX)/bin/$(APPNAME)-add-luks-key; fi
	if [ -f $(DISTDIR)/bin/$(APPNAME)-add-luks-key ] && [ -f $(DISTDIR)/share/man/man8/$(APPNAME)-add-luks-key.8.gz ]; then install -g 0 -o 0 -p -m 0644 -D $(DISTDIR)/share/man/man8/$(APPNAME)-add-luks-key.8.gz $(DESTDIR)$(PREFIX)/share/man/man8/$(APPNAME)-add-luks-key.8.gz; fi
	if [ -f $(DISTDIR)/bin/$(APPNAME)-ssh-askpass ]; then install -g 0 -o 0 -p -m 0755 -D $(DISTDIR)/bin/$(APPNAME)-ssh-askpass $(DESTDIR)$(PREFIX)/bin/$(APPNAME)-ssh-askpass; fi
	if [ -f $(DISTDIR)/bin/$(APPNAME)-ssh-askpass ] && [ -f $(DISTDIR)/share/man/man1/$(APPNAME)-ssh-askpass.1.gz ]; then install -g 0 -o 0 -p -m 0644 -D $(DISTDIR)/share/man/man1/$(APPNAME)-ssh-askpass.1.gz $(DESTDIR)$(PREFIX)/share/man/man1/$(APPNAME)-ssh-askpass.1.gz; fi

.PHONY: uninstall
uninstall:
	$(RM) $(DESTDIR)/lib/initcpio/hooks/$(APPNAME)
	$(RM) $(DESTDIR)/lib/initcpio/install/$(APPNAME)
	$(RM) $(DESTDIR)$(PREFIX)/share/bash-completion/completions/$(APPNAME)
	$(RM) $(DESTDIR)$(PREFIX)/share/man/man1/$(APPNAME).1.gz
	$(RM) $(DESTDIR)$(PREFIX)/share/man/man1/$(APPNAME)-ssh-askpass.1.gz
	$(RM) $(DESTDIR)$(PREFIX)/share/man/man8/$(APPNAME)-add-luks-key.8.gz
	$(RM) $(DESTDIR)$(PREFIX)/bin/$(APPNAME)-add-luks-key
	$(RM) $(DESTDIR)$(PREFIX)/bin/$(APPNAME)-ssh-askpass
	$(RM) $(DESTDIR)$(PREFIX)/bin/$(APPNAME)

.PHONY: clean
clean: cleandep cleanobj cleandist

# Development build targets
.PHONY: debug
debug: CFLAGS:=-g -DDEBUG $(CFLAGS)
debug: LDFLAGS:=-g -DDEBUG $(LDFLAGS)
debug: $(BINPATH)

.PHONY: lint
lint:
	clang-tidy --fix $(SRCS) -- $(INCLUDEFLAGS) $(DEFINEFLAGS)

.PHONY: shellcheck
shellcheck:
	shellcheck $^

.PHONY: format
format:
	clang-format -style=file -i $(SRCS) $(HEADERS)

# Invidiual source file targets
$(BINPATH): $(OBJS)
	mkdir -p $(DISTDIR)/bin
	$(CC) -o $(BINPATH) $(OBJS) $(LDFLAGS) $(LDLIBS)

-include $(PREREQUISITES)

$(INCDIR)/help.h: $(METAPATH)

%.d: %.c
	$(CC) $(CFLAGS) $< -MM -MT $(@:.d=.o) >$@

# Ancillary files targets
.PHONY: manpages
manpages: $(DISTDIR)/share/man/man1/$(APPNAME).1.gz $(DISTDIR)/share/man/man1/$(APPNAME)-ssh-askpass.1.gz $(DISTDIR)/share/man/man8/$(APPNAME)-add-luks-key.8.gz

$(DISTDIR)/share/man/man1/%.1.gz: $(DISTDIR)/share/man/man1/%.1
	gzip -f $<

$(DISTDIR)/share/man/man8/%.8.gz: $(DISTDIR)/share/man/man8/%.8
	gzip -f $<

.INTERMEDIATE: $(DISTDIR)/share/man/man1/%.1
$(DISTDIR)/share/man/man1/%.1: $(MANDIR)/1/%.m4 $(METAPATH) $(M4VARSPATH)
	mkdir -p $(DISTDIR)/share/man/man1
	m4 $(M4FLAGS) $< > $@

.INTERMEDIATE: $(DISTDIR)/share/man/man8/%.8
$(DISTDIR)/share/man/man8/%.8: $(MANDIR)/8/%.m4 $(METAPATH) $(M4VARSPATH)
	mkdir -p $(DISTDIR)/share/man/man8
	m4 $(M4FLAGS) $< > $@


.PHONY: bash-completion
bash-completion: $(DISTDIR)/share/bash-completion/completions/$(APPNAME)
shellcheck: $(DISTDIR)/share/bash-completion/completions/$(APPNAME)

$(DISTDIR)/share/bash-completion/completions/$(APPNAME): $(SCRIPTDIR)/bash-completion.m4 $(METAPATH) $(M4VARSPATH)
	mkdir -p $(DISTDIR)/share/bash-completion/completions
	m4 $(M4FLAGS) $(SCRIPTDIR)/bash-completion.m4 > $@


.PHONY: initcpio
initcpio: $(DISTDIR)/lib/initcpio/install/$(APPNAME) $(DISTDIR)/lib/initcpio/hooks/$(APPNAME) $(DISTDIR)/bin/$(APPNAME)-add-luks-key
shellcheck: $(DISTDIR)/lib/initcpio/install/$(APPNAME) $(DISTDIR)/lib/initcpio/hooks/$(APPNAME) $(DISTDIR)/bin/$(APPNAME)-add-luks-key

$(DISTDIR)/lib/initcpio/install/$(APPNAME): $(SCRIPTDIR)/initcpio-install.m4 $(M4VARSPATH)
	mkdir -p $(DISTDIR)/lib/initcpio/install
	m4 $(M4FLAGS) $(SCRIPTDIR)/initcpio-install.m4 > $@

$(DISTDIR)/lib/initcpio/hooks/$(APPNAME): $(SCRIPTDIR)/initcpio-run.m4 $(M4VARSPATH)
	mkdir -p $(DISTDIR)/lib/initcpio/hooks
	m4 $(M4FLAGS) $(SCRIPTDIR)/initcpio-run.m4 > $@

$(DISTDIR)/bin/$(APPNAME)-add-luks-key: $(SCRIPTDIR)/add-luks-key.m4 $(M4VARSPATH)
	mkdir -p $(DISTDIR)/bin
	m4 $(M4FLAGS) $(SCRIPTDIR)/add-luks-key.m4 > $@


.PHONY: ssh-askpass
ssh-askpass: $(DISTDIR)/bin/$(APPNAME)-ssh-askpass
shellcheck: $(DISTDIR)/bin/$(APPNAME)-ssh-askpass

$(DISTDIR)/bin/$(APPNAME)-ssh-askpass: $(SCRIPTDIR)/ssh-askpass.m4 $(METAPATH) $(M4VARSPATH)
	mkdir -p $(DISTDIR)/bin
	m4 $(M4FLAGS) $(SCRIPTDIR)/ssh-askpass.m4 > $@


# Cleanup targets
.PHONY: cleandist
cleandist:
	$(RM) -rf $(DISTDIR)

.PHONY: cleandep
cleandep:
	$(RM) $(PREREQUISITES)

.PHONY: cleanobj
cleanobj:
	$(RM) $(OBJS)
