local gpio = require "pigpiod"
local pretty = require "pl.pretty"
local host, port = "localhost", 8888
local wait = gpio.wait
local host, port = "localhost", 8888
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port)
printf("Session with host %s on port %d opened, handle = %d", host, port, sess.handle)

local dev = sess:openI2CSlave(0x13,"myslave")

while true do
   printf("Start slave transfer ...")
   local rdata, status = dev:transfer(string.char(0xa0, 0xa1, 0xa2, 0xa3, 0xa4))
   if rdata == nil then
      printf("ERROR: %s", status)
   else
      printf("len rdata: %d; status: 0x%04x", #rdata, status)
      print(string.byte(rdata, 1, #rdata))
      local t = dev:convertStatus(status)
      printf("status: %s", pretty.write(t))
   end
   io.stdout:write("Hit return ...")
   s = io.stdin:read("*l")
   if s == "exit" then break end
--   wait(0.5)
end

printf("Closing session ...")
assert(dev:close())
assert(sess:close())
