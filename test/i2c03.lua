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
   lsm90s1_a = {
      addr = 0x6a
   },
   lsm90s1_m = {
      addr = 0x1c
   },
   other = {
      addr = 0x1c
   }
}

printf("Open I2C devices ...")
local dev0 = assert(sess:openI2C(BUS, sensehat_i2c_devices.hts221.addr, "HTS221 Humidity"))
printf("  dev0: handle=%d, name=%q", dev0.handle, dev0.name)
local dev1 = assert(sess:openI2C(BUS, sensehat_i2c_devices.lps25h.addr, "LPS25H Pressure"))
printf("  dev1: handle=%d, name=%q", dev1.handle, dev1.name)
local dev2 = assert(sess:openI2C(BUS, sensehat_i2c_devices.lsm90s1_a.addr, "LSM90S1 Accelerometer"))
printf("  dev2: handle=%d, name=%q", dev2.handle, dev2.name)
local dev3 = assert(sess:openI2C(BUS, sensehat_i2c_devices.lsm90s1_m.addr, "LSM90S1 Magentometer"))
printf("  dev3: handle=%d, name=%q", dev3.handle, dev3.name)

printf("Reading block data SMBUS format (should fail: block read on SMBUS device not supported) ...")
local bdata, err = dev0:readBlockData(ID_REG)
if not bdata then
   printf("  err = %q", err)
end

printf("Reading block data I2C format...")
for i = 1, 32 do
   local bdata = assert(dev3:readI2CBlockData(ID_REG, i))
   io.stdout:write(string.format("  dev3: len=%2d", #bdata))
   io.stdout:write("  ")
   for j = 1, #bdata do
      io.stdout:write(string.format("%02x ", string.byte(string.sub(bdata, j))))
   end
   print()
end

printf("Writing block data I2C format...")
local reg = 0x05
local tdata = "abcdefg"
local ddata = assert(dev3:readI2CBlockData(reg, 6))
printf("  read len: %d ddata: %q", #ddata, ddata)
assert(dev3:writeI2CBlockData(reg, tdata))
local rdata, err = assert(dev3:readI2CBlockData(reg, 6))
printf("  read len: %d rdata: %q", #rdata, rdata)
assert(dev3:writeI2CBlockData(reg, ddata))
local rdata, err = assert(dev3:readI2CBlockData(reg, 6))
printf("  read len: %d rdata: %q", #rdata, rdata)
--assert(dev3:writeI2CBlockData(reg, string.char(0,0,0,0,0,0)))

printf("Closing I2C devices ...")

dev0:close()
dev1:close()
dev2:close()
dev3:close()

printf("Closing session ...")
sess:close()
