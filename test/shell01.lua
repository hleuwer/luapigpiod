local gpio = require "pigpiod"
local util = require "test.test_util"
local wait = gpio.wait
local host, port = "localhost", 8888

local function printf(fmt, ...)
   print(string.format(fmt, ...))
end
local fname = "/tmp/shell_example_log"

local sess = gpio.open(host, port)
printf("Session with host %s on port %d opened, handle = %d", host, port, sess.handle)

printf("executing shell command ...")
local ret, err = sess:shell("shell_example", "Welcome to luaPIGPIOD")

local f = io.open(fname, "r")
printf("  output: %s", f:read("*a"))
os.execute("sudo rm ".. fname)
sess:close()
