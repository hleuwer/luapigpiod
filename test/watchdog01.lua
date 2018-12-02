local gpio = require "pigpiod"
local util = require "test.test_util"
local wait = gpio.wait
local host, port = "localhost", 8888
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port)
printf("Session with host %s on port %d opened, handle = %d", host, port, sess.handle)

print(gpio.info())

local pinp, pout = 20, 21

sess:setMode(pinp, gpio.INPUT)
sess:setMode(pout, gpio.OUTPUT)

local last_tick = 0
local cbcnt = 1

---
-- Alert callback
---
local function alert(pi, pin, level, tick)
   local trcv = pi:tick()
   local tsnd = tick
   local tdel = trcv - tsnd
   local tper = tick - last_tick
   if level == 2 then
      printf("TIMEOUT callback %d: tsnd=%d us, trcv=%d us, tdel=%d us, tper=%d us, gpio=%d (ok=%s), level=%d gc=%.1f (%d)",
             cbcnt, tsnd, trcv, tdel, tper, pin, tostring(pin==pinp), level, collectgarbage("count"))
   else
      printf("ALERT callback %d: tsnd=%d us, trcv=%d us, tdel=%d us, tper=%d us, gpio=%d (ok=%s), level=%d gc=%.1f (%d)",
             cbcnt, tsnd, trcv, tdel, tper, pin, tostring(pin==pinp), level, collectgarbage("count"))
   end
   last_tick = tick
   last_level = level
   cbcnt = cbcnt +1
   if cbcnt == 10 then
      printf("  Cancel watchdog ...")
      sess:setWatchdog(pinp, 0)
   end
end

printf("set alert func ...")
local cb, err = assert(sess:callback(pinp, gpio.EITHER_EDGE, alert))
printf("  callback ID: %d", cb.id)

local tout = util.getNumber("Timeout [ms]: ", 500)

print("Config Watchdog ...")
local rc = assert(sess:setWatchdog(pinp, tout))

print("Write level 1 ...")
sess:write(pout, 1)
last_tick = sess:tick()

print("Capture Watchdog timeouts for 5 seconds ...")
wait(5)

print("cleanup ...")
sess:setMode(pout, gpio.INPUT)
sess:close()
