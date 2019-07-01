module.exports = {
  title: "raspbee"
  RaspBeeSystem: {
    title: "Control Center Device properties"
    type: "object"
    extensions: ["xLink"]
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "string"
        required: true
      networkopenduration:
        description: "Scan for new device duration"
        type: "integer"
        default: 60
        required: false
  },
  RaspBeeMotionSensor: {
    title: "RaspBee MotionSensor"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "integer"
        required: true
      resetTime:
        description: "Reset time in seconds"
        type: "integer"
        default: 60
        required: false
      sensorIDs:
        description: "All the ids of the sensors"
        type: "array"
        default: []
        items:
          type: "integer"
  },
  RaspBeeContactSensor: {
    title: "RaspBee ContactSensor"
    type: "object"
    extensions: ["xConfirm", "xLink", "xClosedLabel", "xOpenedLabel", "xAttributeOptions"]
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "integer"
        required: true
      resetTime:
        description: "Optional auto reset time in milli seconds"
        type: "integer"
        default: 0
      inverted:
        description: "Invert open/close state of contact device."
        type: "boolean"
        default: false
  },
  RaspBeeLightSensor: {
    title: "RaspBee LightSensor"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "integer"
        required: true
  },
  RaspBeeSwitchSensor: {
    title: "RaspBee SwitchSensor"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "integer"
      resetTime:
        description: "Auto reset time in milliseconds"
        type: "integer"
        default: 100
  },
  RaspBeeWaterSensor: {
    title: "RaspBee WaterSensor"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "integer"
  },
  RaspBeeRemoteControlNavigator: {
    title: "RaspBee MotionSensor"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "string"
      buttons:
        description: "Remote buttons"
        type: "array"
        items:
          type: "object"
          properties:
            id:
              type: "string"
            text:
              type: "string"
  },
  RaspBeeSwitch: {
    title: "Raspbee Switch Device"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
  },
  RaspBeeDimmer: {
    title: "Raspbee Dimmer Light Device"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
      transtime:
        description: "Raspbee transtime"
        type: "integer"
        default: 5
  },
  RaspBeeCT: {
    title: "Raspbee Color Temperature Light Device"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
      transtime:
        description: "Raspbee transtime"
        type: "integer"
        default: 5
  },
  RaspBeeRGB: {
    title: "Raspbee Color Temperature Light Device"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
      transtime:
        description: "Raspbee transtime"
        type: "integer"
        default: 5
  },
  RaspBeeRGBCT: {
    title: "Raspbee Color Temperature Light Device"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
      transtime:
        description: "Raspbee transtime"
        type: "integer"
        default: 5
  },
  RaspBeeDimmerGroup: {
    title: "Raspbee Dimmer Light Device"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
      transtime:
        description: "Raspbee transtime"
        type: "integer"
        default: 5
  },
  RaspBeeRGBCTGroup: {
    title: "Raspbee Dimmer Light Device"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
      transtime:
        description: "Raspbee transtime"
        type: "integer"
        default: 5
  },
  RaspBeeMultiSensor: {
    title: "Raspbee Multi sensor"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:
      deviceID:
        description: "Raspbee address"
        type: "string"
      sensorIDs:
        description: "All the ids of the sensors"
        type: "array"
        items:
          type: "integer"
      supportsBattery:
        description: "does this sensor have a battery?"
        type: "boolean"
        default: false
      supports:
        description: "Feature List"
        type: "array"
        default: []
        items:
          type: "string"
      configMap:
        description: "Config map"
        type: "array"
        default: []
        items:
          type:"object"
          properties:
            id:
              type: "integer"
            parameter:
              type: "string"
            value:
              type: "integer"
      temperatureAcronym:
        description: "temperature acronym"
        type: "string"
        default: "T"
      humidityAcronym:
        description: "humidity acronym"
        type: "string"
        default: "H"
      pressureAcronym:
        description: "pressure acronym"
        type: "string"
        default: "P"
      resetTime:
        description: "Auto reset time in milliseconds"
        type: "integer"
        default: 100
  },
  RaspBeeGroupScenes: {
    title: "RaspBeeScenes"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
      buttons:
        description: "Scene buttons"
        type: "array"
        items:
          type: "object"
          properties:
            id:
              type: "integer"
            text:
              type: "string"
            name:
              type: "string"
  }
}
