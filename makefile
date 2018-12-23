MODULE	= pigpiod
WRAPPER	= $(MODULE)_wrap.c
WOBJS	= $(WRAPPER:.c=.o) pigpiod_util.o
OBJS 	= $(WOBJS)
CFLAGS	= -ggdb -Wall -c -fpic
LDFLAGS	= -shared
LIBS	= -lpigpiod_if2 -lpthread
LUAV	= 5.2
INC	= -I/usr/include/lua$(LUAV) -I/usr/local/include
LIBDIR	= -L/usr/local/lib 
IFILE	= $(MODULE).i
HFILE	= /usr/local/include/pigpiod_if2.h pigpio_const.h
INDEXFILE=index.txt
TARGET	= $(MODULE)/core.so
LUALIBDIR = /usr/local/lib/lua/$(LUAV)
SWIG_IDIR = /usr/share/swig3.0
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
	swig -w302 -I$(SWIG_IDIR) -lua $(IFILE)

doc::
	ldoc $(MODULE).lua

doc-clean::
	rm -rf doc

clean:
	rm -f $(TARGET) $(WOBJS)
	rm -f `find . -name "*~"`
uclean:
	$(MAKE) clean
	rm -f $(WRAPPER)

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

pigpiod_util.o: pigpiod_util.c pigpiod_util.h
