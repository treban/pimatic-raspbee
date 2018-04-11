module.exports = (env) ->

  _ = env.require 'lodash'
  M = env.matcher
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  t = env.require('decl-api').types

  class RaspBeeSceneActionProvider extends env.actions.ActionProvider

    constructor: (@framework) ->

      # ### parseAction()
      ###
      Parses the above actions.
      ###
    parseAction: (input, context) =>
      # The result the function will return:
      matchCount = 0
      matchingScene = null
      scenes = []
      @deviceScenes = {}
      end = () => matchCount++
      onSceneMatch = (m, {scene}) =>
        matchingScene = scene

      TradfriDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeGroupScenes',
        ], device.config.class
      ).value()

      if TradfriDevices.length is 0 then return

      for id, d of TradfriDevices
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

    constructor: (@device, @scene) ->
      assert @device?
      assert @scene? and typeof @scene is "string"

    setup: ->
      @dependOnDevice(@device)
      super()

    ###
    Handles the above actions.
    ###
    _doExecuteAction: (simulate) =>
      return (
        if simulate
          Promise.resolve __("would activate scene %s of device %s", @scene, @device.id)
        else
          @device.buttonPressed(@scene)
            .then( =>__("activate scene %s of device %s", @scene, @device.id) )
      )

# ### executeAction()
    executeAction: (simulate) => @_doExecuteAction(simulate)
# ### hasRestoreAction()
    hasRestoreAction: -> no

  class RaspBeeTempActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @device, @valueTokens) ->
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

    ###
    Handles the above actions.
    ###
    _doExecuteAction: (simulate, value) =>
      return (
        if simulate
          __("would change %s to %s%%", @device.name, value)
        else
          @device.setCT(value).then( => __("change color temp from %s to %s%%", @device.name, value) )
      )

    # ### executeAction()
    executeAction: (simulate) =>
      @device.getCt().then( (lastValue) =>
        @lastValue = lastValue or 0
        return @framework.variableManager.evaluateNumericExpression(@valueTokens).then( (value) =>
          value = @_clampVal value
          return @_doExecuteAction(simulate, value)
        )
      )

    # ### hasRestoreAction()
    hasRestoreAction: -> yes
    # ### executeRestoreAction()
    executeRestoreAction: (simulate) => Promise.resolve(@_doExecuteAction(simulate, @lastValue))


  class RaspBeeTempActionProvider extends env.actions.ActionProvider
    constructor: (@framework) ->
      super()

    parseAction: (input, context) =>
      # The result the function will return:
      retVar = null
      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeCT',
        ], device.config.class
      ).value()

      device = null
      valueTokens = null
      match = null

      if RaspBeeDevices.length is 0 then return

      # Try to match the input string with:
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
          actionHandler: new RaspBeeTempActionHandler(@framework, device, valueTokens)
        }
      else
        return null


  class RaspBeeRGBActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @device, @hex) ->
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
          @device.setRGB(@r,@g,@b).then( => __("set color %s to %s", @device.name, @hex) )
      )

    executeAction: (simulate) =>
      return @_doExecuteAction(simulate)

    hasRestoreAction: -> no


  class RaspBeeRGBActionProvider extends env.actions.ActionProvider
    constructor: (@framework) ->
      super()

    parseAction: (input, context) =>
      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => _.includes [
          'RaspBeeRGB'
        ], device.config.class
      ).value()

      m = M(input, context).match(['set color rgb '])

      device = null
      hex = null
      match = null
      r = null
      g = null
      b = null

      m.matchDevice RaspBeeDevices, (m, d) ->
        if device? and device.id isnt d.id
          context?.addError(""""#{input.trim()}" is ambiguous.""")
          return
        device = d
        m.match [' to '], (m) ->
          m.or [
            (m) -> m.match [/(#[a-fA-F\d]{6})(.*)/], (m, s) ->
              hex = s.trim()
              match = m.getFullMatch()
          ]
      if match?
        assert hex?
        return {
          token : match
          nextInput: input.substring(match.length)
          actionHandler: new RaspBeeRGBActionHandler(@framework, device, hex)
        }
      else
        return null

  return exports = {
    RaspBeeSceneActionProvider
    RaspBeeRGBActionProvider
    RaspBeeTempActionProvider
  }
