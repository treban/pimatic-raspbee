module.exports = {
  title: "raspbee"
  RaspBeeSystem: {
    title: "Control Center Device properties"
    type: "object"
    extensions: ["xLink"]
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "integer"
        required: true
      networkopenduration:
        description: "Scan for new device duration"
        type: "integer"
        default: 60
        required: false
      backupfolder:
        description: "backupfolder"
        type: "string"
        default: null
        required: false
  },
  RaspBeeMotionSensor: {
    title: "RaspBee MotionSensor"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:
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
  },
  RaspBeeContactSensor: {
    title: "RaspBee ContactSensor"
    type: "object"
    extensions: ["xLink", "xClosedLabel", "xOpenedLabel", "xAttributeOptions"]
    properties:
      resetTime:
        description: "Optional auto reset time in milli seconds"
        type: "integer"
        default: 0
      sensorIDs:
        description: "All the ids of the sensors"
        type: "array"
        default: []
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
  },
  RaspBeeLightSensor: {
    title: "RaspBee LightSensor"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:
      sensorIDs:
        description: "All the ids of the sensors"
        type: "array"
        default: []
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
  },
  RaspBeeSwitchSensor: {
    title: "RaspBee SwitchSensor"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:
      resetTime:
        description: "Auto reset time in milliseconds"
        type: "integer"
        default: false
      sensorIDs:
        description: "All the ids of the sensors"
        type: "array"
        default: []
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
  },
  RaspBeeWaterSensor: {
    title: "RaspBee WaterSensor"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:
      sensorIDs:
        description: "All the ids of the sensors"
        type: "array"
        default: []
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
  },
  RaspBeeRemoteControlNavigator: {
    title: "RaspBee MotionSensor"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "integer"
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
  RaspBeeRGBDummy: {
    title: "Raspbee Color Temperature Light Dummy Device"
    type: "object"
    properties: {}
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
        default: []
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
      temperatureOffset:
        description: "temperature offset"
        type: "number"
        default: 0
      humidityAcronym:
        description: "humidity acronym"
        type: "string"
        default: "H"
      pressureAcronym:
        description: "pressure acronym"
        type: "string"
        default: "P"
      powerAcronym:
        description: "power acronym"
        type: "string"
        default: "P"
      currentAcronym:
        description: "power acronym"
        type: "string"
        default: "I"
      voltageAcronym:
        description: "voltage acronym"
        type: "string"
        default: "U"
      consumtionAcronym:
        description: "consumtion acronym"
        type: "string"
        default: "W"
      resetTime:
        description: "Auto reset time in milliseconds"
        type: "integer"
        default: 1000
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
  },
  RaspBeeCover: {
    title: "Raspbee Cover Device"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
      rollerTime:
        description: "time in seconds for cover to move from closed to open"
        type: "number"
        default: 20
      invertedOut:
        description: "If lift / open states are send inverted to the shutter"
        type: "boolean"
        default: false
      invertedIn:
        description: "If lift / open states are received inverted from the shutter"
        type: "boolean"
        default: false
  },
  RaspBeeWarning: {
    title: "Raspbee warning Device"
    type: "object"
    extensions: ["xAttributeOptions"]
    properties:
      deviceID:
        description: "Raspbee address"
        type: "integer"
  }
}
