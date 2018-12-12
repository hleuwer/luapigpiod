local gpio = require "pigpiod"
local wait = gpio.wait

local TTYDEV = "/dev/serial0"
local baudrates = gpio.baudrates

local dest = {
   me = {host = "localhost", port = 8888},
   you = {host = "raspberrypi2", port = 8888}
}
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = {}

local sendbuf = ""
for i = 1, 16*1024 do
   sendbuf = sendbuf .. string.char(0x55) .. string.char(0xaa)
end

printf("Open sessions ...")

sess.me = gpio.open(dest.me.host, dest.me.port, "sess-me")
printf("Session %q with host %q on port %d opened, handle = %d",
       sess.me.name, dest.me.host, dest.me.port, sess.me.handle)

sess.you = gpio.open(dest.you.host, dest.you.port, "sess-you")
printf("Session %q with host %q on port %d opened, handle = %d",
       sess.you.name, dest.you.host, dest.you.port, sess.you.handle)

for _, baudrate in ipairs(baudrates) do
   printf("Open serial devices with baudrate %d ...", baudrate)
   local dev = {}

   dev.me = sess.me:openSerial(baudrate, TTYDEV)
   printf("   dev.me: handle=%d pihandle=%d", dev.me.handle, dev.me.pihandle)
   
   dev.you = sess.you:openSerial(baudrate, TTYDEV)
   printf("   dev.you: handle=%d pihandle=%d", dev.you.handle, dev.you.pihandle)
   
   printf("Send single byte ...")
   assert(dev.me:writeByte(0x55))
   local t0 = gpio.time()
   while dev.you:dataAvailable() == 0 do
      assert(gpio.time() - t0 < 1)
   end
   assert(dev.you:readByte() == 0x55)
   
   printf("Send messages of different length (note: 4095 is max possible burst len) ...")
   local fmt = string.format
   for _, len in ipairs{1,32,64,256,512,1024,2048,4095} do
      local ds = string.sub(sendbuf, 1, len)
      local ns = #ds
      local te = len * 10 / baudrate 
      io.stdout:write(fmt("  Send %d bytes (%.2f sec) ...", ns, te)) io.stdout:flush()
      local t0 = gpio.time()
      assert(dev.me:write(ds))
      local nr = assert(dev.you:dataAvailable())
      while nr < ns do
         nr = dev.you:dataAvailable()
      end
      local dr = assert(dev.you:read(ns))
      dt = gpio.time() - t0
      printf(" recv %d bytes (%.2f sec) gc: %d %d", #dr, dt, collectgarbage("count"))
   end
   printf("  Closing serial devices ...")
   dev.me:close()
   dev.you:close()
end
print("Cleanup ...")

printf("  Closing sessions ...")
sess.me:close()
sess.you:close()
