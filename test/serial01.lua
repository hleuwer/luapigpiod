local gpio = require "pigpiod"
local wait = gpio.wait

local TTYDEV = "/dev/serial0"
local baudrates = {9600, 19200, 38400, 57600, 115200, 230400}

local dest = {
   me = {host = "localhost", port = 8888},
   you = {host = "raspberrypi2", port = 8888}
}
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = {}

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
   
   printf("Send messages of different length ...")
   for _, len in ipairs{1,32,64} do
      local ds = ""
      for i = 1, len do ds = ds .. "a" end
      local ns = #ds
      printf("  Send %d bytes ...", ns)
      assert(dev.me:write(ds))
      local nr = assert(dev.you:dataAvailable())
      local t0 = gpio.time()
      while nr < ns do
         nr = dev.you:dataAvailable()
         assert(gpio.time() - t0 < 5)
      end
      local dr = assert(dev.you:read(nr))
      printf("  Recv %d bytes", #dr)
   end
   printf("  Closing serial devices ...")
   dev.me:close()
   dev.you:close()
   wait(1)
end
print("Cleanup ...")

printf("  Closing sessions ...")
sess.me:close()
sess.you:close()
