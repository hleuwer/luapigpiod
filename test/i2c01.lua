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
local REF_P_XL_REG = 0x08
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


printf("reading ID registers ...")
local dev0_id = assert(dev0:readByte(ID_REG))
printf("  dev0: id=0x%0x", dev0_id)

local dev1_id = assert(dev1:readByte(ID_REG))
printf("  dev1: id=0x%0x", dev1_id)

local dev2_id = assert(dev2:readByte(ID_REG))
printf("  dev2: id=0x%0x", dev2_id)

local dev3_id = assert(dev3:readByte(ID_REG))
printf("  dev3: id=0x%0x", dev3_id)

print("read ID register as words ...")
printf("  dev0..3: id (word)=0x%04x 0x%04x 0x%04x 0x%04x",
       dev0:readWord(ID_REG),
       dev1:readWord(ID_REG),
       dev2:readWord(ID_REG),
       dev3:readWord(ID_REG))

printf("write/read pressure sensor register (byte) " .. 0x08 .. " ...")
local defval = assert(dev1:readByte(REF_P_XL_REG))
printf("  dev read 1: ref_p=0x%0x", defval)
assert(dev1:writeByte(REF_P_XL_REG, 0x55))
local newval = assert(dev1:readByte(REF_P_XL_REG))
printf("  dev read 2: ref_p=0x%0x ok=%s", newval, tostring(newval == 0x55))
assert(dev1:writeByte(REF_P_XL_REG, defval))
local newval = assert(dev1:readByte(REF_P_XL_REG))
printf("  dev read 2: ref_p=0x%0x ok=%s", newval, tostring(newval == defval))

printf("write/read  pressure sensor register (word) (will fail) " .. 0x08 .. " ...")
local defval = assert(dev1:readWord(REF_P_XL_REG))
printf("  dev read 1: ref_p=0x%0x", defval)
assert(dev1:writeWord(REF_P_XL_REG, 0x55aa))
local newval = assert(dev1:readWord(REF_P_XL_REG))
printf("  dev read 2: ref_p=0x%0x ok=%s", newval, tostring(newval == 0x55aa))
assert(dev1:writeWord(REF_P_XL_REG, defval))
local newval = assert(dev1:readWord(REF_P_XL_REG))
printf("  dev read 2: ref_p=0x%0x ok=%s", newval, tostring(newval == defval))



printf("I2C performance test ...")
local t1 = os.clock()
for i = 1, N do
   dev0:readByte(ID_REG)
end
local t2 = os.clock()
printf("i2c reads per second: %d", N/(t2-t1))
printf("Closing I2C devices ...")

dev0:close()
dev1:close()
dev2:close()
dev3:close()

printf("Closing session ...")
sess:close()
