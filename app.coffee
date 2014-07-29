fs = require 'fs'
_ = require 'underscore'
async = require 'async'
colors = require 'colors'

decorators = require 'decorators2'
decorate = decorators.decorate
helpers = require 'helpers'

http = require 'http'
express = require 'express'
ejs = require 'ejs'
ejslocals = require 'ejs-locals'

settings =
    httpport: 3000
    cookiesecret: 'no secret'
    cookiedomain: 'test.com'
    viewsFolder: __dirname + '/views'
    staticFolder: __dirname + '/static'

settings = _.extend settings, require('./settings').settings

env = { settings: settings }

# --------------------------------

initLogger = (env,callback) ->    
    env.log = (text,data,taglist...) ->
        tags = {}
        _.map taglist, (tag) -> tags[tag] = true
        if tags.error then text = text.red
        if tags.error and _.keys(data).length then json = " " + JSON.stringify(tags.error) else json = ""
        console.log String(new Date()).yellow + " " + _.keys(tags).join(', ').green + " " + text + json

    env.logres = (name, callback) ->
        (err,data) -> 
            if (err)
                env.log name + ': ' + err, {error: err}, 'init', 'fail'
            else
                env.log name + "...", {}, 'init', 'ok'
            callback(err,data)
        
    env.log('logger initialized', {}, 'init','info')
    callback()


initExpress = (callback) ->
    env.app = app = express()

    app.configure ->
        app.engine 'ejs', ejslocals
        app.set 'view engine', 'ejs'
        app.set 'views', settings.viewsFolder

        app.use express.static(settings.staticFolder, { maxAge: 18000 })
        app.use express.cookieParser()
        app.use express.bodyParser()

        app.use express.favicon( settings.staticFolder + "/favicon.ico")
        app.use express.logger('dev')
    
        #app.use express.session(
        #    secret: env.settings.cookiesecret,
        #    key: 'test',
        #    store: env.sessionstore = new connectmongodb( db: env.db )
        #    cookie: {
        #        domain: settings.cookiedomain,0
        #        httpOnly: false,
        #        maxAge: 60000 * 60 * 24 * 3
        #    })

        app.use app.router

        app.use (err, req, res, next) ->
            console.log err.stack
            env.log 'web request error', { stack: err.stack }, 'error', 'http'
            res.end 'error'

        env.server = http.createServer env.app
        env.server.listen settings.httpport
        env.log 'http server listening', {}, 'info', 'init', 'http'

        callback undefined, true


initRoutes = (callback) ->
    env.app.get '/', (req,res) ->
        res.render 'index', { }
    callback()


initSocketIo = (callback) ->
    io = require('socket.io')(env.server)

    io.on 'connection', (socket) ->
        console.log "user connected"
        socket.on 'msg', (msg) ->
            console.log "got message",msg
        socket.on 'disconnect', ->
            console.log "user disconnected"
    callback()



makeLogDecorator = (name) -> 
    (f,args) ->
        callback = args.shift()
        f (err,data) ->
            if not err
                env.log(name + ' ready', {}, 'info', 'init', 'done', name)
            else
                env.log(name + ' failed!', {}, 'info', 'init', 'error', name)
            callback(err,data)

wraplog = (name,f) -> decorators.decorate makeLogDecorator(name), f

init = (callback) ->
    async.auto
        logger: (callback) -> initLogger(env,callback)
        express: [ 'logger', wraplog('express',initExpress) ]
        routes: [ 'express', 'socketio', wraplog('routes',initRoutes) ]
        socketio: [ 'express', wraplog('socketio',initSocketIo) ]
        callback


init (err,data) ->
    if not err
        env.log 'system initialized',{}, 'info','init','done'
    else
        env.log 'system init failed',{}, 'info','init','error'
