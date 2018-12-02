local gpio = require "pigpiod"
local util = require "test.test_util"
local posix = require "posix"
local wait = gpio.wait

local host, port = "localhost", 8888
local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local sess = gpio.open(host, port)
printf("Session with host %s on port %d opened, handle = %d", host, port, sess.handle)

print(gpio.info())

local pinp, pout = 20, 21

local x = 1
local last_tick
local cbcnt = 1

local notify = sess:notifyOpen()
local fname = notify.filename
--local fh = io.open(fname, "r")
local fd = posix.open(fname, posix.O_RDONLY)

---
--Alert callback.
---
local function alert(pi, pin, level, tick)
   local trcv = pi:tick()
   local tsnd = tick
   local tdel = trcv - tsnd
   local tper = tick - last_tick
   printf("ALERT callback %d: tsnd=%d us, trcv=%d us, tdel=%d us, tper=%d us, gpio=%d (ok=%s), level=%d gc=%.1f (%d)",
          cbcnt, tsnd, trcv, tdel, tper, pin, tostring(pin==pinp), level, collectgarbage("count"))
   if level == last_level then
      printf("   NOTE: level change not detected - input frequency probably too high!")
   end
   last_tick = tick
   last_level = level
   cbcnt = cbcnt +1 
end

print("set pin pullup ...")
sess:setPullUpDown(pinp, gpio.PUD_UP)
print("set pin to input ...")
sess:setMode(pinp, gpio.INPUT)
print("set pout to output ...")
sess:setMode(pout, gpio.OUTPUT)
--print("preset 1 ...")
--gpio.write(pout, 1)

local N = util.getNumber("Number of transitions: ", 20)
local ton = util.getNumber("T_on [ms]: ", 10)
local toff = util.getNumber("T_off [ms] ", 10)
local bitmode = util.getString("Bit mode (yes/no): ", "yes")
print("T_on:", ton)
print("T_off:", toff)
print("Bitmode:", bitmode)

print("set alert func ...")

local cb, err = assert(sess:callback(pinp, gpio.EITHER_EDGE, alert))
printf("  callback ID: %d", cb.id)

notify:begin(bit32.lshift(1, pinp))

last_tick = sess:tick()
local last_tick2 = last_tick
for i = 1, N do
   --   print("set 1")
   if bitmode == "yes" then
      sess:write(pout, 1)
   else
      sess:setBank1(bit32.lshift(1,pout))
   end
   wait(ton/1000)

   --   print("set 0")
   if bitmode == "yes" then
      sess:write(pout, 0)
   else
      sess:clearBank1(bit32.lshift(1, pout))
   end
   wait(toff/1000)
   if i == 5 then notify:pause() end
   if i == N - 5 then notify:begin(bit32.lshift(1,pinp)) end
   
end

print("Reading notification buffer ...")
-- Note: This will only return the first 10 and last 10 transitions - indpendently on
--       the number of total transitions.
while posix.rpoll(fd, 100) == 1 do
   local s = posix.read(fd, 12)
   local t = notify:decode(s)
   print(string.format("sample %d: flags=%04X tick=%d level=%08X dt=%d",
                       t.seqno, t.flags, t.tick, t.level, t.tick - last_tick2))
   last_tick2 = t.tick
end

print("close notification ...")
notify:close()

print("wait a second ...")
wait(1)

print("cleanup ...")
sess:setMode(pout, gpio.INPUT)
