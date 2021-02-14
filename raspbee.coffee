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
        RaspBeeGroupScenes,
        RaspBeeRGBDummy,
        RaspBeeCover
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
      @framework.ruleManager.addActionProvider(new RaspBeeAction.RaspBeeHueSatActionProvider(@framework))
      @framework.ruleManager.addActionProvider(new RaspBeeAction.RaspbeeCoverActionProvider(@framework))

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
            when dev.type == "Window covering device" then "RaspBeeCover"
            when dev.type == "Window covering controller" then "RaspBeeCover"
          if @lclass == "RaspbeeCover"
            config = {
              class: @lclass,
              name: dev.name,
              id: "raspbee_c#{dev.etag}#{i}",
              deviceID: i
            }
            if not @inConfig(i, @lclass)
              @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Cover: #{config.name} - #{dev.modelid}", config )
          else
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
        env.logger.debug("group list")
        env.logger.debug(devices)
        for i of devices
          dev=devices[i]
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
          newdevice = not @framework.deviceManager.devicesConfig.some (config_device, iterator) =>
            config_device.deviceID is id
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
# RaspBee MultiSensor
##############################################################

  class RaspBeeMultiSensor extends env.devices.Sensor

    template: "raspbee-multi"

    constructor: (@config,lastState) ->
      if @config.supportsHumidity?
        @config.supports.push("temperature")
        if @config.supportsPressure=true
          @config.supports.push("pressure")
        if @config.supportsHumidity=true
          @config.supports.push("humidity")
        delete @config.supportsHumidity
        delete @config.supportsPressure

      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @sensorIDs = @config.sensorIDs
      @configMap = @config.configMap
      @_online = lastState?.online?.value or false
      @attributes = {}
      @actions = {}
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
        @_tempoffset = @config.temperatureOffset
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
      if "consumption" in @config.supports
        @_consumtion = lastState?.consumtion?.value
        @attributes.consumtion = {
          description: "the measured consumtion"
          type: "number"
          unit: 'Wh'
          acronym: @config.consumtionAcronym
        }
      if "open" in @config.supports
        @_contact = lastState?.contact?.value
        @attributes.contact = {
          description: "the measured power"
          type: "boolean"
          labels: ['closed', 'opened']
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
        @_presence = lastState?.presence?.value or false
        @attributes.presence = {
          description: "motion detection"
          type: "boolean"
          labels: ['motion detected', 'no motion']
        }
      if "dark" in @config.supports
        @_dark = lastState?.dark?.value
        @attributes.dark = {
          description: "dark detection"
          type: "boolean"
          labels: ['dark', 'not dark']
        }
      if "fire" in @config.supports
        @_fire = lastState?.fire?.value
        @attributes.fire = {
          description: "fire detection"
          type: "boolean"
          labels: ['fire detected', 'no fire']
        }
      if "lowbattery" in @config.supports
        @_lowbattery = lastState?.lowbattery?.value
        @attributes.lowbattery = {
          description: "low battery detection"
          type: "boolean"
          labels: ['low battery  ', 'battery ok']
        }
      if "voltage" in @config.supports
        @_voltage = lastState?.voltage?.value
        @attributes.voltage = {
          description: "the measured voltage"
          type: "number"
          unit: 'V'
          acronym: @config.voltageAcronym
        }
      if "current" in @config.supports
        @_current = lastState?.current?.value
        @attributes.current = {
          description: "the measured current"
          type: "number"
          unit: 'mA'
          acronym: @config.currentAcronym
        }
      if "daylight" in @config.supports
        @_daylight = lastState?.daylight?.value
        @attributes.daylight = {
          description: "daylight detection"
          type: "boolean"
          labels: ['daylight', 'no daylight']
        }
        @_suncalc = lastState?.suncalc?.value
        @attributes.suncalc = {
          description: "suncalc"
          type: "string"
        }

      #FIXME tampered missing

      super()
      myRaspBeePlugin.on "event", (data) =>
        if data.id in @sensorIDs and data.resource is "sensors" and data.event is "changed"
          @_updateAttributes data

      myRaspBeePlugin.on "config", () =>
        @_setCfg()

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _updateAttributes: (data,first=false) ->
      @_setAlarm(data.state.alarm) if data.state?.alarm?
      @_setBattery(data.config.battery) if data.config?.battery?
      @_setCarbon(data.state.carbonmonoxide) if data.state?.carbonmonoxide?
      @_setConsumtion(data.state.consumption) if data.state?.consumption?
      @_setCurrent(data.state.current) if data.state?.current?
      @_setDark(data.state.dark) if data.state?.dark?
      @_setDaylight(data.state.daylight) if data.state?.daylight?
      @_setFire(data.state.fire) if data.state?.fire?
      @_setHumidity(data.state.humidity / 100) if data.state?.humidity?
      @_setLowbaterry(data.state.lowbattery) if data.state?.lowbattery?
      @_setLux(data.state.lux) if data.state?.lux?
      @_setPresence(data.state.presence) if data.state?.presence?
      @_setOnline(data.config.reachable) if data.config?.reachable?
      @_setContact(data.state.open) if data.state?.open?
      @_setPower(data.state.power) if data.state?.power?
      @_setPressure(data.state.pressure ) if data.state?.pressure?
      @_setSuncalc(data.state.status) if data.state?.status?
      @_setSwitch(data.state.buttonevent.toString()) if (data.state?.buttonevent?) and not first
      @_setTemperature(data.config.temperature / 100) if data.config?.temperature?
      @_setTemperature(data.state.temperature / 100) if data.state?.temperature?
      @_setVibration(data.state.vibration) if data.state?.vibration?
      @_setVoltage(data.state.voltage) if data.state?.voltage?
      @_setWater(data.state.water) if data.state?.water?

      if data.state?.buttonevent? and not first
        for cmdval in @CmdMap
          if cmdval.getCommand() == data.state.buttonevent.toString()
            cmdval.emit('change', 'event')

    getInfos: (first) ->
      if (myRaspBeePlugin.ready)
        for id in @sensorIDs
          myRaspBeePlugin.Connector.getSensor(id).then((res) =>
            @_updateAttributes(res,true)
          ).catch( (error) =>
            env.logger.error (error)
          )

    _setCfg: ->
      if myRaspBeePlugin.ready
        for id,cfg of @configMap
          sconfig = {}
          sconfig[cfg.parameter]=cfg.value
          myRaspBeePlugin.Connector.setSensorConfig(cfg.id,sconfig).then( (res) =>
            env.logger.debug ("config send to #{@name}:")
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
      newt=if @_tempoffset? then @_tempoffset+value else value
      if @_temperature is newt then return
      @_temperature = newt
      @emit 'temperature', newt

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

    _setPresence: (value) ->
      if @_presence is value then return
      @_presence = value
      @emit 'presence', value

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

    _setCurrent: (value) ->
      if @_current is value then return
      @_current = value
      @emit 'current', value

    _setVoltage: (value) ->
      if @_voltage is value then return
      @_voltage = value
      @emit 'voltage', value

    _setContact: (value) ->
      if @_contact is !value then return
      @_contact = !value
      @emit 'contact', !value

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

    _setLowbaterry: (value) ->
      if @_lowbattery is value then return
      @_lowbattery = value
      @emit 'lowbattery', value


    _setDaylight: (value) ->
      if @_daylight is value then return
      @_daylight = value
      @emit 'daylight', value

    _setSuncalc: (value) ->
      @_suncalc = switch
        when value == 100 then "NADIR"
        when value == 110 then "NIGHT END"
        when value == 120 then "NAUTICAL DAWN"
        when value == 130 then "DAWN"
        when value == 140 then "SUNRISE START"
        when value == 150 then "SUNRISE END"
        when value == 160 then "GOLDENHOUR"
        when value == 170 then "SOLAR NOON"
        when value == 180 then "GOLDENHOUR"
        when value == 190 then "SUNSET START"
        when value == 200 then "SUNSET STOP"
        when value == 210 then "DUSK"
        when value == 220 then "NAUTICAL DUSK"
        when value == 230 then "NIGHT START"
        else  value.toString()
      @emit 'suncalc', @_suncalc

    _setSwitch: (value) ->
      clearTimeout(@_resetTimeout)
      @_resetTimeout = setTimeout ( =>
        @_switch = "waiting"
        @emit 'switch', @_switch
      ), @config.resetTime
      @_switch = value
      @emit 'switch', @_switch

    getAlarm: -> Promise.resolve(@_alarm)
    getBattery: -> Promise.resolve(@_battery)
    getCarbon: -> Promise.resolve(@_carbon)
    getConsumtion: -> Promise.resolve(@_consumtion)
    getCurrent: -> Promise.resolve(@_current)
    getDark: -> Promise.resolve(@_dark)
    getDaylight: -> Promise.resolve(@_daylight)
    getFire: -> Promise.resolve(@_fire)
    getHumidity: -> Promise.resolve(@_humidity)
    getLowbattery: -> Promise.resolve(@_lowbattery)
    getLux: -> Promise.resolve(@_lux)
    getPresence: -> Promise.resolve(@_presence)
    getOnline: -> Promise.resolve(@_online)
    getContact: -> Promise.resolve(@_contact)
    getPower: -> Promise.resolve(@_power)
    getPressure: -> Promise.resolve(@_pressure)
    getSuncalc: -> Promise.resolve(@_suncalc)
    getSwitch: -> Promise.resolve(@_switch)
    getTemperature: -> Promise.resolve(@_temperature)
    getVibration: -> Promise.resolve(@_vibration)
    getVoltage: -> Promise.resolve(@_voltage)
    getWater: -> Promise.resolve(@_water)

    registerPredicate: (@Cmd) =>
      @CmdMap.push @Cmd
      env.logger.debug "Register command: #{@Cmd.getCommand()} for #{@name}"

    deregisterPredicate: (@Cmd) =>
      @CmdMap.splice(@CmdMap.indexOf(@Cmd),1)
      env.logger.debug "Deregister command: #{@Cmd.getCommand()} for #{@name}"

##############################################################
# RaspBee SwitchSensor
##############################################################

  class RaspBeeSwitchSensor extends RaspBeeMultiSensor

    constructor: (config,lastState) ->

      if config.deviceID?
        config.supports = []
        config.sensorIDs = []
        config.sensorIDs.push(parseInt(config.deviceID))
        config.supports.push("switch")
        delete config.deviceID

      super(config,lastState)

##############################################################
# RaspBee WaterSensor
##############################################################

  class RaspBeeWaterSensor extends RaspBeeMultiSensor

    constructor: (config,lastState) ->

      if config.deviceID?
        config.supports = []
        config.sensorIDs = []
        config.sensorIDs.push(parseInt(config.deviceID))
        config.supports.push("water")
        delete config.deviceID

      super(config,lastState)

##############################################################
# RaspBee LightSensor
##############################################################

  class RaspBeeLightSensor extends RaspBeeMultiSensor

    constructor: (config,lastState) ->

      if config.deviceID?
        config.supports = []
        config.sensorIDs = []
        config.sensorIDs.push(parseInt(config.deviceID))
        config.supports.push("lux")
        delete config.deviceID

      super(config,lastState)

##############################################################
# RaspBee MotionSensor
##############################################################

  class RaspBeeMotionSensor extends RaspBeeMultiSensor

    template: "presence"

    constructor: (config,lastState) ->

      if config.deviceID?
        config.supports = []
        config.sensorIDs = []
        config.sensorIDs.push(parseInt(config.deviceID))
        config.supports.push("presence")
        delete config.deviceID

      super(config,lastState)

##############################################################
# RaspBee ContactSensor
##############################################################

  class RaspBeeContactSensor extends RaspBeeMultiSensor

    template: "contact"

    constructor: (config,lastState) ->

      if config.deviceID?
        config.supports = []
        config.sensorIDs = []
        config.sensorIDs.push(parseInt(config.deviceID))
        config.supports.push("open")
        delete config.deviceID
        delete config.inverted

      super(config,lastState)


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
      super(@config,lastState)
      myRaspBeePlugin.on "event", (data) =>
        if data.resource is "sensors" and data.id is @deviceID and data.event is "changed"
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

    template: "raspbee-switch"    

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @_presence = lastState?.presence?.value or false
      @_state = lastState?.state?.value or off

      @addAttribute  'presence',
        description: "online status",
        type: t.boolean
      super()
      myRaspBeePlugin.on "event", (data) =>
        if data.resource is "lights" and data.id is @deviceID and data.event is "changed"
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

    getTemplateName: -> "raspbee-switch"

    _setPresence: (value) ->
      if @_presence is value then return
      @_presence = value
      @emit 'presence', value

    getPresence: -> Promise.resolve(@_presence)

    changeStateTo: (state) ->
      @_sendState({on: state}).then( () =>
        return Promise.resolve()
      ).catch( (error) =>
        env.logger.error error
        return Promise.reject(error)
      )

    _sendState: (param) ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.setLightState(@deviceID,param).then( (res) =>
          env.logger.debug ("New value send to device #{@name}")
          env.logger.debug (param)
          if res[0].success?
            return Promise.resolve()
          else
            if (res[0].error.type is 3 )
              @_setPresence(false)
              return Promise.reject(Error("device #{@name} not reachable"))
            else if (res[0].error.type is 201 )
              return Promise.reject(Error("device #{@name} is not modifiable. Device is set to off"))
        ).catch( (error) =>
          return Promise.reject(error)
        )
      else
        env.logger.error("gateway not online")
        return Promise.reject(Error("gateway not online"))

  class RaspBeeDimmer extends env.devices.DimmerActuator

    _lastdimlevel: null
    template: 'raspbee-dimmer'

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @_presence = lastState?.presence?.value or false
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
        if data.resource is "lights" and data.id is @deviceID and data.event is "changed"
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
          env.logger.debug (param)
          if res[0].success?
            return Promise.resolve()
          else
            if (res[0].error.type is 3 )
              @_setPresence(false)
              return Promise.reject(Error("device #{@name} not reachable"))
            else if (res[0].error.type is 201 )
              return Promise.reject(Error("device #{@name} is not modifiable. Device is set to off"))
            else Promise.reject(Error("general error"))
        ).catch( (error) =>
          return Promise.reject(error)
        )
      else
        env.logger.error ("gateway not online")
        return Promise.reject(Error("gateway not online"))


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
        on: true,
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
      @actions.changeHueSatTo =
        description: 'set light color'
        params:
          hue:
            type: t.number
          sat:
            type: t.number
          time:
            type: t.number
            optional: yes
      @actions.changeHueSatValTo =
        description: 'set light color values without transmit'
        params:
          hue:
            type: t.number
          sat:
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
      @actions.changeHueTo =
        description: 'set light color'
        params:
          hue:
            type: t.number
          time:
            type: t.number
            optional: yes
      @actions.changeSatTo =
        description: 'set light color'
        params:
          sat:
            type: t.number
          time:
            type: t.number
            optional: yes
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

    changeHueTo: (hue, time) ->
      param = {
        on: true,
        hue: parseInt(hue/100*65535),
# not working with transtime
#        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        @_setHue hue
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    changeSatTo: (sat, time) ->
      param = {
        on: true,
        sat: parseInt (sat/100*254),
# not working with transtime
#        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        @_setSat sat
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )
    changeHueSatValTo: (hue, sat) ->
      @_setHue hue
      @_setSat sat
      return Promise.resolve()

    changeHueSatTo: (hue, sat, time) ->
      param = {
        on: true,
        sat: (sat/100*254),
        hue: (hue/100*65535),
        transitiontime: time or @_transtime
      }
      p1 = @changeSatTo(sat,time)
      p2 = @changeHueTo(hue,time)

      Promise.all([p1,p2]).then( () =>
        @_setHue hue
        @_setSat sat
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    setRGB: (r,g,b,time) ->
      xy=Color.rgb_to_xyY(r,g,b)
      param = {
        on: true,
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

  class RaspBeeRGB extends RaspBeeCT

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
      @actions.changeHueSatTo =
        description: 'set light color'
        params:
          hue:
            type: t.number
          sat:
            type: t.number
          time:
            type: t.number
            optional: yes
      @actions.changeHueSatValTo =
        description: 'set light color values without transmit'
        params:
          hue:
            type: t.number
          sat:
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
      @actions.changeHueTo =
        description: 'set light color'
        params:
          hue:
            type: t.number
          time:
            type: t.number
            optional: yes
      @actions.changeSatTo =
        description: 'set light color'
        params:
          sat:
            type: t.number
          time:
            type: t.number
            optional: yes
      super(@config,lastState)

    parseEvent: (data) ->
      if data.state.hue?
        @_setHue(data.state.hue / 65535 * 100)
      if data.state.sat?
        @_setSat(data.state.sat / 255 * 100)
      if data.state.xy?
        @_setkelvin(data.state.xy)
      super(data)

    getTemplateName: -> "raspbee-rgbct"

    _setkelvin: (xy) =>
      kalvin=Color.xyY_to_kelvin(xy[0],xy[1])
      ncol=(kalvin-2000)/(6500-2000)
      ncol=Math.min(Math.max(ncol, 0), 1)
      @_setCt(Math.round(ncol*100))

    setCT: (color,time) =>
      kalvin=Math.round(2000 + color / 100 * (6500-2000))
      xy=Color.kelvin_to_xy(kalvin)
      param = {
        on: true,
        xy: xy,
        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        @_setCt(color)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

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

    changeHueTo: (hue, time) ->
      param = {
        on: true,
        hue: parseInt(hue/100*65535),
# not working with transtime
#        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        @_setHue hue
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    changeSatTo: (sat, time) ->
      param = {
        on: true,
        sat: parseInt (sat/100*254),
# not working with transtime
#        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
        @_setSat sat
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    changeHueSatTo: (hue, sat, time) ->
      param = {
        on: true,
        sat: (sat/100*254),
        hue: (hue/100*65535),
        transitiontime: time or @_transtime
      }
      p1 = @changeSatTo(sat,time)
      p2 = @changeHueTo(hue,time)

      Promise.all([p1,p2]).then( () =>
        @_setHue hue
        @_setSat sat
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    changeHueSatValTo: (hue, sat) ->
      @_setHue hue
      @_setSat sat
      return Promise.resolve()

    setRGB: (r,g,b,time) ->
      xy=Color.rgb_to_xyY(r,g,b)
      param = {
        on: true,
        xy: xy,
        transitiontime: time or @_transtime
      }
      @_sendState(param).then( () =>
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
      if data.resource is "groups" and data.id is @deviceID and data.event is "changed"
        @_setPresence(true)
        if (data.state.any_on?)
          @_setState(data.state.any_on)

    _sendState: (param) ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.setGroupState(@deviceID,param).then( (res) =>
          env.logger.debug ("New value send to group #{@name}")
          env.logger.debug (param)
          if res[0].success?
            return Promise.resolve()
          else
            if (res[0].error.type is 3 )
              return Promise.reject(Error("device #{@name} not reachable"))
            else if (res[0].error.type is 201 )
              return Promise.reject(Error("device #{@name} is not modifiable. Device is set to off"))
        ).catch( (error) =>
          return Promise.reject(error)
        )
      else
        env.logger.error ("gateway not online")
        return Promise.reject(Error("gateway not online"))

  class RaspBeeRGBCTGroup extends RaspBeeRGBCT

    template: 'raspbee-group-rgbct'

    constructor: (@config,lastState) ->
      super(@config,lastState)
      myRaspBeePlugin.on "event", (data) =>
        @parseEvent(data)

    parseEvent: (data) ->
      if data.resource is "groups" and data.id is @deviceID and data.event is "changed"
        @_setPresence(true)
        if (data.state.any_on?)
          @_setState(data.state.any_on)

    _sendState: (param) ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.setGroupState(@deviceID,param).then( (res) =>
          env.logger.debug ("New value send to group #{@name}")
          env.logger.debug (param)
          if res[0].success?
            return Promise.resolve()
          else
            if (res[0].error.type is 3 )
              return Promise.reject(Error("device #{@name} not reachable"))
            else if (res[0].error.type is 201 )
              return Promise.reject(Error("device #{@name} is not modifiable. Device is set to off"))
        ).catch( (error) =>
          return Promise.reject(error)
        )
      else
        env.logger.error ("gateway not online")
        return Promise.reject(Error("gateway not online"))

  class RaspBeeRGBDummy extends RaspBeeRGBCT

    template: 'raspbee-group-rgbct'

    constructor: (@config,lastState) ->
      super(@config,lastState)

    parseEvent: (data) ->
      return

    _sendState: (param) ->
      return Promise.resolve()

  class RaspBeeGroupScenes extends env.devices.Device

    template: "buttons"

    attributes:
      button:
        description: "The last pressed button"
        type: t.string

    actions:
      buttonPressed:
        params:
          buttonId:
            type: t.integer
        description: "Press a button"

    _lastPressedButton: null

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @buttons = @config.buttons
      myRaspBeePlugin.on "ready", (data) =>
        @getScenes()
      super(@config,lastState)

      @_lastPressedButton = lastState?.button?.value
      for button in @config.buttons
        @_button = button if button.id is @_lastPressedButton
    
    getButton: -> Promise.resolve(@_lastPressedButton)
    
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
                return Promise.reject(Error("Can't activate scene"))
            ).catch( (error) =>
              return Promise.reject(error)
            )
            return Promise.resolve()
          return Promise.reject(Error("connector not ready"))
      return Promise.reject(Error("Unknown scene "+scene_name))

  class RaspBeeCover extends env.devices.DimmerActuator

    _lastdimlevel: null
    template: 'raspbee-dimmer'

    constructor: (@config,lastState) ->
      @id = @config.id
      @name = @config.name
      @deviceID = @config.deviceID
      @_presence = lastState?.presence?.value or false
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
        if data.resource is "lights" and data.id is @deviceID and data.event is "changed"
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
      env.logger.debug "Received values: " + JSON.stringify(data,null,2)
      if data.state.lift?
        val = data.state.lift
        #val = Math.ceil((data.state.bri / 255) * 100)
        #if @_state
        @_setDimlevel(val)
        #if val > 0
        #  @_lastdimlevel = val
      if (data.state.open?)
        if data.state.lift is 100
          @_setDimlevel(100)
          #@_setDimlevel(@_lastdimlevel)
          #else
          #if @_dimlevel > 0
          #  @_lastdimlevel = @_dimlevel
          #@_setDimlevel(0)

    destroy: ->
      super()

    getTemplateName: -> "raspbee-dimmer"

    _setPresence: (value) ->
      if @_presence is value then return
      @_presence = value
      @emit 'presence', value

    getPresence: -> Promise.resolve(@_presence)

    turnOn: ->
      @changeDimlevelTo(100)
      # @changeDimlevelTo(@_lastdimlevel)

    turnOff: ->
      @changeDimlevelTo(0)

    stop: ->
      param = {
        bri_inc: 0
      }
      @_sendState(param).then( () =>
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    changeDimlevelTo: (level, time) ->
      param = {
        on: level != 0
      }
      if (level > 0)
        param["bri"] = Math.round(level * (2.54)) # Math.round(level*(2.54))
        # param["bri"] = 254 - Math.round(level * (2.54)) # Math.round(level*(2.54))
      @_sendState(param).then( () =>
        #unless @_dimlevel is 0
        #  @_lastdimlevel = @_dimlevel
        @_setDimlevel(level)
        return Promise.resolve()
      ).catch( (error) =>
        return Promise.reject(error)
      )

    _sendState: (param) ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.setLightState(@deviceID,param).then( (res) =>
          env.logger.debug ("New value send to device #{@name}")
          env.logger.debug (param)
          if res[0].success?
            return Promise.resolve()
          else
            if (res[0].error.type is 3 )
              @_setPresence(false)
              return Promise.reject(Error("device #{@name} not reachable"))
            else if (res[0].error.type is 201 )
              return Promise.reject(Error("device #{@name} is not modifiable. Device is set to off"))
            else Promise.reject(Error("general error"))
        ).catch( (error) =>
          return Promise.reject(error)
        )
      else
        env.logger.error ("gateway not online")
        return Promise.reject(Error("gateway not online"))



##############################################################
# Raspbee system device
##############################################################

  class RaspBeeSystem extends env.devices.Device

    template: "raspbee-system"

    constructor: (@config,lastState) ->
      @name = @config.name
      @id = @config.id
      @deviceID = @config.deviceID
      @networkopenduration = @config.networkopenduration ? @configDefaults.networkopenduration
      @backupfolder = @config.backupfolder ? null
      @_online = false
      @count = 0


      myRaspBeePlugin.on "ready", (data) =>
        @_setOnline(true)

      myRaspBeePlugin.on "error", (data) =>
        @_setOnline(false)

      myRaspBeePlugin.on "event", (data) =>
        @parseEvent(data)

      #myRaspBeePlugin.Connector.getConfig().then( (res) =>
      #  @networkopenduration = res.networkopenduration
      #)

      super(@config,lastState)

    parseEvent: (data) ->
      if data.event is "added"
        env.logger.info("new device paired!")
        env.logger.info("ID > " + data.id)
        env.logger.info("Resource > " + data.resource)
        env.logger.info("UID > " + data.uniqueid)
        if data.newdev?
          env.logger.info("Name > " + data.newdev.name)
          env.logger.info("Manu > " + data.newdev.manufacturername)
          env.logger.info("Model > " + data.newdev.modelid)
          env.logger.info("Type > " + data.newdev.type)

    destroy: ->
      super()

    attributes:
      online:
        description: "deconz reachability"
        type: t.boolean
        labels: ['online', 'offline']

    actions:
      getOnline:
        description: "Returns the current online state"
        returns:
          online:
            type: t.boolean
      changeOnlineTo:
        params:
          online:
            type: "boolean"
      setLightDiscovery:
        description: 'discover light devices'
      setSensorDiscovery:
        description: 'discover sensor devices'
      setBackup:
        description: 'create device backup'
      setConfig:
        description: 'create device backup'

    _setOnline: (value) ->
      if @_online is value then return
      @_online = value
      @emit 'online', value

    changeOnlineTo: (online) ->
      @_setOnline(online)
      return Promise.resolve()

    getOnline: -> Promise.resolve(@_online)

    setLightDiscovery: () ->
      if myRaspBeePlugin.ready
        myRaspBeePlugin.Connector.discoverLights().then( (res) =>
          env.logger.info ("Start pairing mode for "+@networkopenduration+" seconds" )
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
          env.logger.error("discovery not possible : #{error}")
          return Promise.reject(Error("discovery not possible : #{error}"))
        )
      else
        return Promise.reject(Error("general discovery error"))

    setSensorDiscovery: () ->
      if myRaspBeePlugin.ready
        myRaspBeePlugin.Connector.discoverSensors().then( (res) =>
          env.logger.info ("Start new pairing mode for "+@networkopenduration+" seconds" )
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
          env.logger.error("discovery not possible : #{error}")
          return Promise.reject(Error("discovery not possible : #{error}"))
        )
      else
        return Promise.reject(Error("general discovery error"))

    setBackup: () ->
      storageDir = path.resolve(@backupfolder or path.resolve(myRaspBeePlugin.framework.maindir, '../..'))
      if myRaspBeePlugin.ready
        myRaspBeePlugin.Connector.createBackup(storageDir).then( (res) =>
          env.logger.info ("backup finished")
          return Promise.resolve()
        ).catch((error) =>
          env.logger.error ("backup not possible : #{error}")
          return Promise.reject(Error("backup error"))
        )
      else
        return Promise.reject(Error("general backup error"))

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
          return Promise.reject(error)
        )
        myRaspBeePlugin.emit 'config'
      else
        return Promise.reject(Error("general config error"))

  myRaspBeePlugin = new RaspBeePlugin()
  return myRaspBeePlugin
