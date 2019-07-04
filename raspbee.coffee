module.exports = (env) ->

  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  t = env.require('decl-api').types
  Color = require('./color')(env)
  path = require('path')

  RaspBeeConnection = require('./raspbee-connector')(env)
  RaspBeeAction = require('./action.coffee')(env)
  RaspBeePredicate = require('./predicate.coffee')(env)

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
        RaspBeeSystem,
        RaspBeeMotionSensor,
        RaspBeeContactSensor,
        RaspBeeLightSensor,
        RaspBeeSwitchSensor,
        RaspBeeMultiSensor,
        RaspBeeWaterSensor,
        RaspBeeRemoteControlNavigator,
        RaspBeeSwitch,
        RaspBeeDimmer,
        RaspBeeCT,
        RaspBeeRGB,
        RaspBeeRGBCT,
        RaspBeeDimmerGroup,
        RaspBeeRGBCTGroup,
        RaspBeeGroupScenes
      ]
      deviceConfigDef = require("./device-config-schema.coffee")
      for DeviceClass in deviceClasses
        do (DeviceClass) =>
          @framework.deviceManager.registerDeviceClass(DeviceClass.name, {
            configDef: deviceConfigDef[DeviceClass.name],
            createCallback: (deviceConfig,lastState) => new DeviceClass(deviceConfig, lastState, this)
          })

      @framework.ruleManager.addActionProvider(new RaspBeeAction.RaspBeeSceneActionProvider(@framework))
      @framework.ruleManager.addActionProvider(new RaspBeeAction.RaspBeeRGBActionProvider(@framework))
      @framework.ruleManager.addActionProvider(new RaspBeeAction.RaspBeeTempActionProvider(@framework))
      @framework.ruleManager.addActionProvider(new RaspBeeAction.RaspbeeDimmerActionProvider(@framework))
      @framework.ruleManager.addPredicateProvider(new RaspBeePredicate.RaspBeePredicateProvider(@framework, @config))

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
        env.logger.error ("api key is not set! perform a device discovery to generate a new one")
      else
        @connect()

    scan:() =>
      @sensorCollection = {}
      config = {
        class: "RaspBeeSystem",
        name: "RaspBee System",
        id: "raspbee_system",
        deviceID: "42",
      }
      if not @inConfig(config.deviceID, config.class)
        @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Gateway: #{config.name}", config )

      @Connector.getLight().then((devices)=>
        env.logger.debug("light list")
        env.logger.debug(devices)
        for i of devices
          dev=devices[i]
          @lclass = switch
            when dev.type == "On/Off plug-in unit" then "RaspBeeSwitch"
            when dev.type == "Smart plug" then "RaspBeeSwitch"
            when dev.type == "Dimmable light" then "RaspBeeDimmer"
            when dev.type == "Color temperature light" then "RaspBeeCT"
            when dev.type == "Color light" then "RaspBeeRGB"
            when dev.type == "Extended color light" then "RaspBeeRGBCT"
          config = {
            class: @lclass,
            name: dev.name,
            id: "raspbee_l#{dev.etag}#{i}",
            deviceID: i
          }
          if not @inConfig(i, @lclass)
            @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Light: #{config.name} - #{dev.modelid}", config )
      )
      @Connector.getSensor().then((devices)=>
        env.logger.debug("sensor list")
        env.logger.debug(devices)
        for i of devices
          dev=devices[i]
          @addToCollection(i, dev)
        @discoverMultiSensors()
      )
      @Connector.getGroup().then((devices)=>
        for i of devices
          dev=devices[i]
          @groupid=i
          @lclass = switch
            when dev.type == "LightGroup" then "RaspBeeRGBCTGroup"
          config = {
            class: @lclass,
            name: dev.name,
            id: "raspbee_g#{dev.etag}#{i}",
            deviceID: i
          }
          if not @inConfig(i, @lclass)
            @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Group: #{config.name}", config )
          do (config) =>
            myRaspBeePlugin.Connector.getScenes(i).then( (res) =>
              buttonsArray=[]
              for id, cfg of res
                buttonsArray.push({
                  id: parseInt(id)
                  name: cfg.name
                  text: cfg.name
                })
              config = {
                class: "RaspBeeGroupScenes"
                name: "Scenes for #{config.name}"
                id: "scene_#{config.id}_#{config.deviceID}"
                deviceID: config.deviceID
              }
              if buttonsArray.length > 0 and not @inConfig(config.deviceID, "RaspBeeGroupScenes")
                config.buttons=buttonsArray
                @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "#{config.name}", config )
            ).catch( (err) =>
              env.logger.error(err)
            )
      )

    addToCollection: (id, device) =>
      if device.uniqueid?
        uniqueid = device.uniqueid.split('-')
        uniqueid = uniqueid[0].replace(/:/g,'')
        if not @sensorCollection[uniqueid]
          @sensorCollection[uniqueid] =
            model: device.modelid
            name: device.name
            ids: []
            supports: []
            config: []
            supportsBattery: false
        @sensorCollection[uniqueid].ids.push(parseInt(id))
        if (device.config.battery?)
          @sensorCollection[uniqueid].supportsBattery=true
        if (device.type == "ZHASwitch")
          @sensorCollection[uniqueid].supports.push('switch')
        if (device.state.alarm?)
          @sensorCollection[uniqueid].supports.push('alarm')
        if (device.config.temperature?) or (device.state.temperature?)
          @sensorCollection[uniqueid].supports.push('temperature')
        if (device.state.dark?)
          @sensorCollection[uniqueid].supports.push('dark')
        if (device.state.carbonmonoxide?)
          @sensorCollection[uniqueid].supports.push('carbon')
        if (device.state.fire?)
          @sensorCollection[uniqueid].supports.push('fire')
        if (device.state.humidity?)
          @sensorCollection[uniqueid].supports.push('humidity')
        if (device.state.lowbattery?)
          @sensorCollection[uniqueid].supports.push('lowbattery')
        if (device.state.presence?)
          @sensorCollection[uniqueid].supports.push('presence')
        if (device.state.open?)
          @sensorCollection[uniqueid].supports.push('open')
        if (device.state.pressure?)
          @sensorCollection[uniqueid].supports.push('pressure')
        if (device.state.tampered?)
          @sensorCollection[uniqueid].supports.push('tampered')
        if (device.state.water?)
          @sensorCollection[uniqueid].supports.push('water')
        if (device.state.vibration?)
          @sensorCollection[uniqueid].supports.push('vibration')
        if (device.state.lux?)
          @sensorCollection[uniqueid].supports.push('lux')
        if (device.state.consumption?)
          @sensorCollection[uniqueid].supports.push('consumption')
        if (device.state.power?)
          @sensorCollection[uniqueid].supports.push('power')
        if (device.state.voltage?)
          @sensorCollection[uniqueid].supports.push('voltage')
        if (device.state.current?)
          @sensorCollection[uniqueid].supports.push('current')
        if (device.state.daylight?)
          @sensorCollection[uniqueid].supports.push('daylight')
        if (device.state.lowbattery?)
          @sensorCollection[uniqueid].supports.push('lowbattery')
        for parameter,value of device.config
          id=parseInt(id)
          if parameter not in ["battery","on","reachable","alert",\
              "configured","temperature","group","pending","sensitivitymax"]
            @sensorCollection[uniqueid].config.push({id,parameter,value})

    discoverMultiSensors: () =>
      for id, device of @sensorCollection
        if device.ids.length > 0
          config = {
            class: "RaspBeeMultiSensor",
            name: device.name,
            id: "raspbee_#{id}",
            deviceID: id,
            sensorIDs: device.ids
            supportsBattery: device.supportsBattery
          }
          config.configMap=device.config
          config.supports=JSON.parse(JSON.stringify(device.supports))
          env.logger.debug(device.supports)
          env.logger.debug(config.supports)
          newdevice = not @framework.deviceManager.devicesConfig.some (config_device, iterator) =>
            config_device.deviceID is id
          env.logger.debug(config)
          if newdevice
            @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "MultiDevice: #{config.name} - #{device.model}", config )

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
              if res.config?.duration?
                @_setDuration(id)
              @_updateAttributes res
            ).catch( (error) =>
              env.logger.error (error)
            )
        else
          myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
            if res.config?.duration?
              @_setDuration(@deviceID)
            @_updateAttributes res
          ).catch( (error) =>
            env.logger.error (error)
          )

    destroy: ->
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
      @_setPresence(value)

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    _setDuration: (id) ->
      duration = @config.resetTime
      if duration < 60
        duration = 60
      config = {
        duration: duration
      }
      myRaspBeePlugin.Connector.setSensorConfig(id, config).then( (res) =>

      )
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
      super()
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
        myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
          @_updateAttributes res
        ).catch( (error) =>
          env.logger.error (error)
        )

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
      super()

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
        myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
          @_updateAttributes res
        ).catch( (error) =>
          env.logger.error (error)
        )

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
      @CmdMap = []
      super()

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
        for cmdval in @CmdMap
          if cmdval.getCommand() == data.state.buttonevent.toString()
            cmdval.emit('change', 'event')
      @_setBattery(data.config.battery) if data.config?.battery?
      @_setOnline(data.config.reachable) if data.config?.reachable?

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
          @_updateAttributes res, false
        ).catch( (error) =>
          env.logger.error (error)
        )

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

    registerPredicate: (@Cmd) =>
      @CmdMap.push @Cmd
      env.logger.debug "Register command: #{@Cmd.getCommand()} for #{@name}"

    deregisterPredicate: (@Cmd) =>
      @CmdMap.splice(@CmdMap.indexOf(@Cmd),1)
      env.logger.debug "Deregister command: #{@Cmd.getCommand()} for #{@name}"

##############################################################
# RaspBee MultiSensor
##############################################################

  class RaspBeeMultiSensor extends env.devices.Device

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @sensorIDs = @config.sensorIDs
      @configMap = @config.configMap
      @_online = lastState?.online?.value or false
      @attributes = {}
      @_resetTimeout = null
      @CmdMap = []

      if @config.supportsBattery
        @_battery = lastState?.battery?.value
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
      if "switch" in @config.supports
        @_switch = "waiting"
        @attributes.switch = {
          description: "the switch event"
          type: "string"
        }
      if "temperature" in @config.supports
        @_temperature = lastState?.temperature?.value
        @attributes.temperature = {
          description: "the measured temperature"
          type: "number"
          unit: "°C"
          acronym: @config.temperatureAcronym
        }
      if "humidity" in @config.supports
        @_humidity = lastState?.humidity?.value
        @attributes.humidity = {
          description: "the measured humidity"
          type: "number"
          unit: '%'
          acronym: @config.humidityAcronym
        }
      if "pressure" in @config.supports
        @_pressure = lastState?.pressure?.value
        @attributes.pressure = {
          description: "the measured pressure"
          type: "number"
          unit: 'hPa'
          acronym: @config.pressureAcronym
        }
      if "lux" in @config.supports
        @_lux = lastState?.lux?.value
        @attributes.lux = {
          description: "the measured lux"
          type: "number"
          unit: 'lux'
          acronym: @config.luxAcronym
        }
      if "power" in @config.supports
        @_power = lastState?.power?.value
        @attributes.power = {
          description: "the measured power"
          type: "number"
          unit: 'W'
          acronym: @config.powerAcronym
        }
      if "consumtion" in @config.supports
        @_consumtion = lastState?.consumtion?.value
        @attributes.consumtion = {
          description: "the measured consumtion"
          type: "number"
          unit: 'Wh'
          acronym: @config.consumtionAcronym
        }
      if "open" in @config.supports
        @_openclose = lastState?.openclose?.value
        @attributes.openclose = {
          description: "the measured power"
          type: "boolean"
          labels: ['open', 'close']
        }
      if "water" in @config.supports
        @_water = lastState?.water?.value
        @attributes.water = {
          description: "the water alarm"
          type: "boolean"
          labels: ['water detected', 'no water']
        }
      if "vibration" in @config.supports
        @_vibration = lastState?.vibration?.value
        @attributes.vibration = {
          description: "the water vibration"
          type: "boolean"
          labels: ['vibration detected', 'no vibration']
        }
      if "alarm" in @config.supports
        @_alarm = lastState?.alarm?.value
        @attributes.alarm = {
          description: "the alarm detection"
          type: "boolean"
          labels: ['alarm detected', 'no alarm']
        }
      if "carbon" in @config.supports
        @_carbon = lastState?.carbon?.value
        @attributes.carbon = {
          description: "the carbon detection"
          type: "boolean"
          labels: ['carbon detected', 'no carbon']
        }
      if "presence" in @config.supports
        @_motion = lastState?.motion?.value
        @attributes.motion = {
          description: "the motion detection"
          type: "boolean"
          labels: ['motion detected', 'no motion']
        }
      if "dark" in @config.supports
        @_dark = lastState?.dark?.value
        @attributes.dark = {
          description: "dark detection"
          type: "boolean"
          labels: ['not dark', 'dark']
        }
      if "fire" in @config.supports
        @_fire = lastState?.fire?.value
        @attributes.fire = {
          description: "fire detection"
          type: "boolean"
          labels: ['fire detected', 'fire']
        }
      super()
      myRaspBeePlugin.on "event", (data) =>
        if data.id in @sensorIDs and data.type is "sensors"
          @_updateAttributes data

      myRaspBeePlugin.on "config", () =>
        @_setCfg()

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _updateAttributes: (data) ->
      @_setTemperature(data.state.temperature / 100) if data.state?.temperature?
      @_setTemperature(data.config.temperature / 100) if data.config?.temperature?
      @_setHumidity(data.state.humidity / 100) if data.state?.humidity?
      @_setPressure(data.state.pressure ) if data.state?.pressure?
      @_setBattery(data.config.battery) if data.config?.battery?
      @_setOnline(data.config.reachable) if data.config?.reachable?

      @_setMotion(data.state.presence) if data.state?.presence?
      @_setLux(data.state.lux) if data.state?.lux?

      @_setWater(data.state.water) if data.state?.water?
      @_setCarbon(data.state.carbonmonoxide) if data.state?.carbonmonoxide?

      @_setVibration(data.state.vibration) if data.state?.vibration?
      @_setFire(data.state.fire) if data.state?.fire?
      @_setOpenclose(data.state.open) if data.state?.open?
      @_setCarbon(data.state.carbonmonoxide	) if data.state?.carbonmonoxide?
      @_setSwitch(data.state.buttonevent) if data.state?.buttonevent?

      @_setPower(data.state.power) if data.state?.power?
      @_setConsumtion(data.state.consumtion) if data.state?.consumtion?

      @_setAlarm(data.state.alarm) if data.state?.alarm?

      @_setDark(data.state.dark) if data.state?.dark?
      @_setFire(data.state.fire) if data.state?.fire?

      if data.state?.buttonevent?
        for cmdval in @CmdMap
          if cmdval.getCommand() == data.state.buttonevent.toString()
            cmdval.emit('change', 'event')

    getInfos: ->
      if (myRaspBeePlugin.ready)
        for id in @sensorIDs
          myRaspBeePlugin.Connector.getSensor(id).then((res) =>
            @_updateAttributes res
          ).catch( (error) =>
            env.logger.error (error)
          )

    _setCfg: ->
      if myRaspBeePlugin.ready
        for id,cfg of @configMap
          env.logger.debug(@)
          env.logger.debug(cfg)
          sconfig = {}
          sconfig[cfg.parameter]=cfg.value
          env.logger.debug(sconfig)
          myRaspBeePlugin.Connector.setSensorConfig(cfg.id,sconfig).then( (res) =>
            env.logger.info ("config send")
            env.logger.debug (res)
          ).catch((error) =>
            env.logger.error ("error : #{error}")
          )
      return Promise.resolve()

    destroy: ->
      clearTimeout(@_resetTimeout) if @_resetTimeout?
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

    _setLux: (value) ->
      if @_lux is value then return
      @_lux = value
      @emit 'lux', value

    _setMotion: (value) ->
      if @_motion is value then return
      @_motion = value
      @emit 'motion', value

    _setWater: (value) ->
      if @_water is value then return
      @_water = value
      @emit 'water', value

    _setState: (value) ->
      if @_state is value then return
      @_state = value
      @emit 'state', value

    _setPower: (value) ->
      if @_power is value then return
      @_power = value
      @emit 'power', value

    _setConsumtion: (value) ->
      if @_consumtion is value then return
      @_consumtion = value
      @emit 'consumtion', value

    _setOpenclose: (value) ->
      if @_openclose is value then return
      @_openclose = value
      @emit 'openclose', value

    _setVibration: (value) ->
      if @_vibration is value then return
      @_vibration = value
      @emit 'vibration', value

    _setCarbon: (value) ->
      if @_carbon is value then return
      @_carbon = value
      @emit 'carbon', value

    _setAlarm: (value) ->
      if @_alarm is value then return
      @_alarm = value
      @emit 'alarm', value

    _setDark: (value) ->
      if @_dark is value then return
      @_dark = value
      @emit 'dark', value

    _setFire: (value) ->
      if @_fire is value then return
      @_fire = value
      @emit 'fire', value

    _setSwitch: (value) ->
      clearTimeout(@_resetTimeout)
      @_resetTimeout = setTimeout ( =>
        @_switch = "waiting"
        @emit 'switch', @_switch
      ), @config.resetTime
      @_switch = value
      @emit 'switch', value

    getOnline: -> Promise.resolve(@_online)

    getBattery: -> Promise.resolve(@_battery)

    getTemperature: -> Promise.resolve(@_temperature)

    getHumidity: -> Promise.resolve(@_humidity)

    getPressure: -> Promise.resolve(@_pressure)

    getSwitch: -> Promise.resolve(@_switch)

    getMotion: -> Promise.resolve(@_motion)

    getOpenclose: -> Promise.resolve(@_openclose)

    getLux: -> Promise.resolve(@_lux)

    getPower: -> Promise.resolve(@_power)

    getConsumtion: -> Promise.resolve(@_consumtion)

    getWater: -> Promise.resolve(@_water)

    getVibration: -> Promise.resolve(@_vibration)

    getAlarm: -> Promise.resolve(@_alarm)

    getCarbon: -> Promise.resolve(@_carbon)

    getDark: -> Promise.resolve(@_dark)

    getFire: -> Promise.resolve(@_fire)

    registerPredicate: (@Cmd) =>
      @CmdMap.push @Cmd
      env.logger.debug "Register command: #{@Cmd.getCommand()} for #{@name}"

    deregisterPredicate: (@Cmd) =>
      @CmdMap.splice(@CmdMap.indexOf(@Cmd),1)
      env.logger.debug "Deregister command: #{@Cmd.getCommand()} for #{@name}"

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
      super()
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
        ).catch( (error) =>
          env.logger.error (error)
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
      super()
      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getSensor(@deviceID).then( (res) =>
          @_setBattery(res.config.battery)
          @_setOnline(res.config.reachable)
        ).catch( (error) =>
          env.logger.error (error)
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

  class RaspBeeSwitch extends env.devices.PowerSwitch

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_state = lastState?.state?.value or off

      @addAttribute  'presence',
        description: "online status",
        type: t.boolean
      super()
      myRaspBeePlugin.on "event", (data) =>
        if data.type is "lights" and data.id is @deviceID
          @parseEvent(data)

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getLight(@deviceID).then( (res) =>
          @parseEvent(res)
        ).catch( (error) =>
          env.logger.error (error)
        )

    parseEvent: (data) ->
      @_setPresence(data.state.reachable) if data.state?.reachable?
      @_setState(data.state.on)

    destroy: ->
      super()

    _setPresence: (value) ->
      if @_presence is value then return
      @_presence = value
      @emit 'presence', value

    getPresence: -> Promise.resolve(@_presence)

    changeStateTo: (state) ->
      @_sendState({on: state}).then( () =>
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

  class RaspBeeDimmer extends env.devices.DimmerActuator

    _lastdimlevel: null
    template: 'raspbee-dimmer'

    constructor: (@config,lastState) ->
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
      super()
      myRaspBeePlugin.on "event", (data) =>
        if data.type is "lights" and data.id is @deviceID
          @parseEvent(data)

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getLight(@deviceID).then( (res) =>
          @parseEvent(res)
        ).catch( (error) =>
          env.logger.error (error)
        )

    parseEvent: (data) ->
      @_setPresence(data.state.reachable) if data.state?.reachable?
      if data.state.bri?
        val = Math.ceil(data.state.bri / 255 * 100)
        if @_state
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

    changeDimlevelTo: (level, time) ->
      param = {
        on: level != 0,
        transitiontime: time or @_transtime
      }
      if (level > 0)
        param.bri=Math.round(level*(2.54))
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

    constructor: (@config,lastState) ->
      @ctmin = 153
      @ctmax = 500
      @_ct = lastState?.ct?.value or @ctmin
      @addAttribute  'ct',
          description: "color Temperature",
          type: t.number

      @actions.setCT =
        description: 'set light color'
        params:
          colorCode:
            type: t.number
      super(@config)

    parseEvent: (data) ->
      if (data.state.ct?)
        ncol=(data.state.ct-@ctmin)/(@ctmax-@ctmin)
        ncol=Math.min(Math.max(ncol, 0), 1)
        @_setCt(Math.round(ncol*100))
      if (data.ctmin?)
        @ctmin=data.ctmin
      if (data.ctmax?)
        @ctmax=data.ctmax
      super(data)

    getTemplateName: -> "raspbee-ct"

    getCt: -> Promise.resolve(@_ct)

    _setCt: (color) =>
      if @_ct is color then return
      @_ct = color
      @emit "ct", color

    setCT: (color,time) =>
      param = {
        ct: Math.round(@ctmin + color / 100 * (@ctmax-@ctmin)),
        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        @_setCt(color)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    destroy: ->
      super()


  class RaspBeeRGBCT extends RaspBeeCT

    @_color = 0
    @_hue = 0
    @_sat = 0

    template: 'raspbee-rgbct'

    constructor: (@config,lastState) ->
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
      super(@config,lastState)

    parseEvent: (data) ->
      if data.state.hue?
        @_setHue(data.state.hue / 65535 * 100)
      if data.state.sat?
        @_setSat(data.state.sat / 255 * 100)
      super(data)

    getTemplateName: -> "raspbee-rgbct"

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

    setRGB: (r,g,b,time) ->
      xy=Color.rgb_to_xyY(r,g,b,time)
      param = {
        xy: xy,
        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        #@_setCt(color)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    destroy: ->
      super()


  class RaspBeeRGB extends RaspBeeDimmer

    @_color = 0
    @_hue = 0
    @_sat = 0

    template: 'raspbee-rgb'

    constructor: (@config,lastState) ->
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
      super(@config,lastState)

    parseEvent: (data) ->
      if data.state.hue?
        @_setHue(data.state.hue / 65535 * 100)
      if data.state.sat?
        @_setSat(data.state.sat / 255 * 100)
      super(data)

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

    setRGB: (r,g,b,time) ->
      xy=Color.rgb_to_xyY(r,g,b)
      param = {
        xy: xy,
        transitiontime: time or @_transtime
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

    constructor: (@config,lastState) ->
      super(@config,lastState)
      myRaspBeePlugin.on "event", (data) =>
        @parseEvent(data)

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getGroup(@deviceID).then( (res) =>
          @_setState(res.state.any_on)
        ).catch( (error) =>
          env.logger.error (error)
        )

    parseEvent: (data) ->
      if data.type is "groups" and data.id is @deviceID
        @_setPresence(true)
        if (data.state.any_on?)
          @_setState(data.state.any_on)

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

  class RaspBeeRGBCTGroup extends RaspBeeRGBCT

    constructor: (@config,lastState) ->
      super(@config,lastState)
      myRaspBeePlugin.on "event", (data) =>
        @parseEvent(data)

    parseEvent: (data) ->
      if data.type is "groups" and data.id is @deviceID
        @_setPresence(true)
        if (data.state.any_on?)
          @_setState(data.state.any_on)

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

  class RaspBeeGroupScenes extends env.devices.Device

    template: "buttons"

    actions:
      buttonPressed:
        params:
          buttonId:
            type: t.integer
        description: "Press a button"

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @buttons = @config.buttons
      myRaspBeePlugin.on "ready", (data) =>
        @getScenes()
      super(@config,lastState)

    destroy: () ->
      super()

    getScenes: ->
      myRaspBeePlugin.Connector.getScenes(@config.deviceID).then( (res) =>
        @config.buttons = []
        for id, config of res
          @config.buttons.push({
            id: parseInt(id)
            name: config.name
            text: config.name
          })
      ).catch( (error) =>
        env.logger.error(error)
      )

    buttonPressed:  (scene_name)->
      scene_id = null
      for scene in @config.buttons
        if scene.id is parseInt(scene_name) or scene.name is scene_name
          #env.logger.debug scene.name
          scene_id = scene.id
          if myRaspBeePlugin.ready
            myRaspBeePlugin.Connector.setGroupScene(@deviceID, scene_id).then( (res) =>
              if res[0].success?
                return Promise.resolve()
              else
                return Promise.reject("Can't activate scene")
            ).catch( (error) =>
              return Promise.reject(error)
            )
            return Promise.resolve()
          return Promise.reject("connector not ready")
      return Promise.reject("Unknown scene "+scene_name)

##############################################################
# Raspbee system device
##############################################################

  class RaspBeeSystem extends env.devices.Sensor

    template: "raspbee-system"
    _presence: undefined

    constructor: (@config,lastState) ->
      @name = @config.name
      @id = @config.id
      @deviceID = @config.deviceID
      @networkopenduration = @config.networkopenduration ? @configDefaults.networkopenduration
      @_presence = lastState?.presence?.value or true
      @_discover = null
      @count = 0


      myRaspBeePlugin.on "ready", (data) =>
        @_setPresence(true)

      myRaspBeePlugin.on "error", (data) =>
        @_setPresence(false)

      myRaspBeePlugin.on "event", (data) =>
        @parseEvent(data)

      myRaspBeePlugin.Connector.getConfig().then( (res) =>
      #  @networkopenduration = res.networkopenduration
      )

      super(@config,lastState)

    parseEvent: (data) ->
      if data.event is "added"
        env.logger.info("new device paired!")
        env.logger.info("> " + data.newdev.name)
        env.logger.info("> " + data.newdev.manufacturername)
        env.logger.info("> " + data.newdev.modelid)
        env.logger.info("> " + data.newdev.type)

    destroy: ->
      super()

    attributes:
      presence:
        description: "deconz reachability"
        type: t.boolean
        labels: ['present', 'absent']

    actions:
      getPresence:
        description: "Returns the current presence state"
        returns:
          presence:
            type: t.boolean
      changePresenceTo:
        params:
          presence:
            type: "boolean"
      setLightDiscovery:
        description: 'discover light devices'
      setSensorDiscovery:
        description: 'discover sensor devices'
      setBackup:
        description: 'create device backup'
      setConfig:
        description: 'create device backup'

    _setPresence: (value) ->
      if @_presence is value then return
      @_presence = value
      @emit 'presence', value

    changePresenceTo: (presence) ->
      @_setPresence(presence)
      return Promise.resolve()

    getPresence: -> Promise.resolve(@_presence)

    setLightDiscovery: () ->
      if myRaspBeePlugin.ready
        myRaspBeePlugin.Connector.discoverLights().then( (res) =>
          env.logger.debug ("Start new pairing mode for "+@networkopenduration+" seconds" )
          clearInterval(@discover)
          @discover = setInterval ( =>
            myRaspBeePlugin.Connector.checkLights().then( (res) =>
              env.logger.debug('scanning...')
              env.logger.debug(res)
              if !(res.lastscan is "active")
                env.logger.info('scan finished')
                clearInterval(@discover)
            )
          ),5000
          return Promise.resolve()
        ).catch((error) =>
          env.logger.error ("discovery not possible : #{error}")
          return Promise.reject()
        )
      else
        return Promise.reject()

    setSensorDiscovery: () ->
      if myRaspBeePlugin.ready
        myRaspBeePlugin.Connector.discoverSensors().then( (res) =>
          env.logger.debug ("Start new pairing mode for "+@networkopenduration+" seconds" )
          clearInterval(@discover)
          @count = 1
          @discover = setInterval ( =>
            myRaspBeePlugin.Connector.checkSensors().then( (res) =>
              env.logger.debug('scanning...')
              env.logger.debug(res)
              if !(res.lastscan is "active")
                env.logger.info('scan finished')
                clearInterval(@discover)
            )
          ),5000
          return Promise.resolve()
        ).catch((error) =>
          env.logger.error ("discovery not possible : #{error}")
          return Promise.reject()
        )
      else
        return Promise.reject()

    setBackup: () ->
      storageDir = path.resolve(myRaspBeePlugin.framework.maindir, '../..')
      if myRaspBeePlugin.ready
        myRaspBeePlugin.Connector.createBackup(storageDir).then( (res) =>
          env.logger.info ("backup finished")
          return Promise.resolve()
        ).catch((error) =>
          env.logger.error ("backup not possible : #{error}")
          return Promise.reject()
        )
      else
        return Promise.reject()

    setConfig: () ->
      if myRaspBeePlugin.ready
        config = {
          networkopenduration: @networkopenduration
        }
        myRaspBeePlugin.Connector.setConfig(config).then( (res) =>
          env.logger.info ("config send")
          return Promise.resolve()
        ).catch((error) =>
          env.logger.error ("error : #{error}")
          return Promise.reject()
        )
        myRaspBeePlugin.emit 'config'
      else
        return Promise.reject()

  myRaspBeePlugin = new RaspBeePlugin()
  return myRaspBeePlugin
