pimatic-raspbee
=======================

[![build status](https://img.shields.io/travis/treban/pimatic-raspbee.svg?branch=master?style=flat-square)](https://travis-ci.org/treban/pimatic-raspbee)
[![version](https://img.shields.io/npm/v/pimatic-raspbee.svg?branch=master?style=flat-square)](https://www.npmjs.com/package/pimatic-raspbee)
[![downloads](https://img.shields.io/npm/dm/pimatic-raspbee.svg?branch=master?style=flat-square)](https://www.npmjs.com/package/pimatic-raspbee)
[![license](https://img.shields.io/github/license/treban/pimatic-raspbee.svg)](https://github.com/treban/pimatic-raspbee)


This plugin provides a raspbee interface for [pimatic](https://pimatic.org/).

#### Features

* Auto-discover devices, groups and sensors
* Control lights
* Control groups
* Control scenes
* Support for all sensors
* Observe changes over websocket
* Start pairing for new devices
* Backup the deconz config

### Prerequisite

You need a rasbpee or conbee device and the [deCONZ REST API](https://github.com/dresden-elektronik/deconz-rest-plugin/blob/master/README.md#install-deconz) must be installed and configured.

An other good solution is to run deconz as a [docker container](https://github.com/marthoc/docker-deconz).

### => [go to the WIKI](https://github.com/treban/pimatic-raspbee/wiki) - there are installation instructions and other useful tips.

### Installation

Just activate the plugin over the pimatic webUI. The plugin manager automatically installs the package with his dependencys.

### Configuration

You can also load the plugin by adding following in the config.json from your pimatic server:

    {
      "plugin": "raspbee",
      "debug": true,
      "active": true,
      "ip": "<deconz ip>",
      "port": "<deconz port>"
    }

### Usages

To create a connection to the raspbee gateway, **the gateway must be unlocked over the deconz UI.**
[check the unlock howto](https://github.com/treban/pimatic-raspbee/wiki/Connect-the-raspbee-plugin-to-deconz)
Then make a device discovery in pimatic.

### Supported devices

#### Lights

| pimatic Device type    | Feature                      | Deconz Resource Type
| ---------------------- | ---------------------------- | --------------
| `RaspBeeSwitch`        | switch on/off                | `On/Off plug-in unit` & `Smart plug`
| `RaspBeeDimmer`        | switch and dimm light        | `Dimmable light`
| `RaspBeeCT`            | change temperature           | `Color temperature light`
| `RaspBeeRGB`           | change color                 | `Color light`
| `RaspBeeRGBCT`         | change color and temperature | `Extended color light`


#### Groups

| pimatic Device type               | Feature                      | Deconz Resource Type
| --------------------------------- | ---------------------------- | --------------
| `RaspBeeDimmerGroup` (DEPRECATED) | switch and dimm              | `Group`
| `RaspBeeRGBCTGroup`               | change color and temperature | `Group`
| `RaspBeeGroupScenes`              | change temperature           | `Group Scenes`


#### Sensors

All sensors are represented as a `RaspBeeMultiDevice`.
The device has 3 arrays.
* associated device IDs
* support parameter flag
* configMap

| supports parameter flag  | Feature                      | Deconz Resource Type
| ------------------------ | ---------------------------- | ---------------
| `battery`                | %                            | (any battery-powered sensor)
| `lowbattery`             | bool                         | (any IAS Zone sensor)
| `carbon`                 | bool                         | ZHACarbonMonoxide
| `switch`                 | string                       | ZHASwitch
| `fire`                   | bool                         | ZHAFire
| `humidity`               | %                            | ZHAHumidity
| `temperature`            | °C                           | ZHATemperature and any sensor with temperaure support
| `presence`               | bool                         | ZHAPresence
| `dark`                   | bool                         | ZHAPresence & ZHALightLevel
| `lux`                    | lux                          | ZHALightLevel
| `daylight`               | bool                         | ZHALightLevel
| `open`                   | bool                         | ZHAOpenClose
| `pressure`               | hPA                          | ZHAPressure
| `water`                  | bool                         | ZHAWater
| `vibration`              | bool                         | ZHAVibration
| `tampered`               | bool                         | (any IAS Zone sensor)
| `consumption`            | Wh                           | ZHAConsumption
| `power`                  | W                            | ZHAPower & ZHAConsumption
| `voltage`                | V                            | ZHAPower
| `current`                | mA                           | ZHAPower


The other device types are DEPRECATED

* RaspBeeMotionSensor
* RaspBeeContactSensor
* RaspBeeLightSensor
* RaspBeeSwitchSensor
* RaspBeeWaterSensor

### RaspBeeSystem device

#### discover lights & discover sensors

#### create backup
This button creates a local backup of the deconz config

#### send config
This button sends for all devices all config parater to the deconz apikey.








### ActionProvider

* **"activate group scene -name-"**  

* **"set color temp -name- to -value-"**  

* **"set color rgb -name- to -hexvalue-"**

Example:
set color temp Light 1 to 10 and set color rgb Light 3 to #121212 and activate group scene All-ON


### PredicateProvider

* **"received from -name- event "2001""**


### ButtonEvents
|   | Value | Action
| - | ----- | -------
| 0 | x000  | Initial Press
| 1 | x001  | Hold
| 2 | x002  | Release (after press)
| 3 | x003  | Release (after hold)
| 4 | x004  | Double press
| 5 | x005  | Triple press
| 6 | x006  | Quadruple press
| 7 | x007  | Shake
| 8 | x008  | Drop
| 9 | x009  | Tilt
| 10 | x010 | Many press



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
* 0.0.10 : add device type "Smart plug" for aqara devices fix for #19 & #22
* 0.0.11 : New features and BUGFIX
  * BUGFIX #28 & #29
  * Groups with ct and rgb #22
  * support for all sensor types #23
  * device and sensor discovery over pimatic #25
  * backup over pimatic #26
  * new RaspBeeMultiSensor device which supports all sensor types

----------------------------
### Contributors

* [kosta](https://github.com/treban)
* [sweebee](https://github.com/sweebee)
* [mwittig](https://github.com/mwittig)
