module.exports = {
  title: "RaspBee plugin config options"
  type: "object"
  required: []
  properties:
    debug:
      description: "Enabled debug messages"
      type: "boolean"
      default: false
    ip:
      description: "IP address from the deconz rest api"
      type: "string"
      required: true
    port:
      description: "port from the deconz rest api"
      type: "string"
      default: 80
    apikey:
      description: "api key"
      type: "string"
      default: ""
}
