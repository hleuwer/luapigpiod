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

printf("Reading ID registers ...")
local dev0_id = assert(dev0:readByte(ID_REG))
printf("  dev0: id=0x%0x %s", dev0_id, dev0.name)

local dev1_id = assert(dev1:readByte(ID_REG))
printf("  dev1: id=0x%0x %s", dev1_id, dev1.name)

local dev2_id = assert(dev2:readByte(ID_REG))
printf("  dev2: id=0x%0x %s", dev2_id, dev2.name)

local dev3_id = assert(dev3:readByte(ID_REG))
printf("  dev3: id=0x%0x %s", dev3_id, dev3.name)

print("Read ID registers as words ...")
printf("  Note: this works only for dev2 and dev3!")
printf("  dev0..3: id (word)=0x%04x 0x%04x 0x%04x 0x%04x",
       dev0:readWord(ID_REG),
       dev1:readWord(ID_REG),
       dev2:readWord(ID_REG),
       dev3:readWord(ID_REG))

local reg = REF_P_XL_REG
printf("Write/read register (byte) reg=0x%02x ...", reg)
local defval = assert(dev1:readByte(reg))
printf("  dev read 1: ref_p=0x%02x", defval)
assert(dev1:writeByte(reg, 0x55))
local newval = assert(dev1:readByte(reg))
printf("  dev read 2: ref_p=0x%02x ok=%s", newval, tostring(newval == 0x55))
assert(dev1:writeByte(reg, defval))
local newval = assert(dev1:readByte(reg))
printf("  dev read 2: ref_p=0x%02x ok=%s", newval, tostring(newval == defval))

local reg = REF_P_XL_REG
printf("Write/read register (word) reg=0x%02x (will fail on this device: %q) ...", reg, dev1.name)
local defval = assert(dev1:readWord(reg))
printf("  dev read 1: ref_p=0x%04x", defval)
assert(dev1:writeWord(reg, 0x55aa))
local newval = assert(dev1:readWord(reg))
printf("  dev read 2: ref_p=0x%04x ok=%s", newval, tostring(newval == 0x55aa))
assert(dev1:writeWord(reg, defval))
local newval = assert(dev1:readWord(reg))
printf("  dev read 2: ref_p=0x%04x ok=%s", newval, tostring(newval == defval))

local reg = 0x05
printf("Write/read register (word) reg=0x%02x (works on this device: %q) ...", reg, dev3.name)
local defval = assert(dev3:readWord(reg))
printf("  dev read 1: ref_p=0x%04x", defval)
assert(dev3:writeWord(reg, 0x55aa))
local newval = assert(dev3:readWord(reg))
printf("  dev read 2: ref_p=0x%04x ok=%s", newval, tostring(newval == 0x55aa))
assert(dev3:writeWord(reg, defval))
local newval = assert(dev3:readWord(reg))
printf("  dev read 2: ref_p=0x%04x ok=%s", newval, tostring(newval == defval))

printf("I2C performance test: %d samples ...", N)
local t1 = os.clock()
for i = 1, N do
   dev0:readByte(ID_REG)
end
local t2 = os.clock()
printf("i2c reads per second: %d", N/(t2-t1))

printf("Closing I2C devices (optional, will be automatically closed when closing session) ...")
dev0:close()
dev1:close()
dev2:close()
dev3:close()

printf("Closing session ...")
sess:close()
