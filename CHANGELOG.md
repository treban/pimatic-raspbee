# Changelog
All notable changes to this project will be documented in this file.

## [0.1.0][Unreleased]
### Added
* a new groups device **RaspBeeRGBCTGroup**  with ct and rgb #22   
* a new **RaspBeeSystem** device which represents the deconz api
  * device and sensor discovery over pimatic #25  
  * backup deconz api #26
  * send device configuration to deconz
* homekit support for hap plugin dimmer and RGB capabilities #30  
* **new action provider for dimming /  all actions with transition time option**   
  Example: **dim raspbee** Light to 75 **transition time 2s** and set color rgb LightRGB to #FF0000 **with transition time 10s**
* new predicate provide: **recieved from** Switch1 event "2001"

### Changed
* **new RaspBeeMultiSensor device** which supports all sensor types   
  The new sensor device has been completely refactored and supports all sensor types now #23.
  It also replaces all old sensor devices. However, these are still available for downward compatibility.

### Fixed
* #28
* #29

### Deprecated
* Following device types are now deprecated
  * RaspBeeMotionSensor
  * RaspBeeContactSensor
  * RaspBeeLightSensor
  * RaspBeeSwitchSensor
  * RaspBeeWaterSensor
  * RaspBeeDimmerGroup

### Security
* Update all package dependencies
  (node 4 support still preserved)

## [0.0.10]
### Added  
* "Smart plug"
### Fixed
* #19
* #22

## [0.0.9]
### Fixed
* Hotfix, plugin not starting

## [0.0.8]
### Added  
* WebSocket keep alive
* support for wall plug
* debug output for device discovery
* xAttributeOptions
* pressureAttribute in hPa instead kPa

### Fixed
* #16
* #21

## [0.0.7]
### Added  
* Actionprovider for scenes and light color / rgb
* Scenes are now a standalone device as a button device

## [0.0.6]
### Fixed
* Hotfix, plugin not starting

## [0.0.5]
### Added
* MultiSensor devices
* Scenes

## [0.0.4]
### Fixed
* Some BUGFIX

## [0.0.3]
### Fixed
* BUGFIX #1

## [0.0.2]
First public version
