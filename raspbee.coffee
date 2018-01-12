module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  t = env.require('decl-api').types

  Request = require 'request-promise'
  WebSocket = require 'ws'
  events = require 'events'

  class RaspBeePlugin extends env.plugins.Plugin

    @cfg = null

    init: (app, @framework, @config) =>
      deviceConfigDef = require("./device-config-schema.coffee")
      @apikey = "API"
      @websocketport = null
      @apikey = @config.apikey
      @gatewayip = @config.ip
      @gatewayport = @config.port
      @cfg=@config
      @ready=false

      deviceClasses = [
        #RaspBeeSystem,
        RaspBeeMotionSensor,
        RaspBeeRemoteControlNavigator,
        #RaspBeeRemoteControlNavigator2,
        #RaspBeeRemoteControlDimmer,
        #RaspBeeLightOnOff,
        #RaspBeeGroupOnOff,
        #RaspBeeDimmableLight,
        #RaspBeeDimmableLightGroup,
        #RaspBeeColorTempLight,
        #RaspBeeColorTempLightGroup,
        #RaspBeeColorLight,
        #RaspBeeColorLightGroup,
      ]
      deviceConfigDef = require("./device-config-schema.coffee")
      for DeviceClass in deviceClasses
        do (DeviceClass) =>
          @framework.deviceManager.registerDeviceClass(DeviceClass.name, {
            configDef: deviceConfigDef[DeviceClass.name],
            createCallback: (deviceConfig,lastState) => new DeviceClass(deviceConfig, lastState, this)
          })

      @framework.on "after init", =>
        mobileFrontend = @framework.pluginManager.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js',   "pimatic-raspbee/app/raspbee.coffee"
          mobileFrontend.registerAssetFile 'html', "pimatic-raspbee/app/raspbee.jade"
          mobileFrontend.registerAssetFile 'css',  "pimatic-raspbee/app/raspbee.css"

      @.on 'connect', =>
        @connect()

      @framework.deviceManager.on 'discover', (eventData) =>
        if (! @ready)
          @framework.deviceManager.discoverMessage 'pimatic-raspbee', "generating API Key ..."
          RaspBeeConnection.generateAPIKey(@gatewayip,@gatewayport).then( (resp) =>
            @apikey=resp
            @cfg.apikey=@apikey
            @framework.pluginManager.updatePluginConfig 'raspbee', @cfg
            @emit 'connect'
          )

      if ( @apikey == "" or @apikey == undefined or @apikey == null)
        env.logger.error ("api key is not set! please set an api key or generate a new one")
      else
        @emit 'connect'


    connect: () =>
      @Connector = new RaspBeeConnection(@gatewayip,@gatewayport,@apikey)
      @Connector.on "event", (data) =>
        env.logger.debug(data)
        @emit "event", (data)
      @Connector.on "ready", =>
        @ready = true
      @Connector.on "error", =>
        @ready = false
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
          @ws.on('open', (data) =>
            env.logger.debug("Event Receiver connected.")
            @emit 'ready'
          )
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
            @emit 'error'
          )
        else
          env.logger.error("API key not valid")
      ).catch ( (err) =>
        env.logger.error(err)
        env.logger.error("Connection could not be establised")
        @emit 'error'
      )

    getSensor: (id) =>
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/sensors/"+id).then( (res) =>
        return JSON.parse(res)
      ).catch ( (err) =>
        env.logger.error( err.statusCode)
        env.logger.error("Connection could not be establised")
      )

    @generateAPIKey: (host,port) ->
      options = {
        uri: 'http://' + host + ':' + port + '/api',
        method: 'POST',
        body: '{"devicetype": "pimatic"}'
      }
      Request(options).then( (res) =>
        response = JSON.parse(res)
        return response[0].success.username
      ).catch ( (err) =>
        env.logger.error(err)
        env.logger.error("apikey could not be generated")
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
      @resetTime = @config.resetTime
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_battery= lastState?.battery?.value or 0
      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if (( data.type == "sensors") and (data.id == "#{@deviceID}"))
          if (data.state != undefined)
            @_setPresence(data.state.presence)
          if (data.config != undefined)
            env.logger.debug("config")
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

    _setMotion: (value) ->
      clearTimeout(@_resetTimeout)
      _setPresence(value)
      if (@config.resetTime > 0) and (value = true)
        @_resetTimeout = setTimeout(( =>
          @_setPresence(false)
        ), @config.resetTime)

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
# RaspBee Remote Control
##############################################################

  class RaspBeeRemoteControlNavigator extends env.devices.ButtonsDevice

    template: "raspbeeremote"

    _lastPressedButton: null

    constructor: (@config,lastState) ->
      super(@config,lastState)
      @deviceID = @config.deviceID
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_battery= lastState?.battdownery?.value or 0
      @remote=[
        { id : "power" , text : "Power" },
        { id : "up" , text : "Up" },
        { id : "down" , text : "Down" },
        { id : "left" , text : "Down" },
        { id : "right" , text : "Down" },
        { id : "longpower" , text : "Down" },
        { id : "longup" , text : "Down" },
        { id : "longdown" , text : "Down" },
        { id : "longright" , text : "Down" },
        { id : "longleft" , text : "Down" }
      ]
      myRaspBeePlugin.on "event", (data) =>
        if (( data.type == "sensors") and (data.id == "#{@deviceID}"))
          if (data.state != undefined)
            switch data.state.buttonevent
              when 1002 then @buttonPressed("power")
              when 2002 then @buttonPressed("up")
              when 3002 then @buttonPressed("down")
              when 4002 then @buttonPressed("left")
              when 5002 then @buttonPressed("right")
              when 1001 then @buttonPressed("longpower")
              when 2001 then @buttonPressed("longup")
              when 3001 then @buttonPressed("longdown")
              when 4001 then @buttonPressed("longleft")
              when 5001 then @buttonPressed("longright")
          if (data.config != undefined)
            env.logger.debug("config")
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

    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    getOnline: -> Promise.resolve(@_online)

    getBattery: -> Promise.resolve(@_battery)

    getButton: -> Promise.resolve(@_lastPressedButton)

    buttonPressed: (buttonId) ->
      for b in @remote
        if b.id is buttonId
          @emit 'button', b.id
          env.logger.debug("button pressed #{buttonId}")
          return Promise.resolve()
      env.logger.error ("No button with the id #{buttonId} found")


##############################################################
# TradfriDimmer
##############################################################

#  class TradfriDimmer extends env.devices.DimmerActuator
#
#    _lastdimlevel: null
#
#    template: 'tradfridimmer-dimmer'
#
#
  myRaspBeePlugin = new RaspBeePlugin()
  return myRaspBeePlugin
