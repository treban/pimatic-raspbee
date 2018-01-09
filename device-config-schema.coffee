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
  },
  RaspBeeRemoteControl: {
    title: "RaspBee MotionSensor"
    type: "object"
    properties:
      deviceID:
        description: "Raspbee device id"
        type: "string"
  },
}
