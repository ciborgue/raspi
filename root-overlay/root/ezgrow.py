#!/usr/bin/env python3
import re
import json
import smtplib
import time
import datetime
import tempfile
from deepmerge import Merger
from subprocess import getstatusoutput

class EZGrow():
	def __init__(self):
		self.conf = dict()
		self.merger = Merger(
				[ (list, ["append"]), (dict, ["merge"])],
				["override"],
				["override"]
				)
		for c in ['/etc/ezgrow/ezgrow.json', '/site/etc/ezgrow/ezgrow.json']:
			try:
				with open(c, 'r') as s:
					self.merger.merge(self.conf, json.load(s))
			except Exception as e:
				print("Can't load config %s: [%s]" % (c, e))
		if len(self.conf) == 0:
			raise RuntimeError('Config is empty, NOT rebooting the host')

	def reload_sensors(self):
		value = dict()
		for f in self.conf['json']:
			try:
				with open(f) as s:
					self.merger.merge(value, json.load(s))
			except Exception as e:
				print("Can't load sensor %s: [%s]" % (f, e))
		return value

	def update_watchdog(self):
		try:
			self.watchdog.write('X')
			self.watchdog.flush()
		except AttributeError:
			print("Opening watchdog device %s" % self.conf['watchdog'])
			self.watchdog = open(self.conf['watchdog'], 'w')

	def reload_gpio(self):
		status,gpio = getstatusoutput('gpio allreadall')
		assert(not status), 'Failed to run gpio'
		value = dict()
		for line in filter(lambda x: len(x) > 10 and x[1][0].isdigit(),
				map(lambda x: x.split(None), gpio.splitlines())):
			value[int(line[1])] = 1 if line[5] == 'High' else 0     # col 1
			value[int(line[8])] = 1 if line[12] == 'High' else 0    # col 2
		return value

	def reload_snmp(self):
		on_value = self.conf['snmp']['value']['on']
		return dict(map(lambda x: (x[0], on_value == self.snmp_get(x[1])), \
				self.conf['snmp']['oid'].items()))

	def snmp_get(self, oid):
		status,snmp = getstatusoutput('snmpget -v1 -Oq -c%s %s %s' % \
				(self.conf['snmp']['pass'], self.conf['snmp']['addr'], oid)
				)
		assert(not status), 'Failed to run snmpget'
		for line in map(lambda x: x.split(None), snmp.splitlines()):
			return line[1]

	def snmp_set(self, oid, kind, value):
		status,snmp = getstatusoutput('snmpset -v1 -Oq -c%s %s %s %s %s' % \
				(self.conf['snmp']['pass'], self.conf['snmp']['addr'], oid, kind, value)
				)
		assert(not status), 'Failed to run snmpset'
		return self.snmp_get(oid)

	def avg(self): # return [min. max, avg]
		value, count = [ float('inf'), float('-inf'), 0.0 ], 0.0
		for inside in self.conf['inside-temperature']:
			for sensor in filter(lambda x: x.startswith(inside), self.conf['tempdata']):
				value[0] = min(value[0],
						float(self.conf['tempdata'][sensor]['temperature']))
				value[1] = max(value[1],
						float(self.conf['tempdata'][sensor]['temperature']))
				value[2] += float(self.conf['tempdata'][sensor]['temperature'])
				count += 1.0
		value[2] = value[2] / count if count != 0 else float('inf')
		return value

	def _any_low(self, name): # returns True if any pin is low
		for pin in self.conf['gpio'][name]:
			#print('Checking pin (l): %d' % pin)
			if self.conf['gpiodata'][pin] == 0:
				return True
		return False

	def _any_high(self, name): # returns True if any pin is high
		for pin in self.conf['gpio'][name]:
			#print('Checking pin (h): %d' % pin)
			if self.conf['gpiodata'][pin] != 0:
				return True
		return False

	def get_pump(self):
		return not(self._any_low('leak') \
				or self._any_high('water-high'))

	def get_lamp(self):
		mode = self.conf['time']['mode'] # grow or bloom
		return self.conf['timestamp'].hour < self.conf['time'][mode]['off'] \
				or self.conf['timestamp'].hour > self.conf['time'][mode]['on']

	def get_fan_ext(self):
		avg = self.avg()[2]
		fan = self.conf['snmpdata']['fan-ext']
		if fan:
			# fan is on now
			if avg < self.conf['temp']['off']:
				return False
		else:
			# fan is off now
			if avg > self.conf['temp']['on']:
				return True
		return fan != 0 # keep fan unchanged

	def run(self):
		for group in self.conf['gpio']:
			for pin in self.conf['gpio'][group]:
				status,gpio = getstatusoutput('gpio -g mode %d in' % pin)
				assert(not status), 'Failed to run gpio mode in'
				status,gpio = getstatusoutput('gpio -g mode %d down' % pin)
				assert(not status), 'Failed to run gpio mode down'

		while True:
			# used for system schedulig (lamps, etc.)
			self.conf['timestamp'] = datetime.datetime.now()

			self.update_watchdog()
			self.conf['gpiodata'] = self.reload_gpio()

			self.update_watchdog()
			self.conf['tempdata'] = self.reload_sensors()

			self.update_watchdog()
			self.conf['snmpdata'] = self.reload_snmp()

			self.update_watchdog()
			self.conf['update'] = {
					'lamp': self.get_lamp(), # this only depend on timer
					'pump': self.get_pump(), # this only depend on sensors
					'fan-ext': self.get_fan_ext(),
					'fan-int': True, # TODO some logic
					#'lamp-aux': False, # TODO
					}

			for outlet in self.conf['update'].items():
				self.update_watchdog()
				if outlet[1] == self.conf['snmpdata'][outlet[0]]:
					continue
				oid = self.conf['snmp']['oid'][outlet[0]]
				value = self.conf['snmp']['value']['on' if outlet[1] else 'off']
				self.snmp_set(oid, 'i', value)

			tm = datetime.datetime.now() # update timestamp
			self.conf['timestamp'] = '%s' % tm # is not JSON serializable

			with open(tempfile.gettempdir() + '/status.json', 'w') as s:
				json.dump(self.conf, s, indent=4, sort_keys=True)
			time.sleep(self.conf['sleep'] - tm.second % self.conf['sleep'])

EZGrow().run()
# vim: set ts=4 sts=4 sw=4 noet:
