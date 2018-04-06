module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  t = env.require('decl-api').types
  Color = require('./color')(env)

  RaspBeeConnection = require('./raspbee-connector')(env)

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
      @sensorCollection = {}

      deviceClasses = [
        #RaspBeeSystem,
        RaspBeeMotionSensor,
        RaspBeeContactSensor,
        RaspBeeLightSensor,
        RaspBeeSwitchSensor,
        RaspBeeMultiSensor,
        RaspBeeWaterSensor,
        RaspBeeRemoteControlNavigator,
        RaspBeeDimmer,
        RaspBeeCT,
        RaspBeeRGB,
        RaspBeeDimmerGroup,
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
          mobileFrontend.registerAssetFile 'js',   "pimatic-raspbee/app/raspbee-template.coffee"
          mobileFrontend.registerAssetFile 'html', "pimatic-raspbee/app/raspbee-template.jade"
          mobileFrontend.registerAssetFile 'css',  "pimatic-raspbee/app/raspbee-template.css"
          mobileFrontend.registerAssetFile 'js',  "pimatic-raspbee/app/spectrum.js"
          mobileFrontend.registerAssetFile 'css',  "pimatic-raspbee/app/spectrum.css"

      @framework.deviceManager.on 'discover', (eventData) =>
        if (! @ready)
          @framework.deviceManager.discoverMessage 'pimatic-raspbee', "generating API Key ..."
          RaspBeeConnection.generateAPIKey(@gatewayip,@gatewayport).then( (resp) =>
            @apikey=resp
            @cfg.apikey=@apikey
            @framework.pluginManager.updatePluginConfig 'raspbee', @cfg
            @connect()
            @scan()
          ).catch( (error) =>
            env.logger.error(error)
          )
        else
          @scan()

      if ( @apikey == "" or @apikey == undefined or @apikey == null)
        env.logger.error ("api key is not set! please set an api key or generate a new one")
      else
        @connect()

    scan:() =>

      @Connector.getSensor().then((devices)=>
        @sensorCollection = {}
        for i of devices
          dev=devices[i]
          @addToCollection(i, dev)
          @lclass = switch
            when dev.modelid == 'lumi.sensor_motion.aq2' then ""
            when dev.modelid == "TRADFRI remote control" then "RaspBeeRemoteControlNavigator"
            when dev.type == "ZHASwitch" then "RaspBeeSwitchSensor"
            when dev.type == "ZHAPresence" then "RaspBeeMotionSensor"
            when dev.type == "ZHAOpenClose" then "RaspBeeContactSensor"
            when dev.type == "ZHALightLevel" then "RaspBeeLightSensor"
            when dev.type == "ZHAWater" then "RaspBeeWaterSensor"
          config = {
            class: @lclass,
            name: dev.name,
            id: "raspbee_#{dev.etag}",
            deviceID: i
          }

          if @lclass and not @inConfig(i, @lclass)
            @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Sensor: #{config.name} - #{dev.modelid}", config )

        @discoverMultiSensors()

      )
      @Connector.getLight().then((devices)=>
        for i of devices
          dev=devices[i]
          @lclass = switch
            when dev.type == "On/Off plug-in unit" then "RaspBeeDimmer"
            when dev.type == "Dimmable light" then "RaspBeeDimmer"
            when dev.type == "Color temperature light" then "RaspBeeCT"
            when dev.type == "Color light" then "RaspBeeRGB"
            when dev.type == "Extended color light" then "RaspBeeRGB"
          config = {
            class: @lclass,
            name: dev.name,
            id: "raspbee_#{dev.etag}",
            deviceID: i
          }
          #if not @inConfig(i, @lclass)
          if not @inConfig(i, @lclass)
            @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Light: #{config.name} - #{dev.modelid}", config )
      )
      @Connector.getGroup().then((devices)=>
    #    env.logger.debug(devices)
        for i of devices
    #      env.logger.debug(devices[i])
          dev=devices[i]
    #      env.logger.debug(dev.type)
          @lclass = switch
            when dev.type == "LightGroup" then "RaspBeeDimmerGroup"
          config = {
            class: @lclass,
            name: dev.name,
            id: "raspbee_#{dev.etag}",
            deviceID: i
          }
          if not @inConfig(i, @lclass)
            @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Group: #{config.name}", config )
      )

    addToCollection: (id, device) =>
      if not @sensorCollection[device.etag]
        @sensorCollection[device.etag] =
          model: device.modelid
          name: device.name
          ids: []
          supports: []
      @sensorCollection[device.etag].ids.push(parseInt(id))
      @sensorCollection[device.etag].supports.push(device.type)

    discoverMultiSensors: () =>
      for id, device of @sensorCollection
        if device.ids.length > 1
          @lclass = switch
            when device.model == "lumi.weather" then "RaspBeeMultiSensor"
            when device.model == "lumi.sensor_ht" then "RaspBeeMultiSensor"
            when device.model == 'lumi.sensor_motion.aq2' then "RaspBeeMotionSensor"

          config = {
            class: @lclass,
            name: device.name,
            id: "raspbee_#{id}",
            deviceID: id,
            sensorIDs: device.ids
          }

          if 'ZHAHumidity' in device.supports
            config.supportsHumidity = true
          if 'ZHAPressure' in device.supports
            config.supportsPressure = true

          newdevice = not @framework.deviceManager.devicesConfig.some (config_device, iterator) =>
            config_device.deviceID is id

          if newdevice
            @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Light: #{config.name} - #{device.model}", config )

    connect: () =>
      @Connector = new RaspBeeConnection(@gatewayip,@gatewayport,@apikey)
      @Connector.on "event", (data) =>
      #  env.logger.debug(data)
        @emit "event", (data)
      @Connector.on "ready", =>
        @ready = true
        @emit "ready"
      @Connector.on "error", =>
        @ready = false
      #@framework.on('destroy', (context) =>
      #  env.logger.info("Plugin finish...")
      #)

    inConfig: (deviceID, className) =>
      deviceID = parseInt(deviceID)
      for device in @framework.deviceManager.devicesConfig
        if parseInt(device.deviceID) is deviceID and device.class is className
          env.logger.debug("device "+deviceID+" ("+className+") already exists")
          return true
      return false

##############################################################
# RaspBee MotionSensor
##############################################################

  class RaspBeeMotionSensor extends env.devices.PresenceSensor

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @sensorIDs = @config.sensorIDs
      @resetTime = @config.resetTime
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_battery = lastState?.battery?.value

      @addAttribute('battery', {
        description: "Battery",
        type: "number"
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
      })
      @['battery'] = ()-> Promise.resolve(@_battery)

      @addAttribute('online', {
        description: "Online status",
        type: "boolean"
        labels: ['online', 'offline']
      })
      @['online'] = ()-> Promise.resolve(@_online)

      # If lux is enabled, add it
      if @sensorIDs.length
        @addAttribute('lux', {
          description: "Lux",
          type: "number"
          unit: "lux"
        })
        @['lux'] = ()-> Promise.resolve(@_lux)

      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if data.id is parseInt(@deviceID) or data.id in @sensorIDs
          if data.type is "sensors"
            @_updateAttributes data

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _updateAttributes: (data) ->
      @_setMotion(data.state.presence) if data.state?.presence?
      @_setLux(data.state.lux) if data.state?.lux?
      @_setBattery(data.config.battery) if data.config?.battery?
      @_setOnline(data.config.reachable) if data.config?.reachable?

    getInfos: ->
      if (myRaspBeePlugin.ready)
        if @sensorIDs.length
          for id in @sensorIDs
            myRaspBeePlugin.Connector.getSensor(id).then( (res) =>
              @_updateAttributes res
            )
        else
          myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
            @_updateAttributes res
          )

    destroy: ->
      clearTimeout(@_resetTimeout) if @_resetTimeout?
      super()

    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    _setLux: (value) ->
      if @_lux is value then return
      @_lux = value
      @emit 'lux', value

    _setMotion: (value) ->
      clearTimeout(@_resetTimeout)
      @_setPresence(value)
      if (@config.resetTime > 0) and (value = true)
        @_resetTimeout = setTimeout(( =>
          @_setPresence(false)
        ), @config.resetTime)

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    getOnline: -> Promise.resolve(@_online)

    getLux: -> Promise.resolve @_lux

    getBattery: -> Promise.resolve(@_battery)

##############################################################
# RaspBee ContactSensor
##############################################################

  class RaspBeeContactSensor extends env.devices.ContactSensor

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @resetTime = @config.resetTime
      @_contact = lastState?.contact?.value or @_value(false)
      @_online = lastState?.online?.value or false
      @_battery= lastState?.battery?.value
      @_resetTimeout = null
      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if data.id is @deviceID and data.type is "sensors"
          @_updateAttributes data

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _value: (state) ->
      if @config.inverted then not state else state

    _updateAttributes: (data) ->
      if data.state?
        @_changeContactTo(@_value(not data.state.open)) if data.state.open?
      if data.config?
        @_setBattery(data.config.battery) if data.config.battery?
        @_setOnline(data.config.reachable) if data.config.reachable?

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getSensor(@deviceID).then (res) =>
          @_updateAttributes res

    destroy: ->
      clearTimeout(@_resetTimeout) if @_resetTimeout?
      super()

    attributes:
      contact:
        description: "State of the contact"
        type: t.boolean
        labels: ['closed', 'opened']
      battery:
        description: "Battery status"
        type: t.number
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
      online:
        description: "online status"
        type: t.boolean
        labels: ['online', 'offline']

    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    _changeContactTo: (value) ->
      clearTimeout(@_resetTimeout) if @_resetTimeout?
      @_setContact(value)
      if (@config.resetTime > 0) and (value = true)
        @_resetTimeout = setTimeout(( =>
          @_resetTimeout = null
          @_setContact(false)
        ), @config.resetTime)

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    getOnline: -> Promise.resolve(@_online)

    getBattery: -> Promise.resolve(@_battery)

##############################################################
# RaspBee LightSensor
##############################################################

  class RaspBeeLightSensor extends env.devices.Device

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @_lux = lastState?.lux?.value or 0
      @_online = lastState?.online?.value or false
      @_battery = lastState?.battery?.value
      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if data.id is @deviceID and data.type is "sensors"
          @_updateAttributes data

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _updateAttributes: (data) ->
      @_setLux(data.state.lux) if data.state?.lux?
      @_setBattery(data.config.battery) if data.config?.battery?
      @_setOnline(data.config.reachable) if data.config?.reachable?

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getSensor(@deviceID).then (res) =>
          @_updateAttributes res

    destroy: ->
      super()

    attributes:
      battery:
        description: "Battery status"
        type: t.number
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
      online:
        description: "online status"
        type: t.boolean
        labels: ['online', 'offline']
      lux:
        description: "Lux level",
        type: t.number
        unit: "lux"


    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    _setLux: (value) ->
      if @_lux is value then return
      @_lux = value
      @emit 'lux', value

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    getOnline: -> Promise.resolve(@_online)

    getBattery: -> Promise.resolve(@_battery)

    getLux: -> Promise.resolve(@_lux)


##############################################################
# RaspBee SwitchSensor
##############################################################

  class RaspBeeSwitchSensor extends env.devices.Device

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @_state = lastState?.state?.value or "waiting"
      @_online = lastState?.online?.value or false
      @_battery = lastState?.battery?.value
      @_resetTimeout = null
      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if data.id is @deviceID and data.type is "sensors"
          @_updateAttributes data

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _updateAttributes: (data, updateState = true) ->
      if data.state?.buttonevent? and updateState
        @_setState(data.state.buttonevent.toString())
        @_resetTimeout = setTimeout(( =>
          @_resetTimeout = null
          @_setState("waiting")
        ), @config.resetTime)
      @_setBattery(data.config.battery) if data.config?.battery?
      @_setOnline(data.config.reachable) if data.config?.reachable?

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getSensor(@deviceID).then (res) =>
          @_updateAttributes res, false

    destroy: ->
      clearTimeout(@_resetTimeout) if @_resetTimeout?
      super()

    attributes:
      battery:
        description: "Battery status"
        type: t.number
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
      online:
        description: "online status"
        type: t.boolean
        labels: ['online', 'offline']
      state:
        description: "State of the sensor",
        type: t.string


    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    _setState: (value) ->
      if @_state is value then return
      @_state = value
      @emit 'state', value

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    getOnline: -> Promise.resolve(@_online)

    getBattery: -> Promise.resolve(@_battery)

    getState: -> Promise.resolve(@_state)


##############################################################
# RaspBee MultiSensor
##############################################################

  class RaspBeeMultiSensor extends env.devices.Device

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @sensorIDs = @config.sensorIDs
      @_temperature = lastState?.temperature?.value
      if @config.supportsHumidity
        @_humidity = lastState?.humidity?.value
      if @config.supportsPressure
        @_pressure = lastState?.pressure?.value
      @_online = lastState?.online?.value or false
      @_battery = lastState?.battery?.value

      @attributes = {}

      @attributes.battery = {
        description: "Battery",
        type: "number"
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
      }

      @attributes.online = {
        description: "Online status",
        type: "boolean"
        labels: ['online', 'offline']
      }

      @attributes.temperature = {
        description: "the measured temperature"
        type: "number"
        unit: "°C"
        acronym: 'T'
      }

      if @config.supportsHumidity
        @attributes.humidity = {
          description: "the measured humidity"
          type: "number"
          unit: '%'
          acronym: 'H'
        }

      if @config.supportsPressure
        @attributes.pressure = {
          description: "the measured pressure"
          type: "number"
          unit: 'kPa'
          acronym: 'P'
        }

      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if data.id in @sensorIDs and data.type is "sensors"
          @_updateAttributes data

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _updateAttributes: (data) ->
      @_setTemperature(data.state.temperature / 100) if data.state?.temperature?
      if @config.supportsHumidity
        @_setHumidity(data.state.humidity / 100) if data.state?.humidity?
      if @config.supportsPressure
        @_setPressure(data.state.pressure / 100) if data.state?.pressure?
      @_setBattery(data.config.battery) if data.config?.battery?
      @_setOnline(data.config.reachable) if data.config?.reachable?

    getInfos: ->
      if (myRaspBeePlugin.ready)
        for id in @sensorIDs
          myRaspBeePlugin.Connector.getSensor(id).then (res) =>
            @_updateAttributes res

    destroy: ->
      super()

    _setBattery: (value) ->
      if @_battery is value then return
      @_battery = value
      @emit 'battery', value

    _setTemperature: (value) ->
      if @_temperature is value then return
      @_temperature = value
      @emit 'temperature', value

    _setHumidity: (value) ->
      if @_humidity is value then return
      @_humidity = value
      @emit 'humidity', value

    _setPressure: (value) ->
      if @_pressure is value then return
      @_pressure = value
      @emit 'pressure', value

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    getOnline: -> Promise.resolve(@_online)

    getBattery: -> Promise.resolve(@_battery)

    getTemperature: -> Promise.resolve(@_temperature)

    getHumidity: -> Promise.resolve(@_humidity)

    getPressure: -> Promise.resolve(@_pressure)


  ##############################################################
# RaspBee WaterSensor
##############################################################

  class RaspBeeWaterSensor extends env.devices.PresenceSensor

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @resetTime = @config.resetTime
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_battery = lastState?.battery?.value
      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if data.id is @deviceID and data.type is "sensors"
          @_updateAttributes data

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _updateAttributes: (data) ->
      @_setPresence(data.state.water) if data.state?.water?
      @_setBattery(data.config.battery) if data.config?.battery?
      @_setOnline(data.config.reachable) if data.config?.reachable?

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
          @_updateAttributes res
        )

    destroy: ->
      super()

    attributes:
      presence:
        description: "water detection"
        type: t.boolean
        labels: ['present', 'absent']
      battery:
        description: "Battery status"
        type: t.number
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
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

##############################################################
# RaspBee Remote Control
##############################################################

  class RaspBeeRemoteControlNavigator extends env.devices.ButtonsDevice

    template: "raspbee-remote"

    _lastPressedButton: null

    constructor: (@config,lastState) ->
      super(@config,lastState)
      @deviceID = @config.deviceID
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_battery= lastState?.battery?.value
      @config.buttons=[
        { id : "raspbee_#{@deviceID}_power" , text : "Power" },
        { id : "raspbee_#{@deviceID}_up" , text : "Up" },
        { id : "raspbee_#{@deviceID}_down" , text : "Down" },
        { id : "raspbee_#{@deviceID}_left" , text : "Down" },
        { id : "raspbee_#{@deviceID}_right" , text : "Down" },
        { id : "raspbee_#{@deviceID}_longpower" , text : "Down" },
        { id : "raspbee_#{@deviceID}_longup" , text : "Down" },
        { id : "raspbee_#{@deviceID}_longdown" , text : "Down" },
        { id : "raspbee_#{@deviceID}_longright" , text : "Down" },
        { id : "raspbee_#{@deviceID}_longleft" , text : "Down" }
      ]
      myRaspBeePlugin.on "event", (data) =>
        if data.type is "sensors" and data.id is @deviceID
          if (data.state != undefined)
            switch data.state.buttonevent
              when 1002 then @buttonPressed("raspbee_#{@deviceID}_power")
              when 2002 then @buttonPressed("raspbee_#{@deviceID}_up")
              when 3002 then @buttonPressed("raspbee_#{@deviceID}_down")
              when 4002 then @buttonPressed("raspbee_#{@deviceID}_left")
              when 5002 then @buttonPressed("raspbee_#{@deviceID}_right")
              when 1001 then @buttonPressed("raspbee_#{@deviceID}_longpower")
              when 2001 then @buttonPressed("raspbee_#{@deviceID}_longup")
              when 3001 then @buttonPressed("raspbee_#{@deviceID}_longdown")
              when 4001 then @buttonPressed("raspbee_#{@deviceID}_longleft")
              when 5001 then @buttonPressed("raspbee_#{@deviceID}_longright")
          if (data.config != undefined)
            if data.config.battery?
              @_setBattery(data.config.battery)
            if data.config.reachable?
              @_setOnline(data.config.reachable)

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
          @_setBattery(res.config.battery)
          @_setOnline(res.config.reachable)
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
        displaySparkline: false
        unit: "%"
        icon:
          noText: true
          mapping: {
            'icon-battery-empty': 0
            'icon-battery-fuel-1': [0, 20]
            'icon-battery-fuel-2': [20, 40]
            'icon-battery-fuel-3': [40, 60]
            'icon-battery-fuel-4': [60, 80]
            'icon-battery-fuel-5': [80, 100]
            'icon-battery-filled': 100
          }
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


  class RaspBeeDimmer extends env.devices.DimmerActuator

    _lastdimlevel: null

    template: 'raspbee-dimmer'

    constructor: (@config, lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_battery= lastState?.battdownery?.value or 0
      @_dimlevel = lastState?.dimlevel?.value or 0
      @_lastdimlevel = lastState?.lastdimlevel?.value or 100
      @_state = lastState?.state?.value or off
      @_transtime = @config.transtime

      @addAttribute  'presence',
        description: "online status",
        type: t.boolean

      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if data.type is "lights" and data.id is @deviceID
          if (data.state != undefined)
            @_setPresence(true)
            @parseEvent(data)

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getLight(@deviceID).then( (res) =>
          @_setPresence(res.state.reachable)
          @_setDimlevel(parseInt(res.state.bri / 255 * 100))
          @_setState(res.state.on)
        )

    parseEvent: (data) ->
      if data.state.bri?
        val = parseInt(data.state.bri / 255 * 100)
        @_setDimlevel(val)
        if val > 0
          @_lastdimlevel = val
      if (data.state.on?)
        if data.state.on
          @_setDimlevel(@_lastdimlevel)
        else
          if @_dimlevel > 0
            @_lastdimlevel = @_dimlevel
          @_setDimlevel(0)

    destroy: ->
      super()

    getTemplateName: -> "raspbee-dimmer"

    _setPresence: (value) ->
      if @_presence is value then return
      @_presence = value
      @emit 'presence', value

    getPresence: -> Promise.resolve(@_presence)

    turnOn: ->
      @changeDimlevelTo(@_lastdimlevel)

    turnOff: ->
      @changeDimlevelTo(0)

    changeDimlevelTo: (level) ->
      if @_dimlevel is level then return Promise.resolve true
      if level is 0
        state = false
        bright = 0
      else
        state = true
        bright=Math.round(level*(2.54))
      param = {
        on: state,
        bri: bright,
        transitiontime: @_transtime
      }
      @_sendState(param).then( () =>
        unless @_dimlevel is 0
          @_lastdimlevel = @_dimlevel
        @_setDimlevel(level)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    _sendState: (param) ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.setLightState(@deviceID,param).then( (res) =>
          env.logger.debug ("New value send to device #{@name}")
          #env.logger.debug (param)
          if res[0].success?
            return Promise.resolve()
          else
            if (res[0].error.type is 3 )
              @_setPresence(false)
              return Promise.reject("device #{@name} not reachable")
            else if (res[0].error.type is 201 )
              return Promise.reject("device #{@name} is not modifiable. Device is set to off")
        ).catch( (error) =>
          return Promise.reject(error)
        )
      else
        env.logger.error ("gateway not online")
        return Promise.reject()


##############################################################
# RaspBeeDimmerTempSliderItem
##############################################################

  class RaspBeeCT extends RaspBeeDimmer

    template: 'raspbee-ct'

    constructor: (@config, @plugin, @framework, lastState) ->
      @ctmin = 153
      @ctmax = 500
      @_ct = @ctmin
      @addAttribute  'ct',
          description: "color Temperature",
          type: t.number

      @actions.setCT =
        description: 'set light color'
        params:
          colorCode:
            type: t.number
      super(@config, @plugin, @framework, lastState)

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getLight(@deviceID).then( (res) =>
          @_setPresence(res.state.reachable)
          @_setDimlevel(res.state.bri / 255 * 100)
          @_setState(res.state.on)
      #    @ctmin = res.ctmin
          @ctmax = res.ctmax
          #env.logger.debug(res)
        ).catch( (err) =>
          env.logger.debug(err)
        )

    parseEvent: (data) ->
      super(data)
      if (data.state.ct?)
        ncol=(data.state.ct-@ctmin)/(@ctmax-@ctmin)
        ncol=Math.min(Math.max(ncol, 0), 1)
        @_setCt(Math.round(ncol*100))

    getTemplateName: -> "raspbee-ct"

    getCt: -> Promise.resolve(@_ct)

    _setCt: (color) =>
      if @_ct is color then return
      @_ct = color
      @emit "ct", color

    setCT: (color) =>
      if @_ct is color then return Promise.resolve true
      param = {
        ct: Math.round(@ctmin + color / 100 * (@ctmax-@ctmin)),
        transitiontime: @_transtime
      }
      @_sendState(param).then( () =>
        @_setCt(color)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    destroy: ->
      super()


  class RaspBeeRGB extends RaspBeeCT

    @_color = 0
    @_hue = 0
    @_sat = 0

    template: 'raspbee-rgb'

    constructor: (@config, lastState) ->
      @addAttribute  'hue',
          description: "color Temperature",
          type: t.number
      @addAttribute  'sat',
          description: "color Temperature",
          type: t.number

      @actions.setHuesat =
        description: 'set light color'
        params:
          hue:
            type: t.number
          sat:
            type: t.number
          val:
            type: t.number
      @actions.setRGB =
        description: 'set light color'
        params:
          r:
            type: t.number
          g:
            type: t.number
          b:
            type: t.number
      @actions.setHue =
        description: 'set light color'
        params:
          hue:
            type: t.number
      @actions.setSat =
        description: 'set light color'
        params:
          sat:
            type: t.number
      super(@config, lastState)


    parseEvent: (data) ->
      if data.state.hue?
        @_setHue(data.state.hue / 65535 * 100)
      if data.state.sat?
        @_setSat(data.state.sat / 255 * 100)

    getTemplateName: -> "raspbee-rgb"

    _setHue: (hueVal) ->
      hueVal = parseFloat(hueVal)
      assert not isNaN(hueVal)
      assert 0 <= hueVal <= 100
      unless @_hue is hueVal
        @_hue = hueVal
        @emit "hue", hueVal

    _setSat: (satVal) ->
      satVal = parseFloat(satVal)
      assert not isNaN(satVal)
      assert 0 <= satVal <= 100
      unless @_sat is satVal
        @_sat = satVal
        @emit "sat", satVal

    getHue: -> Promise.resolve(@_hue)

    getSat: -> Promise.resolve(@_sat)

    setRGB: (r,g,b) ->
      xy=Color.rgb_to_xyY(r,g,b)
      param = {
        xy: xy,
        transitiontime: @_transtime
      }
      @_sendState(param).then( () =>
        #@_setCt(color)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    destroy: ->
      super()


  class RaspBeeDimmerGroup extends RaspBeeDimmer

    _lastdimlevel: null

    template: 'raspbee-dimmer'

    constructor: (@config, lastState) ->
      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        @parseEvent(data)

      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getGroup(@deviceID).then( (res) =>
          @_setState(res.state.any_on)
        )

    parseEvent: (data) ->
      if data.type is "groups" and data.id is @deviceID
        if (data.state.any_on?)
          @_setState(data.state.any_on)

    destroy: ->
      super()

    getTemplateName: -> "raspbee-dimmer"

    _setPresence: (value) ->
      if @_presence is value then return
      @_presence = value
      @emit 'presence', value

    getPresence: -> Promise.resolve(@_presence)

    turnOn: ->
      param = {
        on: true,
        transitiontime: @_transtime
      }
      @_sendState(param)

    turnOff: ->
      @changeDimlevelTo(0)

    changeDimlevelTo: (level) ->
      if @_dimlevel is level then return Promise.resolve true
      if level is 0
        state = false
        bright = 0
      else
        state = true
        bright=Math.round(level*(2.54))
      param = {
        on: state,
        bri: bright,
        transitiontime: @_transtime
      }
      @_sendState(param).then( () =>
        unless @_dimlevel is 0
          @_lastdimlevel = @_dimlevel
        @_setDimlevel(level)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    _sendState: (param) ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.setGroupState(@deviceID,param).then( (res) =>
          env.logger.debug ("New value send to group #{@name}")
      #    env.logger.debug (param)
          if res[0].success?
            return Promise.resolve()
          else
            if (res[0].error.type is 3 )
              return Promise.reject("device #{@name} not reachable")
            else if (res[0].error.type is 201 )
              return Promise.reject("device #{@name} is not modifiable. Device is set to off")
        ).catch( (error) =>
          return Promise.reject(error)
        )
      else
        env.logger.error ("gateway not online")
        return Promise.reject()

  myRaspBeePlugin = new RaspBeePlugin()
  return myRaspBeePlugin
