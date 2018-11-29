--------------------------------------------------------------------------------
-- A Lua wrapper for the pigpiod C interface.
-- luapigpiod allows control of Raspberry Pi GPIO pins from userspace.
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

tsleep = 0.001
sec = 1e6
msec = 1000
us = 1

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
-- Active sessions are maintained in a global table.
-- Used to retrieve session object from handle in callbacks and for finalization
-- during object garbage collection.
_G._PIGPIOD_SESSIONS = {}

---
-- Active waveforms are maintained in a global table.
-- Used to retrieve session object from handle in callbacks and for finalization
-- during object garbage collection.
_G._PIGPIOD_WAVEFORMS = {}

--------------------------------------------------------------------------------
--- Waveforms
-- @type classWave
--------------------------------------------------------------------------------
local classWave = {}

---
-- Close given waveform.<br>
-- This will delete all waveforms intermediately stored.
-- @param self Waveform.
-- @return true on success, nil + errormsg on failure.
classWave.close = function(self)
   local ret, err = tryB(wave_delete(self.pihandle, self.handle))
   if not ret then
      return ret, err
   end
   _G._PIGPIOD_WAVEFORMS[self.handle] = nil
   return true
end
classWave.delete = classWave.close

---
-- Send waveform once.
-- @param self Waveform.
-- @return Number of DMA block in waveform.
classWave.sendOnce = function(self)
   return tryV(wave_send_once(self.pihandle, self.handle))
end

---
-- Send waveform repeatedly until cancelled.
-- @param self Waveform.
-- @return Number of DMA blocks.
classWave.sendRepeat = function(self)
   return tryV(wave_send_repeat(self.pihandle, self.handle))
end

---
-- Send the given waveform with given mode.
-- The mode is by a textstring:<br>
-- 'oneshot', 'repeat', 'oneshotsync', 'repeatsync'
-- @param self Waveform.
-- @param mode Mode to be used for sending.
-- @return Number of DMA blocks.
classWave.sendUsingMode = function(self, mode)
   local wavemode = waveModes[mode]
   if not wavemode then
      return nil, "invalid wave mode"
   end
   return tryV(send_using_mode(self.pihandle, self.handle, wavemode))
end

--------------------------------------------------------------------------------
--- Scripting
-- @type classScript
--------------------------------------------------------------------------------
local classScript = {}

---
-- Run a script.<br>
-- Scripts are executed in a specialized VM in the pigpiod daemon and provides
-- a means to produce very high toggling rates. 
-- @param self Script.
-- @param param List of up to 10 parameters for the script.
-- @return true on success, nil + errormsg on failure.
classScript.run = function(self, param)
   return tryB(run_script(self.pihandle, self.handle, param))
end

---
-- Update parameters of a script, which may already run.
-- @param self Script.
-- @param param List of up to 10 parameters replacing the corresponding
--              subset of previous parameters.
-- @return true on success, nil + errormsg on failure.
classScript.update = function(self, param)
   return tryB(update_script(self.pihandle, self.handle, param))
end

---
-- Retrieve the run status and the parameters of given script.
-- @param self Script.
-- @return Run status and list of parameters on success; nil + errormsg on failure.
classScript.status = function(self)
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
classScript.stop = function(self)
   return tryB(stop_script(self.pihandle, self.handle))
end

---
-- Delete the given script.
-- @param self Script.
-- @return true on success, nil + errormsg on failure.
classScript.delete = function(self)
   return tryB(delete_script(self.pihandle, self.handle))
end

--------------------------------------------------------------------------------
--- Pin event callback
-- @type classCallback
--------------------------------------------------------------------------------
local classCallback = {}
---
-- Cancel callback.
-- @param self Callback.
-- @return true on success, nil + errormsg on failure.
function classCallback.cancel(self)
   return tryB(callback_cancel(self.id))
end

--------------------------------------------------------------------------------
--- User event callback.
-- @type classEventCallback.
--------------------------------------------------------------------------------
local classEventCallback = {}
---
-- Cancel event callback.
-- @param self Eventcallback
-- @return true on success, nil + errormsg on failure.
function classEventCallback.cancel(self)
   return tryB(event_callback_cancel(self.id))
end

--------------------------------------------------------------------------------
-- Class: serial.
-- @type classSerial.
--------------------------------------------------------------------------------
local classSerial = {}
function classSerial.close(self)
   return tryB(serial_close(self.pihandle, self.handle))
end

function classSerial.writeByte(self, val)
   return tryB(serial_write_byte(self.pihandle, self.handle, val))
end

function classSerial.readByte(self)
   return tryV(serial_read_byte(self.pihandle, self.handle))
end

function classSerial.write(self, data)
   return tryB(serial_write(self.pihandle, self.handle, data, #data))
end

function classSerial.read(self, nbytes)
   return tryV(serial_read(self.pihandle, self.handle, nbytes))
end

function classSerial.dataAvailable(self)
   return tryV(serial_data_available(self.pihandle, self.handle))
end

--------------------------------------------------------------------------------
-- Class: i2c.
-- @type classI2C.
--------------------------------------------------------------------------------
local classI2C = {}
---
-- Close the given I2C device.
-- @param self Device.
-- @return I2C interface instance as table.
function classI2C.close(self)
   return tryB(i2c_close(self.pihandle, self.handle))
end

---
-- Send a single bit (0 or 1) via the given device.
-- @param self Device.
-- @param bit Bit to send.
-- @return true on success, nil + errormsg on failure.
function classI2C.writeQuick(self, bit)
   return tryB(i2c_write_quick(self.pihandle, self.handle, bit))
end

---
-- Send a byte via the given device.
-- @param self Device.
-- @param byte Byte to send.
-- @return true on success, nil + errormsg on failure
function classI2C.writeByte(self, byte)
   return tryB(i2c_write_byte(self.pihandle, self.handle, byte))
end

---
-- Receive  a byte via given device.
-- @param self Device.
-- @return Byte received on success, nil + errormsg on failure
function classI2C.readByte(self)
   return tryV(i2c_read_byte(self.pihandle, self.handle))
end

---
-- Write the given byte to the given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @param byte Byte to write.
-- @return true on success, nil + errormsg on failure
function classI2C.writeByteData(self, reg, byte)
   return tryB(i2c_write_byte_data(self.pihandle, self.handle, reg, byte))
end

---
-- Write the given 16 bit word to the given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @param word  Word to write.
-- @return true on success, nil + errormsg on failure
function classI2C.writeWordData(self, reg, word)
   return tryB(i2c_write_word_data(self.pihandle, self.handle, reg, byte))
end

---
-- Read a byte from the given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @return Byte read on success, nil + errormsg on failure.
function classI2C.readByteData(self, reg)
   return tryV(i2c_read_byte_data(self.pihandle, self.handle, reg))
end

---
-- Read a 16 bit word from the given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @return Word read on success, nil + errormsg on failure.
function classI2C.readWordData(self, reg)
   return tryV(i2c_read_word_data(self.pihandle, self.handle, reg))
end

---
-- Write + read (process) given 16 bit value to/freom given device.
-- @param self Device.
-- @param reg Register number.
-- @param val Word to write.
-- @return Value read on success, nil + errormsg on failure.
function classI2C.processCall(self, reg, val)
   return tryV(i2c_process_call(self.pihandle, self.handle, reg, val))
end

---
-- Write a block of bytes into given register of given device.
-- @param self Device.
-- @param reg Register number.
-- @param data Binary data stored in Lua string allowing embedded zeros.
-- @return Binary data from device on success, nil + errormsg on failure.
function classI2C.writeBlockData(self, reg, data)
   return tryB(write_block_data(self.pihandle, self.handle, reg, data, #data))
end

---
-- Read a block of bytes from given register of given device.
-- @param self Device.
-- @param reg Register number.
-- @param nbytes Number of bytes to read.
-- @return Binary data stored in Lua string allowing embedded zeros on success
--         nil + errormsg on failure.
function classI2C.readBlockData(self, reg, nbytes)
   return tryV(read_block_data(self.pihandle, self.handle, reg))
end

---
-- Send + receive a block of data to/from given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @param data Lua string with data to be written.
-- @return Data read in a Lua string allowing embedded zeros.
function classI2C.blockProcessCall(self, reg, data)
   return tryV(i2c_block_process_call(self.pihandle, self.handle, reg, data));
end

---
-- Write 1 to 32 bytes to given register on given device.
-- @param self Device.
-- @param reg Register number.
-- @param data Lua string with data to be written.
-- @return true on success, nil + errormsg on failure.
function classI2C.writeI2CBlockData(self, reg, data)
   return tryB(i2c_write_i2c_block_data(self.pihandle, self.handle, reg, data, #data))
end

---
-- Read given number of bytes from given register in given device.
-- @param self Device.
-- @param reg Register number.
-- @param nbytes Number of bytes to be read.
-- @return Number of byte read.
function classI2C.readI2CBlockData(self, reg, nbytes)
   return tryV(i2c_read_i2c_block_data(self.pihandle, self.handle, reg, nbytes))
end

---
-- Read given number bytes from given device.
-- @param self Device.
-- @param nbytes Number of bytes to be read.
-- @return Lua string with read data.
function classI2C.readDevice(self, nbytes)
   return tryV(i2c_read_device(self.pihandle, self.handle))
end

---
-- Write given data to given device.
-- @param self Device.
-- @param data Lua string with data to write.
-- @return true on success, nil + errormsg on failure.
function classI2C.writeDevice(self, data)
   return tryB(i2c_write_device(self.pihandle, self.handle, data, #data))
end

---
-- Write and read given amount of  data to/from given device.
-- @param self Device.
-- @param inbuf Lua String with data to be sent.
-- @param nbytes Number of Byte transfers.
-- @return Bytes read in a Lua string.
function classI2C.zip(self, inbuf, nbytes)
   return tryV(i2c_zip(self.pihandle, self.handle, inbuf, #inbuf, nbytes))
end

--------------------------------------------------------------------------------
-- All GPIO control and status operations occurs in the context of a session.
-- A session is create by connecting to a remote Raspberry Pi instance via
-- network or locally.
-- A session is created with a call to open(host, port)
-- @type classSession.
--------------------------------------------------------------------------------
local classSession = {}

---
-- Close session.
-- @param self Session.
-- @return true on success, nil + errormsg on error.
classSession.close = function(self)
   local res, err = tryB(pigpio_stop(self.handle))
   if not res then
      return nil, err
   end
   _G._PIGPIOD_SESSIONS[self.handle] = nil
   self.handle = nil
   return true
end

---
-- Set pin mode.
-- @param self Session.
-- @param pin GPIO number.
-- @param mode gpio.INPUT or gpio.OUTPUT.
-- @return ture on success, nil + errormsg on error.
classSession.setMode = function(self, pin, mode)
   return tryB(set_mode(self.handle, pin, mode))
end

---
-- Get pin mode.
-- @param self Session.
-- @param pin GPIO number.
-- @return true on success, nil + errormsg on error.
classSession.getMode = function(self, pin)
   return tryV(get_mode(self.handle, pin))
end

---
-- Set pull-up/down configuration of pin.
-- @param self Session.
-- @param pin GPIO number.
-- @param pud gpio.PUD_UP, gpio.PUD_DOWN or gpio.PUD_OFF
-- @return true on success, nil + errormsg on error.
classSession.setPullUpDown = function(self, pin, pud)
   return tryB(set_pull_up_down(self.handle, pin, pud)) 
end

---
-- Read pin level.
-- @param self Session.
-- @param pin GPIO number.
-- @return Pin level.
classSession.read = function(self, pin)
   return tryV(gpioread(self.handle, pin))
end

---
-- Write pin level.
-- @param self Session.
-- @param pin GPIO number.
-- @param val Level to set, 0 or 1.
-- @return true on success, nil + errormsg on failure.
classSession.write = function(self, pin, val)
   return tryB(gpio_write(self.handle, pin, val))
end

---
-- Start Software controlled PWM on given pin.
-- @param self Session.
-- @param pin GPIO number.
-- @param dutycycle Dutycycle to use (0..range) default: 0..255.
-- @return true on success, nil + errormsg on failure.
classSession.setPwmDutycycle = function(self, pin, dutycycle)
   return tryB(set_PWM_dutycycle(self.handle, pin, dutycycle))
end

---
-- Get the PWM duty cycle.
-- @param self Session.
-- @param pin GPIO number.
-- @return Active dutycycle: 0..range 
classSession.getPwmDutycycle = function(self, pin)
   return tryV(get_PWM_dutycycle(self.handle, pin))
end

---
-- Set the dutycycle range for PWM on given pin.
-- @param self Session.
-- @param pin GPIO number.
-- @param range Range between 25 and 40000.
-- @return true on success; nil + errormsg on failure
classSession.setPwmRange = function(self, pin, range)
   return tryB(set_PWM_range(self.handle, pin, range))
end

---
-- Get current PWM range for given pin.
-- @param self Session.
-- @param pin GPIO number.
-- @return Dutycycle range for given pin.
classSession.getPwmRange = function(self, pin)
   return tryV(get_PWM_range(self.handle, pin))
end

---
-- Get current PWM real range for given pin.
-- @param self Session.
-- @param pin GPIO number.
-- @return PWM real range.
classSession.getPwmRealRange = function(self, pin)
   return tryV(get_PWM_real_range(self.handle, pin))
end

---
-- Set PWM frequency.
-- @param self Session.
-- @param pin GPIO number.
-- @param frequency Frequency in Hz. 
classSession.setPwmFrequency = function(self, pin, frequency)
   return tryV(set_PWM_frequency(self.handle, pin, frequency))
end

---
-- Get PWM frequency.
-- @param self Session.
-- @param pin GPIO number.
-- @return Frequency in Hz.
classSession.getPwmFrequency = function(self, pin)
   return tryV(get_PWM_frequency(self.handle, pin))
end

---
-- Start servo pulses. Can be alternatively called via classSession.servo(...).
-- @param self Session.
-- @param pin GPIO number.
-- @param pulsewidth Pulsewidth between 500 and 2500, default: 1500.
classSession.setServoPulsewidth = function(self, pin, pulsewidth)
   return tryB(set_servo_pulsewidth(self.handle, pin, pulsewidth))
end
classSession.servo = classSession.setServoPulsewidth

---
-- Get servo pulsewidth.
-- @param self Session.
-- @param pin GPIO number.
-- @return Servo pulsewidth.
classSession.getServoPulsewidth = function(self, pin)
   return tryV(get_servo_pulsewidth(self.handle, pin))
end

---
-- Open a notification channel.
-- Data can be read from file /dev/pigpio<handle> with <handle>
-- as returned by this function.
-- @param self Session.
-- @return Notifcation channel handle.
classSession.notifyOpen = function(self)
   return tryV(notify_open(self.handle))
end

---
-- Start notification operation.
-- @param self Session.
-- @param handle Handle of notification channel.
-- @param bits Bitmask defining the GPIOs to monitor.
-- @return true on success, nil + errormsg on failure.
classSession.notifyBegin = function(self, handle, bits)
   return tryB(notify_begin(self.handle, handle, bits))
end

---
-- Pause notification monitoring.
-- @param self Session.
-- @param handle Handle of notification channel.
-- @return true on success, nil + errormsg on failure.
classSession.notifyPause = function(self, handle)
   return tryB(notify_pause(self.handle, handle))
end

---
--
classSession.notifyClose = function(self, handle)
   return tryB(notify_close(self.handle, handle))
end

classSession.setWatchdog = function(self, pin, timeout)
   return tryB(set_watchdog(self.handle, pin, timeout))
end

classSession.setGlitchFilter = function(self, pin, steady)
   return tryB(set_glitch_filter(self.handle, pin, steady))
end

classSession.setNoiseFilter = function(self, pin, steady, active)
   return tryB(set_noise_filter(self.handle, pin, steady, active))
end

classSession.readBank1 = function(self)
   return tryV(read_bank_1(self.handle))
end

classSession.readBank2 = function(self)
   return tryV(read_bank_2(self.handle))
end

classSession.clearBank1 = function(self, bits)
   return tryB(clear_bank_1(self.handle, bits))
end

classSession.clearBank2 = function(self, bits)
   return tryB(clear_bank_2(self.handle, bits))
end

classSession.setBank1 = function(self, bits)
   return tryB(clear_bank_1(self.handle, bits))
end

classSession.setBank2 = function(self, bits)
   return tryB(clear_bank_2(self.handle, bits))
end

classSession.hardwareClock = function(self, pin, clkfreq)
   return tryB(hardware_clock(self.handle, pin, clkfreq))
end

classSession.hardwarePwm = function(self, pin, pwmfreq, pwmduty)
   return tryB(hardware_PWM(self.handle, pin, pwmfreq, pwmduty))
end

classSession.getCurrentTick = function(self)
   return tryV(get_current_tick(self.handle))
end
classSession.tick = classSession.getCurrentTick

classSession.getHardwareRevision = function(self)
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

classSession.getPinning = function(self, typ)
   if typ < 1 or typ > 3 then
      return nil, "invalid type."
   end
   return pinnings[typ]
end

classSession.getPigpioVersion = function(self)
   return tryV(get_pigpio_version(self.handle))
end

--classSession.waveAddNew = function(self) return
--   tryB(wave_add_new(self.handle))
--end

--classSession.waveAddGeneric = function(self, pulses)
--   return tryV(wave_add_generic(self.handle, pulses))
--end

--classSession.waveAddSerial = function(self, pin, baud, nbits, stopbits, timeoffs, str)
--   return tryV(wave_add_serial(self.handle, pin, baud, nbits, stopbits, timeoffs, #str, str))
--end

---
-- Open a waveform as defined by parameter 'waveform'.<br>
-- An optional user defined name can be provided. If nil, a name 'wave-<wave.handle>' is
-- automatically created.
-- @param self Session.
-- @param waveform List of waveforms in the following format:
-- <ul>
-- <li>{typ, WF1, WF2, ..., WFn}.
-- <li>typ is either 'generic' or 'serial'.
-- <li>WFi is a table in one of the following formats:
-- <ul>
-- <li>generic: {on=PINMASK, off=PINMASK, delay=TIME_in_us}.
-- <li>serial: {baud=BAUDRATE, nbits=NBITS, stopbits=STOPBITS, timeoffs=TIME_in_us, STRING}.
-- </ul></ul>
-- @param name Name of the waveform (optional).
-- @return wave object handle.
classSession.waveOpen = function(self, waveform, name)
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
                 __index = classWave,
                 __gc = function(self) self:delete() end
   })
   _G._PIGPIOD_WAVEFORMS[wave.handle] = wave
   return wave
end

--[[
classSession.waveCreate = function(self, name)
   local wave = {}
   wave.handle = wave_create(self.handle)
   wave.name = name or ("wave-"..wave.handle)
   wave.pihandle = self.handle
   if wave.handle < 0 then
      return nil, perror(wave.handle), wave.handle
   end
   setmetatable(wave, {
                   __index = classWave,
                   __gc = function(self) self:delete() end
   })
   _G._PIGPIOD_WAVEFORMS[wave.handle] = wave
   return wave
end
]]

---
-- Clear all waveforms.
-- @param self Session.
-- @return true on success, nil + errormsg on failure.
classSession.waveClear = function(self)
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
classSession.waveChain = function(self, list)
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

classSession.waveTxAt = function(self)
   local ret, err = tryV(wave_tx_at(self.handle))
   if not ret then
      return nil, err
   end
   return _G._PIGPIOD_WAVEFORMS[ret].name, ret
end

classSession.waveTxBusy = function(self)
   return tryV(wave_tx_busy(self.handle))
end

classSession.waveTxStop = function(self)
   return tryB(wave_tx_stop(self.handle))
end

classSession.waveGetMicros = function(self)
   return tryV(wave_get_micros(self.handle))
end

classSession.waveGetHighMicros = function(self)
   return tryV(wave_get_high_micros(self.handle))
end

classSession.waveGetMaxMicros = function(self)
   return tryV(wave_get_max_micros(self.handle))
end

classSession.waveGetPulses = function(self)
   return tryV(wave_get_pulses(self.handle))
end

classSession.waveGetHighPulses = function(self)
   return tryV(wave_get_high_pulses(self.handle))
end

classSession.waveGetMaxPulses = function(self)
   return tryV(wave_get_max_pulses(self.handle))
end

classSession.waveGetCbs = function(self)
   return tryV(wave_get_cbs(self.handle))
end

classSession.waveGetHighCbs = function(self)
   return tryV(wave_get_high_cbs(self.handle))
end

classSession.waveGetMaxCbs = function(self)
   return tryV(wave_get_max_cbs(self.handle))
end   

classSession.trigger = function(self, pin, pulselen, level)
   return tryB(gpio_trigger(self.handle, pin, pulselen, level)) 
end

classSession.scriptOpen = function(self, code)
   local script = {}
   script.handle = store_script(self.handle, code)
   script.pihandle = self.handle
   if script.handle < 0 then
      return nil, perror(script.handle), script.handle
   end
   setmetatable(script, {
                   __index = classScript,
                   __gc = function(self) self:delete() end
   })
   return script
end
classSession.storeScript = classSession.storeScript

classSession.callback = function(self, pin, edge, func, userdata)
   local callback = {}
   callback.id = gpio.callback(self.handle, pin, edge, func, userdata)
   if callback.id < 0 then
      return nil, perror(callback.id), callback.id
   end
   setmetatable(callback, {
                   __index = classCallback,
                   __gc = function(self) self:cancel() end
   })
   return callback
end

classSession.eventCallback = function(self, event, func, userdata)
   local callback = {}
   callback.id = event_callback(self.handle, event, func, userdata)
   if callback.id < 0 then
      return nil, perror(callback.id), callback.id
   end
   setmetatable(callback, {
                   __index = classEventCallback,
                   __gc = function(self) self:cancel() end
   })
   return callback
end

classSession.waitEvent = function(self, event, timeout)
   return tryV(wait_for_event(self.handle, event, timeout))
end

classSession.triggerEvent = function(self, event)
   return tryB(event_trigger(self.handle, event))
end

classSession.openSerial = function(self, baud, tty)
   local serial = {}
   local baud = baud or 9600
   local tty = tty or "/dev/serial"
   local flags = 0
   serial.handle = serial_open(self.handle, tty, baud, flags)
   serial.pihandle = self.handle
   setmetatable(serial, {
                   __index = classSerial,
                   __gc = function(self) self:close() end
   })
   return serial
end

classSession.getPadStrength = function(self, pad)
   if pad < 0 or pad > 3 then
      return nil, "invalid pad index."
   end
   return tryV(get_pad_strength(self.handle, pad))
end

classSession.setPadStrength = function(self, pad, mamps)
   if pad < 0 or pad > 3 then
      return nil, "invalid pad index."
   end
   if mamps < 1 or mamps > 16 then
      return nil, "strength out of range (1..16) mA."
   end
   return tryB(set_pad_strength(self.handle, pad, mamps))
end

classSession.shell = function(self, name, script)
   local status = shell_(self.handle, name, script)
   if status == 32512 then
      return nil, "script not found."
   end
   return status / 256
end

classSession.openI2C = function(self, bus, address)
   local i2c = {}
   local flags = 0
   if bus < 0 then return nil, "invalid bus index." end
   if address < 0 or address > 0x7f then return nil, "invalid address." end
   i2c.handle = i2c_open(self.handle, bus, address, flags)
   i2c.pihandle = self.handle
   setmetatable(i2c, {
                   __index = classI2C,
                   __gc = function(self) self:close() end
   })
   return i2c
end

--------------------------------------------------------------------------------
-- Module functions. Most important: the function 'open(...)' is used to open
-- a session with a connectivity to the local or a remote pigpiod daemon.
-- @section Functions
--------------------------------------------------------------------------------

---
-- Open a session with given host on given port. An optional user defined name
-- can be defined; if nil a name 'sess-<sess.handle>' is created automatically.
-- @param host Hostname of target system. Default: localhost.
-- @param port Port to be used. Default: 8888.
-- @param name Name of this session (optional).
-- @return Session object of class classSession.
function open(host, port, name)
   local sess = {}
   sess.host = tostring(host or "localhost")
   sess.port = tostring(port or 8888)
   sess.handle = pigpio_start(sess.host, sess.port)
   if sess.handle < 0 then
      return nil, perror(sess.handle), sess.handle
   end
   sess.name = name or ("sess-"..sess.handle)
   _G._PIGPIOD_SESSIONS[sess.handle] = sess
   setmetatable(sess, {
                   __index = classSession,
                   __gc = function(self) self:close() end
   })
   return sess
end

---
-- Wait for a while.
-- This function blocks in time chunks allowing Lua callbacks to be called
-- by the pigpiod library. The given waiting time t is split into n=t/ts
-- blocking calls to gpio.sleep(ts) with ts = 1 ms by default.
-- @param t time to sleep in seconds.
-- @param ts time step to use - optional.
-- @return none
function wait(t, ts)
   local ts = (ts or tsleep)
   local n = t / ts
   for i = 1, n do
      sleep(ts)
   end
end

---
-- Busy wait for a while.
-- @param t time to sleep in seconds.
-- @return none.
---
function busyWait(t)
   local n = t * 3 * 1e7
   for i = 1, n do
   end
end

---
-- Convert a notification sample into a table.
---
function decodeNotificationSample(s)
   local t = {}
   t.seqno = strbyte(s,2) * 256 + strbyte(s,1)
   t.flags = strbyte(s,4) * 256 + strbyte(s,3)
   t.tick = strbyte(s,8) * 0x1000000 + strbyte(s,7) * 0x10000 + strbyte(s,6) * 0x100 + strbyte(s,5)
   t.level = strbyte(s,12) * 0x1000000 + strbyte(s,11) * 0x10000 + strbyte(s,10) * 0x100 + strbyte(s,9)
   return t
end

function info()
   return infostring
end

return _ENV