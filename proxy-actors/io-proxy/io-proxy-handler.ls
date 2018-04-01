/*-------------------------------------

# IoProxyHandler
----------------

## Events:

    read handle, respond(err, value)

    write handle, value, respond(err)

handle Object:

    address: Original address representation
    type: bool, int, ...

## Request Message Format

    ..write:
        payload: {val: newValue}

    ..read:
        payload: null

## Response Message Format:

    ..read
        err: error if there are any
        res:
            curr: current value
            prev: previous value

    ..write (see read response)

## Example: (see PhysicalTargetSimulator)

*/

require! 'dcs': {EventEmitter, Actor}
require! './errors': {CodingError}

export class IoProxyHandler extends Actor
    (topic, protocol) ->
        topic or throw new CodingError "A topic MUST be provided to IoProxyHandler."
        super topic

        if protocol?
            # assign handlers internally
            @on \read, (handle, respond) ~>
                #console.log "requested read!"
                err, value <~ protocol.read handle.address, handle.amount
                #console.log "responding read value: ", err, value
                respond err, value

            @on \write, (handle, value, respond) ~>
                #console.log "requested write for #{handle.address}, value: ", value
                err <~ protocol.write handle.address, value
                #console.log "write error status: ", err
                respond err

        @subscribe "#{@name}.**"
        @subscribe "app.logged-in"

        handle = {
            address: @name
        }

        prev = null
        curr = null
        RESPONSE_FORMAT = (err, curr) ->
            {err, res: {curr, prev}}

        broadcast-value = (err, value) ~>
            @send "#{@name}.read", RESPONSE_FORMAT(err, value)
            if not err and value isnt prev
                @log.log "Store previous value (from #{prev} to #{curr})"
                prev := curr
                curr := value

        response-value = (msg) ~>
            (err, value) ~>
                @send-response msg, RESPONSE_FORMAT(err, value)
                if not err and value isnt prev
                    @log.log "Store previous value (from #{prev} to #{curr})"
                    prev := curr
                    curr := value

        @on-topic "#{@name}.read", (msg) ~>
            # send response directly to requester
            @log.todo "triggering response 'read'."
            @trigger \read, handle, response-value(msg)

        @on-topic "#{@name}.write", (msg) ~>
            @log.warn "triggering 'write'."
            new-value = msg.payload.val
            @trigger \write, handle, new-value, (err) ~>
                if err
                    # write failed, send response directly to the requester
                    @send-response msg, {err: err}
                else
                    # write succeeded, broadcast the value
                    broadcast-value err=null, new-value

        @on-topic "#{@name}.update", (msg) ~>
            # send response directly to requester
            @log.warn "triggering 'read' because update requested."
            @trigger \read, handle, response-value(msg)

        @on-topic "app.logged-in", (msg) ~>
            # broadcast the status
            @log.warn "triggering broadcast 'read' because we are logged in."
            @trigger \read, handle, broadcast-value

        # broadcast update on "power up"
        @log.warn "triggering broadcast 'read' because we are initialized now."
        @trigger \read, handle, broadcast-value
