MODULE=pigpiod
WRAPPER=$(MODULE)_wrap.c
WOBJS=$(WRAPPER:.c=.o) pigpiod_util.o
OBJS = $(WOBJS)
CFLAGS= -ggdb -Wall -c -fpic
LDFLAGS= -shared
LIBS=-lpigpiod_if2 -lpthread
LUAV=5.2
INC=-I/usr/include/lua$(LUAV) -I/usr/local/include
LIBDIR=-L/usr/local/lib 
IFILE=$(MODULE).i
HFILE=/usr/local/include/pigpiod_if2.h pigpio_const.h
INDEXFILE=index.txt
TARGET=$(MODULE)/core.so
LUALIBDIR=/usr/local/lib/lua/$(LUAV)
SWIG_IDIR=/usr/share/swig3.0

.SUFFIXES: .c .o

.c.o: 
	gcc $(CFLAGS) $(INC) -o $@ $<

$(TARGET): $(OBJS)
	mkdir -p pigpiod && gcc $(LDFLAGS) $(OBJS) $(LIBDIR) $(LIBS) -o $(TARGET)

$(WRAPPER:.c=.o): $(WRAPPER)

$(WRAPPER): $(IFILE) $(HFILE)
	swig -I$(SWIG_IDIR) -lua $(IFILE)

doc:

clean:
	rm -f $(TARGET) $(WOBJS)
	rm -f `find . -name "*~"`
uclean:
	$(MAKE) clean
	rm -f $(WRAPPER)

install:
	mkdir -p $(LUALIBDIR) && cp -f $(TARGET) $(LUALIBDIR)

uninstall:
	rm -rf $(LUALIBDIR)/$(TARGET)

index::
	lua -l $(MODULE) -e 'for k,v in pairs(pigpiod) do print(k,v) end' > etc/$(INDEXFILE)

pigpiod_util.o: pigpiod_util.c pigpiod_util.h
