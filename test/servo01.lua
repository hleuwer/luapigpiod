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

local step = tonumber(os.getenv("p") or 1500)
-- not required: local freq = tonumber(os.getenv("f") or 20)

print(gpio.info())

local pinp, pout = 20, 21

sess:setMode(pinp, gpio.INPUT)
sess:setMode(pout, gpio.OUTPUT)

local count = 1
local cbcnt = 1

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

-- not required: local freq = util.getNumber("Frequency [Hz]:", freq)
local step = util.getNumber("PulseWidth [500..2500]:", step)
-- not required: sess:setPwmFrequency(pout, freq)
assert(sess:setServoPulsewidth(pout, step))
-- not required: printf("PWM frequency: %d", sess:getPwmFrequency(pout))
printf("Pulse width: %d", sess:getServoPulsewidth(pout))


last_tick = sess:tick()
local cb, err = assert(sess:callback(pinp, gpio.EITHER_EDGE, alert))
printf("  callback ID: %d", cb.id)
wait(0.2)

print("cleanup ...")
sess:setMode(pout, gpio.INPUT)
