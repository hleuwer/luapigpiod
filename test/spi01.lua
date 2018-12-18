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

local msize = tonumber(os.getenv("n") or "16")
local rate = tonumber(os.getenv("r") or "100") * 1000

local sendbuf = mkmsg(0x55, msize)
local nullbuf = mkmsg(0x00, msize)
local randombuf = mkmsg(0x00, msize, true)

local sess = assert(gpio.open(host, port))
printf("Session with host %s on port %d opened, handle = %d", host, port, sess.handle)

local dev = assert(sess:openSPI(0, rate, 0, "mySPI"))
printf("Device %s opened on channel 0 with rate of %d kbps, handle = %d", dev.name, rate/1000, dev.handle)

printf("Sending message of len=%d bytes (no receive check) ...", #sendbuf)
assert(dev:write(sendbuf))

printf("Receive message (check all 0) of len=%d bytes ...", #nullbuf)
local rxb = dev:read(#nullbuf)
print("nullbuf:", string.byte(nullbuf, 1, #nullbuf))
print("rxb    :", string.byte(rxb, 1, #rxb))
assert(rxb == nullbuf)

printf("Transfer message (receive = transmit = random) of len=%d bytes ...", #randombuf)
rxb = dev:transfer(randombuf)
print("randbuf:", string.byte(randombuf, 1, #randombuf))
print("rxb    :", string.byte(rxb, 1, #rxb))
assert(rxb == randombuf)

printf("Transfer message (receive = transmit = const) ...")
rxb = dev:transfer(sendbuf)
print("sendbuf:", string.byte(sendbuf, 1, #sendbuf))
print("rxb    :", string.byte(rxb, 1, #rxb))
assert(rxb == sendbuf)


print("cleanup ...")
dev:close()
sess:close()
