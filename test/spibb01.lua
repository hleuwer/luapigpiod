local gpio = require "pigpiod"
local util = require "test.test_util"
local wait = gpio.wait
local host, port = "localhost", 8888

local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local function mkmsg(d, n, random)
   local t = {}
   for i = 1, n do
      if random == true then
         table.insert(t, string.char(math.random(0,255)))
      else
         table.insert(t, string.char(d))
      end
   end
   return table.concat(t)
end

local devs = {}

local MOSI, MISO, CS, SCLK = 21, 20, {5, 26}, 13

local msize = tonumber(os.getenv("n") or "16")
local rate = tonumber(os.getenv("r") or "100") * 1000

local sendbuf = mkmsg(0x55, msize)
local nullbuf = mkmsg(0x00, msize)
local randombuf = mkmsg(0x00, msize, true)

local sess = assert(gpio.open(host, port))
printf("Session with host %s on port %d opened, handle = %d", host, port, sess.handle)
for i = 1, 2 do
   local dev = assert(sess:openSPIbb(CS[i], MISO, MOSI, SCLK, rate, 0, "mySPIbb:"..i))
   printf("  Device %s opened on CS=%d MOSI=%d MISO=%d SCLK=%d with rate of %d kbps, handle = %d",
          dev.name, dev.cs, dev.mosi, dev.miso, dev.sclk, rate/1000, dev.handle)
   devs[i] = dev
end

for i = 1, 2 do
   printf("Transfer message (receive = transmit = random) of len=%d bytes ...", #randombuf)
   local rxb, err = devs[i]:transfer(randombuf)
   assert(rxb, err)
   --print("randbuf:", string.byte(randombuf, 1, #randombuf))
   --print("rxb    :", string.byte(rxb, 1, #rxb or "nil"))
   assert(rxb == randombuf)
end
for i = 1, 2 do
   printf("Transfer message (receive = transmit = const) ...")
   local rxb, err = devs[i]:transfer(sendbuf)
   assert(rxb, err)
   --print("sendbuf:", string.byte(sendbuf, 1, #sendbuf))
   --print("rxb    :", string.byte(rxb, 1, #rxb))
   assert(rxb == sendbuf)
end

print("cleanup ...")
for i=1,2 do devs[i]:close() end
sess:close()
