local gpio = require "pigpiod"
local util = require "test.test_util"
local wait = gpio.wait
local host, port = "localhost", 8888
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port, "raspi")
printf("Session with host %s on port %d opened, handle = %d, name = %q", host, port, sess.handle, sess.name)

printf(gpio.info())

local pinp, pout = 20, 21

local x = 1
local last_tick
local cbcnt = 1
---
--Alert callback.
---
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
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 1000},
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 3000},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 1000},
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 4000},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 1000},
   },
   {
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 1000 * 10},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 1000 * 10},
      {on = bit32.lshift(1, pout), off = 0, delay = ton * 2000 * 10},
      {on = 0, off = bit32.lshift(1, pout), delay = toff * 2000 * 10}
   }
}

--sess:waveAddGeneric(waveform[1])
--sess:waveAddGeneric(waveform[2])
--local wave = sess:waveCreate()
local wave, npuls = sess:waveOpen(waveform, "mywave")
printf("   wave id:        %d", wave.handle)
printf("   wave pulses:    %d", npuls)
printf("   wave name:      %q", wave.name)
printf("   wave length:    %d us", sess:waveGetMicros())
printf("   wave hi length: %d us", sess:waveGetHighMicros())
printf("   max micros    : %d us", sess:waveGetMaxMicros())
printf("   num pulses    : %d", sess:waveGetPulses())
printf("   wave hi pulses: %d", sess:waveGetHighPulses())

printf("send waveform: single shot ...")
last_tick = sess:tick()
local dmablocks = wave:sendOnce()
printf("   dmablocks: %d", dmablocks)
while sess:waveTxBusy() == 1 do
end
printf("send waveform: repeat mode ...")
last_tick = sess:tick()
local dmablocks = wave:sendRepeat()
printf("   dmablocks: %d", dmablocks)
while sess:waveTxBusy() == 1 do
   if cbcnt > N then
      printf("Stopping waveform at %q, %d ...", sess:waveTxAt())
      sess:waveTxStop()
      break
   end
end
printf("Delete waveform ...")
wave:delete()

printf("Try to start deleted waveform ...")
local res, err = wave:sendRepeat()
printf("  err: %s", err)

print("cleanup ...")
cb:cancel()
sess:setMode(pout, gpio.INPUT)
