local gpio = require "pigpiod"
local posix = require "posix"
local sig = require "posix.signal"
local host = "localhost"
local remHost = "raspberrypi2"
local port = 8888

local signum = sig.SIGUSR1

local wait = gpio.wait

local eventindex = 1

local function printf(fmt, ...)
   print(string.format(fmt, ...))
end


local function cbfunc(pi, event, tick, udata)
   printf("EVENT CALLBACK %s: event=%d tick=%d udata=%q", pi.name, event, tick, udata.sess.name)
end

printf("Open session ...")
sess = gpio.open(host, port, "sess-me")
printf("Session %q with host %q on port %d opened, handle = %d",
       sess.name, host, port, sess.handle)

printf("Open notification channel ...")
local notify = sess:openNotify()
printf("  notify handle:%d", notify.handle)

printf("Open notification file ...")
local fd = posix.open(notify.filename, posix.O_RDONLY)
printf("  fd=%d", fd)

printf("Begin notifications ...")
notify:begin(eventindex)

printf("Register event callback %d ...", eventindex)
local cb, err = sess:eventCallback(eventindex, cbfunc, {sess = sess.me})
assert(cb, err)
printf("  callback handle: %d", cb.id)
printf("Wait a second ...")
wait(1)

printf("Trigger event index=%d to session.handle=%d ...", eventindex, sess.handle)
local res, err, errcode = sess:triggerEvent(eventindex)
printf("  res:%s err:%q errcode: %s", tostring(res), tostring(err), tostring(errcode))

printf("Wait a second ...")
wait(1)

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

printf("Cleanup ...")
printf("  Cancel event callback ...")
cb:cancel()

printf("  Close notification ...")
notify:close()

printf("  Close notification file ...")
posix.close(fd)

printf("  Closing session(s) ...")
sess:close()
