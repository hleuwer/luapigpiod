local gpio = require "pigpiod"
local socket = require "socket"

function printf(fmt, ...)
   print(string.format(fmt, ...))
end

local M = {}
_ENV = setmetatable(M, {__index = _G})

tsleep=0.001
sec = 1e6
msec = 1e6/1000
usec = 1

function getNumber(prompt, default)
   local n
   repeat
      io.write(string.format("%s [%.2f]: ", prompt, default))
      io.flush()
      local s = io.read("*l")
      if #s == 0 then
         return default
      end
      n = tonumber(s)
   until type(n) == "number"
   return n
end

function getString(prompt, default)
   local n
   io.write(string.format("%s [%s]: ", prompt, default))
   io.flush()
   local s = io.read("*l")
   if #s == 0 then
      return default
   end
   return s   
end

function intro_1()
   printf("%s",gpio.info())
end

return _ENV
