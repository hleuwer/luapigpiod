SYSTEM  = $(shell uname)
MODULE	= pigpiod
WRAPPER	= $(MODULE)_wrap.c
WOBJS	= $(WRAPPER:.c=.o) pigpiod_util.o
OBJS 	= $(WOBJS)
HDRS    = pigpiod_if2.h pigpio_const.h
OPT     = -ggdb
CFLAGS	= -DSYSTEM='$(SYSTEM)' $(OPT) -Wall -c -fPIC
LUAV	= 5.2
ifeq ($(SYSTEM), Darwin)
  PIGPIODIR = ../pigpio.git
  INC	= -I/usr/local/include/lua/$(LUAV) -I/usr/local/include -I../pigpio.git
  LIBDIR = -L/usr/local/lib/ -L/usr/local/lib/lua/$(LUAV)
  HFILE	= ../pigpio.git/pigpiod_if2.h pigpio_const.h
  SWIG_IDIR = /usr/share/swig3.0
  LIBS	= -lpthread 
  OBJS += pigpiod_if2.o command.o
  LDFLAGS = -dynamiclib -undefined dynamic_lookup $(OPT)
else
  INC	= -I/usr/include/lua$(LUAV) -I/usr/local/include
  LIBDIR = -L/usr/local/lib 
  HFILE	= /usr/local/include/pigpiod_if2.h pigpio_const.h
  SWIG_IDIR = /opt/local/share/swig3.0.12
  LIBS	= -lpigpiod_if2 -lpthread
  LDFLAGS = -shared -g3
endif
IFILE	= $(MODULE).i
INDEXFILE = index.txt
TARGET	= $(MODULE)/core.so
LUALIBDIR = /usr/local/lib/lua/$(LUAV)
SHELL_CMD = shell_example
PIGPIO_OPTDIR = /opt/pigpio
ACCESS_FILE = access

.Suffixes: .c .o

.c.o:
	gcc $(CFLAGS) $(INC) -o $@ $<

$(TARGET): $(OBJS)
	mkdir -p pigpiod && gcc $(LDFLAGS) $(OBJS) $(LIBDIR) $(LIBS) -o $(TARGET)

$(WRAPPER:.c=.o): $(WRAPPER)

$(WRAPPER): $(IFILE) $(HFILE)
	swig -w302 -DSYSTEM=$(SYSTEM) -I$(SWIG_IDIR) -lua $(IFILE)

doc::
	ldoc $(MODULE).lua

doc-clean::
	rm -rf doc

clean:
	rm -f $(TARGET) $(OBJS)
	rm -f `find . -name "*~"`

depend: makefile.deps

makefile.deps: $(OBJS:.o=.c) 
	rm -f makefile.deps
	test -z "$(OBJS)" || $(CC) -MM $(CFLAGS) $(INC) $(OBJS:.o=.c) >> makefile.deps

uclean::
	$(MAKE) clean
	rm -f $(WRAPPER)
	rm -rf makefile.deps

install:: install-shell install-file
	mkdir -p $(LUALIBDIR) && cp -f $(TARGET) $(LUALIBDIR)

uninstall:: uninstall-shell uninstall-file
	rm -rf $(LUALIBDIR)/$(TARGET)

install-shell::
	mkdir -p $(PIGPIO_OPTDIR)/cgi
	cp etc/$(SHELL_CMD) $(PIGPIO_OPTDIR)/cgi

uninstall-shell::
	rm /opt/pigpio/cgi/$(SHELL_CMD)

install-file::
	mkdir -p $(PIGPIO_OPTDIR)
	cp etc/$(ACCESS_FILE) $(PIGPIO_OPTDIR)

uninstall-file::
	rm -rf /opt/pigpio/access

index::
	lua -l $(MODULE) -e 'for k,v in pairs(pigpiod) do print(k,v) end' > etc/$(INDEXFILE)

patch::
	cp $(PIGPIODIR)/pigpiod_if2.h _pigpiod_if2.h && patch _pigpiod_if2.h -i pigpiod_if2.patch -o pigpiod_if2.h
	rm -rf _pigpiod_if2.h
	cp $(PIGPIODIR)/pigpio.h _pigpio_const.h && patch _pigpio_const.h -i pigpio_const.patch -o pigpio_const.h
	rm -rf _pigpio_const.h
	cp $(PIGPIODIR)/command.c .

-include makefile.deps
