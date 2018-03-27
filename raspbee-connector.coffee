module.exports = (env) ->

  Request = require 'request-promise'
  WebSocket = require 'ws'
  events = require 'events'
  Promise = env.require 'bluebird'

  class RaspBeeConnection extends events.EventEmitter

    constructor: (@host,@port,@apikey) ->
      super()

      # Connect to WebSocket
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/config").then( (res) =>
        rconfig = JSON.parse(res)
        env.logger.info("Connection establised")
        env.logger.info("Name #{rconfig.name}")
        env.logger.info("API #{rconfig.apiversion}")
        @websocketport=rconfig.websocketport
        if ( @websocketport != undefined )
          env.logger.debug("API key valid")
          @ws = new WebSocket('ws://'+@host+':'+@websocketport, {
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
            env.logger.error("websocket error")
            env.logger.debug(err)
            @emit 'error'
          )
        else
          env.logger.error("API key not valid")
      ).catch ( (err) =>
        env.logger.error("Connection could not be establised")
        env.logger.debug(err)
        @emit 'error'
      )

    getSensor: (id) =>
      if (id == undefined)
        id = ""
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/sensors/"+id).then( (res) =>
        return JSON.parse(res)
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject("Device not found")
        else
          return Promise.reject("Bad request")
      )

    getLight: (id) =>
      if (id == undefined)
        id = ""
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/lights/"+id).then( (res) =>
        return JSON.parse(res)
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject("Device not found")
        else
          return Promise.reject("Bad request")
      )

    getGroup: (id) =>
      if (id == undefined)
        id = ""
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/groups/"+id).then( (res) =>
        return JSON.parse(res)
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject("Device not found")
        else
          return Promise.reject("Bad request")
      )

    setLightState: (id,param) =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/lights/'+id+'/state',
        method: 'PUT',
        body: JSON.stringify(param)
      }
      Request(options).then( (res) =>
        return JSON.parse(res)
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject("Device not found")
        else
          return Promise.reject("Bad request")
      )

    setGroupState: (id,param) =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/groups/'+id+'/action',
        method: 'PUT',
        body: JSON.stringify(param)
      }
      Request(options).then( (res) =>
        return JSON.parse(res)
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject("Device not found")
        else
          return Promise.reject("Bad request")
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
        env.logger.error("apikey could not be generated")
        if (err.statusCode is 403)
          return Promise.reject("unlock gateway!")
        else
          return Promise.reject("Bad request!")
      )
