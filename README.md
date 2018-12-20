# LuaPIGPIOD
Use Lua to control a Raspberry PI's GPIO pins from user space

LuaPGPIO is a binding to the [pigpiod](https://github.com/joan2937/pigpio) library. 

It provides indirect access to the GPIO pins of a Raspberry Pi connected via network interface (local or remote host). It talks to the GPIO daemon named `pigpiod` running in the connected platform.

LuaPIGPIOD can produce approximately 12000 toggles per second when connected to localhost. This is about twice as fast as the Python frontend to pigpiod. 

## General
LuaPIGPIOD uses [SWIG](http://www.swig.org/) to automatically generate the binding from pgpio header file pigpio_if2.h. The original names of definitions have been changed to a more structured naming scheme using CamelCase notation.

## Sessions
All operations are executed in the context of sessions. A session is an instance of Lua defined class `cSession`. A specific instance `sess` of this class is created by calling

`sess = gpio.open(host, port, name)`. 

Multiple session instances may exist in parallel allowing any host to control the GPIO pins of multiple Raspberry Pi boards:

Basic GPIO operation are then performed in methods provided called as a method of such a session:

`success, err = sess.write(sess, pin, level)` or
`success, err = sess:write(pin, level)`.

## Advanced Features ##
There are classes for advanced features like waveforms, scripts, callbacks, event callbacks, serial, I2C or SPI interfaces.

Instances are created by calling the corresponding constructor function within the running session, e.g.:

`dev, err = sess:openI2C(bus, address)`

Device specific operations are executed as methods of such devices, e.g.:

`data, err = dev:readBlockData(register, nbytes)`.

Binary data is handled via Lua strings which allow embedded zeros.



## Event Handling
LuaPIGPIOD provides means to write event handlers functions as Lua functions. This occurs via Lua's debug hook interface in order to avoid pre-emptive calls of Lua defined event handlers.
Event issued by pigpiod c i/f are queued in a linear list waiting for subsequent processing by Lua debug hooks. During execution of such a hook additional events may occur, which are simply stored in the linear list and the processed as debug hooks one after the other.
Each event is tagged with an additional time (tick) parameter in order to keep track of it's occurence. This gives Lua knowledge when the event occured independently on how many events are waiting in the qeueue for further processing and how long the event needs to travel from the connected host to the machine running the Lua script.

Events may receive an arbitrary Lua value as an opaque parameter defined by the user.

The event handling kernel monitors the size of the internal event FIFO and counts the events that have been dropped due to FIFO overflow.

## Thread Handling
The pigpiod c i/f library provides a simple interface for starting and stopping threads. LuaPIGPIOD associates a separate Lua state with each thread. The new state receives an arbitrary number of arguments which must be of type number, string or boolean. Tables and function must first be externally serialized into a string.

## Status
#### Done: 
* GPIO 
* Pin events and callbacks 
* waves
* scripts
* serial i/f
* i2c i/f
* spi i/f
* threads

#### ToDo: 
* Bit banging (software IO based) interfaces bbi2c, bbserial, bbspi
* i2c and spi slave
* Files (I used luaposix mostly)

#### Not tested
* Event callbacks - I wasn't able to bring them to work (not a luapigpiod issue probably).

