local gpio = require "pigpiod"
local util = require "test.test_util"
local host, port = "localhost", 8888
local wait = gpio.wait
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port, "mysession")
printf("Session %q with host %s on port %d opened, handle = %d", sess.name, host, port, sess.handle)

print(gpio.info())

local pinp, pout = 20, 21

sess:setPullUpDown(pinp, gpio.PUD_UP)
sess:setMode(pinp, gpio.INPUT)
sess:setMode(pout, gpio.OUTPUT)

local last_tick = 0
local cbcnt = 1
---
-- Alert function.
---
local function alert(pi, pin, level, tick)
   local trcv = pi:tick()
   local tsnd = tick
   local tdel = trcv - tsnd
   local tper = tick - last_tick
   printf("ALERT callback %d: tsnd=%d us, trcv=%d us, tdel=%d us, tper=%d us, gpio=%d (ok=%s), level=%d gc=%.1f (%d)",
          cbcnt, tsnd, trcv, tdel, tper, pin, tostring(pin==pinp), level, collectgarbage("count"))
   last_tick = tick
   last_level = level
   cbcnt = cbcnt +1 
end

local N = util.getNumber("Number of triggers: ", 5)
local ton = util.getNumber("Pulse length [us]: ", 100)

printf("Set alert func ...")
local cb, err = assert(sess:callback(pinp, gpio.EITHER_EDGE, alert))
printf("  callback ID: %d", cb.id)

last_tick = sess:tick()
for i = 1, N do
   printf("Trigger ton=%d level=%d...", ton, 1)
   sess:trigger(pout, ton, 1)
   wait(0.5)
end

printf("Wait a second ...")
wait(1)

printf("Cleanup ...")
sess:setMode(pout, gpio.INPUT)

printf("Close session ...")
sess:close()
