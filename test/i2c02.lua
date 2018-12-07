local gpio = require "pigpiod"
local host, port = "localhost", 8888
local wait = gpio.wait
local host, port = "localhost", 8888
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port)
printf("Session with host %s on port %d opened, handle = %d", host, port, sess.handle)

printf("Note: This test requires a sensehat board.")

for bus = 0, 1 do
   printf("Scanning i2c bus %d ...", bus)
   local devs, err = sess:scanI2C(bus)
   if devs then
      for k,v in pairs(devs) do
         printf("bus=%d: addr=0x%02x data=0x%02x status=%q", bus, v.addr, v.data, v.status)
      end
   else
      printf("bus=%d: %s", bus, err)
   end
end
printf("Closing session ...")
sess:close()
