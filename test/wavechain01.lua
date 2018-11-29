local gpio = require "pigpiod"
local util = require "test.test_util"
local wait = gpio.wait

local host, port = "localhost", 8888
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port, "raspi")
printf("Session with host %s on port %d opened, handle = %d, name = %q", host, port, sess.handle, sess.name)


print(gpio.info())

local pinp, pout = 20, 21

local cbcnt = 1
local last_tick

---
--Alert callback.
---
local function alert(pi, pin, level, tick)
   local trcv = pi:tick()
   local tsnd = tick
   local tdel = trcv - tsnd
   local tper = tick - last_tick
   printf("ALERT callback %d: tsnd=%d us, trcv=%d us, tdel=%d us, tper=%d us, gpio=%d (ok=%s), level=%d wave=%s gc=%.1f (%d)",
          cbcnt, tsnd, trcv, tdel, tper, pin, tostring(pin==pinp), level, pi:waveTxAt(), collectgarbage("count"))
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
local N = util.getNumber("Transitions: ", 20)
local ton = util.getNumber("T_on [ms]: ", 10)
local toff = util.getNumber("T_off [ms] ", 10)
printf("T_on: %d", ton)
printf("T_off: %d", toff)

printf("set alert func ...")
local cb, err = assert(sess:callback(pinp, gpio.EITHER_EDGE, alert))
printf("  callback ID: %d", cb.id)

printf("define wave ...")
-- Define wave
local waveform = {
   {
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 1000},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 1000},
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 2000},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 2000},
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 3000},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 3000},
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 4000},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 4000},
   },
   {
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 1000 * 10},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 1000 * 10},
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 2000 * 10},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 2000 * 10}
   }
}

local waves = {}
waves[1] = sess:waveOpen({waveform[1]}, "wave-1")
waves[2] = sess:waveOpen({waveform[2]}, "wave-2")

   printf("waves:")
for _, w in ipairs(waves) do printf("%s %d", w.name, w.handle) end

printf("start wave chain ...")
last_tick = sess:tick()
sess:waveChain{
   waves[1],
   "start",
   waves[2],
   "delay ".. (100*1000),
   "repeat 10",
   "start",
   waves[1],
   "repeat 20"
}
while sess:waveTxBusy() == 1 do
   gpio.wait(0.1)
   if false and cbcnt > N then
      printf("Stopping waveform at %q, %d ...", sess:waveTxAt())
      sess:waveTxStop()
      break
   end
end

printf("Closing waveforms ...")
waves[1]:close()
waves[2]:close()

printf("cleanup ...")
sess:setMode(pout, gpio.INPUT)
