#ifndef PIGPIOD_UTIL_INCL
#define PIGPIOD_UTIL_INCL

#include <pthread.h>
#include "lua.h"
#include "pigpiod_if2.h"

#define DEBUG (0)
#define DEBUG1 (0)
#define DEBUG2 (0)

#define TRUE (1)
#define FALSE (0)
#define LIMIT_EVENT_QUEUE (100)

#define MAX_CALLBACKS (32)
#define MAX_EVENTCALLBACKS (32)

#define PIGPIO_SESSIONS "_PIGPIOD_SESSIONS"

struct callbackfuncEx {
  CBFuncEx_t f;
  void *u;
};
typedef struct callbackfuncEx callbackfuncEx_t;

struct eventcallbackfuncEx {
  evtCBFuncEx_t f;
  void *u;
};
typedef struct eventcallbackfuncEx eventcallbackfuncEx_t;

struct threadfunc {
  gpioThreadFunc_t *f;
  lua_State *L;
  int a;
  pthread_t *t;
  char *n;
};
typedef struct threadfunc threadfunc_t;

enum slottype {
               CALLBACK= 0,
               EVENTCALLBACK = 1,
};
typedef enum slottype slottype_t;

struct callbackslot {
  int pi;
  unsigned index;  
  int level;
  uint32_t tick;
};
typedef struct callbackslot callbackslot_t;

struct eventcallbackslot {
  int pi;
  unsigned index;
  uint32_t tick;
};
typedef struct eventcallbackslot eventcallbackslot_t;

union slot {
  callbackslot_t callback;
  eventcallbackslot_t eventcallback;
};
typedef union slot slot_t;

struct event {
  slottype_t type;
  struct event *next;
  slot_t slot;
};
typedef struct event event_t;

struct anchor {
  event_t *first;
  event_t *last;
  int count;
  int limit;
  unsigned long drop;
};
typedef struct anchor anchor_t;

struct eventstat {
  unsigned long maxcount;
  unsigned long drop;
};
typedef struct eventstat eventstat_t;


int utlStartThread(lua_State *L);
int utlStopThread(lua_State *L);
int utlWaveAddGeneric(lua_State *L);
int utlRunScript(lua_State *L);
int utlUpdateScript(lua_State *L);
int utlScriptStatus(lua_State *L);
int utlCallback(lua_State *L);
int utlEventCallback(lua_State *L);
int utlSerialWrite(lua_State *L);
int utlSerialRead(lua_State *L);
int utlI2CReadBlockData(lua_State *L);
int utlI2CBlockProcessCall(lua_State *L);
int utlI2CReadI2CBlockData(lua_State *L);
int utlI2CReadDevice(lua_State *L);
int utlI2CZip(lua_State *L);
int utlSPIRead(lua_State *L);
int utlSPITransfer(lua_State *L);
#endif
