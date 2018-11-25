local gpio = require "pigpiod"
local util = require "test.test_util"
local host, port = "localhost", 8888

local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port)
printf("Session with host %s on port %d opened, handle = %d", host, port, sess.handle)

print(gpio.info())

local pinp, pout = 25, 18

assert(sess:setMode(pinp, gpio.INPUT))
assert(sess:setMode(pout, gpio.OUTPUT))

local last_tick = sess:tick()
local count = 1
local cbcnt = 1

local function alert(pi, pin, level, tick, udata)
   local trcv = pi:tick()
   local tsnd = tick
   local tdel = trcv - tsnd
   local tper = tick - last_tick
   printf("ALERT callback %d: tsnd=%d us, trcv=%d us, tdel=%d us, tper=%d us, duty=%d, gpio=%d (ok=%s), level=%d gc=%.1f (%d)",
          cbcnt, tsnd, trcv, tdel, tper, udata.duty, pin, tostring(pin==pinp), level, collectgarbage("count"))
   if level == last_level then
      printf("   NOTE: level change not detected - input frequency probably too high!")
   end
   last_tick = tick
   last_level = level
   cbcnt = cbcnt + 1 
end


local freq = util.getNumber("PWM frequency [Hz]:", 100)
local wait = util.getNumber("burst size [ms]:", 200)
local dutymax = 1000000
local udata = {duty = dutymax * 0.5}
printf("Duty cycle range: %d", sess:getPwmRange(pout))
printf("Duty cycle real range: %d", sess:getPwmRealRange(pout))

printf("Start PWM: duty cyle %d (%.1f %%) ...", dutymax * 0.5, (dutymax * 0.5) / dutymax * 100)
io.write("Hit <return> ...") io.flush() io.read()

local cb, err = assert(sess:callback(pinp, gpio.EITHER_EDGE, alert, udata))
last_tick = sess:tick()

local rc = sess:hardwarePwm(pout, freq, dutymax * 0.5)
gpio.wait(wait/1000)
sess:setMode(pout, gpio.INPUT)
sess:setMode(pout, gpio.OUTPUT)
gpio.wait(wait/1000)
udata.duty = dutymax * 0.99
printf("Start PWM: duty cyle %d (%.1f %%) ...", dutymax * 0.99, (dutymax * 0.99) / dutymax * 100)
io.write("Hit <return> ...") io.flush() io.read()
last_tick = sess:tick()
rc = sess:hardwarePwm(pout, freq, dutymax * 0.99)
gpio.wait(wait/1000)
sess:setMode(pout, gpio.INPUT)

sess:setMode(pout, gpio.OUTPUT)
gpio.wait(wait/1000)
udata.duty = dutymax * 0.01
printf("Start PWM: duty cyle %d (%.1f %%) ...", dutymax * 0.01, (dutymax * 0.01) / dutymax * 100)
io.write("Hit <return> ...") io.flush() io.read()
last_tick = sess:tick()
sess:hardwarePwm(pout, freq, dutymax * 0.01)
gpio.wait(wait/1000)
sess:setMode(pout, gpio.INPUT)

print("cleanup ...")
sess:setMode(pout, gpio.INPUT)
