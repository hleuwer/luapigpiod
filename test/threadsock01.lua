local gpio = require "pigpiod"
local util = require "test.test_util"
local wait = gpio.wait
local socket = require "socket"

local m = tonumber(os.getenv("m")) or 500
local n = tonumber(os.getenv("n")) or 2
local portbase = tonumber(os.getenv("port")) or 20000
local host = os.getenv("host") or "127.0.0.1"
local showhisto = os.getenv("hist") == "yes"
local hdt = 10

local function put_histogram(h, v)
   local ix = math.floor(v/hdt)
   h[ix] = (h[ix] or 0) + 1
end

local function disp_histogram(h, min, max)
   local min = math.floor(min/hdt)
   local max = math.floor(max/hdt)
   local nmax = 0
   for _,v in pairs(h) do
      if v then
         if v > nmax then nmax = v end
      end
   end
   local w = 50/nmax
   for i = min, max do
      local rep = (h[i] or 0)*w
      if h[i] == nil then
         print(string.format("%4d: |", i*hdt))
      else
         print(string.format("%4d: %s (%d)", i*hdt, string.rep("#", rep * w), h[i]))
      end
   end
end


local function code(host, port)
   return [[
local gpio = require "pigpiod"
local socket = require "socket"
local name, host, port = select(1, ...)
local sess = gpio.open()
pport = port
print(name .. ": Binding to host '" ..host.. "' and port " ..port.. "...")
udp = socket.udp()
udp:setsockname(host, port)
udp:settimeout(5)
ip, port = udp:getsockname()
print("Waiting packets on " .. ip .. ":" .. port .. "...")
while 1 do
  dgram, ip, port = udp:receivefrom()
  if dgram then
    dgram = dgram .. " "..sess:tick()
    udp:sendto(dgram, ip, port)
  else
    print(ip, pport)
  end
end
]]
end
-- Create session
local sess = gpio.open()

-- Create threads (echo servers) and client sockets
local sock, meas = {},{}
for i = 1,n do
   local mycode = code(host, portbase + i - 1)
   print("CODE:\n" .. mycode)
   local res = gpio.startThread(mycode, "srvThread-"..i, host, portbase + i - 1)
   sock[i] = socket.udp()
   sock[i]:setpeername(host, portbase + i - 1)
   sock[i]:settimeout(5)
end
print("Wait a second ...")
--collectgarbage("stop")
gpio.wait(1)
local seq = 0
for i = 1, n do
   meas[i] = {
      dtsmax=0, dtrmax=0, dtmax=0,
      dtsmin=1e6, dtrmin=1e6, dtmin=1e6,
      hdts = {}, hdtr = {}
   }   
end
local dts, dtr, dt
for j = 1,m do
   for i = 1, n do
      sock[i]:send(seq .. " " .. portbase + i - 1 .. " " .. sess:tick())
      seq = seq + 1
   end
   for i = 1, n do
      local s = meas[i]
      local dgram, err = sock[i]:receive() .. " " .. sess:tick()
      string.gsub(dgram, "(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)",
                  function(seq, port, t1, t2, t3)
                     --                     print(seq, port, t1, t2, t3)
                     dts, dtr, dt = t2-t1, t3-t2, t3-t1
                     if dts > s.dtsmax then s.dtsmax = dts end
                     if dts < s.dtsmin then s.dtsmin = dts end
                     if dtr > s.dtrmax then s.dtrmax = dtr end
                     if dtr < s.dtrmin then s.dtrmin = dtr end
                     if dt > s.dtmax then s.dtmax = dt end
                     if dt < s.dtmin then s.dtmin = dt end
                     put_histogram(s.hdts, dts)
                     put_histogram(s.hdtr, dtr)
                     print(string.format("seq=%5d port=%5d dTsend=%4d dTrecv=%4d dT=%4d",
                                         seq, port, t2-t1, t3-t2, t3-t1))
                  end
      )
   end
end
for i = 1, n do
   print("CON-"..i .. " min/max")
   local s = meas[i]
   print("send:", s.dtsmin .." us", s.dtsmax .." us")
   print("recv:", s.dtrmin .." us", s.dtrmax .." us")
   print("rtt: ", s.dtmin .." us", s.dtmax .." us")
   if showhisto == true then
      print("Histogram send latency 'dts':")
      disp_histogram(s.hdts, s.dtsmin, s.dtsmax)
      print("Histogram recv latency 'dtr':")
      disp_histogram(s.hdtr, s.dtrmin, s.dtrmax)
   end
end
