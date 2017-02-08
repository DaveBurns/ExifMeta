--[[
        Sidekick.lua
        
        Sidekick task - designed to be extended.
        
        Instructions:
        
            - Extend this background class to do something useful.
              - Override init method to do special initialization, if desired.
              - Override process method to do special processing.
            - Create (extended) background object and start background task in init.lua, perhaps conditioned by pref.
            
        Notes: This is intended to be used as interface to sidekick app.
        It is intended to support single or multiple sidekick app instances (multiples would require unique http-comm-port).
--]]

local Sidekick, dbg = Background:newClass{ className = 'Sidekick' }



--- Constructor for extending class.
--
function Sidekick:newClass( t )
    return Background.newClass( self, t )
end



--- Constructor for new instance.
--
--  @param      t       initialization table, including:
--                      <br>interval (number, default: 1 second) process frequency base-rate. Recommend .2 as normal minimum, .1 if process is quick and fast response is necessary.
--                      <br>minInitTime (number, default: 10 seconds), but recommend setting to 15 or 20 - so user has time to inspect startups in progress corner, or set to zero to suppress init progress indicator altogether.
--
function Sidekick:new( t )
    local o = Background.new( self, t )
    if t and t.delegate then
        -- good
    else
        error( "Sidekick requires delegate for command processing." )
    end
    if t.url then
        o.rpc = XmlRpc:new{ url = t.url } -- note: self is class-var, not instance var.
    else
        error( "Sidekick requires url" )
    end
    if t.appPath then -- sub-path
        o.appPath = t.appPath -- name - path is relative to plugin parent.
    else
        error( "Sidekick requires app-path" )
    end
    if t.appName then -- app-name
        o.appName = t.appName
    else
        error( "Sidekick requires app-name" )
    end
    o.seqNum = 1
    o.sending = false
    return o
end



--- Sidekick init function.
--
--  @param      call object - usually not needed, but its got the name, and context... just in case.
--
--  @usage      override to do special initialization, if desired.
--              <br>Try not to throw errors in init, but instead set initStatus to true or false depending on whether successful or not.
--              <br>no need to call this method from extended class, yet.
--
--  @usage      if init is lengthy, check for shutdown sometimes and abort(return) if set - initStatus a dont care in that case.
--
function Sidekick:init( call )
    repeat
        repeat
            if not app:isPluginEnabled() then
                app:sleepUnlessShutdown( 1 )
                if call.scope:isCanceled() then
                    call:abort( "Canceled" )
                    return
                elseif shutdown then
                    return
                end
                break
            end            
            local sts
            local msgOrValues
            sts, msgOrValues = self.rpc:sendAndReceive( 'areYouThere' ) -- this is the standard check for existence of plugin's other half.
            if sts then
                local values = msgOrValues[1] -- tuple: app-name, version, restart-flag
                if #values > 0 and type( values[1] ) == 'string' and values[1] == self.appName then
                    self.delegate:init( values ) -- delegate can deal with version number and restart-flag as desired, and set init-status of bg.
                    if self.initStatus then
                        app:logInfo( str:fmt( "^1 init OK", self.appName ) )
                        return -- delegate must pause / continue if desired.
                    else
                        app:logInfo( str:fmt( "^1 cant init", self.appName ) )
                        if call.scope:isCanceled() then
                            call:abort( "Canceled" )
                            return
                        elseif shutdown then
                            return
                        end
                    end
                else
                    error( "Not sure who's there." )                
                end
            else

                -- if app needs lrcat access, it has to start Lightroom, not the other way around - just wait for it...                
                app:sleepUnlessShutdown( 1 )
                if call.scope:isCanceled() then
                    call:abort( "Canceled" )
                    return
                elseif shutdown then
                    return
                end
                
            end
        until true
    until false
end



--- Sidekick process function.
--
--  @param      call object - usually not needed, but its got the name, and context... just in case.
--
--  @usage      Extending class should call this method, if not every time, every other time...
--  @usage      Sends command to solicit app. if app returns command its processed and the response transmitted.
--              <br>App must distinguish messages that warrant a response and those that are replies, the app response to a reply should always simply be 'true'.
--
function Sidekick:process( call )
    local sts, msgOrValues = self.rpc:sendAndReceive( "solicitCommand", self.seqNum )
    if sts then
        local values = msgOrValues[1] -- solicited command values are always in a tuple.
        if #values then
            -- dbg( "first: " .. str:to( values[1] ) )
            local seqNum = tonumber( values[#values] )
            if seqNum == self.seqNum then -- last value is always seq-num.
                dbg( "Seq num match: " .. str:to( seqNum ) )
                self.seqNum = self.seqNum + 1
            else
                app:logError( str:fmt( "Solicited command seq-num mismatch, expected: ^1, received: ^2, ^3", self.seqNum, str:to( values[#values] ), type( values[#values] ) ) )
                self.seqNum = self.seqNum + 1
                return
            end
        else
            app:logError( str:fmt( "Solicited command must always return at least one value." ) )
            return
        end
        -- fall-through => seq-num match.
        local command = nil
        if type( values[1] ) == 'boolean' then
            if values[1] then
                -- fall-through
                dbg( "Why true?" )
                return
            else
                dbg( "No command" )
                -- return
            end
        elseif type( values[1] ) == 'string' then -- assume method name.
            command = values[1]
        else
            app:logError( "first solicit-command reply param from app should be boolean or string" )
            return
        end
        if command then
            dbg( "Processing command:", command )
            -- fall-through => command.
            local name, params = self.delegate:processCommand( values ) -- command processor can ignore last value (seq-num).
            if name then
                local sts, msgOrValues = self.rpc:sendAndReceive( 'reply', name, params )
                if sts then
                    local values = msgOrValues -- should always just be 'True'.
                    if type( values[1] ) == 'boolean' then
                        if values[1] then
                            app:logVerbose( "Solicited command reply acked affirmatively" )
                        else
                            local sn = values[2]
                            app:logWarning( "Solicited command reply nak'd, sn: " .. str:to( sn ) )
                        end
                    else
                        app:logError( str:fmt( "Solicited command reply ack status not boolean - type: ^1, value: ^2", str:to( type ), str:to( values[1] ) ) )
                    end
                else
                    app:logError( "Bad response from app when sending solicited command response - hmmm..." )
                end
            else
                dbg( "No reply to send." )
                app:logInfo( "No reply to send." )
            end
        else
            dbg( "Soliciting self for command to send." )
            app:logInfo( "Soliciting self for command to send." )
            self.delegate:sendCommand( self.rpc ) -- or not.
        end
    else
        app:logError( "No response from app when sending solicited command request - hmmm..." )
    end
end



--- Send command & receive response.
--
--  @usage Use this instead of xml-rpc methods, since this coordinates with initialization and other tasks trying to do same...
--
function Sidekick:sendAndReceive( command, ... )
    local sts, msgOrVals
    app:call( Call:new{ name="sendAndReceive", async=false, main=function( context, command, ... )
    
        --app:logInfo( "sending-and-receiving..." )
    
        local time = LrDate.currentTime()
        while not self.initStatus or self.sending and not shutdown do
            LrTasks.sleep( .1 )
            if ( LrDate.currentTime() - time ) > 30 then
                if self.initStatus then
                    error( "app no longer responding" )
                    --###2self.initStatus = 
                else
                    --self.initStatus
                    error( "app won't init" )
                end
            end
        end
        if shutdown then
            sts = false
            msgOrVals = "shutdown"
            return
        end
        self.sending = true

        sts, msgOrVals = self.rpc:sendAndReceive( command, unpack{ ... } )
        --app:logInfo( "Command: " .. str:to( command ) )
        --for i,v in ipairs{ ... } do
        --    app:logInfo( str:fmt( "Paramater ^1: ^2", i, str:to( v ) )  )
        --end
        
    end, finale=function( call, status, message )
        self.sending = false
        if status then -- worked: sts, msg-or-vals as set by call to xml-rpc-send-and-receive.
            app:logVerbose( "sent-and-received" )
        else
            app:logWarning( "send-rcv failed" )
            sts = false -- reverse polarity
            msgOrVals = message
            
        end
    end }, command, unpack{ ... } )
    return sts, msgOrVals
end



return Sidekick