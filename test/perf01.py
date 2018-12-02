#!/usr/bin/env python

import time

import pigpio

PIN=4

TOGGLE=10000

pi = pigpio.pi() # Connect to local Pi.

s = time.time()

for i in range(TOGGLE):
   pi.write(PIN, 1)
   pi.write(PIN, 0)

e = time.time()

print("pigpio did {} toggles per second".format(int(TOGGLE/(e-s))))

pi.stop()
