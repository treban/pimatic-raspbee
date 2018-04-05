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

      deviceClasses = [
        #RaspBeeSystem,
        RaspBeeMotionSensor,
        RaspBeeContactSensor,
        RaspBeeLightSensor,
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
        for i of devices
          dev=devices[i]
          @lclass = switch
            when dev.type == "ZHASwitch" then "RaspBeeRemoteControlNavigator"
            when dev.type == "ZHAPresence" then "RaspBeeMotionSensor"
            when dev.type == "ZHAOpenClose" then "RaspBeeContactSensor"
            when dev.type == "ZHALightLevel" then "RaspBeeLightSensor"
          config = {
            class: @lclass,
            name: dev.name,
            id: "raspbee_#{dev.etag}",
            deviceID: i
          }
          if not @inConfig(i, @lclass)
            @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Sensor: #{config.name} - #{dev.modelid}", config )
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
            @framework.deviceManager.discoveredDevice( 'pimatic-raspbee ', "Group: #{config.name} - #{dev.modelid}", config )
      )

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
          env.logger.debug("device "+deviceID+" already exists")
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
      @resetTime = @config.resetTime
      @_presence = lastState?.presence?.value or false
      @_online = lastState?.online?.value or false
      @_battery = lastState?.battery?.value
      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if data.type is "sensors" and data.id is @deviceID
          if (data.state != undefined)
            @_setMotion(data.state.presence)
          @_setBattery(data.config.battery) if data.config?.battery?
          @_setOnline(data.config.reachable) if data.config?.reachable?

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

    attributes:
      presence:
        description: "motion detection"
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
        @_updateAttributes data

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _value: (state) ->
      if @config.inverted then not state else state

    _updateAttributes: (data) ->
      if data.type is "sensors" and data.id is @deviceID
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
        @_updateAttributes data

      @getInfos()
      myRaspBeePlugin.on "ready", () =>
        @getInfos()

    _updateAttributes: (data) ->
      if data.type is "sensors" and data.id is @deviceID
        @_setLux(data.state.lux) if data.state?.lux?
        @_setBattery(data.config.battery) if data.config?.battery?
        @_setOnline(data.config.reachable) if data.config?.reachable?

    getInfos: ->
      if (myRaspBeePlugin.ready)
        myRaspBeePlugin.Connector.getSensor(@deviceID).then (res) =>
          @_updateAttributes res

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
        if (( data.type == "sensors") and (data.id == "#{@deviceID}"))
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
      @_transtime=@config.transtime or 5

      @addAttribute  'presence',
        description: "online status",
        type: t.boolean

      super(@config,lastState)

      myRaspBeePlugin.on "event", (data) =>
        if (( data.type == "lights") and (data.id == "#{@deviceID}"))
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
          @_setDimlevel(res.state.bri)
          @_setState(res.state.on)
        )

    parseEvent: (data) ->
      if (data.state.bri?)
        if ((parseInt(data.state.bri/254*100) == 0) and (data.state.bri > 0) )
          val=1
        else
          val=parseInt(data.state.bri/254*100)
        if (@_state)
          @_setDimlevel(val)
        else
          @_lastdimlevel = val
      if (data.state.on?)
        if (data.state.on)
          @_setDimlevel(@_lastdimlevel)
        else
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
# TradfriDimmerTempSliderItem
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
          @_setDimlevel(res.state.bri)
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

      @cmin = 24933
      @cmax = 33137
      @min = 2000
      @max = 4700

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

    # h=0-360,s=0-1,l=0-1
    setHuesat: (h,s,l=0.75) ->
      rgb=Color.hslToRgb(h,s,l)
      xy=Color.rgb_to_xyY(rgb[0],rgb[1],rgb[2])
      if (tradfriReady)
        tradfriHub.setColorXY(@address, parseInt(xy[0]), parseInt(xy[1]), @_transtime
        ).then( (res) =>
          env.logger.debug ("New Color send to device")
          return Promise.resolve()
        )
      else
        return Promise.reject()

    setColorHex: (hex) ->
      if (tradfriReady)
        tradfriHub.setColorHex(@address, hex, @_transtime
        ).then( (res) =>
          env.logger.debug ("New Color send to device")
          return Promise.resolve()
        )
      else
        return Promise.reject()

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
      if (( data.type == "groups") and (data.id == "#{@deviceID}"))
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
