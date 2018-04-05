module.exports = {
  title: "raspbee"
  RaspBeeSystem: {
    title: "Controle Center Device properties"
    type: "object"
    extensions: ["xLink"]
    properties:
      messagecount:
        description: "Message count to display"
        type: "integer"
        default: 10
  },
  RaspBeeMotionSensor: {
    title: "RaspBee MotionSensor"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "string"
        required: true
      resetTime:
        description: "Optional auto reset time in milli seconds"
        type: "integer"
        default: 0
        required: false
  },
  RaspBeeContactSensor: {
    title: "RaspBee ContactSensor"
    type: "object"
    extensions: ["xConfirm", "xLink", "xClosedLabel", "xOpenedLabel"]
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "string"
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
        type: "string"
        required: true
  },
  RaspBeeRemoteControlNavigator: {
    title: "RaspBee MotionSensor"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "string"
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
}
