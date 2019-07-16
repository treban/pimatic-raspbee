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
      # The result the function will return:
      matchCount = 0
      matchingScene = null
      scenes = []
      @deviceScenes = {}
      end = () => matchCount++
      onSceneMatch = (m, {scene}) =>
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
          @deviceScenes[s.name] = d

      m = M(input, context)
        .match('activate group scene ')
        .match(
          scenes,
          onSceneMatch
        )

      match = m.getFullMatch()
      if match?
        assert matchingScene?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new SceneActionHandler(@deviceScenes[matchingScene], matchingScene)
        }
      else
        return null

  class SceneActionHandler extends env.actions.ActionHandler

    constructor: (device, scene) ->
      super()
      @device=devices
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

################################################################################
## Color RGB ACTIONS
################################################################################
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
          'RaspBeeRGBCTGroup'
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

  return exports = {
    RaspBeeSceneActionProvider
    RaspBeeRGBActionProvider
    RaspBeeTempActionProvider
    RaspbeeDimmerActionProvider
  }
