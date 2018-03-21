require! './helpers': {MessageBinder}
require! '../src/auth-request': {AuthRequest}
require! 'colors': {bg-red, red, bg-yellow, green, bg-blue}
require! '../lib': {sleep, pack, unpack}
require! 'prelude-ls': {split, flatten, split-at, empty}
require! '../src/signal':{Signal}
require! '../src/actor': {Actor}
require! '../src/topic-match': {topic-match}


export class ProxyClient extends Actor
    (@socket, @opts) ->
        super \ProxyClient

    action: ->
        # actor behaviours
        @role = \client
        @connected = no
        @data-binder = new MessageBinder!
        @proxy = yes
        @permissions-rw = []

        @auth = new AuthRequest!
            ..on \to-server, (msg) ~>
                @socket.write pack msg

            ..on \login, (permissions) ~>
                @permissions-rw = flatten [permissions.rw]
                unless empty @permissions-rw
                    @log.log "logged in succesfully. subscribing to: ", @permissions-rw
                    @subscribe @permissions-rw
                    @log.log "requesting update messages for subscribed topics"
                    for topic in @permissions-rw
                        {topic, +update}
                        |> @msg-template
                        |> @auth.add-token
                        |> pack
                        |> @socket.write
                else
                    @log.warn "logged in, but there is no rw permissions found."

        @on do
            receive: (msg) ~>
                #@log.log "forwarding received DCS message #{msg.topic} to TCP socket"
                unless msg.topic `topic-match` @permissions-rw
                    @send-response msg, {err: "
                        How come the ProxyClient is subscribed a topic
                        that it has no rights to send? This is a DCS malfunction.
                        "}
                    return

                if @socket-ready
                    msg
                    |> @auth.add-token
                    |> pack
                    |> @socket.write
                else
                    @log.log bg-yellow "Socket not ready, not sending message: "
                    console.log "msg is: ", msg

            kill: (reason, e) ~>
                @log.log "Killing actor. Reason: #{reason}"
                @socket
                    ..end!
                    ..destroy 'KILLED'

            needReconnect: ~>
                @socket-ready = no

            connected: ~>
                @log.log "<<=== New proxy connection to the server is established. name: #{@name}"
                @socket-ready = yes
                @trigger \relogin, {forget-password: @opts.forget-password}  # triggering procedures on (re)login
                @subscribe "public.**"


        # ----------------------------------------------
        #            network interface events
        # ----------------------------------------------
        @socket
            ..on \connect, ~>
                @trigger \connected
                @connected = yes

            ..on \disconnect, ~>
                @log.log "Client disconnected."
                @connected = no

            ..on "data", (data) ~>
                # in "client mode", authorization checks are disabled
                # message is only forwarded to manager
                for msg in @data-binder.get-messages data
                    if \auth of msg
                        #@log.log "received auth message, forwarding to AuthRequest."
                        @auth.trigger \from-server, msg
                    else
                        #@log.log "received data: ", pack msg
                        @send-enveloped msg

            ..on \error, (e) ~>
                if e.code in <[ EPIPE ECONNREFUSED ECONNRESET ETIMEDOUT ]>
                    @log.err red "Socket Error: ", e.code
                else
                    @log.err bg-red "Other Socket Error: ", e

                @trigger \needReconnect, e.code

            ..on \end, ~>
                @log.log "socket end!"
                @trigger \needReconnect

    login: (credentials, callback) ->
        # normalize parameters
        if typeof! credentials is \Function
            callback = credentials
            credentials = null

        @off \relogin
        @on \relogin, (opts) ~>
            @log.log "sending credentials..."
            err, res <~ @auth.login credentials
            if opts?.forget-password
                #@log.warn "forgetting password"
                credentials := token: try
                    res.auth.session.token
                catch
                    null
            unless err
                @trigger \logged-in

            callback err, res

        if @connected
            @trigger \relogin, {forget-password: @opts.forget-password}

    logout: (callback) ->
        @auth.logout callback
