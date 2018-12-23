local gpio = require "pigpiod"
local posix = require "posix"
local host = "localhost"
local port = 8888

local function printf(fmt, ...)
   print(string.format(fmt, ...))
end

printf("Open session ...")
sess = gpio.open(host, port, "mysess")
printf("   Session %q with host %q on port %d opened, handle = %d",
       sess.name, host, port, sess.handle)

printf("Retrieve list of files ...")
local flist = assert(sess:listFiles("/usr/lib/*"))
printf("   Found %d entries in %q", #flist, "/usr/lib")

printf("Creating 100 files in /home/leuwer/tmp ...")
for i=1,10 do
   os.execute(string.format("echo '%d' > /home/leuwer/tmp/file_%s", i,i))
end
printf("Retrieving list of files ...")
flist = assert(sess:listFiles("/home/leuwer/tmp/file_*"))
assert(#flist == 10)
printf("   ok - found %d entries", #flist)

printf("Deleting files again ...")
for i=1,10 do
   os.execute(string.format("rm /home/leuwer/tmp/file_%s", i))
end
local ts = "1234567890"

printf("Creating a new file ...")
local openflags = bit32.bor(gpio.FILE_RW, gpio.FILE_CREATE)
local f = assert(sess:openFile("/home/leuwer/tmp/example.txt", openflags))

printf("Writing ...")
assert(f:write(ts))

printf("Position to begin of file ...")
printf("Reading ...")
res = assert(f:seek(0, gpio.FROM_START))
local s = assert(f:read(100))
assert(s==ts)

printf("Seeking ...")
res = assert(f:seek(5, gpio.FROM_START))

printf("Reading ...")
s = assert(f:read(100))
assert(#s ==5)
assert(s == string.sub(ts,6,#ts))

printf("Cleanup ...")
printf("  Closing file ...")
f:close()
printf("  Closing session(s) ...")
sess:close()
