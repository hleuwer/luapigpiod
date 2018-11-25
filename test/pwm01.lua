local gpio = require "pigpiod"
local util = require "test.test_util"
local host, port = "localhost", 8888

local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port)
printf("Session with host %s on port %d opened, handle = %d", host, port, sess.handle)

local wait = gpio.wait
local last_tick = sess:tick()

print(gpio.info())

local pinp, pout = 20, 21

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

local freq = util.getNumber("PWM frequency:", 100)
local udata = {duty=128}

sess:setPwmFrequency(pout, freq)
printf("PWM frequency: %d", sess:getPwmFrequency(pout))
printf("Duty cycle range: %d", sess:getPwmRange(pout))
printf("Duty cycle real range: %d", sess:getPwmRealRange(pout))

printf("Start PWM: duty cyle 128 (%.1f %%) ...", 128/256 * 100)
io.write("Hit <return> ...") io.flush() io.read()

local cb, err = assert(sess:callback(pinp, gpio.EITHER_EDGE, alert, udata))

last_tick = sess:tick()
sess:setPwmDutycycle(pout, 128)

printf("duty cycle: %d", sess:getPwmDutycycle(pout))
wait(0.4)
sess:setPwmDutycycle(pout, 0)
printf("duty cycle: %d", sess:getPwmDutycycle(pout))

wait(0.2)
udata.duty=255
printf("Start PWM: duty cyle 255 (%.1f %%) ...", 255/256 * 100)
io.write("Hit <return> ...") io.flush() io.read()
last_tick = sess:tick()
sess:setPwmDutycycle(pout, 255)
printf("duty cycle: %d", sess:getPwmDutycycle(pout))
wait(0.2)
sess:setPwmDutycycle(pout, 0)
printf("duty cycle: %d", sess:getPwmDutycycle(pout))

wait(0.2)
udata.duty=1
printf("Start PWM: duty cyle 1 (%.1f %%) ...", 1/256 * 100)
io.write("Hit <return> ...") io.flush() io.read()
last_tick = sess:tick()
sess:setPwmDutycycle(pout, 1)
printf("duty cycle: %d", sess:getPwmDutycycle(pout))
wait(0.2)
sess:setPwmDutycycle(pout, 0)
printf("duty cycle: %d", sess:getPwmDutycycle(pout))

print("cleanup ...")
sess:setMode(pout, gpio.INPUT)
