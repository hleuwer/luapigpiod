local gpio = require "pigpiod"
local sleep = gpio.sleep
local host, port = "localhost", 8888

local pi = gpio.open(host, port)

local function getNumber(prompt, default)
   local n
   repeat
      io.write(string.format("%s [%.2f]: ", prompt, default))
      io.flush()
      local s = io.read("*l")
      if #s == 0 then
         return default
      end
      n = tonumber(s)
   until type(n) == "number"
--   print(n, type(n))
   return n
end

print("Setting mode to 'BCM' ...")
--gpio.setmode(gpio.BCM)
--gpio.setwarnings(1)
local coil_A_1_pin = 27  -- pink
local coil_A_2_pin = 17 -- orange
local coil_B_1_pin = 23 -- blau
local coil_B_2_pin = 24 -- gelb
-- #enable_pin   = 7 # Nur bei bestimmten Motoren benoetigt (+Zeile 24 und 30)
 
-- # anpassen, falls andere Sequenz
local StepCount = 8
local _Seq = {
   {0,1,0,0},
   {0,1,0,1},
   {0,0,0,1},
   {1,0,0,1},
   {1,0,0,0},
   {1,0,1,0},
   {0,0,1,0},
   {0,1,1,0}
} 
local Seq = {
   {0,0,0,1},
   {0,0,1,1},
   {0,0,1,0},
   {0,1,1,0},
   {0,1,0,0},
   {1,1,0,0},
   {1,0,0,0},
   {1,0,0,1}
} 

local function cleanup()
   pi:setMode(coil_A_1_pin, gpio.INPUT)
   pi:setMode(coil_A_2_pin, gpio.INPUT)
   pi:setMode(coil_B_1_pin, gpio.INPUT)
   pi:setMode(coil_B_2_pin, gpio.INPUT)
end

-- gpio.setup(enable_pin, gpio.OUT)
print("Setting up IO pins ...")
pi:setMode(coil_A_1_pin, gpio.OUTPUT)
pi:setMode(coil_A_2_pin, gpio.OUTPUT)
pi:setMode(coil_B_1_pin, gpio.OUTPUT)
pi:setMode(coil_B_2_pin, gpio.OUTPUT)
 
-- gpio.output(enable_pin, 1)
 
local function setStep(n, w1, w2, w3, w4)
--   print("setStep:", n, w1, w2, w3, w4)
   pi:write(coil_A_1_pin, w1)
   pi:write(coil_A_2_pin, w2)
   pi:write(coil_B_1_pin, w3)
   pi:write(coil_B_2_pin, w4)
end

local function forward(delay, steps)
   print("Stepping forward ".. steps)
   for i = 1, steps do
      for j = 1, StepCount do
         setStep(i, Seq[j][1], Seq[j][2], Seq[j][3], Seq[j][4]) 
         sleep(delay)
      end
   end
end

local function backwards(delay, steps)
   print("Stepping backwards ".. steps)
   for i = 1, steps do
      for j = StepCount, 1, -1 do
         setStep(i, Seq[j][1], Seq[j][2], Seq[j][3], Seq[j][4]) 
         sleep(delay)
      end
   end
end

local function main()
   local delay, steps, dir = 1, math.random(1,512), math.random(0,1)
   delay = getNumber("Delay in ms?", delay)
   while true do
      for i = 1, math.random(5) do
         steps = math.random(1,5*i)
         dir = math.random(0,1)
         if dir == 0 then
            forward(delay/1000, steps)
         else
            backwards(delay/1000, steps)
         end
      end
   end
end

main()

