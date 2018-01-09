module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  t = env.require('decl-api').types

  Request = require 'request-promise'
  WebSocket = require 'ws'
  events = require 'events'

   class RaspBeePlugin extends env.plugins.Plugin

    @apikey = "KEY"

    init: (app, @framework, @config) =>
      deviceConfigDef = require("./device-config-schema.coffee")
      @apikey = "API"
      @websocketport = null

      @framework.deviceManager.registerDeviceClass("RaspBeeMotionSensor",{
        configDef : deviceConfigDef.RaspBeeMotionSensor,
        createCallback : (config, lastState) => new RaspBeeMotionSensor(config,lastState, @framework)
      })

      @framework.deviceManager.registerDeviceClass("RaspBeeRemoteControl",{
        configDef : deviceConfigDef.RaspBeeRemoteControl,
        createCallback : (config, lastState) => new RaspBeeRemoteControl(config,lastState, @framework)
      })


      @framework.on "after init", =>
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js',   "pimatic-raspbee/app/raspbee.coffee"
          mobileFrontend.registerAssetFile 'html', "pimatic-raspbee/app/raspbee.jade"
          mobileFrontend.registerAssetFile 'css',  "pimatic-raspbee/app/raspbee.css"

      @Connector = new RaspBeeConnection("hostname","3535",@apikey)
      @Connector.on "event", (data) =>
        env.logger.debug(data)
      #@framework.on('destroy', (context) =>
      #  env.logger.info("Plugin finish...")
      #)

  class RaspBeeConnection extends events.EventEmitter

    constructor: (@host,@port,@apikey) ->
      super()

      # Connect to WebSocket
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/config").then( (res) =>
        rconfig = JSON.parse(res)
        env.logger.debug("Connection establised")
        env.logger.debug("Name #{rconfig.name}")
        env.logger.debug("API #{rconfig.apiversion}")
        @websocketport=rconfig.websocketport
        if ( @websocketport != undefined )
          env.logger.debug("API key valid")
          @ws = new WebSocket('ws://mia:'+@websocketport, {
                perMessageDeflate: false
          })
          @ws.on('message', (data) =>
            jdata = JSON.parse(data)
            env.logger.debug(jdata)
            eventmessage =
              id : jdata.id
              type : jdata.r
              state : jdata.state
              config : jdata.config
            @emit 'event', (eventmessage)
          )
          @ws.on('error', (err) =>
            env.logger.error(err)
          )
        else
          env.logger.error("API key not valid")
      ).catch ( (err) =>
        env.logger.error(err)
        env.logger.error("Connection could not be establised")
      )

    getSensor: (id) =>
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/sensors/"+id).then( (res) =>
        return JSON.parse(res)
      ).catch ( (err) =>
        env.logger.error( err.statusCode)
        env.logger.error("Connection could not be establised")
      )

##############################################################
# RaspBee MotionSensor
##############################################################

  class RaspBeeMotionSensor extends env.devices.Sensor

    template: "presence"

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_battery= lastState?.battery?.value or 0
      super()
      myRaspBeePlugin.Connector.on "event", (data) =>
        if (( data.type == "sensors") and (data.id == "#{@deviceID}"))
          @_setPresence(data.state.presence)
        env.logger.debug(data)
      myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
        @_setBattery(res.config.battery)
        @_setOnline(res.config.reachable)
        env.logger.debug(res)
      )

    destroy: ->
      super()

    attributes:
      presence:
        description: "motion detection"
        type: t.boolean
        labels: ['present', 'absent']
      battery:
        description: "Battery status"
        type: t.number
      online:
        description: "online status"
        type: t.boolean
        labels: ['online', 'offline']

    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    _setPresence: (value) ->
      if @_presence is value then return
      @_presence = value
      @emit 'presence', value

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    getPresence: -> Promise.resolve(@_presence)

    getOnline: -> Promise.resolve(@_online)

    getBattery: -> Promise.resolve(@_battery)

##############################################################
# RaspBee MotionSensor
##############################################################

  class RaspBeeRemoteControl extends env.devices.Device

    template: "raspbeeremote"

    _lastPressedButton: null

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_battery= lastState?.battery?.value or 0
      @remote=[
        { id : 1 , text : "Power" },
        { id : 2 , text : "Up" },
      ]
      super()
      myRaspBeePlugin.Connector.on "event", (data) =>
      #  if (( data.type == "sensors") and (data.id == "#{@deviceID}"))
      #    @_setPresence(data.state.presence)
        env.logger.debug(data)
      myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
        @_setBattery(res.config.battery)
        @_setOnline(res.config.reachable)
        env.logger.debug(res)
      )

    destroy: ->
      super()

    actions:
      buttonPressed:
        params:
          buttonId:
            type: t.string
        description: "Press a button"

    attributes:
      battery:
        description: "Battery status"
        type: t.number
      online:
        description: "online status"
        type: t.boolean
        labels: ['online', 'offline']
      remote:
        description: "online status"
        type: t.array

    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    getOnline: -> Promise.resolve(@_online)

    getRemote: -> Promise.resolve(@remote)

    getBattery: -> Promise.resolve(@_battery)

    getButton: -> Promise.resolve(@_lastPressedButton)

    buttonPressed: (buttonId) ->
      for b in @remote
        if b.id is buttonId
          @emit 'button', b.id
          return Promise.resolve()
      throw new Error("No button with the id #{buttonId} found")

  myRaspBeePlugin = new RaspBeePlugin()
  return myRaspBeePlugin
