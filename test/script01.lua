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
printf("T_on: %d", ton)
printf("T_off: %d", toff)

printf("open and store script ...")
local script, err = assert(sess:openScript("tag 999 w 21 1 mils ".. ton .." w 21 0 mils " ..toff .. " dcr p0 jp 999"), err)
printf("  handle: %d", script.handle)

printf("  script status: %q", script:status())

printf("set alert func ...")

local cb, err = assert(sess:callback(pinp, gpio.EITHER_EDGE, alert))
printf("  callback ID: %d", cb.id)
last_tick = sess:tick()
printf("  tick: %d", last_tick)

printf("run script ...")
local res, err = script:run({N/2})
printf("  res: %s", tostring(res))

local stat, param = script:status()
printf("  script status: %q", stat)
while stat == "running" do
   stat = script:status()
   if stat == "waiting" then
      printf("  script status: %q", stat)
   end
end

--printf("wait a second ...")
--gpio.wait(1)

printf("  stop script ...")
script:stop()
printf("  script status: %q", script:status())

printf("cleanup ...")
printf("  delete script ...")
script:delete()

printf("Capture event stats ...")
local stat, err = gpio.getEventStats()
printf("  drop: %d events", stat.drop)
printf("  maxcount: %d events in queue", stat.maxcount)

printf("  pin cleanup ...")
sess:setMode(pout, gpio.INPUT)
