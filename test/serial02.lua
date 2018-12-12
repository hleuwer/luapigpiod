local gpio = require "pigpiod"
local wait = gpio.wait

local arg = {select(1, ...)}
local index = tonumber(arg[1] or "3")
local kb = tonumber(arg[2] or "10")
assert(index > 0 and index < 7, "index must be 1..6")
local TTYDEV = "/dev/serial0"
local baudrate = gpio.baudrates[index]

local dest = {
   you = {host = "localhost", port = 8888},
   me = {host = "raspberrypi2", port = 8888}
}
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = {}

local sendbuf = ""
local t = {}
for i = 1, kb*1024 do
   table.insert(t, string.char(0x55))
--   sendbuf = sendbuf .. string.char(0x55) .. string.char(0xaa)
end
sendbuf = table.concat(t)

printf("Will transmit %d kBytes with %d bit/s. Hit return to continue ...", kb, baudrate)
io.stdin:read()


printf("Open sessions ...")

sess.me = gpio.open(dest.me.host, dest.me.port, "sess-me")
printf("Session %q with host %q on port %d opened, handle = %d",
       sess.me.name, dest.me.host, dest.me.port, sess.me.handle)

sess.you = gpio.open(dest.you.host, dest.you.port, "sess-you")
printf("Session %q with host %q on port %d opened, handle = %d",
       sess.you.name, dest.you.host, dest.you.port, sess.you.handle)

printf("Open serial devices with baudrate %d ...", baudrate)
local dev = {}

dev.me = sess.me:openSerial(baudrate, TTYDEV)
printf("   dev.me: handle=%d pihandle=%d", dev.me.handle, dev.me.pihandle)

dev.you = sess.you:openSerial(baudrate, TTYDEV)
printf("   dev.you: handle=%d pihandle=%d", dev.you.handle, dev.you.pihandle)

local txsum, left, chunk = 1, kb*1024, 256

receiver = coroutine.wrap(function()
      local rxbytes = 0
      local rxsum = 0
      while true do
         rxbytes = dev.you:dataAvailable()
         if rxbytes > 0 then
            rxdata = dev.you:read(rxbytes)
            rxsum = rxsum + #rxdata
            coroutine.yield(rxsum, #rxdata)
         end
      end
end)

local rxsum, rxbytes = 0, 0
while left > 0 do
   ds = string.sub(sendbuf, txsum, txsum + chunk)
   dev.me:write(ds)
   txsum = txsum + #ds
   rxsum, rxbytes = receiver()
   left = left - chunk
   if left < chunk then
      chunk = left
   end
   printf("bytes received: rxsum=%d rxbytes=%d txsum=%d left=%d chunk=%d", rxsum, rxbytes, txsum-1, left, chunk)
end

printf("Emptying receiver ...")
repeat
   rxsum, rxbytes = receiver()
   printf("bytes received: rxsum=%d rxbytes=%d txsum=%d left=%d", rxsum, rxbytes, txsum-1, left)
   wait(0.2) -- wait for better utilization of receive buffer
until rxsum >= txsum-1

print("Cleanup ...")
printf("  Closing sessions ...")
sess.me:close()
sess.you:close()
