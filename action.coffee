module.exports = (env) ->

  _ = env.require 'lodash'
  M = env.matcher
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  t = env.require('decl-api').types

  matchTransitionExpression = (match, callback, optional=yes) ->
    matcher = ( (next) =>
      next.match(" with", optional: yes)
        .match([" transition time "])
        .matchTimeDuration(wildcard: "{duration}", type: "text", callback)
    )
    return if optional then match.optional(matcher) else matcher(match)

################################################################################
## SCENE ACTIONS
################################################################################
  class RaspBeeSceneActionProvider extends env.actions.ActionProvider

    constructor: (framework) ->
      super()
      @framework=framework

    parseAction: (input, context) =>
      matchingScene = null
      matchingDevice = null
      scenes = []
      onSceneMatch = (m, {device,scene}) =>
        matchingDevice = device
        matchingScene = scene

      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeGroupScenes',
        ], device.config.class
      ).value()

      if RaspBeeDevices.length is 0 then return

      for id, d of RaspBeeDevices
        for s in d.config.buttons
          scenes.push [{device: d, scene: s.name}, s.name]

      m = M(input, context)
        .match('activate group scene ')
        .match(
          scenes,
          onSceneMatch
        )

      match = m.getFullMatch()
      if match?
        assert matchingScene?
        assert matchingDevice?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new SceneActionHandler(matchingDevice, matchingScene)
        }
      else
        return null

  class SceneActionHandler extends env.actions.ActionHandler

    constructor: (device, scene) ->
      super()
      @device=device
      @scene=scene
      assert @device?
      assert @scene? and typeof @scene is "string"

    setup: ->
      @dependOnDevice(@device)
      super()

    _doExecuteAction: (simulate) =>
      return (
        if simulate
          Promise.resolve __("would activate scene %s of device %s", @scene, @device.id)
        else
          @device.buttonPressed(@scene)
            .then( =>__("activate scene %s of device %s", @scene, @device.id) )
      )

    executeAction: (simulate) => @_doExecuteAction(simulate)
    hasRestoreAction: -> no

################################################################################
## Color temperature ACTIONS
################################################################################
  class RaspBeeTempActionHandler extends env.actions.ActionHandler

    constructor: (framework, device, valueTokens, @transitionTime=null) ->
      super()
      @framework=framework
      @device=device
      @valueTokens=valueTokens
      assert @device?
      assert @valueTokens?

    setup: ->
      @dependOnDevice(@device)
      super()

    _clampVal: (value) ->
      assert(not isNaN(value))
      return (switch
        when value > 100 then 100
        when value < 0 then 0
        else value
      )

    _doExecuteAction: (simulate, value) =>
      return (
        if simulate
          __("would change %s to %s%%", @device.name, value)
        else
          @device.setCT(value,@transitionTime).then( => __("change color temp from %s to %s%%", @device.name, value) )
      )

    executeAction: (simulate) =>
      @device.getCt().then( (lastValue) =>
        @lastValue = lastValue or 0
        return @framework.variableManager.evaluateNumericExpression(@valueTokens).then( (value) =>
          value = @_clampVal value
          return @_doExecuteAction(simulate, value)
        )
      )

    hasRestoreAction: -> yes
    executeRestoreAction: (simulate) => Promise.resolve(@_doExecuteAction(simulate, @lastValue))

  class RaspBeeTempActionProvider extends env.actions.ActionProvider

    constructor: (framework) ->
      super()
      @framework=framework

    parseAction: (input, context) =>
      retVar = null
      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeCT',
          'RaspBeeRGB',
          'RaspBeeRGBCT',
          'RaspBeeRGBCTGroup'
        ], device.config.class
      ).value()

      device = null
      valueTokens = null
      match = null
      transitionMs = null

      if RaspBeeDevices.length is 0 then return

      M(input, context)
        .match('set color temp ')
        .matchDevice(RaspBeeDevices, (next, d) =>
          next.match(' to ')
            .matchNumericExpression( (next, ts) =>
              m = next.match('%', optional: yes)
              if device? and device.id isnt d.id
                context?.addError(""""#{input.trim()}" is ambiguous.""")
                return
              device = d
              valueTokens = ts

              m = matchTransitionExpression(m, ( (m, {time, unit, timeMs}) =>
                transitionMs = timeMs/100
              ), yes)
              match = m.getFullMatch()
            )
        )

      if match?
        if valueTokens.length is 1 and not isNaN(valueTokens[0])
          value = valueTokens[0]
          assert(not isNaN(value))
          value = parseFloat(value)
          if value < 0.0
            context?.addError("Can't dim to a negative dimlevel.")
            return
          if value > 100.0
            context?.addError("Can't dim to greater than 100%.")
            return
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new RaspBeeTempActionHandler(@framework, device, valueTokens, transitionMs)
        }
      else
        return null

################################################################################
## Color RGB ACTIONS
################################################################################
  class RaspBeeRGBActionHandler extends env.actions.ActionHandler

    constructor: (framework, device, hex, @transitionTime=null) ->
      super()
      @framework=framework
      @device=device
      @hex=hex
      assert @device?
      assert @hex?
      @result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(@hex)
      @r = parseInt(@result[1], 16)
      @g = parseInt(@result[2], 16)
      @b = parseInt(@result[3], 16)

    setup: ->
      @dependOnDevice(@device)
      super()

    _doExecuteAction: (simulate) =>
      return (
        if simulate
          Promise.resolve __("would set color %s to %s%", @device.name)
        else
          @device.setRGB(@r,@g,@b,@transitionTime).then( => __("set color %s to %s", @device.name, @hex) )
      )

    executeAction: (simulate) =>
      return @_doExecuteAction(simulate)

    hasRestoreAction: -> no

  class RaspBeeRGBActionProvider extends env.actions.ActionProvider
    constructor: (framework) ->
      super()
      @framework=framework

    parseAction: (input, context) =>
      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeRGB'
          'RaspBeeRGBCT',
          'RaspBeeRGBCTGroup'
        ], device.config.class
      ).value()

      m = M(input, context).match(['set color rgb '])

      device = null
      hex = null
      match = null
      r = null
      g = null
      b = null
      transitionMs = null
      m.matchDevice RaspBeeDevices, (m, d) ->
        if device? and device.id isnt d.id
          context?.addError(""""#{input.trim()}" is ambiguous.""")
          return
        device = d
        m.match [' to '], (m) ->
          m.or [
            (m) -> m.match [/(#[a-fA-F\d]{6})(.*)/], (m, s) ->
              hex = s.trim()
              m = matchTransitionExpression(m, ( (m, {time, unit, timeMs}) =>
                transitionMs = timeMs/100
              ), yes)
              match = m.getFullMatch()
          ]
      if match?
        assert hex?
        return {
          token : match
          nextInput: input.substring(match.length)
          actionHandler: new RaspBeeRGBActionHandler(@framework, device, hex, transitionMs)
        }
      else
        return null

  class RaspBeeHueSatActionHandler extends env.actions.ActionHandler
    constructor: (@framework, @device, @hueExpr, @satExpr, @transitionTime=null) ->
      assert @device?
      assert @hueExpr? or @satExpr?

    executeAction: (@simulate) =>

      if @hueExpr? and isNaN(@hueExpr)
        huePromise = @framework.variableManager.evaluateExpression(@hueExpr)
      else
        huePromise = Promise.resolve @hueExpr
      if @satExpr? and isNaN(@satExpr)
        satPromise = @framework.variableManager.evaluateExpression(@satExpr)
      else
        satPromise = Promise.resolve @satExpr

      return Promise.join huePromise, satPromise, @_changeHueSat

    _changeHueSat: (hueValue, satValue) =>
      if hueValue? and satValue?
        f = (hue, sat) => @device.changeHueSatTo hue, sat, @transitionTime
        msg = "changed color to hue #{hueValue}% and sat #{satValue}%"
      else if hueValue?
        f = (hue, sat) => @device.changeHueTo hue, @transitionTime
        msg = "changed color to hue #{hueValue}%"
      else if satValue?
        f = (hue, sat) => @device.changeSatTo sat, @transitionTime
        msg = "changed color to sat #{satValue}%"
      msg += " transition time #{@transitionTime}ms" if @transitionTime?

      if @simulate
        return Promise.resolve "would have #{msg}"
      else
        return f(hueValue, satValue).then( => msg )


  class RaspBeeHueSatActionProvider extends env.actions.ActionProvider
    constructor: (framework) ->
      super()
      @framework=framework

    parseAction: (input, context) =>
      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeRGB'
          'RaspBeeRGBCT',
          'RaspBeeRGBCTGroup'
        ], device.config.class
      ).value()

      hueValueTokens = null
      satValueTokens = null
      device = null

      hueMatcher = (next) =>
        next.match(" hue ")
          .matchNumericExpression( (next, ts) => hueValueTokens = ts )
          .match('%', optional: yes)
      satMatcher = (next) =>
        next.match([" sat ", " saturation "])
          .matchNumericExpression( (next, ts) => satValueTokens = ts )
          .match('%', optional: yes)

      match = M(input, context)
        .match("set color ")
        .matchDevice(RaspBeeDevices, (next, d) =>
          if device? and device.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous.""")
            return
          device = d
        )
        .match(" to")
        .or([
          ( (next) =>
            hueMatcher(next)
              .optional( (next) =>
                satMatcher(next.match(" and", optional: yes))
              )
          ),
          ( (next) =>
            satMatcher(next)
              .optional( (next) =>
                hueMatcher(next.match(" and", optional: yes))
              )
          )
        ])

      transitionMs = null
      match = matchTransitionExpression(match, (m, {time, unit, timeMs}) =>
        transitionMs = timeMs
      )

      if not (match? and (hueValueTokens? or satValueTokens?))
        return null

      if hueValueTokens?.length is 1 and not isNaN(hueValueTokens[0])
        hueExpr = parseFloat(hueValueTokens[0])
        unless hueExpr? and (0.0 <= hueExpr <= 100.0)
          context?.addError("Hue value should be between 0% and 100%")
          return null
      else if hueValueTokens?.length > 0
        hueExpr = hueValueTokens

      if satValueTokens?.length is 1 and not isNaN(satValueTokens[0])
        satExpr = parseFloat(satValueTokens[0])
        unless satExpr? and (0.0 <= satExpr <= 100.0)
          context?.addError("Saturation value should be between 0% and 100%")
          return null
      else if satValueTokens?.length > 0
        satExpr = satValueTokens

      return {
        token: match.getFullMatch()
        nextInput: input.substring(match.getFullMatch().length)
        actionHandler: new RaspBeeHueSatActionHandler(@framework, device, hueExpr, satExpr, transitionMs)
      }

  class RaspbeeDimmerActionProvider extends env.actions.ActionProvider

    constructor: (framework) ->
      super()
      @framework=framework

    parseAction: (input, context) =>
      retVar = null

      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeDimmer',
          'RaspBeeCT',
          'RaspBeeRGB',
          'RaspBeeDimmerGroup',
          'RaspBeeRGBCT',
          'RaspBeeRGBCTGroup',
          'RaspBeeCover'
        ], device.config.class
      ).value()

      if RaspBeeDevices.length is 0 then return

      device = null
      valueTokens = null
      match = M(input, context)
        .match("dim raspbee ")
        .matchDevice(RaspBeeDevices, (next, d) =>
          if device? and device.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous (device).""")
            return
          device = d
        )
        .match(" to ")
        .matchNumericExpression( (next, ts) => valueTokens = ts )
        .match('%', optional: yes)

      transitionMs = null
      match = matchTransitionExpression(match, ( (m, {time, unit, timeMs}) =>
        transitionMs = timeMs/100
      ), yes)

      unless match? and valueTokens? then return null

      if valueTokens.length is 1 and not isNaN(valueTokens[0])
        unless 0.0 <= parseFloat(valueTokens[0]) <= 100.0
          context?.addError("Dimlevel must be between 0% and 100%")
          return null

      return {
        token: match.getFullMatch()
        nextInput: input.substring(match.getFullMatch().length)
        actionHandler: new RaspbeeDimmerActionHandler(@framework, device, valueTokens, transitionMs)
      }

  class RaspbeeDimmerActionHandler extends env.actions.ActionHandler

    constructor: (framework, device, valueTokens, @transitionTime=null) ->
      super()
      @framework=framework
      @device=device
      @valueTokens=valueTokens
      assert @device?
      assert @valueTokens?

    setup: ->
      @dependOnDevice(@device)
      super()

    _doExecuteAction: (simulate, value, transtime) =>
      return (
        if simulate
          __("would dim %s to %s%%", @device.name, value)
        else
          @device.changeDimlevelTo(value, @transitionTime).then( => __("dimmed %s to %s%%", @device.name, value) )
      )

    executeAction: (simulate) =>
      return @framework.variableManager.evaluateNumericExpression(@valueTokens).then( (value) =>
        return @_doExecuteAction(simulate, value )
      )

    hasRestoreAction: -> yes
    executeRestoreAction: (simulate) => Promise.resolve(@_doExecuteAction(simulate, @lastValue))

  class RaspbeeCoverActionProvider extends env.actions.ActionProvider

    constructor: (framework) ->
      super()
      @framework=framework

    parseAction: (input, context) =>
      retVar = null

      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeCover'
        ], device.config.class
      ).value()

      if RaspBeeDevices.length is 0 then return

      device = null
      valueTokens = null
      action = 
        action: "stop"

      match = M(input, context)
        .match("set raspbee ")
        .matchDevice(RaspBeeDevices, (next, d) =>
          if device? and device.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous (device).""")
            return
          device = d
        )
        .or([
          ((m) =>
            m.match(" to ")
              .matchNumericExpression( (next, ts) =>
                valueTokens = ts
              )
              .match('%', optional: yes)          
          ),
          ((m) =>
            m.match(" open", (m)=>
              action.action = "open"
            )
          )
          ((m) =>
            m.match(" close", (m)=>
              action.action = "close"
            )
          )
          ((m) =>
            m.match(" stop", (m)=>
              action.action = "stop"
            )
          )
        ])

      #transitionMs = null
      #match = matchTransitionExpression(match, ( (m, {time, unit, timeMs}) =>
      #  transitionMs = timeMs/100
      #), yes)

      if not match.getFullMatch()? and not valueTokens? and not stop? then return null

      if valueTokens.length is 1 and not isNaN(valueTokens[0])
        unless 0.0 <= parseFloat(valueTokens[0]) <= 100.0
          context?.addError("Set must be between 0% and 100%")
          return null

      return {
        token: match.getFullMatch()
        nextInput: input.substring((match.getFullMatch()).length)
        actionHandler: new RaspbeeCoverActionHandler(@framework, device, action, valueTokens, null) #transitionMs)
      }

  class RaspbeeCoverActionHandler extends env.actions.ActionHandler

    constructor: (framework, device, action, valueTokens, @transitionTime=null) ->
      super()
      @framework=framework
      @device=device
      @stop=stop
      @valueTokens=valueTokens
      assert @device?
      assert @valueTokens? if valueTokens?

    setup: ->
      @dependOnDevice(@device)
      super()

    _doExecuteAction: (simulate, value, transtime) =>
      return (
        if simulate
          __("would set cover %s to %s%%", @device.name, value)
        else
          @device.changeActionTo(action.action).then( => __("set cover %s to %s%%", @device.name, value) )
      )

    executeAction: (simulate) =>
      return @framework.variableManager.evaluateNumericExpression(@valueTokens).then( (value) =>
        return @_doExecuteAction(simulate, value )
      )

    hasRestoreAction: -> yes
    executeRestoreAction: (simulate) => Promise.resolve(@_doExecuteAction(simulate, @lastValue))

  class RaspbeeWarningActionProvider extends env.actions.ActionProvider

    constructor: (framework) ->
      super()
      @framework=framework

    parseAction: (input, context) =>
      retVar = null

      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeWarning'
        ], device.config.class
      ).value()

      if RaspBeeDevices.length is 0 then return

      device = null
      valueTokens = null
      action = 
        action: "off"

      match = M(input, context)
        .match("set raspbee ")
        .matchDevice(RaspBeeDevices, (next, d) =>
          if device? and device.id isnt d.id
            context?.addError(""""#{input.trim()}" is ambiguous (device).""")
            return
          device = d
        )
        .or([
          ((m) =>
            m.match(" off", (m)=>
              action.action = "off"
            )
          )
          ((m) =>
            m.match(" silent", (m)=>
              action.action = "silent"
            )
          )
          ((m) =>
            m.match(" sound", (m)=>
              action.action = "sound"
            )
          )
          ((m) =>
            m.match(" long", (m)=>
              action.action = "long"
            )
          )
        ])

      #transitionMs = null
      #match = matchTransitionExpression(match, ( (m, {time, unit, timeMs}) =>
      #  transitionMs = timeMs/100
      #), yes)

      if not match.getFullMatch()? then return null

      ###
      if valueTokens.length is 1 and not isNaN(valueTokens[0])
        unless 0.0 <= parseFloat(valueTokens[0]) <= 100.0
          context?.addError("Set must be between 0% and 100%")
          return null
      ###

      return {
        token: match.getFullMatch()
        nextInput: input.substring((match.getFullMatch()).length)
        actionHandler: new RaspbeeWarningActionHandler(@framework, device, action, null) #transitionMs)
      }

  class RaspbeeWarningActionHandler extends env.actions.ActionHandler

    constructor: (framework, device, action, @transitionTime=null) ->
      super()
      @framework=framework
      @device=device
      assert @device?
      @valueTokens = null
      @action = action
      #assert @valueTokens? if valueTokens?

    setup: ->
      @dependOnDevice(@device)
      super()

    _doExecuteAction: (simulate, value, transtime) =>
      return (
        if simulate
          __("would set cover %s to %s", @device.name, value)
        else
          @device.changeWarningTo(value).then( => __("set warning %s to %s", @device.name, value) )
      )

    executeAction: (simulate) =>
      #return @framework.variableManager.evaluateNumericExpression(@valueTokens).then( (value) =>
      return @_doExecuteAction(simulate, @action.action )
      #)

    hasRestoreAction: -> yes
    executeRestoreAction: (simulate) => Promise.resolve(@_doExecuteAction(simulate, @lastValue))


  return exports = {
    RaspBeeSceneActionProvider
    RaspBeeRGBActionProvider
    RaspBeeTempActionProvider
    RaspbeeDimmerActionProvider
    RaspBeeHueSatActionProvider
    RaspbeeCoverActionProvider
    RaspbeeWarningActionProvider
  }
