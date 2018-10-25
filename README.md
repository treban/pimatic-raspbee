pimatic-raspbee
=======================

[![build status](https://img.shields.io/travis/treban/pimatic-raspbee.svg?branch=master?style=flat-square)](https://travis-ci.org/treban/pimatic-raspbee)
[![version](https://img.shields.io/npm/v/pimatic-raspbee.svg?branch=master?style=flat-square)](https://www.npmjs.com/package/pimatic-raspbee)
[![downloads](https://img.shields.io/npm/dm/pimatic-raspbee.svg?branch=master?style=flat-square)](https://www.npmjs.com/package/pimatic-raspbee)
[![license](https://img.shields.io/github/license/treban/pimatic-raspbee.svg)](https://github.com/treban/pimatic-raspbee)


This plugin provides a raspbee interface for [pimatic](https://pimatic.org/).

!! This plugin is still in beta state !!

#### Features

* Auto-discover devices, groups and sensors
* Support for motion sensors
* Support for remote controls and switches
* Support for temperature, humidity, pressure and much more sensors
* Control lights
* Control groups
* Controle scenes
* Observe changes over websocket

### Prerequisite

You need a rasbpee or conbee device and [deCONZ REST API](https://github.com/dresden-elektronik/deconz-rest-plugin/blob/master/README.md#install-deconz) must be installed and configured.

An other good solution is to run deconz as a [docker container](https://github.com/marthoc/docker-deconz).

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

### Supported devices

* **RaspBeeLightDevices**
There are three typs of light devices:
  - Dimmer only
  - Color temperature
  - RGB

* **RaspBeeSwitch**

* **RaspBeeDimmerGroup**

* **RaspBeeGroupScenes**
The scenes are associated with the groups
and are represented by a button device.
After each restart of pimatic all scenes are updated.

* **RaspBeeMotionSensor**

The motion sensor is like a normal presence sensor.
You can configure an optional auto-reset time in milliseconds.
The sensor has an optional lux attribute.

* **RaspBeeMultiSensor**
Devices with more than one sensor are represented as multidevices.

* **RaspBeeWaterSensor**

* **RaspBeeLightSensor**

* **RaspBeeContactSensor**

* **RaspBeeSwitchSensor**

* **RaspBeeRemoteControlNavigator**

This device represents a 5 button remote control and is like a normal button device.
There a predefined buttons which are useable in rules with this format: raspbee_deviceid_button
possible button are:
power / up /
down /
left /
right /
longpower /
longright /
longleft /
longup /
longdown

### ActionProvider

* **"activate group scene <name>"**  

* **"set color temp <name> to <value>"**  

* **"set color rgb <name> to <hexvalue>"**

Example:
set color temp Light 1 to 10 and set color rgb Light 3 to #121212 and activate group scene All-ON

### ChangeLog
* 0.0.2 : First public version
* 0.0.3 : BUGFIX #1
* 0.0.4 : BUGFIX
* 0.0.5 : New features and BUGFIX
  * MultiSensor devices
  * Scenes
* 0.0.6 : HOTFIX
* 0.0.7 : New features and BUGFIX
  * Actionprovider for scenes and light color / rgb
  * Scenes are now a standalone device as a button device
* 0.0.8 : New features and BUGFIX
  * WebSocket keep alive
  * support for wall plug
  * Fix for #16 & #21
  * debug output for device discovery
  * xAttributeOptions
  * pressureAttribute in hPa instead kPa
* 0.0.9 : HOTFIX
* 0.0.10 : add device type "Smart plug" for aqara devices

----------------------------
### Contributors

* [kosta](https://github.com/treban)
* [sweebee](https://github.com/sweebee)
* [mwittig](https://github.com/mwittig)
