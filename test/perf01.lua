local gpio = require "pigpiod"
local host, port = "localhost", 8888

local sess = gpio.open(host, port)

local pinp, pout = 20, 21
local N = 10000
sess:setPullUpDown(pinp, gpio.PUD_UP)
sess:setMode(pinp, gpio.INPUT)
sess:setMode(pout, gpio.OUTPUT)

local t1 = os.clock()
for i = 1, N do
   sess:write(pout, 1)
   sess:write(pout, 0)
end
local t2 = os.clock()
print(string.format("pigpio did %d toggles per second", N/(t2-t1)))

sess:setMode(pout, gpio.INPUT)
