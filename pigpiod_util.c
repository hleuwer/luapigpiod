#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#include "pigpiod_util.h"
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

//#define DEBUG
#if DEBUG == 1
#define dprintf(...) fprintf(stderr, __VA_ARGS__)
#else
#define dprintf(...)
#endif

#if DEBUG2 == 1
#define dprintf2(...) fprintf(stderr, __VA_ARGS__)
#else
#define dprintf2(...)
#endif

#if DEBUG1 == 1
#define eprintf(...) fprintf(stderr, __VA_ARGS__)
#else
#define eprintf(...)
#endif
/*
 * Forward declaration.
 */
static int enqueue(anchor_t* anchor, event_t *event);
static event_t* dequeue(anchor_t* anchor);

/*
 * Array of callback function entries. We use addresses within the members
 * as keys into LUA_REGISTRYTABLE.
 */
static callbackfuncEx_t callbackfuncsEx[MAX_CALLBACKS];
static eventcallbackfuncEx_t eventcallbackfuncsEx[MAX_EVENTCALLBACKS];

static lua_State *LL = NULL;
static lua_Hook oldhook = NULL;
static int oldmask = 0;
static int oldcount = 0;
static anchor_t anchor = {NULL, NULL, 0, LIMIT_EVENT_QUEUE};
static eventstat_t eventstat = {0, 0};
pthread_mutex_t eventmutex = PTHREAD_MUTEX_INITIALIZER;

/*
 * Process gpio argument.
 */
static unsigned int get_numarg(lua_State *L, int stackindex, unsigned min, unsigned max)
{
  unsigned arg;
  if (lua_isnumber(L, stackindex) == 0){
    luaL_error(L, "Number expected as arg %d, received %s.",
               stackindex, lua_typename(L, lua_type(L, stackindex)));
  }
  arg = lua_tonumber(L, stackindex);
  if (arg < min || arg > max){
    luaL_error(L, "Value or arg %d exceeds range of %d to %d.", stackindex, min, max - 1);
  }
  return arg;
}
#if 0
/*
 * Copy data from C universe (buffer) to Lua universe (table)
 */
static void buf_to_table(lua_State *L, char *buf, int n)
{
  int i;
  lua_newtable(L);
  for (i = 0; i < n; i++){
    lua_pushnumber(L, i + 1);
    lua_pushnumber(L, buf[i]);
    lua_settable(L, -3);
  }
  free(buf);
}

/*
 * Copy data from Lua universe (table) to C universe (buffer)
 */
static char *table_to_buf(lua_State *L, int n)
{
  int i;
  char *buf = malloc(n * sizeof(char));
  for (i = 0; i < n; i++){
    lua_pushnumber(L, i + 1);
    lua_gettable(L, -2);
    buf[i] = lua_tonumber(L, -1);
    lua_settop(L, -1);
  }
  return buf;
}
#endif
/*
 * new thread: param, func 
 */
static void *threadFunc(void *uparam)
{
  threadfunc_t *cbfunc = uparam;
  lua_State *L = cbfunc->L;
  int narg = cbfunc->a;
  dprintf("thread: %s %d\n", lua_typename(L, lua_type(L,1)), lua_gettop(L));
  luaL_openlibs(L);
  lua_call(L, narg, 0);
  return NULL;
}

/*
 * Lua binding: succ = startThread(code, name, ...)
 */
int utlStartThread(lua_State *L)
{
  threadfunc_t *cbfunc;
  size_t len;
  int i;
  lua_State *newL;
  const char *code;
  const char *name;
  int narg;

  /* allocate a descriptor*/
  cbfunc = malloc(sizeof(threadfunc_t));
  cbfunc->f = threadFunc;
  narg = lua_gettop(L);
  cbfunc->a = narg - 1;
  newL = luaL_newstate();
  cbfunc->L = newL;
  if (lua_type(L, 1) != LUA_TSTRING){
    luaL_error(L, "Cannot use '%s' to define thread main routine.",
               luaL_typename(L, lua_type(L, 1)));
  }
  /* get code from stack */
  code = lua_tolstring(L, 1, &len);
  /* Get name and */
  name = luaL_checkstring(L, 2);
  /* Check if name already exists */
  lua_pushstring(L, name);
  lua_gettable(L, LUA_REGISTRYINDEX);
  if (lua_isnil(L, -1) == 0){
    luaL_error(L, "Name '%s' already registered.", name);
  }
  /* load and compile string into new state */
  if (luaL_loadbuffer(newL, code, len, name) != 0){  /* ns: func */
    lua_pushstring(L, lua_tostring(newL, -1));
    lua_close(newL);
    luaL_error(L, lua_tostring(L, -1));
  }
  /* Push name on new stack */
  lua_pushstring(newL, name);                        /* ns: name, func */
  cbfunc->n = strdup(name);
  /* Provide parameters on new stack */
  for (i = 3; i <= narg; i++){
    switch(lua_type(L, i)){
    case LUA_TNUMBER:
      lua_pushnumber(newL, lua_tonumber(L, i));      /* ns: param, name, func */
      break;
    case LUA_TSTRING:
      lua_pushstring(newL, lua_tostring(L, i));
      break;
    case LUA_TBOOLEAN:
      lua_pushboolean(newL, lua_toboolean(L, 1));
      break;
    case LUA_TNIL:
      lua_pushnil(newL);
      break;
    case LUA_TLIGHTUSERDATA:
      lua_pushlightuserdata(L, lua_touserdata(L, 1));
      break;
    default:
      luaL_error(L, "Invalid parameter type '%s'.",
                 lua_typename(L, lua_type(L, i)));
      break;
    }
  }
  /* 
   * Start new pthread.
   * Stack: param_n, ..., param_2, param_1, name, func  
   */
  cbfunc->t = start_thread(cbfunc->f, cbfunc);
  /* remind descriptor  in registry for later usage */
  lua_pushstring(L, cbfunc->n);
  lua_pushlightuserdata(L, cbfunc);
  lua_settable(L, LUA_REGISTRYINDEX);
  if (cbfunc->t == NULL){
    free(cbfunc);
    luaL_error(L, "Cannot start thread.");
  } else {
    lua_pushlightuserdata(L, cbfunc);
  }
  return 1;
}

/*
 * Lua binding: succ = stopThread(name | userdata)
 */
int utlStopThread(lua_State *L)
{
  threadfunc_t *cbfunc;
  int argtype = lua_type(L, 1);
  
  if (argtype == LUA_TSTRING) {
    /* get thread descriptor */
    lua_gettable(L, LUA_REGISTRYINDEX);
    if (lua_isnil(L, -1)){
      luaL_error(L, "Thread with name '%s' cannot be found.", lua_tostring(L, 1));
    }
  } else if (argtype != LUA_TLIGHTUSERDATA){
    luaL_error(L, "String or userdata expected as arg %d 'name', received %s.", 1,
               lua_typename(L, lua_type(L, 1)));
  }
  cbfunc = lua_touserdata(L, -1);
  lua_pushstring(L, cbfunc->n);
  stop_thread(cbfunc->t);
  lua_pushnil(L);
  lua_settable(L, LUA_REGISTRYINDEX);
  free(cbfunc->n);
  free(cbfunc);
  lua_pushnumber(L, TRUE);
  return 1;
}

/*
 * Lua binding: succ = waveAddGeneric(pi, pulses)
 * pulses = {{on=PATTERN, off=PATTERN, tick=TICKS},...}
 */
int utlWaveAddGeneric(lua_State *L)
{
  int res, i, pi, n;
  gpioPulse_t *pulses;

  pi = luaL_checkint(L, 1);
  
  if (!lua_istable(L, 2)){
    luaL_error(L, "Table expected as arg %d 'pulses', received %s.", 2,
               lua_typename(L, lua_type(L, 2)));
  }
  n = luaL_len(L, 2);            /* pulses */
  pulses = malloc(n * sizeof(gpioPulse_t));
  for (i = 0; i < n; i++){
    lua_pushnumber(L, i + 1);    /* ix, pulses */
    lua_gettable(L, -2);         /* puls, pulses */
    lua_pushstring(L, "on");     /* key, puls, pulses */
    lua_gettable(L, -2);         /* on, puls, pulses */
    pulses[i].gpioOn = lua_tonumber(L, -1);
    lua_pushstring(L, "off");    /* key, on, puls, pulses */
    lua_gettable(L, -3);         /* off, on, puls, pulses */   
    pulses[i].gpioOff = lua_tonumber(L, -1);
    lua_pushstring(L, "delay");  /* key, off, on, puls, pulses */
    lua_gettable(L, -4);         /* delay, off, on, puls, pulses */
    pulses[i].usDelay = lua_tonumber(L, -1);
    lua_settop(L, -5);           /* pulses */
  }
  res = wave_add_generic(pi, n, pulses);
  free(pulses);
  lua_pushnumber(L, res);
  return 1;
}

/*
 * Translate parameters given as Lua list into uint32_t array.
 */
static uint32_t *get_params(lua_State *L, int arg, int *nparam)
{
  uint32_t *params;
  int i, n;
  
  if (!lua_istable(L, arg)){
    luaL_error(L, "Table expected as arg %d 'params', received %s.", 3,
               lua_typename(L, lua_type(L, arg)));
  }
  n = luaL_len(L, arg);
  if (n > 10)
    n = 10;
  params = malloc(n * sizeof(uint32_t));
  for (i = 0; i < n; i++){
    lua_pushnumber(L, i + 1);
    lua_gettable(L, -2);
    params[i] = lua_tonumber(L, -1);
    lua_settop(L, -1);
  }
  *nparam = n;
  return params;
}

static void get_ids(lua_State *L, int arg, int *pi, int *id)
{
  *pi = luaL_checkint(L, arg);
  *id = luaL_checkint(L, arg + 1);
}
/*
 * Lua binding: succ = runScript(pi, id, params)
 * params = {param1, param2, ..., param10}
 */
int utlRunScript(lua_State *L)
{
  int pi, id, n, res;
  uint32_t *params;
  
  get_ids(L, 1, &pi, &id);
  params = get_params(L, 3, &n);
  res = run_script(pi, id, n, params);
  free(params);
  lua_pushnumber(L, res);
  return 1;
}

int utlUpdateScript(lua_State *L)
{
  int pi, id, n, res;
  uint32_t *params;
  get_ids(L, 1, &pi, &id);
  params = get_params(L, 3, &n);
  res = update_script(pi, id, n, params);
  free(params);
  lua_pushnumber(L, res);
  return 1;
}

int utlScriptStatus(lua_State *L)
{
  int pi, id, res, i;
  uint32_t params[10];
  get_ids(L, 1, &pi, &id);
  res = script_status(pi, id, params);
  lua_newtable(L);                /* tab */
  for (i = 0; i < 10; i++){
    lua_pushnumber(L, i + 1);     /* key, tab */
    lua_pushnumber(L, params[i]); /* val, key, tab */
    lua_settable(L, -3);          /* tab */
  }
  lua_pushnumber(L, res);         /* res, tab */
  return 2;
}

/*
 * Remind Lua hooks.
 * Must only be called when all lgpio event hook slots are empty. 
 */
static void remind_hooks(lua_State *L)
{
  if (anchor.count == 0){
    /* empty slot table: remind old hook */
    dprintf("remind_hooks\n");
    oldhook = lua_gethook(L);
    oldmask = lua_gethookmask(L);
    oldcount = lua_gethookcount(L);
  }
}

/* 
 * Hook handler:
 * Process all slots with a valid entry and call the corresponding Lua callback.
 * - callback(sess, pin, level, tick, uparam)
 * - eventcallback(sess, event, tick, uparam)
 * When all callbacks are processed the Lua hook is restored.
 */
static void handler(lua_State *L, lua_Debug *ar)
{
  (void) ar;
  event_t *event;
  event = dequeue(&anchor);
  dprintf("HANDLER 1: %p qlen=%d qfirst=%p qlast=%p\n",
          event, anchor.count, anchor.first, anchor.last);
  while (event != NULL) {
    switch (event->type){
    case CALLBACK:
      {
        callbackfuncEx_t *cbfunc = &callbackfuncsEx[event->slot.callback.index];
        dprintf("HANDLER 2.1: ev.index=%d ev.level=%d ev.tick=%d\n",
                event->slot.callback.index, even->slot.callback.level,  event->slot.callback.tick);
        lua_pushlightuserdata(L, &cbfunc->f);            
        lua_gettable(L, LUA_REGISTRYINDEX);              /* func */
        lua_getglobal(L, PIGPIO_SESSIONS);               /* stab, func */
        lua_pushnumber(L, event->slot.callback.pi);      /* handle, stab, func */
        lua_gettable(L, -2);                             /* sess, stab, func */
        lua_replace(L, -2);                              /* sess, func */
        lua_pushnumber(L, event->slot.callback.index);
        lua_pushnumber(L, event->slot.callback.level);
        lua_pushnumber(L, event->slot.callback.tick);
        lua_pushlightuserdata(L, &cbfunc->u);
        lua_gettable(L, LUA_REGISTRYINDEX);
        lua_call(L, 5, 0);
      }
      break;
    case EVENTCALLBACK:
      {
        eventcallbackfuncEx_t *cbfunc = &eventcallbackfuncsEx[event->slot.eventcallback.index];
        dprintf("HANDLER 2.2: ev.event=0x%08x ev.tick=%d\n",
                event->slot.eventcallback.event, even->slot.eventcallback.tick);
        lua_pushlightuserdata(L, &cbfunc->f);
        lua_gettable(L, LUA_REGISTRYINDEX);              /* func */
        lua_getglobal(L, PIGPIO_SESSIONS);               /* stab, func */
        lua_pushnumber(L, event->slot.callback.pi);      /* handle, stab, func */
        lua_gettable(L, -2);                             /* sess, stab, func */
        lua_replace(L, -2);                              /* sess, func */
        lua_pushnumber(L, event->slot.eventcallback.index);
        lua_pushnumber(L, event->slot.eventcallback.tick);
        lua_pushlightuserdata(L, &cbfunc->u);
        lua_gettable(L, LUA_REGISTRYINDEX);
        lua_call(L, 4, 0);
      }
      break;
    }
    dprintf("HANDLER 3: almost done. qlen=%d qfirst=%p qlast=%p\n",
            anchor.count, anchor.first, anchor.last);
    free(event);
    event = dequeue(&anchor);
    dprintf("HANDLER 4: %p qlen=%d qfirst=%p qlast=%p\n",
            event, anchor.count, anchor.first, anchor.last);
  }
  /* All slots processed: restore old hooks */
  lua_sethook(L, oldhook, oldmask, oldcount);
}

/*
 * Append event to tail of event queue.
 */
static int enqueue(anchor_t* anchor, event_t* event)
{
  pthread_mutex_lock(&eventmutex);
  if (anchor->count < anchor->limit){
    if (anchor->count++ == 0)
      /* list empty: event becomes first in queue */
      anchor->first = anchor->last = event;
    else {
      /* append event at tail */
      anchor->last->next = event;
      anchor->last = event;
    }
    if (anchor->count > eventstat.maxcount)
      eventstat.maxcount = anchor->count;
    dprintf2("eq: cnt=%d max=%d\n", anchor->count, eventstat.maxcount);
    pthread_mutex_unlock(&eventmutex);
    return 0;
  } else {
    eventstat.drop++;
    eprintf("Warning: event drop=%lu at count=%d.\n", eventstat.drop, anchor->count);
    pthread_mutex_unlock(&eventmutex);
    return -1;
  }  
}

/*
 * Pop an event from head of event queue.
 */
static event_t* dequeue(anchor_t* anchor)
{
  event_t* current;
  pthread_mutex_lock(&eventmutex);
  if (anchor->count-- == 0){
    anchor->count = 0;
    pthread_mutex_unlock(&eventmutex);
    return NULL;
  }
  current = anchor->first;
  anchor->first = current->next;
  dprintf2("dq: %d\n", anchor->count);
  pthread_mutex_unlock(&eventmutex);
  return current;
}

static void callbackFuncEx(int pi, unsigned gpio, unsigned level, uint32_t tick, void *userparam)
{
  lua_State *L = userparam;
  event_t *event;
  
  remind_hooks(L);
  event = malloc(sizeof(event_t));
  event->type = CALLBACK;
  event->slot.callback.pi = pi;
  event->slot.callback.index = gpio;
  event->slot.callback.level = level;
  event->slot.callback.tick = tick;
  enqueue(&anchor, event);
  lua_sethook(L, handler, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);  
}

/*
 * Lua binding: id = callback(pi, gpio, edge, func[, userdata])
 */
int utlCallback(lua_State *L)
{
  unsigned gpio, edge;
  callbackfuncEx_t *cbfunc;
  int pi, retval;
  
  pi = luaL_checkint(L, 1);
  gpio = (int) get_numarg(L, 2, 0, MAX_CALLBACKS - 1);
  edge = get_numarg(L, 3, RISING_EDGE, EITHER_EDGE);
  if (lua_isfunction(L, 4) == 0){
    luaL_error(L, "Function expected as arg 3, receive %s.", lua_typename(L, lua_type(L, 4)));
  }
  cbfunc = &callbackfuncsEx[gpio];
  cbfunc->f = callbackFuncEx;
  lua_pushlightuserdata(L, &cbfunc->f);
  lua_pushvalue(L, 4);
  lua_settable(L, LUA_REGISTRYINDEX);
  if (lua_isnoneornil(L, 5) == 1){
    lua_pushlightuserdata(L, &cbfunc->u);
    lua_pushnil(L);
  } else {
    lua_pushlightuserdata(L, &cbfunc->u);
    lua_pushvalue(L, 5);
  }
  lua_settable(L, LUA_REGISTRYINDEX);
  LL = L;
  retval = callback_ex(pi, gpio, edge, cbfunc->f, L);
  lua_pushnumber(L, retval);
  return 1;
}

static void eventCallbackFuncEx(int pi, unsigned uevent, uint32_t tick, void *userparam)
{
  lua_State *L = userparam;
  event_t *event;
  
  remind_hooks(L);
  event = malloc(sizeof(event_t));
  event->type = EVENTCALLBACK;
  event->slot.eventcallback.index = uevent;
  event->slot.eventcallback.tick = tick;
  enqueue(&anchor, event);
  lua_sethook(L, handler, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);  
}

/*
 * Lua binding: id = eventCallback(pi, event, func[, userdata])
 */
int utlEventCallback(lua_State *L)
{
  int pi, retval;
  unsigned int event;
  eventcallbackfuncEx_t *cbfunc;

  pi = luaL_checkint(L, 1);
  event = get_numarg(L, 2, 0, MAX_EVENTCALLBACKS - 1);
  if (lua_isfunction(L, 3) == 0){
    luaL_error(L, "Function expected as arg 2, received %s.", lua_typename(L, lua_type(L, 2)));
  }
  cbfunc = &eventcallbackfuncsEx[event];
  cbfunc->f = eventCallbackFuncEx;
  lua_pushlightuserdata(L, &cbfunc->f);
  lua_pushvalue(L, 3);
  lua_settable(L, LUA_REGISTRYINDEX);
  if (lua_isnoneornil(L, 4) == 1){
    lua_pushlightuserdata(L, &cbfunc->u);
    lua_pushnil(L);
  } else {
    lua_pushlightuserdata(L, &cbfunc->u);
    lua_pushvalue(L, 4);
  }
  lua_settable(L, LUA_REGISTRYINDEX);
  LL = L;
  retval = event_callback_ex(pi, event, cbfunc->f, L);
  lua_pushnumber(L, retval);
  return 1;
}

#ifdef NOT_NEEDED
/*
 * Lua binding: retval = serialWrite(pi, handle, array)
 */
int utlSerialWrite(lua_State *L)
{
  int pi, handle, n, retval;
  char *buf;
  pi = luaL_checkint(L, 1);
  handle = luaL_checkint(L, 2);
  if (lua_istable(L, 3) == 0){
    luaL_error(L, "Table expected as arg 3, receive %s.", lua_typename(L, lua_type(L, 3)));
  }
  n = luaL_len(L, 3);
  buf = table_to_buf(L, n);
  retval = serial_write(pi, handle, buf, n);
  free(buf);
  lua_pushnumber(L, retval);
  return 1;
}
#endif

/*
 * Lua binding: str = serial:read(n)
 */
int utlSerialRead(lua_State *L)
{
  int pi, n, nbytes;
  lua_Unsigned handle;
  luaL_Buffer lbuf;
  char *cbuf;
  pi = luaL_checkint(L, 1);
  handle = luaL_checkunsigned(L, 2);
  n = (int) luaL_checkunsigned(L, 3);
  luaL_buffinit(L, &lbuf);
  cbuf = malloc(n * sizeof(char));
  nbytes = serial_read(pi, handle, cbuf, n);
  if (nbytes < 0){
    free(cbuf);
    lua_pushnil(L);
    lua_pushnumber(L, nbytes);
    return 2;
  }
  luaL_addlstring(&lbuf, cbuf, nbytes);
  free(cbuf);
  luaL_pushresult(&lbuf);
  return 1;
}

/*
 * Lua binding: str = i2c:readBlockData(reg)
 */
int utlI2CReadBlockData(lua_State *L)
{
  int pi, nbytes;
  lua_Unsigned handle, reg;
  luaL_Buffer lbuf;
  char *cbuf;
  pi = luaL_checkint(L, 1);
  handle = luaL_checkunsigned(L, 2);
  reg = luaL_checkunsigned(L, 3);
  luaL_buffinit(L, &lbuf);
  cbuf = malloc(32 * sizeof(char));
  nbytes = i2c_read_block_data(pi, handle, reg, cbuf);
  if (nbytes < 0){
    free(cbuf);
    lua_pushnil(L);
    lua_pushnumber(L, nbytes);
    return 2;
  }
  luaL_addlstring(&lbuf, cbuf, nbytes);
  free(cbuf);
  luaL_pushresult(&lbuf);
  return 1;
}

/*
 * Lua binding: str = i2c:blockProcessCall(reg, data)
 */
int utlI2CBlockProcessCall(lua_State *L)
{
  int pi, nbytes, n;
  lua_Unsigned handle, reg;
  luaL_Buffer lbuf;
  char *cbuf;
  const char *instr;
  pi = luaL_checkint(L, 1);
  handle = luaL_checkunsigned(L, 2);
  reg = luaL_checkunsigned(L, 3);
  instr = luaL_checkstring(L, 4);
  n = luaL_len(L, 4);
  luaL_buffinit(L, &lbuf);
  cbuf = malloc(32 * sizeof(char));
  strncpy(cbuf, instr, n);
  nbytes = i2c_block_process_call(pi, handle, reg, cbuf, n);
  luaL_addlstring(&lbuf, cbuf, nbytes);
  free(cbuf);
  luaL_pushresult(&lbuf);
  return 1;
}

/*
 * Lua binding: str = i2c:readI2CBlockData(reg, nbytes)
 */
int utlI2CReadI2CBlockData(lua_State *L)
{
  int pi, nbytes, n;
  lua_Unsigned handle, reg;
  luaL_Buffer lbuf;
  char *cbuf;
  pi = luaL_checkint(L, 1);
  handle = luaL_checkunsigned(L, 2);
  reg = luaL_checkunsigned(L, 3);
  n = (int) luaL_checkunsigned(L, 4);
  luaL_buffinit(L, &lbuf);
  cbuf = malloc(32 * sizeof(char));
  nbytes = i2c_read_i2c_block_data(pi, handle, reg, cbuf, n);
  if (nbytes < 0){
    free(cbuf);
    lua_pushnil(L);
    lua_pushnumber(L, nbytes);
    return 2;
  }
  luaL_addlstring(&lbuf, cbuf, nbytes);
  free(cbuf);
  luaL_pushresult(&lbuf);
  return 1;
}

/*
 * Lua binding: str = i2c:readDevice(nbytes)
 */
int utlI2CReadDevice(lua_State *L)
{
  int pi, nbytes, n;
  lua_Unsigned handle;
  luaL_Buffer lbuf;
  char *cbuf;
  pi = luaL_checkint(L, 1);
  handle = luaL_checkunsigned(L, 2);
  n = (int) luaL_checkunsigned(L, 3);
  luaL_buffinit(L, &lbuf);
  cbuf = malloc(n * sizeof(char));
  nbytes = i2c_read_device(pi, handle, cbuf, n);
  luaL_addlstring(&lbuf, cbuf, nbytes);
  free(cbuf);
  luaL_pushresult(&lbuf);
  return 1;
}

/*
 * Lua binding: str = i2c:zip(cmdbuf, nbytes)
 */
int utlI2CZip(lua_State *L)
{
  int pi, nbytes, n, m;
  lua_Unsigned handle;
  luaL_Buffer lbuf;
  char *inbuf;
  char *cbuf;
  pi = luaL_checkint(L, 1);
  handle = luaL_checkunsigned(L, 2);
  inbuf = (char *) luaL_checkstring(L, 3);
  m = luaL_len(L, 3);
  n = (int) luaL_checkunsigned(L, 4);
  cbuf = malloc(n * sizeof(char));
  nbytes = i2c_zip(pi, handle, inbuf, m, cbuf, n);
  luaL_addlstring(&lbuf, cbuf, nbytes);
  free(cbuf);
  luaL_pushresult(&lbuf);
  return 1;
}

struct eventstat *get_event_statistics(void)
{
  struct eventstat *stat = malloc(sizeof(struct eventstat));
  *stat = eventstat;
  return stat;
}

int clear_event_statistics(void)
{
  eventstat.drop = 0;
  eventstat.maxcount = 0;
  return 1;
}
