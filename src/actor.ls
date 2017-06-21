require! 'aea': {sleep}
require! './core': {ActorBase}
require! './actor-manager': {ActorManager}
require! 'prelude-ls': {
    split
}

export class Actor extends ActorBase
    (name) ->
        super ...
        @mgr = new ActorManager!

        @actor-name = name
        @log.sections ++= [
            #\subscriptions
        ]

        @log.section \bare, "actor \"#{@name}\" created with id: #{@actor-id}"

        @msg-seq = 0
        @subscriptions = [] # subscribe all topics by default.
        # if you want to unsubscribe from all topics, do teh following:
        # @subscriptions = void

        @kill-handlers = []

        @_state =
            kill:
                started: no
                finished: no

        # registering to ActorManager requires completion of this
        # constructor, so manually switch the context
        <~ sleep 1ms
        @mgr.register this
        <~ sleep 0 # context-switch
        @action! if typeof! @action is \Function

    subscribe: (topic) ->
        # log section prefix: s1
        topics = [topic] if typeof! topic is \String
        for topic in topics when topic not in @subscriptions
            @subscriptions.push topic
        @log.section \subscriptions, "subscribing to ", topic, "subscriptions: ", @subscriptions
        @mgr.subscribe-actor this

    list-handle-funcs: ->
        methods = [key for key of Object.getPrototypeOf this when typeof! this[key] is \Function ]
        subj = [s.split \handle_ .1 for s in methods when s.match /^handle_.+/]
        @log.log "this actor has the following subjects: ", subj, name

    send: (msg-payload, topic='') ~>
        try
            msg-env = @get-msg-template!
            msg-env.payload = msg-payload
            msg-env.topic = topic
            @send-enveloped msg-env
        catch
            @log.err "sending message failed. msg: ", msg-payload, "enveloped: ", msg-env, e

    send_raw: (msg_raw) ->
        @log.warn "deprecated: use send-envelope function instead."
        msg_raw.sender = @actor-id
        @mgr.inbox-put msg_raw

    send-enveloped: (msg) ->
        @log.warn "FIXME: msg.sender should not be required to set here!"
        msg.sender = @actor-id
        @mgr.inbox-put msg

    on-kill: (handler) ->
        @log.section \debug1, "adding handler to run on-kill..."
        if typeof! handler isnt \Function
            @log.err "parameter passed to 'on-kill' should be a function."
            return
        @kill-handlers.push handler

    kill: (...reason) ->
        unless @_state.kill.started
            @_state.kill.started = yes
            @log.section \debug-kill, "deregistering from manager"
            @mgr.deregister this
            @log.section \debug-kill, "deregistered from manager"
            try
                for handler in @kill-handlers
                    handler.apply this, reason
            catch
                @log.err "problem in kill handler: ", e

            @_state.kill.finished = yes
