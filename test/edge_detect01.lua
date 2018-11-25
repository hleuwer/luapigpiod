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

local cbcnt = 1
local last_tick
local last_level = -1

---
--Alert callback.
---
local function alert(pi, pin, level, tick)
   local trcv = pi:tick()
   local tsnd = tick
   local tdel = trcv - tsnd
   local tper = tick - last_tick
   printf("ALERT callback %d: tsnd=%d us, trcv=%d us, tdel=%d us, tper=%d us, gpio=%d (ok=%s), level=%d gc=%.1f (%d)",
          cbcnt, tsnd, trcv, tdel, tper, pin, tostring(pin==pinp), level, collectgarbage("count"))
   if level == last_level then
      printf("   NOTE: level change not detected - input frequency probably too high!")
   end
   last_tick = tick
   last_level = level
   cbcnt = cbcnt +1 
end

printf("set pin pullup ...")
sess:setPullUpDown(pinp, gpio.PUD_UP)

printf("set pin to input ...")
sess:setMode(pinp, gpio.INPUT)

printf("set pout to output ...")
sess:setMode(pout, gpio.OUTPUT)

local N = util.getNumber("Number of transitions: ", 10)
local ton = util.getNumber("T_on [ms]: ", 10)
local toff = util.getNumber("T_off [ms] ", 10)
local bitmode = util.getString("Bit mode (yes/no): ", "yes")
printf("T_on: %d", ton)
printf("T_off: %d", toff)
printf("Bitmode: %s", bitmode)

printf("set alert func ...")

local cb, err = assert(sess:callback(pinp, gpio.EITHER_EDGE, alert))
printf("  callback ID: %d", cb.id)
last_tick = sess:tick()
printf("  tick: %d", last_tick)
for i = 1, N/2 do
   print("set 1")
   if bitmode == "yes" then
      assert(sess:write(pout, 1))
   else
      assert(sess:setBank1(bit32.lshift(1,pout)))
   end
   wait(ton/1000)
   --   gpio.delay(ton*1000)
   print("set 0")
   if bitmode == "yes" then
      assert(sess:write(pout, 0))
   else
      assert(sess:clearBank0(bit32.lshift(1, pout)))
   end
   print("waiting ...", toff)
   wait(toff/1000)
--   gpio.delay(toff*1000)
--   collectgarbage("collect")
end

--printf("wait a second ...")
--gpio.wait(1)

print("cleanup ...")
sess:setMode(pout, gpio.INPUT)
