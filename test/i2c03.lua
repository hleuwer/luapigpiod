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

local BUS = 1
local ID_REG = 0x0f
local N = 10000
local sensehat_i2c_devices = {
   hts221 = {
      addr = 0x5f
   },
   lps25h = {
      addr = 0x5c
   },
   other = {
      addr = 0x1c
   }
}

printf("Open I2C devices ...")
local dev0 = assert(sess:openI2C(BUS, sensehat_i2c_devices.hts221.addr, "HTS221"))
printf("  dev0: handle=%d, name=%q", dev0.handle, dev0.name)

printf("Reading block data SMBUS format (should fail)...")
local bdata, err = dev0:readBlockData(ID_REG)
if not bdata then
   printf("  err = %q", err)
end

printf("Reading block data I2C format...")
for i = 1, 32 do
   local bdata = assert(dev0:readI2CBlockData(ID_REG, i))
   io.stdout:write(string.format("  dev0: len=%d", #bdata))
   io.stdout:write("  ")
   for j = 1, #bdata do
      io.stdout:write(string.format("%0x ", string.byte(string.sub(bdata, j))))
   end
   print()
end
printf("Closing I2C devices ...")

dev0:close()

printf("Closing session ...")
sess:close()
