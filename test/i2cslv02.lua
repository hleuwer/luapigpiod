local gpio = require "pigpiod"
local pretty = require "pl.pretty"
local host, port = "localhost", 8888
local host2, port2 = "raspberrypi", 8888
local wait = gpio.wait
local host, port = "localhost", 8888
local i2cAddr = 0x13
local N = tonumber(os.getenv("n") or "5")
local cbcnt, ecnt = 0, 0
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port, "primary session")
local sess2 = gpio.open(host2, port2, "secondary session")

local slv = sess:openI2CSlave(i2cAddr,"slave")
local mst = sess2:openI2C(1, i2cAddr, "master")
local eventindex = 31
local mdata = string.char(0x11,0x22,0x33,0x44,0x55, 1, 2, 3 , 4)
local sdata = string.char(0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0x10, 0x20)

local function cbfunc(pi, event, tick, udata)
--   printf("EVENT CALLBACK %q: cnt=%d ecnt=%d event=%d tick=%d udata=%q",
--          pi.name, cbcnt, ecnt, event, tick, udata.sess.name)
   local rdata, status = slv:transfer()
   if rdata then
      print("  SLAVE:", #rdata, string.format("%04x", status), string.byte(rdata, 1, #rdata))
   else
      print("  SLAVE: no data")
   end
   if #rdata == 0 then
      ecnt = ecnt + 1
   end
   cbcnt = cbcnt + 1
--   assert(slv:transfer(sdata))
end

local cb, err = sess:eventCallback(eventindex, cbfunc, {sess = slv})
assert(cb, err)

-- 1. prepare slave for transfer
print("1. Prepare slave ...")
assert(slv:transfer())

-- 2. master write
print("2. Master sends data ...")
assert(mst:writeDevice(mdata))

for i = 1, N do
   assert(mst:writeDevice(mdata))
--   wait(0.5)
--   local rdata = mst:readDevice(8)
--   print("MASTER:", string.byte(rdata, 1, #rdata))
end

print("Wait a second ...")
wait(1)

printf("Closing session ...")
assert(mst:close())
assert(slv:close())
assert(sess:close())
