%module pigpiod_core
%{
#include <stdio.h>
#include "pigpiod_if2.h"
#include "pigpiod_util.h"
  struct eventstat *get_event_statistics(void);
  int clear_event_statistics(void);
%}
%include <stdint.i>
%include <typemaps.i>
 // Global renaming - remove 'gpio' prefix because we have a namespace
%rename("%(regex:/^(PI_)(.*)/\\2/)s") "";
%rename(time) time_time;
%rename(sleep) time_sleep;
%rename(perror) pigpio_error;
%rename(ifVersion) pigpiod_if_version;
//%rename(startThread) start_thread;
//%rename(stopThread) stop_thread;

// Replacements of native calls
%native (start_thread) int utlStartThread(lua_State *L);
%native (stop_thread) int utlStopThread(lua_State *L);
%native (wave_add_generic) int utlWaveAddGeneric(lua_State *L);
%native (run_script) int utlRunScript(lua_State *L);
%native (update_script) int utlUpdateScript(lua_State *L);
%native (script_status) int utlScriptStatus(lua_State *L);
%native (callback) int utlCallback(lua_State *L);
%native (event_callback) int utlEventCallback(lua_State *L);
%native (serial_read) int utlSerialRead(lua_State *L);
%native (i2c_read_block_data) int utlI2CReadBlockData(lua_State *L);
%native (i2c_block_process_call) int utlI2CBlockProcessCall(lua_State *L);
%native (i2c_read_i2c_block_data) int utlI2CReadI2CBlockData(lua_State *L);
%native (i2c_read_device) int utlI2CReadDevice(lua_State *L);
%native (i2c_zip) int utlI2CZip(lua_State *L);
%native (spi_read) int utlSPIRead(lua_State *L);
%native (spi_xfer) int utlSPITransfer(lua_State *L);
%native (bb_spi_xfer) int utlSPIbbTransfer(lua_State *L);
%native (bb_serial_read) int utlSerialbbRead(lua_State *L);
%native (file_read) int utlFileRead(lua_State *L);
%native (file_list) int utlFileList(lua_State *L);
%native (bsc_i2c) int utlI2CSlaveTransfer(lua_State *L);

// type mapping
%typemap(in) uint_32_t {
}

// Headers to parse
%include /usr/local/include/pigpiod_if2.h
%include pigpio_const.h
struct eventstat {
  unsigned long maxcount;
  unsigned long drop;
};
%newobject getEventStatistics;
struct eventstat *get_event_statistics(void);
int clear_event_statistics(void);
