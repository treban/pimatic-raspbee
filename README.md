pimatic-raspbee
=======================

[![build status](https://img.shields.io/travis/treban/pimatic-raspbee.svg?branch=master?style=flat-square)](https://travis-ci.org/treban/pimatic-raspbee)
[![version](https://img.shields.io/npm/v/pimatic-raspbee.svg?branch=master?style=flat-square)](https://www.npmjs.com/package/pimatic-raspbee)
[![downloads](https://img.shields.io/npm/dm/pimatic-raspbee.svg?branch=master?style=flat-square)](https://www.npmjs.com/package/pimatic-raspbee)
[![license](https://img.shields.io/github/license/treban/pimatic-raspbee.svg)](https://github.com/treban/pimatic-raspbee)


This plugin provides a raspbee interface for [pimatic](https://pimatic.org/).

!! This plugin is still in beta state !!

#### Features

* Discover devices, groups and sensors
* Support for motion sensors
* Support for remote controls
* Control lights
* Control groups
* Observe changes


### Prerequisite

The Raspbee device with the [deCONZ REST API](https://dresden-elektronik.github.io/deconz-rest-doc/) must be installed and configured.

### Installation

Just activate the plugin in your pimatic config. The plugin manager automatically installs the package with his dependencys.

### Configuration

You can load the plugin by adding following in the config.json from your pimatic server:

    {
      "plugin": "raspbee",
      "debug": true,
      "active": true,
      "ip": "<deconz ip>",
      "port": "<deconz port>"
    }

### Usages

To create a connection to the raspbee gateway, the gateway must be unlocked.
Then make a device discovery in pimatic.

* RaspBeeMotionSensor
The motion sensor is like a normal presence sensor.
You can configure an optional auto-reset time in milliseconds.

* RaspBeeRemoteControlNavigator
This device represents a 5 button remote control. THe device is lika a normal button device.
There a predefined buttons which a useable in rules with this format: <raspbee_<deviceid>_button_
possible keys are:
power
up
down
left
right
longpower
longright
longleft
longup
longdown


### ChangeLog
* 0.0.2 : First public version
* 0.0.3 : BUGFIX #1
* 0.0.3 : BUGFIX
