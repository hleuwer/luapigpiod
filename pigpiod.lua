--------------------------------------------------------------------------------
-- A Lua wrapper for the pigpiod C interface.
-- Luapigpiod allows control of Raspberry Pi GPIO pins from userspace.
-- All operation are handled in the context of sessions (aka connections) or
-- in the context of subusidiary classes like waves, scripts, callbacks,
-- eventCallback, I2C, Serial or SPI devices.
-- Multiple sessions and thus multiple sets of GPIO pins or interfaces (one set
-- per session) are supported.
-- @module pigpiod
-- @author Herbert Leuwer
-- @copyright (c) Herbert Leuwer, 2018
-- @license MIT
--------------------------------------------------------------------------------

local gpio = require "pigpiod.core"

-- some optimizations
local strbyte = string.byte

---
-- Wave modes Lua => C:
local waveModes = {
   ["oneshot"] = gpio.WAVE_MODE_ONE_SHOT,
   ["repeat"] = gpio.WAVE_MODE_REPEAT,
   ["oneshotsync"] = gpio.WAVE_MODE_ONE_SHOT_SYNC,
   ["repeatsync"] = gpio.WAVE_MODE_REPEAT_SYNC
}

---
-- Script status: C => Lua
local scriptStati = {
   [gpio.SCRIPT_INITING] = "init",
   [gpio.SCRIPT_HALTED] = "halted",
   [gpio.SCRIPT_RUNNING] = "running",
   [gpio.SCRIPT_WAITING] = "waiting",
   [gpio.SCRIPT_FAILED] = "failed"
}

--
-- Pinnings of various Raspberry Pi models.
local pinnings = {
   [1] = [[
* Type 1 - Model B (original model)
  - 26 pin header (P1).
  - Hardware revision numbers of 2 and 3.
  - User GPIO 0-1, 4, 7-11, 14-15, 17-18, 21-25.

Signal	GPIO 	pin 	pin 	GPIO 	Signal
----------------------------------------------
3V3 	- 	1 	2 	- 	5V
SDA 	0	3 	4 	- 	5V
SCL 	1	5 	6 	- 	Ground
	4 	7 	8 	14 	TXD
Ground 	- 	9 	10 	15 	RXD
ce1 	17 	11 	12 	18 	ce0
	21 	13 	14 	- 	Ground
	22 	15 	16 	23 	
3V3 	-	17 	18 	24 	
MOSI 	10 	19 	20 	- 	Ground
MISO 	9 	21 	22 	25 	
SCLK 	11 	23 	24 	8 	CE0
Ground 	- 	25 	26 	7 	CE1]],
   [2] = [[
* Type 2 - Model A, B (revision 2)
  - 26 pin header (P1) and an additional 8 pin header (P5).
  - Hardware revision numbers of 4, 5, 6 (B), 7, 8, 9 (A), and 13, 14, 15 (B).
  - User GPIO 2-4, 7-11, 14-15, 17-18, 22-25, 27-31.

Signal	GPIO 	pin 	pin 	GPIO 	Signal
----------------------------------------------
3V3 	- 	1 	2 	- 	5V
SDA 	2 	3 	4 	- 	5V
SCL 	3 	5 	6 	- 	Ground
	4 	7 	8 	14 	TXD
Ground 	- 	9 	10 	15 	RXD
ce1 	17 	11 	12 	18 	ce0
	27 	13 	14 	- 	Ground
	22 	15 	16 	23 	
3V3 	-	17 	18 	24 	
MOSI 	10 	19 	20 	- 	Ground
MISO 	9 	21 	22 	25 	
SCLK 	11 	23 	24 	8 	CE0
Ground 	- 	25 	26 	7 	CE1

Signal	GPIO 	pin 	pin 	GPIO 	Signal
----------------------------------------------
5V	- 	1 	2 	- 	3V3
SDA	28 	3 	4 	29 	SCL
	30 	5 	6 	31 	Ground
	-	7 	8 	-	Ground]],
   [3] = [[
* Type 3 - Model A+, B+, Pi Zero, Pi2B, Pi3B
  - 40 pin expansion header (J8).
  - Hardware revision numbers of 16 or greater.
  - User GPIO 2-27 (0 and 1 are reserved).

Signal	GPIO 	pin 	pin 	GPIO 	Signal
----------------------------------------------
3V3 	- 	1 	2 	- 	5V
SDA 	2 	3 	4 	- 	5V
SCL 	3 	5 	6 	- 	Ground
	4 	7 	8 	14 	TXD
Ground 	- 	9 	10 	15 	RXD
ce1 	17 	11 	12 	18 	ce0
	27 	13 	14 	- 	Ground
	22 	15 	16 	23 	
3V3 	-	17 	18 	24 	
MOSI 	10 	19 	20 	- 	Ground
MISO 	9 	21 	22 	25 	
SCLK 	11 	23 	24 	8 	CE0
Ground 	- 	25 	26 	7 	CE1
ID_SD 	0 	27 	28 	1 	ID_SC
	5 	29 	30 	- 	Ground
	6 	31 	32 	12 	
	13 	33 	34 	- 	Ground
miso 	19 	35 	36 	16 	ce2
	26 	37 	38 	20 	mosi
Ground 	- 	39 	40 	21 	sclk]]
}

---
-- Info string showing special pin functions.
local infostring = [[
Raspberry Pi 3 GPIO information:
===================================================================================================
    PWM (pulse-width modulation)
        Software PWM available on all pins
        Hardware PWM available on GPIO12, GPIO13, GPIO18, GPIO19
    SPI
        SPI0: MOSI (GPIO10); MISO (GPIO9); SCLK (GPIO11); CE0 (GPIO8), CE1 (GPIO7)
        SPI1: MOSI (GPIO20); MISO (GPIO19); SCLK (GPIO21); CE0 (GPIO18); CE1 (GPIO17); CE2 (GPIO16)
    I2C
        Data: (GPIO2); Clock (GPIO3)
        EEPROM Data: (GPIO0); EEPROM Clock (GPIO1)
    Serial
        TX (GPIO14); RX (GPIO15)
===================================================================================================]]
   
_ENV = setmetatable(gpio, {__index = _G})

local tsleep = 0.001

--------------------------------------------------------------------------------
-- Check result and return true upon success.
-- @param err error code return by pigpiod function.
-- @return true upon success,
--         nil + error text + error code upon failure.
--------------------------------------------------------------------------------
local function tryB(err)
   if err ~= 0 then
      return nil, perror(err), err
   end
   return true
end

--------------------------------------------------------------------------------
-- Check result and return value upon success.
-- @param retval value returned by pigpiod function.
-- @return value upon success (retval >= 0),
--         nil + error text upon failure (retval < 0)
--------------------------------------------------------------------------------
local function tryV(retval)
   if retval < 0 then
      return nil, perror(retval), retval
   end
   return retval
end

---
-- Convert a notification sample given in binary coded form in a Lua string
-- into a table.
-- @param s Encoded notification sample.
-- @return Decoded notification sample as Lua table of form
-- <code>{seqno=SEGNO, flags=FLAGS, tick=TICK, level=LEVEL}</code>
local function decodeNotificationSample(s)
   local t = {}
   t.seqno = strbyte(s,2) * 256 + strbyte(s,1)
   t.flags = strbyte(s,4) * 256 + strbyte(s,3)
   t.tick = strbyte(s,8) * 0x1000000 + strbyte(s,7) * 0x10000 + strbyte(s,6) * 0x100 + strbyte(s,5)
   t.level = strbyte(s,12) * 0x1000000 + strbyte(s,11) * 0x10000 + strbyte(s,10) * 0x100 + strbyte(s,9)
   return t
end

---
-- Active sessions are maintained in a global table.
-- Used to retrieve session object from handle in callbacks and for finalization
-- during object garbage collection.
_G._PIGPIOD_SESSIONS = {}

---
-- Active waveforms are maintained in a global table.
-- Used to retrieve session object from handle in callbacks and for finalization
-- during object garbage collection.
_G._PIGPIOD_WAVEFORMS = {}

---
-- Supported baudrates serial built-in serial interface.
-- 9600 (1), 19200 (2), 38400 (3), 57600 (4), 115200 (5), 230400 (6).
-- @table baudrates
-- @field [1 9600 bps
-- @field [2 19200 bps
-- @field [3 38400 bps
-- @field [4 57600 bps
-- @field [5 115200 bps
-- @field [6 230400 bps
baudrates = {
   [1] = 9600,
   [2] = 19200,
   [3] = 38400,
   [4] = 57600,
   [5] = 115200,
   [6] = 230400
}

--------------------------------------------------------------------------------
--- <h3>Waveforms</h3>
-- Waveforms allow to define waveforms to be output on a number of
-- GPIO pins in a programmable way. Once defined the waveform can be sent
-- once or repeatedly.<br>
-- Constructor: <code>session:openWave(waveform, name)</code>
-- @type cWave
--------------------------------------------------------------------------------
local cWave = {}

---
-- Close given waveform.<br>
-- This will delete all waveforms intermediately stored.
-- @param self Waveform.
-- @return true on success, nil + errormsg on failure.
cWave.close = function(self)
   local ret, err = tryB(wave_delete(self.pihandle, self.handle))
   if not ret then
      return ret, err
   end
   _G._PIGPIOD_WAVEFORMS[self.handle] = nil
   self.session.waveforms[self.handle] = nil
   return true
end
cWave.delete = cWave.close

---
-- Send waveform once.
-- @param self Waveform.
-- @return Number of DMA block in waveform.
cWave.sendOnce = function(self)
   return tryV(wave_send_once(self.pihandle, self.handle))
end

---
-- Send waveform repeatedly until cancelled.
-- @param self Waveform.
-- @return Number of DMA blocks.
cWave.sendRepeat = function(self)
   return tryV(wave_send_repeat(self.pihandle, self.handle))
end

---
-- Send the given waveform with given mode.
-- The mode is by a textstring:<br>
-- 'oneshot', 'repeat', 'oneshotsync', 'repeatsync'
-- @param self Waveform.
-- @param mode Mode to be used for sending.
-- @return Number of DMA blocks.
cWave.sendUsingMode = function(self, mode)
   local wavemode = waveModes[mode]
   if not wavemode then
      return nil, "invalid wave mode"
   end
   return tryV(send_using_mode(self.pihandle, self.handle, wavemode))
end

--------------------------------------------------------------------------------
--- <h3>Scripting</h3>
-- A script is a  microcode program to be executed in a specialized virtual
-- machine in the pigpiod daemon.
-- They allow very high pin toggling rates.
-- See <a href=http://abyz.me.uk/rpi/pigpio/pigs.html#Scripts> Scripting </a><br>
-- Constructor: <code>script=session:openScript(code, name)</code>
-- @type cScript
--------------------------------------------------------------------------------
local cScript = {}

---
-- Run a script.<br>
-- @param self Script.
-- @param param List of up to 10 parameters for the script.
-- @return true on success, nil + errormsg on failure.
cScript.run = function(self, param)
   return tryB(run_script(self.pihandle, self.handle, param))
end

---
-- Update parameters of a script, which may already run.
-- @param self Script.
-- @param param List of up to 10 parameters replacing the corresponding
--              subset of previous parameters.
-- @return true on success, nil + errormsg on failure.
cScript.update = function(self, param)
   return tryB(update_script(self.pihandle, self.handle, param))
end

---
-- Retrieve the run status and the parameters of given script.
-- @param self Script.
-- @return Run status and list of parameters on success; nil + errormsg on failure.
cScript.status = function(self)
   local param, status = script_status(self.pihandle, self.handle)
   if status < 0 then
      return nil, perror(status)
   end
   return scriptStati[status], param
end

---
-- Stop the given  running script.
-- @param self Script.
-- @return true on success, nil + errormsg on failure.
cScript.stop = function(self)
   return tryB(stop_script(self.pihandle, self.handle))
end

---
-- Delete the given script.
-- @param self Script.
-- @return true on success, nil + errormsg on failure.
cScript.delete = function(self)
   local res, err = tryB(delete_script(self.pihandle, self.handle))
   if not res then return nil, err end
   self.session.scripts[self.handle] = nil
   return res
end

--------------------------------------------------------------------------------
--- <h3>Pin event callback</h3>
-- Callbacks are executed when a the state of a certain pin changes. If a
-- watchdog is configured on the pin, the callback is also called with a pseudo
-- level indication.<br>
-- Constructor: <code>cb=session:callback(pin, edge, func, userdata)</code>
-- @type cCallback
--------------------------------------------------------------------------------
local cCallback = {}
---
-- Cancel callback.
-- @param self Callback.
-- @return true on success, nil + errormsg on failure.
function cCallback.cancel(self)
   local res, err = tryB(callback_cancel(self.id))
   if not res then return nil, err end
   self.session.callbacks[self.id] = nil
   return res
end

--------------------------------------------------------------------------------
--- <h3>User initiated event callback</h3>
-- Up to 32 event (0 to 31) are supported.<br>
-- Constructor: <code>cb=session:eventCallback(event, func, userdata)</code>
-- @type cEventCallback
--------------------------------------------------------------------------------
local cEventCallback = {}
---
-- Cancel event callback.
-- @param self Eventcallback
-- @return true on success, nil + errormsg on failure.
function cEventCallback.cancel(self)
   local res, err = tryB(event_callback_cancel(self.id))
   if not res then return nil, err end
   self.session.eventcallbacks[self.id] = nil
   return res
end

--------------------------------------------------------------------------------
-- <h3>Notification channels</h3>
-- Notification channels record pin changes in a FIFO which is readable by a
-- file.<br>
-- Constructor:<code>notify=session:openNotify()</code>
-- @type cNotify
--------------------------------------------------------------------------------
local cNotify = {}
---
-- Start notification operation.
-- @param self Notification channel.
-- @param bits Bitmask defining the GPIOs to monitor.
-- @return true on success, nil + errormsg on failure.
cNotify.begin = function(self, bits)
   return tryB(notify_begin(self.pihandle, self.handle, bits))
end

---
-- Pause notification monitoring.
-- @param self Notification channel.
-- @return true on success, nil + errormsg on failure.
cNotify.pause = function(self)
   return tryB(notify_pause(self.pihandle, self.handle))
end

---
-- Convert a notification sample given in binary coded form in a Lua string
-- into a table.
-- @param self Notification channel.
-- @param s Encoded notification sample.
-- @return Decoded notification sample as Lua table of form
-- <code>{seqno=SEGNO, flags=FLAGS, tick=TICK, level=LEVEL}</code>
cNotify.decode = function(self, s)
   return decodeNotificationSample(s)
end

---
-- Close notification channel.
-- @param self Notification channel.
-- @return true on success, nil + errormsg on failure.
cNotify.close = function(self)
   local res, err = tryB(notify_close(self.pihandle, self.handle))
   if not res then return nil, err end
   self.session.notifychannels[self.handle] = nil
   return res
end

--------------------------------------------------------------------------------
-- <h3>Serial Device</h3>
-- Serial (RS232) Devices.<br>
-- Constructor:<code>device=session:openSerial(baud, tty)</code>
-- @type cSerial.
--------------------------------------------------------------------------------
local cSerial = {}

---
-- Close serial device.
-- @param self Device.
-- @return true on success, nil + errormsg on failure.
function cSerial.close(self)
   local res, err = tryB(serial_close(self.pihandle, self.handle))
   if not res then return nil, err end
   self.session.serialdevs[self.handle] = nil
   return res
end

---
-- Write a single byte to serial interface.
-- @param self Device.
-- @param val Value to write.
-- @return true on success, nil + errormsg on failure.
function cSerial.writeByte(self, val)
   return tryB(serial_write_byte(self.pihandle, self.handle, val))
end

---
-- Read a single byte from serial interface.
-- @param self Device.
-- @return Byte read on success, nil + errormsg on failure.
function cSerial.readByte(self)
   return tryV(serial_read_byte(self.pihandle, self.handle))
end

---
-- Write data to serial interface.
-- @param self Device.
-- @param data Data to send as Lua string.
-- @return true on success, nil + errormsg on failure.
function cSerial.write(self, data)
   return tryB(serial_write(self.pihandle, self.handle, data, #data))
end

---
-- Read data from serial interface. Up to nbytes are read.
-- @param self Device.
-- @param nbytes Number of bytes to read.
-- @return Data read.
function cSerial.read(self, nbytes)
   local res, errno = serial_read(self.pihandle, self.handle, nbytes)
   if res == nil then
      return nil, perror(errno)
   end
   return res
end

---
-- Check whether data is available in the bufffer.
-- @param self Device.
-- @return Number of available data on success, nil + errormsg on failure.
function cSerial.dataAvailable(self)
   return tryV(serial_data_available(self.pihandle, self.handle))
end

--------------------------------------------------------------------------------
-- <h3>I2C Device</h3>
-- This is a master I2C device.<br>
-- Constructor: <code>dev=session:openI2C(bus, address, name)</code>
-- @type cI2C
--------------------------------------------------------------------------------
local cI2C = {}
---
-- Close the given I2C device.
-- @param self Device.
-- @return I2C interface instance as table.
function cI2C.close(self)
   local ret, err = tryB(i2c_close(self.pihandle, self.handle))
   if not ret then return nil, err end
   self.session.i2cdevs[self.handle] = nil
   return ret
end

---
-- Send a single bit (0 or 1) via the given device.
-- @param self Device.
-- @param bit Bit to send.
-- @return true on success, nil + errormsg on failure.
function cI2C.writeQuick(self, bit)
   return tryB(i2c_write_quick(self.pihandle, self.handle, bit))
end

---
-- Send a byte via the given device.
-- @param self Device.
-- @param byte Byte to send.
-- @return true on success, nil + errormsg on failure
function cI2C.sendByte(self, byte)
   return tryB(i2c_write_byte(self.pihandle, self.handle, byte))
end

---
-- Receive  a byte via given device.
-- @param self Device.
-- @return Byte received on success, nil + errormsg on failure
function cI2C.receiveByte(self)
   return tryV(i2c_read_byte(self.pihandle, self.handle))
end

---
-- Write the given byte to the given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @param byte Byte to write.
-- @return true on success, nil + errormsg on failure
function cI2C.writeByte(self, reg, byte)
   return tryB(i2c_write_byte_data(self.pihandle, self.handle, reg, byte))
end

---
-- Write the given 16 bit word to the given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @param word  Word to write.
-- @return true on success, nil + errormsg on failure
function cI2C.writeWord(self, reg, word)
   return tryB(i2c_write_word_data(self.pihandle, self.handle, reg, word))
end

---
-- Read a byte from the given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @return Byte read on success, nil + errormsg on failure.
function cI2C.readByte(self, reg)
   return tryV(i2c_read_byte_data(self.pihandle, self.handle, reg))
end

---
-- Read a 16 bit word from the given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @return Word read on success, nil + errormsg on failure.
function cI2C.readWord(self, reg)
   return tryV(i2c_read_word_data(self.pihandle, self.handle, reg))
end

---
-- Write + read (process) given 16 bit value to/freom given device.
-- @param self Device.
-- @param reg Register number.
-- @param val Word to write.
-- @return Value read on success, nil + errormsg on failure.
function cI2C.processCall(self, reg, val)
   return tryV(i2c_process_call(self.pihandle, self.handle, reg, val))
end

---
-- Write a block of bytes into given register of given device.
-- @param self Device.
-- @param reg Register number.
-- @param data Binary data stored in Lua string allowing embedded zeros.
-- @return Binary data from device on success, nil + errormsg on failure.
function cI2C.writeBlockData(self, reg, data)
   return tryB(i2c_write_block_data(self.pihandle, self.handle, reg, data, #data))
end

---
-- Read a block of bytes from given register of given device.
-- @param self Device.
-- @param reg Register number.
-- @return Binary data stored in Lua string allowing embedded zeros on success
--         nil + errormsg on failure.
function cI2C.readBlockData(self, reg)
   local res, errno = i2c_read_block_data(self.pihandle, self.handle, reg)
   if res == nil then
      return nil, perror(errno)
   end
   return res
end

---
-- Send + receive a block of data to/from given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @param data Lua string with data to be written.
-- @return Data read in a Lua string allowing embedded zeros.
function cI2C.blockProcessCall(self, reg, data)
   return tryV(i2c_block_process_call(self.pihandle, self.handle, reg, data));
end

---
-- Write 1 to 32 bytes to given register on given device.
-- @param self Device.
-- @param reg Register number.
-- @param data Lua string with data to be written.
-- @return true on success, nil + errormsg on failure.
function cI2C.writeI2CBlockData(self, reg, data)
   return tryB(i2c_write_i2c_block_data(self.pihandle, self.handle, reg, data, #data))
end

---
-- Read given number of bytes from given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @param nbytes Number of bytes to be read.
-- @return Number of byte read.
function cI2C.readI2CBlockData(self, reg, nbytes)
   local res, errno = i2c_read_i2c_block_data(self.pihandle, self.handle, reg, nbytes)
   if res == nil then
      return nil, perror(errno)
   end
   return res
end

---
-- Read given number bytes from given device.
-- @param self Device.
-- @param nbytes Number of bytes to be read.
-- @return Lua string with read data.
function cI2C.readDevice(self, nbytes)
   return tryV(i2c_read_device(self.pihandle, self.handle))
end

---
-- Write given data to given device.
-- @param self Device.
-- @param data Lua string with data to write.
-- @return true on success, nil + errormsg on failure.
function cI2C.writeDevice(self, data)
   return tryB(i2c_write_device(self.pihandle, self.handle, data, #data))
end

---
-- Execute a sequence of I2C commands.
-- For details see <a href=http://abyz.me.uk/rpi/pigpio/pdif2.html#i2c_zip> I2C ZIP </a>
-- @param self Device.
-- @param inbuf Lua String with data to be sent.
-- @param outlen Number of Byte to be returned.
-- @return Bytes read in a Lua string on success, nil + errormsg on failure.
function cI2C.zip(self, inbuf, outlen)
   return tryV(i2c_zip(self.pihandle, self.handle, inbuf, #inbuf, outlen))
end

--------------------------------------------------------------------------------
-- <h3>I2C Bit Banging Device</h3>
-- This device is a GPIO based I2C device allowing special service primitives.
-- Constructor: <code>dev=session:openI2Cbb(sda, scl, baud)</code>
-- @type cI2Cbb
--------------------------------------------------------------------------------
local cI2Cbb = {}

---
-- Execute a sequence of I2C commands.
-- For details see <a href=http://abyz.me.uk/rpi/pigpio/pdif2.html#i2c_zip> I2C ZIP </a>
-- @param self Device.
-- @param inbuf Lua String with data to be sent.
-- @param outlen Number of Byte to be returned.
-- @return Bytes read in a Lua string on success, nil + errormsg on failure.
function cI2Cbb.zip(self, inbuf, outlen)
   return tryV(bb_i2c_zip(self.pihandle, self.handle, inbuf, #inbuf, outlen))
end

---
-- Close I2C bit bang device.
-- @param self Device.
-- @return true on success, nil + errormsg on failure.
function cI2Cbb.close(self)
   local res, err = tryB(bb_i2c_close(self.pihandle, self.handle))
   if not res then return nil, err end
   self.session.bbi2cdevs[self.handle] = nil
   return res
end

--------------------------------------------------------------------------------
-- <h3>SPI Device</h3>
-- This is a master SPI device.<br>
-- Constructor: <code>dev=session:openSPI(spichannel, bitraate, flags, name)</code>
-- @type cSPI
--------------------------------------------------------------------------------
local cSPI = {}

---
-- Close SPI device.
-- @param self Decvice.
-- @return true on success, nil + errormsg on failure
function cSPI.close(self)
   local res, err = tryB(spi_close(self.pihandle, self.handle))
   if not res then return nil, err end
   self.session.spidevs[self.handle] = nil
   return true
end

---
-- Read given number of bytes from SPI interface.
-- @param self Device.
-- @param nbytes Number of bytes to read.
-- @return Data read in Lua string, nil + errormsg on failure.
function cSPI.read(self, nbytes)
   local res, errno = spi_read(self.pihandle, self.handle, nbytes)
   if res == nil then
      return nil, perror(errno)
   end
   return res
end

---
-- Write given data to SPI interface.
-- @param self Device.
-- @param data Data to write in a Lua string.
-- @return Number of byte written, nil + errormsg on failure
function cSPI.write(self, data)
   local res, errno = spi_write(self.pihandle, self.handle, data, #data)
   if not res then
      return nil, perror(errno)
   end
   return res
end

---
-- Transfer (write and read) given data.
-- As much bytes are read as being written.
-- @param self Device.
-- @param data Data to write in a Lua string.
-- @return Data read in a Lua string on success, nil + errormsg on failure.
function cSPI.transfer(self, data)
   local s, err = spi_xfer(self.pihandle, self.handle, data, #data)
   if not s then
      return nil, err
   end
   return s
end

--------------------------------------------------------------------------------
-- All GPIO control and status operations occurs in the context of a session.
-- A session is create by connecting to a remote Raspberry Pi instance via
-- network or locally.<br>
-- Constructor: <code>session=pigpiod.open(host, port, name)</code>
-- @type cSession
--------------------------------------------------------------------------------
local cSession = {}

---
-- Close session.
-- @param self Session.
-- @return true on success, nil + errormsg on error.
cSession.close = function(self)

   for _, item in pairs(self.waveforms) do item:close() end
   for _, item in pairs(self.scripts) do item:delete() end
   for _, item in pairs(self.notifychannels) do item:close() end
   for _, item in pairs(self.callbacks) do item:cancel() end
   for _, item in pairs(self.eventcallbacks) do item:cancel() end
   for _, item in pairs(self.i2cdevs) do item:close() end
   for _, item in pairs(self.spidevs) do item:close() end
   for _, item in pairs(self.serialdevs) do item:close() end
   for _, item in pairs(self.bbi2cdevs) do item:close() end
   _G._PIGPIOD_SESSIONS[self.handle] = nil
   pigpio_stop(self.handle)
   self.handle = nil
   return true
end

---
-- Set pin mode.
-- @param self Session.
-- @param pin GPIO number.
-- @param mode gpio.INPUT or gpio.OUTPUT.
-- @return ture on success, nil + errormsg on error.
cSession.setMode = function(self, pin, mode)
   return tryB(set_mode(self.handle, pin, mode))
end

---
-- Get pin mode.
-- @param self Session.
-- @param pin GPIO number.
-- @return true on success, nil + errormsg on error.
cSession.getMode = function(self, pin)
   return tryV(get_mode(self.handle, pin))
end

---
-- Set pull-up/down configuration of pin.
-- @param self Session.
-- @param pin GPIO number.
-- @param pud gpio.PUD_UP, gpio.PUD_DOWN or gpio.PUD_OFF
-- @return true on success, nil + errormsg on error.
cSession.setPullUpDown = function(self, pin, pud)
   return tryB(set_pull_up_down(self.handle, pin, pud)) 
end

---
-- Read pin level.
-- @param self Session.
-- @param pin GPIO number.
-- @return Pin level.
cSession.read = function(self, pin)
   return tryV(gpioread(self.handle, pin))
end

---
-- Write pin level.
-- @param self Session.
-- @param pin GPIO number.
-- @param val Level to set, 0 or 1.
-- @return true on success, nil + errormsg on failure.
cSession.write = function(self, pin, val)
   return tryB(gpio_write(self.handle, pin, val))
end

---
-- Start Software controlled PWM on given pin.
-- @param self Session.
-- @param pin GPIO number.
-- @param dutycycle Dutycycle to use (0..range) default: 0..255.
-- @return true on success, nil + errormsg on failure.
cSession.setPwmDutycycle = function(self, pin, dutycycle)
   return tryB(set_PWM_dutycycle(self.handle, pin, dutycycle))
end

---
-- Get the PWM duty cycle.
-- @param self Session.
-- @param pin GPIO number.
-- @return Active dutycycle: 0..range 
cSession.getPwmDutycycle = function(self, pin)
   return tryV(get_PWM_dutycycle(self.handle, pin))
end

---
-- Set the dutycycle range for PWM on given pin.
-- @param self Session.
-- @param pin GPIO number.
-- @param range Range between 25 and 40000.
-- @return true on success; nil + errormsg on failure
cSession.setPwmRange = function(self, pin, range)
   return tryB(set_PWM_range(self.handle, pin, range))
end

---
-- Get current PWM range for given pin.
-- @param self Session.
-- @param pin GPIO number.
-- @return Dutycycle range for given pin.
cSession.getPwmRange = function(self, pin)
   return tryV(get_PWM_range(self.handle, pin))
end

---
-- Get current PWM real range for given pin.
-- @param self Session.
-- @param pin GPIO number.
-- @return PWM real range.
cSession.getPwmRealRange = function(self, pin)
   return tryV(get_PWM_real_range(self.handle, pin))
end

---
-- Set PWM frequency.
-- @param self Session.
-- @param pin GPIO number.
-- @param frequency Frequency in Hz. 
cSession.setPwmFrequency = function(self, pin, frequency)
   return tryV(set_PWM_frequency(self.handle, pin, frequency))
end

---
-- Get PWM frequency.
-- @param self Session.
-- @param pin GPIO number.
-- @return Frequency in Hz.
cSession.getPwmFrequency = function(self, pin)
   return tryV(get_PWM_frequency(self.handle, pin))
end

---
-- Start servo pulses. Can be alternatively called via cSession.servo(...).
-- @param self Session.
-- @param pin GPIO number.
-- @param pulsewidth Pulsewidth between 500 and 2500, default: 1500.
cSession.setServoPulsewidth = function(self, pin, pulsewidth)
   return tryB(set_servo_pulsewidth(self.handle, pin, pulsewidth))
end
cSession.servo = cSession.setServoPulsewidth

---
-- Get servo pulsewidth.
-- @param self Session.
-- @param pin GPIO number.
-- @return Servo pulsewidth.
cSession.getServoPulsewidth = function(self, pin)
   return tryV(get_servo_pulsewidth(self.handle, pin))
end

---
-- Open a notification channel.
-- Data can be read from file /dev/pigpio<handle> with <handle>
-- as returned by this function.
-- @param self Session.
-- @return Notifcation channel handle.
cSession.openNotify = function(self)
   local notify = {}
   notify.handle = notify_open(self.handle)
   notify.pihandle = self.handle
   if notify.handle < 0  then
      return nil, perror(notify.handle), notify.handle
   end
   setmetatable(notify, {
                   __index = cNotify,
                   __gc = function(self) self:close() end
   })
   notify.filename = "/dev/pigpio"..notify.handle
   notify.session = self
   self.notifychannels[notify.handle] = notify
   return notify
end
cSession.notifyOpen = cSession.openNotify

---
-- Set watchdog for the specified pin.
-- A timeout of 0 cancels the watchdog.
-- @param self Session.
-- @param pin GPIO number.
-- @param timeout Timeout in milliseconds.
-- @return true on success, nil + errormsg on failure.
cSession.setWatchdog = function(self, pin, timeout)
   return tryB(set_watchdog(self.handle, pin, timeout))
end

---
-- Set glitch filter for given pin.
-- @param self Session.
-- @param pin GPIO number.
-- @param steady Minimum time of stable level in order to report state change.
-- @return true on success, nil + errormsg on failure.
cSession.setGlitchFilter = function(self, pin, steady)
   return tryB(set_glitch_filter(self.handle, pin, steady))
end

cSession.setNoiseFilter = function(self, pin, steady, active)
   return tryB(set_noise_filter(self.handle, pin, steady, active))
end

cSession.readBank1 = function(self)
   return tryV(read_bank_1(self.handle))
end

cSession.readBank2 = function(self)
   return tryV(read_bank_2(self.handle))
end

cSession.clearBank1 = function(self, bits)
   return tryB(clear_bank_1(self.handle, bits))
end

cSession.clearBank2 = function(self, bits)
   return tryB(clear_bank_2(self.handle, bits))
end

cSession.setBank1 = function(self, bits)
   return tryB(clear_bank_1(self.handle, bits))
end

cSession.setBank2 = function(self, bits)
   return tryB(clear_bank_2(self.handle, bits))
end

cSession.hardwareClock = function(self, pin, clkfreq)
   return tryB(hardware_clock(self.handle, pin, clkfreq))
end

cSession.hardwarePwm = function(self, pin, pwmfreq, pwmduty)
   return tryB(hardware_PWM(self.handle, pin, pwmfreq, pwmduty))
end

cSession.getCurrentTick = function(self)
   return tryV(get_current_tick(self.handle))
end
cSession.tick = cSession.getCurrentTick

cSession.getHardwareRevision = function(self)
   local hwrev = get_hardware_revision(self.handle)
   local typ, model, comment
   if hwrev == 2 or hwrev == 3 then
      typ, model, comment = 1, "B", "original"
   elseif hwrev >= 4 and hwrev <= 6 then
      typ , model,comment = 2, "B", "revision 2"
   elseif hwrev >= 7 and hwrev <= 9 then
      typ, model, comment = 2, "A", "revision 2"
   elseif hwrev >= 13 and hwrev < 15 then
      typ, model, comment = 2, "B", "revision 2"
   elseif hwrev > 15 then
      typ, model, comment = 3, "multiple", "A+, B+, Pi Zero, Pi2B, Pi3B"
   else
      return nil, "unknown hardware revision."
   end
   return typ, model, comment
end

cSession.getPinning = function(self, typ)
   if typ < 1 or typ > 3 then
      return nil, "invalid type."
   end
   return pinnings[typ]
end

cSession.getPigpioVersion = function(self)
   return tryV(get_pigpio_version(self.handle))
end

--cSession.waveAddNew = function(self) return
--   tryB(wave_add_new(self.handle))
--end

--cSession.waveAddGeneric = function(self, pulses)
--   return tryV(wave_add_generic(self.handle, pulses))
--end

--cSession.waveAddSerial = function(self, pin, baud, nbits, stopbits, timeoffs, str)
--   return tryV(wave_add_serial(self.handle, pin, baud, nbits, stopbits, timeoffs, #str, str))
--end

---
-- Open a waveform as defined by parameter 'waveform'.<br>
-- An optional user defined name can be provided. If nil, a name 'wave-<wave.handle>' is
-- automatically created.
-- @param self Session.
-- @param waveform List of waveforms in the following format:
-- <ul>
-- <li><code>{typ, WF1, WF2, ..., WFn}</code>.
-- <li>typ is either 'generic' or 'serial'.
-- <li>WFi is a table in one of the following formats:
-- <ul>
-- <li>generic: <code>{on=PINMASK, off=PINMASK, delay=TIME_in_us}</code>.
-- <li>serial: <code>{baud=BAUDRATE, nbits=NBITS, stopbits=STOPBITS, timeoffs=TIME_in_us, STRING}</code>.
-- </ul></ul>
-- @param name Name of the waveform (optional).
-- @return Wave objec on success; nil + errormsg on failure.
cSession.openWave = function(self, waveform, name)
   local wave = {}
   local npulses = 0
   -- 1. add waveforms
   for ix, wf in ipairs(waveform) do
      if wf.typ == "generic" or wf.typ == nil then
         ret, err = tryV(wave_add_generic(self.handle, wf))
         if not ret then return nil, err end
         npulses = npulses + ret
      elseif wf.typ == "serial" then
         ret, err = tryV(wave_add_serial(self.handle, wf.pin, wf.baud, wf.nbits, wf.stopbits, wf.timeoffs, #wf.str, wf.str))
         if not ret then return nil, err end
         npulses = npulses + ret
      end
   end
   -- 2. create waveform
   wave.handle = wave_create(self.handle)
   if wave.handle < 0 then
      return nil, perror(wave.handle), wave.handle
   end
   wave.npulses = npulses
   wave.pihandle = self.handle
   wave.name = name or ("wave-"..wave.handle)
   setmetatable(wave, {
                 __index = cWave,
                 __gc = function(self) self:delete() end
   })
   _G._PIGPIOD_WAVEFORMS[wave.handle] = wave
   self.waveforms[wave.handle] = wave
   wave.session = self
   return wave
end
cSession.waveOpen = cSession.openWave
---
-- Clear all waveforms.
-- @param self Session.
-- @return true on success, nil + errormsg on failure.
cSession.waveClear = function(self)
   local ret, err = tryB(wave_clear(self.handle))
   if not ret then
      return nil, err
   end
   _G._PIGPIOD_WAVEFORMS = {}
   return true
end

---
-- Define and start a chain of waveforms.
-- @param self Session.
-- @param list Lua list with commands defining the chain.
-- <ul>
-- <li>Each list entry presents on line of a chain micro program.
-- <li>Syntax:
-- <li>table interpreted as wave object reference.
--     <ul>
--     <li>'delay m':                     delay m microseconds.
--     <li>'start' ... 'repeat N':        repeat loop N times.  
--     <li>'start' ... 'repeat forever':  repeat forever.
-- </ul></ul>
-- @return true on success, nil + errormsg on failure.
cSession.waveChain = function(self, list)
   local s = ""
   if type(list) ~= "table" then
      error(strinf.format("Table expected as arg %d, received %s.", type(list)))
   end
   for k, v in ipairs(list) do
      if type(v) == "table" then
         -- this is a wave object
         s = s..string.char(v.handle)
      elseif type(v) == "string" then
         if v == "start" then
            -- 'start' command
            s = s .. string.char(255, 0)
         elseif v == "forever" then
            -- 'forever" command
            s = s .. string.char(255, 3)
         else
            -- 'CMD' param command
            string.gsub(v, "(%w+)%s+(%d+)",
                        function(cmd, param)
                           local p = tonumber(param)
                           local hi, lo = bit32.extract(p, 8, 8), bit32.extract(p, 0, 8)
                           if cmd == "repeat" then
                              -- command 'repeat n"
                              s = s .. string.char(255, 1, lo, hi)
                           elseif cmd == "delay" then
                              -- command 'delay n'
                              s = s .. string.char(255, 2, lo, hi)
                           end
                        end
            )
         end
      else
         error(string.format("Invalid chain command '%s' at position %d.", v, k)) 
      end
   end
   return tryB(wave_chain(self.handle, s, #s))
end

cSession.waveTxAt = function(self)
   local ret, err = tryV(wave_tx_at(self.handle))
   if not ret then
      return nil, err
   end
   return _G._PIGPIOD_WAVEFORMS[ret].name, ret
end

cSession.waveTxBusy = function(self)
   return tryV(wave_tx_busy(self.handle))
end

cSession.waveTxStop = function(self)
   return tryB(wave_tx_stop(self.handle))
end

cSession.waveGetMicros = function(self)
   return tryV(wave_get_micros(self.handle))
end

cSession.waveGetHighMicros = function(self)
   return tryV(wave_get_high_micros(self.handle))
end

cSession.waveGetMaxMicros = function(self)
   return tryV(wave_get_max_micros(self.handle))
end

cSession.waveGetPulses = function(self)
   return tryV(wave_get_pulses(self.handle))
end

cSession.waveGetHighPulses = function(self)
   return tryV(wave_get_high_pulses(self.handle))
end

cSession.waveGetMaxPulses = function(self)
   return tryV(wave_get_max_pulses(self.handle))
end

cSession.waveGetCbs = function(self)
   return tryV(wave_get_cbs(self.handle))
end

cSession.waveGetHighCbs = function(self)
   return tryV(wave_get_high_cbs(self.handle))
end

cSession.waveGetMaxCbs = function(self)
   return tryV(wave_get_max_cbs(self.handle))
end   

cSession.trigger = function(self, pin, pulselen, level)
   return tryB(gpio_trigger(self.handle, pin, pulselen, level)) 
end

---
-- Open a gpiod script.
-- on gpiod scripting.
-- @param self Session.
-- @param code Scipt code.
-- @return Script object on success; nil + errormsg on failure.
cSession.openScript = function(self, code)
   local script = {}
   script.handle = store_script(self.handle, code)
   script.pihandle = self.handle
   if script.handle < 0 then
      return nil, perror(script.handle), script.handle
   end
   setmetatable(script, {
                   __index = cScript,
                   __gc = function(self) self:delete() end
   })
   self.scripts[script.handle] = script
   script.session = self
   return script
end
cSession.storeScript = cSession.openScript
cSession.scriptOpen = cSession.openScript

---
-- Define a pin event callback function.
-- The callback function has the following signature:<br>
-- <code>cbfunc(sess, pin, level, tick, [userdata])</code>
-- @param self Session.
-- @param pin GPIO number.
-- @param edge Type of edge:
--        <code>gpio.RISING_EDGE, gpio.FALLING_EDGE, gpio.EITHER_EDGE</code>
-- @param func Lua callback function.
-- @param userdata Any Lua value as user parameter.
-- @return Callback object.
cSession.callback = function(self, pin, edge, func, userdata)
   local callback = {}
   callback.id = gpio.callback(self.handle, pin, edge, func, userdata)
   if callback.id < 0 then
      return nil, perror(callback.id), callback.id
   end
   setmetatable(callback, {
                   __index = cCallback,
                   __gc = function(self) self:cancel() end
   })
   self.callbacks[callback.id] = callback
   callback.session = self
   return callback
end

cSession.eventCallback = function(self, event, func, userdata)
   local callback = {}
   callback.id = event_callback(self.handle, event, func, userdata)
   if callback.id < 0 then
      return nil, perror(callback.id), callback.id
   end
   setmetatable(callback, {
                   __index = cEventCallback,
                   __gc = function(self) self:cancel() end
   })
   self.eventcallbacks[callback.id] = callback
   callback.session = self
   return callback
end

---
-- Wait for an edge to occur.
-- @param self Session.
-- @param pin GPIO number.
-- @param edge Type of edge:
--        <code>gpio.RISING_EDGE, gpio.FALLING_EDGE, gpio.EITHER_EDGE</code>
-- @param timeout Timeout in seconds.
-- @return true if edge occured, nil + "timeout" if edge is not detected.
cSession.waitEdge = function(self, pin, edge, timeout)
   local ret = wait_for_edge(self.handle, pin, edge, timeout)
   if ret == 1 then
      return true
   else
      return nil, "timoeut"
   end
end

cSession.waitEvent = function(self, event, timeout)
   local res, err = tryV(wait_for_event(self.handle, event, timeout))
   if not res then return nil, err end
   return true
end

cSession.triggerEvent = function(self, event)
   return tryB(event_trigger(self.handle, event))
end

---
-- Open serial device.
-- @param self Session.
-- @param baud Baudrate in bits per second.
-- @param tty Serial device file name starting with
--            /dev/serial or /dev/tty
-- @param name Name of the device.
-- @return Device object on success, nil + errormsg on failure.
cSession.openSerial = function(self, baud, tty, name)
   local serial = {}
   local baud = baud or 9600
   local tty = tty or "/dev/serial0"
   local flags = 0
   serial.handle = serial_open(self.handle, tty, baud, flags)
   serial.pihandle = self.handle
   setmetatable(serial, {
                   __index = cSerial,
                   __gc = function(self) self:close() end
   })
   self.serialdevs[serial.handle] = serial
   serial.session = self
   serial.name = name or ("serial-"..serial.handle)
   return serial
end

---
-- Get a pads signal strength in mA.
-- @param self Session.
-- @param pad Pad (pin)
-- <ul>
-- <li>pad = 0: GPIO[0..27]
-- <li>pad = 1: GPIO[28..45]
-- <li>pad = 2: GPIO[46 .. 53]
-- </ul>
-- @return Signal strength in mA.
cSession.getPadStrength = function(self, pad)
   if pad < 0 or pad > 3 then
      return nil, "invalid pad index."
   end
   return tryV(get_pad_strength(self.handle, pad))
end

---
-- Set strength of a pad.
-- @param self Session.
-- @param pad Pad (pin) 
-- <ul>
-- <li>pad = 0: GPIO[0..27]
-- <li>pad = 1: GPIO[28..45]
-- <li>pad = 2: GPIO[46 .. 53]
-- </ul>
-- @param mamps Strength in mA
-- @return true on success, nil + errormsg on failure.
cSession.setPadStrength = function(self, pad, mamps)
   if pad < 0 or pad > 3 then
      return nil, "invalid pad index."
   end
   if mamps < 1 or mamps > 16 then
      return nil, "strength out of range (1..16) mA."
   end
   return tryB(set_pad_strength(self.handle, pad, mamps))
end

---
-- Execute a shell script  on connected host.
-- The script name may contain '-' and '_' and alphanumeric characters.
-- @param self Session.
-- @param name Name of the script.
-- @param scriptparam Parameters for the script.
-- @return 0 on success, nil + error message on failure.
cSession.shell = function(self, name, scriptparam)
   local status = shell_(self.handle, name, scriptparam)
   if status == 32512 then
      return nil, "script not found."
   end
   return status
end

---
-- Open I2C device.
-- @param self Session.
-- @param bus Bus index.
-- @param address Address of the device.
-- @param name Optional name.
-- @return I2C device object; nil + errormsg on failure.
cSession.openI2C = function(self, bus, address, name)
   local i2c = {}
   local flags = 0
   if bus < 0 then return nil, "invalid bus index." end
   if address < 0 or address > 0x7f then return nil, "invalid address." end
   i2c.handle = i2c_open(self.handle, bus, address, flags)
   if i2c.handle < 0 then
      return nil, perror(i2c.handle)
   end
   i2c.pihandle = self.handle
   setmetatable(i2c, {
                   __index = cI2C,
                   __gc = function(self) self:close() end
   })
   i2c.name = name or ("i2cdev-"..i2c.handle)
   i2c.session = self
   self.i2cdevs[i2c.handle] = i2c
   return i2c
end

cSession.openI2Cbb = function(self, sda, scl, baud)
   local i2c = {}
   local res, err = tryB(bb_i2c_open(self.handle, sda, scl, baud))
   if not res then return nil, err end
   i2c.handle = sda
   i2c.pihandle = i2c.handle
   setmetatable(i2c, {
                   __index = cI2Cbb,
                   __gc = function(self) self:close() end
   })
   i2c.session = self
   i2c.bbi2cdevs[i2c.handle] = i2c
   return i2c
end

---
-- Scan an I2C bus for present devices.
-- Returns a list of table in the following form:
-- <code>{{addr=ADDR, status="ok"|"used", data=DATA}, ... {addr, ...}}</code>
-- @param self Session.
-- @param bus Bus index 0 or 1.
-- @return List of connect and usable or not usable devices on success,
--         nil + errormsg on failure.
cSession.scanI2C = function(self, bus)
   local devlist = {}
   for addr = 0x00, 0x7f do
      local dev, err = self:openI2C(bus, addr, "none")
      if not dev then
         if err == "bad I2C bus" then return nil, err end
         table.insert(devlist, {addr=addr, data=0xFF, status="used"})
      else
         local data, err = dev:receiveByte()
         if data then
            table.insert(devlist, {addr=addr, data=data, status="ok"})
         end
         dev:close()
      end
   end
   return devlist
end

---
-- Open SPI device.
-- @param self Session.
-- @param spichannel Channel (chip select) to use: 0..2 - default: 0.
-- @param bitrate Bitrate 32 kbps to 30 Mbps - default: 32 kbps.
-- @param flags Flags to control basic parameters of the device.
-- @param name Name for device - default: spidev-<SPIHANDLE>.
-- @return Device object on success, nil + errormsg on failure.
cSession.openSPI = function(self, spichannel, bitrate, flags, name)
   local spi = {}
   local spichannel = spichannel or 0
   local bitrate = bitrate or 32000
   local flags = flags or 0
   spi.handle = spi_open(self.handle, spichannel, bitrate, flags)
   if spi.handle < 0 then
      return nil, perror(spi.handle)
   end
   spi.pihandle = self.handle
   setmetatable(spi, {
                   __index = cSPI,
                   __gc = function(self) self:close() end
   })
   spi.name = name or ("spidev-" .. spi.handle)
   spi.session = self
   self.spidevs[spi.handle] = spi
   return spi
end

--------------------------------------------------------------------------------
-- <h3>SPI Flags</h3>
-- A set of "macros" (Lua functions) that can be used to assemble the <code>flags</code> parameter
-- for the function <code>cSession:openSPI(spichannel, bitrate, flags, name)</code>.<br>
-- Here is how flags word is constructed:<br>
-- <code>21 20 19 18 17 16 15 14 13 12 11 10  9  8  7  6  5  4  3  2  1  0</code><br>
-- <code> b  b  b  b  b  b  R  T  n  n  n  n  W  A u2 u1 u0 p2 p1 p0  m1  m0</code><br>
-- <ul>
-- <li>mode: operation mode: pol * 2 + pha
-- <li>cslev: chip select level: p2..p0
-- <li>csuse: chip select usage: u2..u0
-- <li>interface: interface to use: "main" or "aux"
-- <li>wires: wires to use: 4 (bidir) or 3 (unidir)
-- <li>masterbytes: 0..15
-- <li>txendian: transmit endian: "big" or "little"
-- <li>rxendian: treceive endian: "big" or "little"
-- <li>wordsize: word size: 0..32
--</ul>
-- NOTE: wrong constructed flag values are not detected before using in call to cSession:openSPI(...).
-- @type spiFlags
--------------------------------------------------------------------------------
spiFlags = {
   --- SPI Mode: 0..3 => 00, 01, 10, 11 = (pol, pha)
   mode = function(pol, pha)
      return bit32.lshift(pol*2 + pha, 0)
   end,
   --- SPI chip select level: 0..7 => 000, 001, ..., 111 = (cs2, cs1, cs0)
   cslev = function(cs2, cs1, cs0)
      return bit32.lshift(cs2*4 + cs1*2 + cs0, 2)
   end,
   --- SPI chip select usage: 0..7 => 000, 001, ..., 111 = (cs2, cs1, cs0)
   csuse = function(cs2, cs1, cs0)
      return bit32.lshift(cs2*4 + cs1*2 + cs0, 5)
   end,
   --- SPI interface: "aux" or "main"
   interface = function(val)
      if val == "aux" then return bit32.lshift(1, 8) else return 0x0000 end
   end,
   --- SPI 3 wire: 3 or 4
   wires = function(val)
      if val == 3 then return bit32.lshift(1, 9) else return 0x0000 end
   end,
   --- SPI MOSI bytes to transmit before changing to MISO: 0..15
   masterbytes = function(val)
      return bit32.lshift(val, 10)
   end,
   --- SPI transmit endianess: "big" or "little"
   txendian = function(val)
      if val == "little" then return bit32.lshift(1, 14) else return 0x0000 end
   end,
   --- SPI receive endianess: "big" or "little"
   rxendian = function(val)
      if val == "little" then return bit32.lshift(1, 15) else return 0x0000 end
   end,
   --- SPI word size: 0 => 1 Byte, 1..8 => 8 bits per char, 9..16 => 16 bits per char, 32 bits per char
   wordsize = function(val)
      if val <= 8 then return 0x0000 else return bit32.lshift(val, 16) end
   end
}

--------------------------------------------------------------------------------
-- Module functions.
-- The pigpio module provides the following functions in the modules name space:
-- <code>open()</code> - opens a session with local or remote host.<br>
-- <code>tick()</code> - returns hosts tick time in microseconds.<br>
-- <code>time()</code> - returns hosts time in seconcs sincd last epoche a floating point.<br>
-- <code>getEventStats()</code> - returns event statistics.<br>
-- <code>clearEventStats()</code> - clears event statistics.<br>
-- <code>wait()</code> - wait a certain time with possibility for lua event callbacks.<br>
-- <code>busyWait()</code> - wait without any process blocking call.<br>
-- <code>perror()</code> - returns a textual description of an error code.<br>
-- @section Functions
--------------------------------------------------------------------------------

---
-- Open a session with given host on given port. An optional user defined name
-- can be defined; if nil a name 'sess-<sess.handle>' is created automatically.
-- @param host Hostname of target system. Default: localhost.
-- @param port Port to be used. Default: 8888.
-- @param name Name of this session (optional).
-- @return Session object of class cSession.
function open(host, port, name)
   local sess = {}
   sess.host = tostring(host or "localhost")
   sess.port = tostring(port or 8888)
   sess.handle = pigpio_start(sess.host, sess.port)
   print("#1#", sess.host, sess.port, sess.handle)
   if sess.handle < 0 then
      return nil, perror(sess.handle), sess.handle
   end
   sess.name = name or ("sess-"..sess.handle)
   _G._PIGPIOD_SESSIONS[sess.handle] = sess
   setmetatable(sess, {
                   __index = cSession,
                   __gc = function(self) self:close() end
   })
   sess.i2cdevs={}
   sess.spidevs={}
   sess.serialdevs={}
   sess.waveforms={}
   sess.scripts={}
   sess.notifychannels={}
   sess.callbacks={}
   sess.eventcallbacks={}
   sess.bbi2cdevs = {}
   sess.bbserialdevs = {}
   return sess
end

---
-- Wait for a while.
-- This function blocks in time chunks allowing Lua callbacks to be called
-- by the pigpiod library. The given waiting time t is split into n=t/ts
-- blocking calls to gpio.sleep(ts) with ts = 1 ms by default.
-- @param t time to sleep in seconds.
-- @param ts time step to use - optional.
-- @return true
function wait(t, ts)
   local ts = (ts or tsleep)
   local n = t / ts
   for i = 1, n do
      sleep(ts)
   end
   return true
end

---
-- Busy wait for a while.
-- @param t time to sleep in seconds.
-- @return true.
function busyWait(t)
   local n = t * 3 * 1e7
   for i = 1, n do
   end
   return true
end

---
-- Returns info string.
-- @return Info string.
function info()
   return infostring
end

---
-- Get event handling statistics in the form.
-- <code>{drop = DROP, maxcount = MAXCOUNT}</code>
-- The function captures a snapshot.
-- @return Event statics on success, nil + errormsg on failure
function getEventStats()
   local ustat = get_event_statistics()
   local t = {
      drop = ustat.drop,
      maxcount = ustat.maxcount
   }
   return t
end

---
-- Clear event statistics.
-- @return true on success, nil + errormsg on failure.
function clearEventStats()
   return tryB(clear_event_statistics())
end

---
-- Start a new thrad.
-- @param code Lua code in a string.
-- @param name Name of the thread.
-- @param ... Paramters passed to the given Lua code as arguments.
-- @return pthread user data on success, nil + errormsg on failure.
function startThread(code, name, ...)
   local ret, err = start_thread(code, name, ...)
   if not ret then return nil, err end
   return ret
end

---
-- Stop given thread.
-- @param pthread Name or pthread userdata of thread.
-- @return true on success, nil + errormsg on failure.
function stopThread(pthread)
   return tryB(stop_thread(pthread))
end

return _ENV
