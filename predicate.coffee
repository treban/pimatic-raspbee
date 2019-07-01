module.exports = (env) ->

  _ = env.require 'lodash'
  M = env.matcher
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'

  class RaspBeePredicateProvider extends env.predicates.PredicateProvider

    constructor: (@framework, @config) ->
      super()

    parsePredicate: (input, context) ->
      fullMatch = null
      nextInput = null
      recCommand = null
      device = null

      setCommand = (m, tokens) => recCommand = tokens

      RaspBeeDevices = _(@framework.deviceManager.devices).values().filter(
        (device) => device.hasAttribute('switch')
      ).value()

      m = M(input, context)
        .match('received from ')
        .matchDevice(RaspBeeDevices, (next, d) =>
          next.match(' event ')
            .matchString( (next, val) =>
              recCommand = val
              if device? and device.id isnt d.id
                context?.addError(""""#{input.trim()}" is ambiguous.""")
                return
              device = d
              fullMatch = next.getFullMatch()
            )
        )

      if fullMatch?
        assert typeof recCommand is "string"
        return {
          token: fullMatch
          nextInput: input.substring(fullMatch.length)
          predicateHandler: new RaspBeePredicateHandler(@framework, device, recCommand)
        }
      return null

  class RaspBeePredicateHandler extends env.predicates.PredicateHandler
    constructor: (framework, @device, @command) ->
      @device.registerPredicate this
      super()

    setup: ->
      super()

    getValue: -> Promise.resolve false
    getType: -> 'event'
    getCommand: -> "#{@command}"

    destroy: ->
      @device.deregisterPredicate this
      super()

  return exports = {
    RaspBeePredicateProvider
  }
