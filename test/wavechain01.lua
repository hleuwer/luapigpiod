local gpio = require "pigpio"
local util = require "test.test_util"
local wait = gpio.wait

print(gpio.info())

local pinp, pout = 20, 21

gpio.initialise()

local x = 1
local last_tick

---
--Alert callback.
---
local function alert(pin, level, tick)
   local _tick = gpio.tick()
   local delta = tick - last_tick
   last_tick = tick
   local inbits = gpio.read_Bits_0_31()
   print(string.format("alert cb %3d at %d (%4d us): gpio=%d (ok=%s), level=%d (%08x), tick=%d us, delta=%.3f ms wave=%d gc=%.1f (%d)",
                       x, _tick, _tick-tick, pin, tostring(pin==pinp), level, inbits, tick, delta/1000,
                       gpio.waveTxAt(),
                       collectgarbage("count")))
   x = x + 1
end

print("set pin pullup ...")
gpio.setPullUpDown(pinp, gpio.PUD_UP)
print("set pin to input ...")
gpio.setMode(pinp, gpio.INPUT)
print("set pout to output ...")
gpio.setMode(pout, gpio.OUTPUT)
local N = util.getNumber("Transitions: ", 20)
local ton = util.getNumber("T_on [ms]: ", 10)
local toff = util.getNumber("T_off [ms] ", 10)
print("T_on:", ton)
print("T_off:", toff)

print("set alert func ...")
gpio.setAlertFunc(pinp, alert)

print("define wave ...")
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
local wave = {}
gpio.waveAddGeneric(waveform[1])
wave[1] = gpio.waveCreate()
gpio.waveAddGeneric(waveform[2])
wave[2] = gpio.waveCreate()
print("start wave chain ...")
last_tick = gpio.tick()
gpio.waveChain{
   wave[1],
   "start",
   wave[2],
   "delay "..100*1000,
   "repeat 10",
   "start",
   wave[1],
   "repeat 20"
}
while gpio.waveTxBusy() == 1 do
   gpio.wait(0.1)
   if false and x > N then
      print("Stopping waveform " .. gpio.waveTxAt() .. " ...")
      gpio.waveTxStop()
      break
   end
end
--print("Delete waveform ...")
--gpio.waveDelete(wave)

print("wait a second ...")
gpio.wait(1)

print("cleanup ...")
gpio.setMode(pout, gpio.INPUT)
gpio.terminate()
