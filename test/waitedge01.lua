local gpio = require "pigpiod"
local util = require "test.test_util"
local wait = gpio.wait
local N = tonumber(os.getenv("n") or "10") 
local your = os.getenv("your") or "yes"
local detectorCode = [[
local name, maxedges = select(1, ...)
local nedges = 0
print("detector: Hi, I am '"..name.."'. Max edges:", maxedges)
local gpio = require "pigpiod"
local sess = gpio.open("localhost", 8888, "Detector")
print("detector: session opened", sess.handle, sess.name)
while (true) do
  print("detector: Waiting for edge ...")
  local res, err = sess:waitEdge(20, gpio.EITHER_EDGE, 1)
  if not res then 
     print("detector: Error:", err) 
     break
  else
     print("detector: Edge detected!", nedges)
  end
  nedges = nedges + 1
end
print("detector: done - Bye!")
]]

print("Start detection thread ...")
local detector = gpio.startThread(detectorCode, "detector", 10)
print("  res:", detector);

local sess = gpio.open("localhost", 8888)


local pinp, pout = 20, 21

printf("Set pin pullup ...")
sess:setPullUpDown(pinp, gpio.PUD_UP)

printf("Set pin to input ...")
sess:setMode(pinp, gpio.INPUT)

printf("Set pout to output ...")
sess:setMode(pout, gpio.OUTPUT)

for i = 1, N do
   printf("Writing 1 ...")
   sess:write(pout, 1)
   wait(0.05)
   printf("Writing 0 ...")
   sess:write(pout, 0)
   wait(0.05)
end
printf("Wait for detector timeout ...")
wait(2)
printf("Cleanup ...")
--assert(gpio.stopThread(detector))
sess:setMode(pout, gpio.INPUT)
sess:close()
