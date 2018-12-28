local gpio = require "pigpiod"
local pretty = require "pl.pretty"
local host, port = "localhost", 8888
local host2, port2 = "raspberrypi", 8888
local wait = gpio.wait
local host, port = "localhost", 8888
local i2cAddr = 0x13
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port)
local sess2 = gpio.open(host2, port2)

local slv = sess:openI2CSlave(i2cAddr,"slave")
local mst = sess2:openI2C(1, i2cAddr, "master")
local ix = 1

local _sdata = {
   "012345",
   "543210"
}
local _mdata = {
   "0123456",
   "6543210"
}
   
while true do
   local sdata, mdata = _sdata[ix], _mdata[ix]
   ix = ix + 1
   if ix == 3 then ix = 1 end
   printf("1. slv transfer:%q", sdata)
   local rdata, status = slv:transfer(sdata)
   if rdata == nil then
      printf("ERROR SLAVE: %s", status)
   else
      printf("SLAVE: len rdata: %d; rdata: %q; status: 0x%04x", #rdata, rdata, status)
      print("  =>", string.byte(rdata, 1, #rdata))
--      local t = slv:convertStatus(status)
--      printf("status: %s", pretty.write(t))
   end
   print("2. mst read")
   rdata = mst:readDevice(#sdata)
   if rdata == nil then
      printf("ERROR MASTER: %s", err)
   else
      printf("MASTER: len rdata: %d; rdata: %q", #rdata, rdata)
      print("  =>", string.byte(rdata, 1, #rdata))
   end
--   wait(0.5)
   printf("3. mst write:%q", mdata)
   assert(mst:writeDevice(mdata))
   io.stdout:write("Hit return ...")
   s = io.stdin:read("*l")
   if s == "exit" then break end
end

printf("Closing session ...")
assert(mst:close())
assert(slv:close())
assert(sess:close())
