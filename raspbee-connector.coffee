module.exports = (env) ->

  Request = require 'request-promise'
  WebSocket = require 'ws'
  events = require 'events'
  Promise = env.require 'bluebird'
  fs = require('fs')

  class RaspBeeConnection extends events.EventEmitter

    constructor: (host,port,apikey) ->
      super()
      @ws_isalive=false
      @websocketport=null
      @host=host
      @port=port
      @apikey=apikey
      @connect()
      reconnect = setInterval =>
        if not @ws_isalive
          env.logger.error("websocket keep alive error, try to reconnect")
          @emit 'error'
          @connect()
        else if not @ws.readState
          @ws_isalive=false
          @ws.ping()
        else
          env.logger.error("socket not ready")
      ,30000

    connect: () =>
      # Connect to WebSocket
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/config", {timeout: 15000}).then( (res) =>
        rconfig = JSON.parse(res)
        env.logger.info("Connection establised")
        env.logger.info("Name #{rconfig.name}")
        env.logger.info("API #{rconfig.apiversion}")
        env.logger.info("Software Version #{rconfig.swversion}")
        @websocketport=rconfig.websocketport
        if ( @websocketport != undefined )
          env.logger.info("API key valid")
          @ws = new WebSocket('ws://'+@host+':'+@websocketport, {
            perMessageDeflate: false
          })
          @ws.on('open', (data) =>
            env.logger.info("Event receiver connected.")
            @emit 'ready'
            @ws_isalive=true
          )
          @ws.on('message', (data) =>
            jdata = JSON.parse(data)
            env.logger.debug("new message received")
            env.logger.debug(jdata)
            @ws_isalive=true
            eventmessage =
              id : parseInt(jdata.id)
              type: jdata.t
              event: jdata.e
              resource : jdata.r
              state : jdata.state
              config : jdata.config
              uniqueid : jdata.uniqueid
              attr: jdata.attr
            eventmessage.newdev = jdata.sensor if jdata.sensor?
            eventmessage.newdev = jdata.light if jdata.light?
            if jdata.attr?
              @emit 'update', (eventmessage)
            else
              @emit 'event', (eventmessage)
          )
          @ws.on('error', (err) =>
            env.logger.error("websocket error")
            env.logger.error(err.message)
            @ws_isalive=false
            @ws.terminate()
            @emit 'error'
          )
          @ws.on('close', (err) =>
            env.logger.error("websocket closed")
            @ws_isalive=false
            @ws.terminate()
            @emit 'error'
          )
          @ws.on('pong', (pong) =>
            @ws_isalive=true
          )
        else
          env.logger.error("API key not valid")
      ).catch ( (err) =>
        env.logger.error("Connection could not be establised")
        env.logger.error(err.message)
      )

    getConfig: () =>
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/config", {timeout: 15000}).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        return Promise.reject(Error("Bad request"))
      )

    getSensor: (id) =>
      if (id == undefined)
        id = ""
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/sensors/"+id).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Device with ID: "+id+ " not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    getLight: (id) =>
      if (id == undefined)
        id = ""
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/lights/"+id).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Light with ID: "+id+ " not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    getGroup: (id) =>
      if (id == undefined)
        id = ""
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/groups/"+id).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Group with ID: "+id+ " not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    getScenes: (id) =>
      Request("http://"+@host+":"+@port+"/api/"+@apikey+"/groups/"+id+"/scenes").then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Scene with ID: "+id+ " not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    setLightState: (id,param) =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/lights/'+id+'/state',
        method: 'PUT',
        body: JSON.stringify(param)
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Light with ID: "+id+ " not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    setGroupState: (id,param) =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/groups/'+id+'/action',
        method: 'PUT',
        body: JSON.stringify(param)
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Device not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    setSensorConfig: (id,param) =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/sensors/'+id+'/config',
        method: 'PUT',
        body: JSON.stringify(param)
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Device not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    setLightConfig: (id,param) =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/lights/'+id+'/config',
        method: 'PUT',
        body: JSON.stringify(param)
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Device not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    setGroupScene: (id, scene_id) =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/groups/'+id+'/scenes/'+scene_id+'/recall',
        method: 'PUT',
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Device not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    discoverLights: () =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/lights',
        method: 'POST',
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Error"))
        else
          return Promise.reject(Error("Bad request"))
      )

    discoverSensors: () =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/sensors',
        method: 'POST',
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Error"))
        else
          return Promise.reject(Error("Bad request"))
      )

    checkSensors: () =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/sensors/new',
        method: 'GET',
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Error"))
        else
          return Promise.reject(Error("Bad request"))
      )

    checkLights: () =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/lights/new',
        method: 'GET',
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Error"))
        else
          return Promise.reject(Error("Bad request"))
      )

    createBackup: (path) =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/config/export',
        method: 'POST',
      }
      options2 = {
        uri: 'http://'+@host+':'+@port+'/deCONZ.tar.gz',
        method: 'GET',
        encoding: null
      }
      env.logger.debug ("generate backup")
      Request(options).then( (res) =>
        Request(options2).then( (res2) =>
          env.logger.debug ("downloading backup")
          fs.writeFileSync(path+'/deCONZ-backup.tar.gz', res2)
          return Promise.resolve(JSON.parse(res))
        ).catch ( (err) =>
          env.logger.error(err)
        )
      ).catch ( (err) =>
        env.logger.error(err)
        if (err.statusCode is 404)
          return Promise.reject(Error("Error"))
        else
          return Promise.reject(Error("Bad request"))
      )

    setConfig: (param) =>
      options = {
        uri: 'http://'+@host+':'+@port+'/api/'+@apikey+'/config',
        method: 'PUT',
        body: JSON.stringify(param)
      }
      Request(options).then( (res) =>
        return Promise.resolve(JSON.parse(res))
      ).catch ( (err) =>
        if (err.statusCode is 404)
          return Promise.reject(Error("Device not found"))
        else
          return Promise.reject(Error("Bad request"))
      )

    @generateAPIKey: (host,port) ->
      options = {
        uri: 'http://' + host + ':' + port + '/api',
        method: 'POST',
        body: '{"devicetype": "pimatic"}'
      }
      Request(options).then( (res) =>
        response = JSON.parse(res)
        return Promise.resolve(response[0].success.username)
      ).catch ( (err) =>
        env.logger.error("apikey could not be generated")
        if (err.statusCode is 403)
          return Promise.reject(Error("unlock gateway!"))
        else
          return Promise.reject(Error("bad request!"))
      )
