local gpio = require "pigpiod"
local util = require "test.test_util"
local wait = gpio.wait
local socket = require "socket"

local your = os.getenv("your") or "yes"

local host, port = "127.0.0.1", 20000

local my_code = [[
local name, host, port = select(1, ...)
print("Hi, I am '"..name.."' on "..host..":"..port)
local gpio = require "pigpiod"
local socket = require "socket"
local sock = socket.udp()
while (true) do
  io.stdout:write(name .. " > ")
  io.stdout:flush()
  s = io.stdin:read()
  if s == "exit" then
    local res = sock:sendto("exit", host, port)
    break
  end
  print("echo: "..s)
  print("waiting...")
  gpio.wait(1)
end
sock:close()
print("thread '" .. name .. "'exiting")
]]

local your_code = [[
local gpio = require "pigpiod"
local name = select(1, ...)
print("Hi, I am '" .. name .. "'")
while true do
--  print("Wait a second in '"..name.."'...")
  gpio.wait(1)
--  os.execute("sleep 1")
end
]]

local sock = socket.udp()
sock:setsockname(host,port)

print("Start my_thread ...")
local mythread = gpio.startThread(my_code, "my_thread", "127.0.0.1", 20000)
print("  res (my_thread)  :", mythread);
local yourthread, yourthread_2

if your == "yes" then
   print("Start your_thread ...")
   yourthread = gpio.startThread(your_code, "your_thread")
   print("  res (your_thread):", yourthread)

   print("Start your_thread 2 ...")
   yourthread_2 = gpio.startThread(your_code, "your_thread_2")
   print("  res (your_thread_2):", yourthread_2)
end

print("Start your_thread 3 with invalid parameter  ...")
local status, result = pcall(gpio.startThread, your_code, "your_thread_3", {1,2,3})
if not status then print(status, result) end
--
-- Try to start a second instance of my_code with same name - should fail
-- We capture error to leave script alive
-- 
print("Start my_thread again - should fail ...")
local status, result = pcall(gpio.startThread, my_code, "my_thread", 2, "duda")
if not status then print(status, result) end
while true do
   local dgram, ip, port = sock:receivefrom()
   if dgram == "exit" then
      if your == "yes" then
         print("Stop your_thread by name ...")
         gpio.stopThread("your_thread")
         print("Stop your_thread_2 by thread instance ...")
         gpio.stopThread(yourthread_2)
      end
      break;
   end
end
print("main thread exits ...")
sock:close()
