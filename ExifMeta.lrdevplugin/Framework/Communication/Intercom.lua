--[[
        Intercom.lua
        
        For inter-plugin and/or plugin-app communication (disk/file-based implementation).
        
        Test Examples:

        Example A, Plugin #1
            local peer = _PLUGIN.id .. "2"
        
            local listenObject = { callback = function( msg )
                dbg( msg )
                if msg.content == 'hello' then
                    -- process hello
                elseif msg.content == 'goodbye' then
                    -- process goodbye
                else
                end
                local method = 2
                local reply
                if method == 1 then
                    reply = msg
                    reply.comment = "this is a reply"
                    dbg( "Base reply reusing command", reply )
                else
                    reply = intercom:createReply( msg )
                    dbg( "Base reply using fresh creation", reply )
                end
                reply.content = msg.content .. " - right back at ya."
                intercom:sendReply( reply )
            end }
        
            local froms = {}
            froms[peer] = true
            intercom:listen( listenObject.callback, listenObject, froms )
        
            local msg = { name="hello", content="world", comment="testing send/receive..." }
            local reply, errm = intercom:sendAndReceive( msg, peer, 5 )
            dbg( reply, errm )    
            Debug.showLogFile()

        Example A, Plugin #2
            local peer = _PLUGIN.id:sub( 1, -2 )
            
            local listenObject = { callback = function( msg )
                dbg( msg )
                if msg.name == 'hello' then
                    -- process hello
                elseif msg.name == 'goodbye' then
                    -- process goodbye
                else
                end
                local method = 2
                local reply
                if method == 1 then
                    reply = msg
                    reply.comment = "this is a reply"
                    dbg( "Base reply reusing command", reply )
                else
                    reply = intercom:createReply( msg )
                    dbg( "Base reply using fresh creation", reply )
                end
                reply.name = msg.name .. " - ack"
                reply.content = msg.content .. " - right back at ya."
                intercom:sendReply( reply, msg.from ) -- to address is optional.
            end }
        
            local froms = {}
            froms[peer] = true
            intercom:listen( listenObject.callback, listenObject, froms )
        
            local msg = { name="hello", content="world", comment="testing send/receive..." }
            local reply, errm = intercom:sendAndReceive( msg, peer, 5 )
            dbg( reply, errm )    
            Debug.showLogFile()

        
        Example B, Plugin #1
            intercom:broadcast( { content="hello" }, 30 )
            intercom:broadcast( { content="goodbye" }, 30 )
            for i = 1, 5 do
                intercom:broadcast( { content=str:fmt( "bleep ^1", i ) }, 30 - (i * 2) )
                app:sleepUnlessShutdown( 5 )
                if shutdown then return end
            end
        
        Example B, Plugin #2
            local cbObj = Object:new{ className="callbackObject2" } -- create callback object and give it a class-name for to-string purposes.
            function cbObj:callback( msg )
                dbg( msg )
                if msg.content == 'hello' then
                    -- process hello
                    app:log( "Hello" )
                elseif msg.content == 'goodbye' then
                    app:log( "goodbye" )
                else
                    app:logVerbose( "Dont understand: ^1", str:to( msg.content ) )
                end
            end
            intercom:listenForBroadcast( cbObj.callback, cbObj, {
                [_PLUGIN.id:sub( 1, -2 )] = true,
            }, 1 ) -- Note: polling interval for broadcast must be shorter than 1/2 the time before msg deleted by sender to be sure it's seen.
            app:sleepUnlessShutdown( 15 )
            intercom:stopBroadcastListening( cbObj )
--]]


local Intercom, dbg, dbgf = Object:newClass{ className="Intercom", register=true }



--[=[

Anatomy of a message filename:
------------------------------
from-plugin-id timestamp seq-no.txt

from-plugin-id must not have spaces, nor timestamp, nor seq-no (space is delimiter)

Example:

com.robcole.lightroom.MyPlugin 2001-01-07_23-12-34 00001.txt

Note: Incoming directory is for unsolicited "command" messages, which may or may not warrant a response.
("from" address matches filename).
Responses comes to reply directory.

Note: reply filenames are the exact same as original message, but address in filename is
"to" address, not "from" address.


Message structure notes:
------------------------

Note: sender and receivers must agree on message content, these are assigned internally,
some based on send function parameters supplied in calling context, but still...

- version:      (number) may come in handy if message format changes, so old plugin can still talk to new plugin.
(- comment:      (string) just for debugging - comments may help to elaborate message intent in debug log file. Supported internally, but assigned externally)
- to:           (string) to address (plugin id) - not really essential for routing, since inbox defines who its to, again for debugging it is useful.
- from:         (string) from address (plugin id) - ditto: for debugging it is useful...
- filename:     (string) name of file from which this message came. Reminder: message files are deleted immediately after reading, so this may help debugging.


Additional notes:
-----------------

Basic intercom implements conduit, but no message processing (no function code "names" are defined by this module).
That part is up to context.

PS - There is an implementation of this in java which allows external apps to talk to plugins (and vice versa), but source code is not released - if you want a copy, ask..

--]=]




--- Constructor for extending class.
--
function Intercom:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @param t (table) initial object members, all optional, including:
--      <br>    dir (string, default=catalog dir) path to root of messaging dirs.
--      <br>    pollingInterval (number, default=.1) seconds between polling for incoming messages and/or replies.
--      <br>                   - faster means more responsive but more disk wear. Default is .1 second - seems a nice balanced value.
--      <br>                   - you can go down to .01 second (windows base clock frequency), for ultra-fast messaging,
--      <br>                   - or up to a half second if speed is not a concern, to save disk wear.
--      <br>    broadcastLifetime (number, default=10) seconds for broadcast messages to last before they're assumed to have been heard, and are cleaned up.
--      <br>    addlNames (array of strings, default={}) names of additional plugin entities to be communicating via the intercom, e.g. "Background" (corresponding from-address {pluginId}.Background).
--
function Intercom:new( t )
    
    local o = Object.new( self, t )
    o.pollingInterval = o.pollingInterval or .1 -- better not be negative. not sure what happens if zero.
    if o.simpleXml then
        app:assert( gbl:getValue( 'simpleXml' ), "initialize simple-xml global" )
    end
    o.dir = o.dir or cat:getCatDir() -- root dir
    o.mainDir = LrPathUtils.child( o.dir, "ElareMessages" )
    o.inDir = LrPathUtils.child( o.mainDir, "Incoming" )
    o.toMeDir = LrPathUtils.child( o.inDir, _PLUGIN.id )
    o:_initDir( o.toMeDir ) -- cleanup only expired messages to me.
    local dir = LrPathUtils.child( o.mainDir, "Replies" )
    o.replyDir = LrPathUtils.child( dir, _PLUGIN.id )
    o:_initDir( o.replyDir )
    if tab:isArray( o.addlNames ) then
        for i, name in ipairs( o.addlNames ) do
            o:_initDir( o.replyDir.."."..name ) -- e.g. Replies/{pluginId}.Background - added to support ftp-agg.
            o:_initDir( o.toMeDir.."."..name ) -- e.g. Incoming/{pluginId}.Background - added to support dir-chg.
        end
    end
    o.bcastDir = LrPathUtils.child( o.mainDir, "Broadcast" )
    o:_initDir( o.bcastDir ) -- Note: unlike reglar, its the sender that defines plugin subfolder in bcast dir, not the receiver.
    o.seqNum = 0
    if o.pollingInterval > 3 then -- this used to be .5, but up'd to 3 to honor more leisurely "networking". Beware that timeouts must be set accordingly..
        app:callingError( "3 second max polling interval" )
    end
    o.broadcastLifetime = o.broadcastLifetime or 10
    if o.broadcastLifetime < 1 then
        app:callingError( "1 second minimum" )
    end
    o.listeners = {}
    return o
end



--- Schedule directory cleanup.
--
--  @usage  bcast & reply dirs are cleaned up by all upon startup, as is to-me.
--      <br>what remains to be cleaned up are dirs to other entities which may not be online or healthy enough to cleanup their own.
--  @usage "cleanup" means "check for and delete expired messages".
--
--  @param incomingAddrs plugin addresses - cleaned up dirs will be in-dir/incoming-addr.
--  @param ival cleanup interval 1 second minimum.
--
function Intercom:scheduleCleanup( incomingAddrs, ival )
    assert( gbl:getValue( 'xml' ), "xml not global" )
    ival = ival or 60
    app:callingAssert( tab:isArray( incomingAddrs ), "incoming to-addresses must be specified as array" )
    local dirs = {}
    for i, v in ipairs( incomingAddrs ) do
        dirs[#dirs + 1] = LrPathUtils.child( self.inDir, v )
    end
    app:pcall{ name="Intercom_scheduledCleanup", async=true, function( call )
        while not call:isQuit() do -- includes shutdown flag.
            for i, d in ipairs( dirs ) do
                self:_cleanupExpired( d, call ) -- cleanup all incoming, note: all plugins will be doing this, but hopefully no interference. ###2
            end
            app:sleep( ival )
        end
    end }
end



--[[ *** hang on..
function Intercom:_getMetaInfo( file )
    local filename = LrPathUtils.leafName( file )
    local nameValuePairs = str:split( filename, "; " )
    local metaInfo = {}
    if #nameValuePairs > 1 then -- not sure this is any faster than opening the file and reading it.
        for i, v in ipairs( nameValuePairs ) do
            nameValuePair = str:split( v, "=" )
            if #nameValuePair==2 then
                local name = nameValuePair[1]
                local value = nameValuePair[2]
                metaInfo[name] = str:isStartingWith( value, "['\"]" ) and value:sub( 2, -2 ) or tonumber( value ) -- beware if regex is what I want here 25/Apr/2014 2:41.
            end
        end
    else
        local s, m = pcall( dofile, file )    
    end
end
--]]



--  Private method to determine if message is expired.
--  msg must be in lua or "pseudo-lua" (expires-in-seconds member assigned to table) format.
--  source file is used to get file-mod date to avoid having to parse from filename member..
function Intercom:_isExpired( msg, now, file )
    if msg.expiresInSeconds then -- interval (the new way @25/Feb/2014 4:54 - version 2).
        local thresh = 3 + msg.expiresInSeconds + ( 2 * self.pollingInterval ) -- we could be late due to polling interval, so don't penalize oblivious sender.
        -- polling-interval doubled just to give a little breathing room - ditto for 3-second baseline. Reminder: expired messages hanging around don't hurt anything too much.
        local cre = fso:getFileModificationDate( file ) -- it seems file-creation date should be same as modification date if file never modified,
        -- however, that't not how it's working (and is maybe the reason java not supporting file-created date - it's wonked. In any case, file-mod date works, file-cre doesn't.
        if cre then
            local expired = ( now - thresh ) > cre
            if expired then
                dbgf( "Expired: ^6, ival=^1/^5, now=^2, diff=^3, fc=^4", msg.expiresInSeconds, now, date:formatTimeDiffMsec( now - cre ), cre, thresh, file )
                --Debug.pause( "Expired" )
            end
            --Debug.pauseIf( expired, str:fmtx( "Expired, ival=^1/^5, now=^2, diff=^3, fc=^4", msg.expiresInSeconds, now, date:formatTimeDiffMsec( now - cre ), cre, thresh ) )
            return expired
        else -- file not found.
            app:logV( "Message dissappeared: ^1", file )
            return false
        end
    elseif msg.expires then -- absolute (epoch-normalized) expiration time - obsolete/deprecated in favor of expires-in-seconds interval (may still be used by *other* plugins, so must be attended to).
        Debug.pause( now - msg.expires )
        return now > msg.expires
    else
        app:logW( "Bad message: ^1", file )
        msg.expiresInSeconds = 60 -- let it go, but give it a minute before giving it the axe.
        return false
    end
end



--  Private method to get a *received* message (i.e. can not be used for getting a sent message), specified by file found in msg (incoming or reply) dir.
--  Received messages are "always" (so far) in Lua format, despite sometimes being sent in simple-xml format.
--  auto-discards expired messages.
function Intercom:_getMessage( file, now )
    local s, m = pcall( dofile, file ) -- translate from serialized file content to lua table.
    if not s then
        for i = 1, 3 do -- up to 3 tries, then give up..
            LrTasks.sleep( .1 ) -- in case temporarily locked or something..
            if LrFileUtils.isReadable( file ) then
                s, m = pcall( dofile, file )
                if s then
                    dbgf( "Got message on retry #^1 from file: ^2", i, file )
                    app:logV( "*** Got message on retry #^1 from file: ^2", i, file )
                    Debug.pause( "message not readable at first, is now.." )
                    break
                end
            else
                m = "File not readable: "..file
            end
        end
    end
    if s then
        if self:_isExpired( m, now or LrDate.currentTime(), file ) then
            LrFileUtils.delete( file )
            return nil, "expired"
        elseif m.seqNum ~= nil then
            app:assert( m.seqNum > 0, "bad sn: ^1 - ^2", m.seqNum, m.filename )
            return m -- msg.
        else
            LrFileUtils.delete( file )
            return false, "No sequence number"
        end
    else -- the quick-try failed - hmm.
        return false, str:fmtx( "unable to get message from file due to error: ^1", m )
    end
end



-- note: this is called only to clean up "sent" messages.
-- all sent messages use v2+ (expires-in-seconds). 
-- call not currently used, but if something seems wrong - abort it..
function Intercom:_cleanupExpired( dir, call )
    app:logV( "Cleaning up expired messages in: ^1", dir )
    local now = LrDate.currentTime()
    local purge = {}
    for file in LrFileUtils.recursiveFiles( dir ) do
        local expSec
        if self.simpleXml and call then -- note, if call (scheduled cleanup) and simple-xml: sent messages are in simple-xml format,
            -- if not scheduled cleanup (or not simple-xml), then messages are to me and will be in lua format.
            local xs, er = fso:readFile( file )
            if str:is( xs ) then
                local doc = xml:parseXml( xs ) -- this is my parser, not LrXml.
                if doc then -- document
                    if doc[1] then
                        if type( doc[1] ) == 'table' then
                            for i, v in ipairs( doc[1] ) do
                                if v.label=="expiresInSeconds" then
                                    expSec = num:numberFromString( v[1] )
                                    break
                                end
                            end
                            if not expSec then
                                er = "no expires-in-seconds element"
                            end
                        else
                            Debug.pause( "Not parsable simple-xml msg", file, doc[1] )
                            er = "not table"
                        end
                    else
                        Debug.pause( doc )
                        er = "no root element"
                    end
                else
                    Debug.pause( xs )
                    er = "no parseable document"
                end
            -- else er already set.
            end
            if not expSec then
                purge[#purge + 1] = file
                app:logVerbose( "Invalid simple-xml message file: ^1 - ^2", file, er )
            end                
        else
            local s, m = pcall( dofile, file ) -- another option is to parse expiry from filename and compare to created date.
            if s then
                expSec = m.expiresInSeconds
            else
                purge[#purge + 1] = file
                app:logVerbose( "Invalid lua message file: ^1 - ^2", file, m )
            end
        end
        if expSec then
            if self:_isExpired( { expiresInSeconds=expSec }, now, file ) then -- ###2 cheating, but should be OK.
                purge[#purge + 1] = file
            else
                app:logVerbose( "Unexpired message: ^1", file )
            end    
        -- else already scheduled for purging, msg logged..
        end
    end
    if #purge > 0 then
        for i, v in ipairs( purge ) do
            app:logVerbose( "Purging '^1'.", v )
            if LrTasks.canYield() then
                fso:deleteFileConfirm( v ) -- delete all messages on the chopping block.
                app:logV( "Deleted: ^1", v )
            else
                local x = LrFileUtils.delete( v )
                app:logV( "^1: ^2", x, fso:existsAsFile( v ) )
            end
        end
    else
        dbgf( "Nothing to purge in '^1'.", dir )
    end
end



-- note: somehow responsibility needs to be taken for sent messages that don't get cleaned up too - maybe just a send-message sleep with cleanup.
-- private method to initialize plugin's incoming or reply directory.
-- assures its creation, and purges all expired messages.
-- does not purge unexpired messages, in case a peer plugin has already
-- sent this plugin a message before it has finished initialization.
function Intercom:_initDir( dir )
    if not fso:existsAsDir( dir ) then
        local s, m, c = fso:assureAllDirectories( dir )
        if not s then
            app:error( m )
        end
    else
        self:_cleanupExpired( dir ) -- deleting all messages to-me whilst I was down..
    end
end



-- private method to serialize message and place in specified file.
function Intercom:_send( msg, path )
    local dir = LrPathUtils.parent( path )
    if not fso:existsAsDir( dir ) then
        local s, m = fso:assureAllDirectories( dir ) -- may be sending before receiver has prepared receptacle, but still want send to succeed.
        if s then
            app:logVerbose( "Receiver was not setup for receiving messages - receptacle directory created: ^1", dir )
        else
            app:error( "Receiver is not setup for receiving messages - directory can not be created: ^1, error message: ^2", dir, m )
        end
    -- else good to go...
    end
    local ser
    if self.simpleXml then
        ser = simpleXml:serializeLua( "message", msg )
    else
        ser = "return " .. luaText:serialize( msg )
    end
    local s, m = fso:writeAtomically( path, ser ) -- dir already assured, overwrite shouldn't be necessary, but would be OK.
    if s then
        -- Debug.pauseIf( not fso:existsAsFile( path ), "no file" ) - this can happen if external app is fast to delete after receiving.
        -- dbgf( "^1 sent from ^2 to ^3, filename: ^4", msg.name, msg.from, msg.to, msg.filename ) -- a little much unless there are specific problems to trouble-shoot..
    else
        app:error( m )
    end
end



-- private method to get filename for outgoing message,
-- and perform other common msg prep...
-- bumps seq-num before using.
function Intercom:_prepareToSend( msg, to, time, expiresInSeconds, from )
    --if msg.name == nil then
    --    app:callingError( "Need msg name." )
    --end
    msg.version = 2 -- expire-time changed. Although it's checked directly, it is technically a version change.
    msg.expiresInSeconds = expiresInSeconds or 60
    
    msg.from = from or _PLUGIN.id
    msg.to = to -- not required for functioning, but is comforting when it matches...
    if msg.filename then
        -- reply: same filename & seq-num.
    else
        time = time or LrDate.currentTime()
        local timeFmt = LrDate.timeToUserFormat( time, "%Y-%m-%d_%H-%M-%S" )
        self.seqNum = self.seqNum + 1
        msg.filename = string.format( "%s %s %05u.txt", msg.from, timeFmt, self.seqNum )
        msg.seqNum = self.seqNum -- for the heck of it.
        if self.seqNum >= 100000 then
            self.seqNum = 1
        end
    end
end



--- Broadcast a messsage.
--
--  @param      msg (table, required) message to be broadcast.
--  @param      lifetime (number, optional) lifetime in seconds, else defaults to whatever was initialized when intercom object created (e.g. 10 seconds).
--
--  @usage      message will exist for specified time for any broadcast listeners to hear, then it's deleted (by sender - listeners just make note to not reprocess).
--  @usage      broadcast messages do not warrant replies, but receiver is free to send message to broadcaster when broadcast message is received...
--  @usage      nothing returned, errors will be thrown.
--  @usage      unlike addressed message cleanup, broadcast messages are cleaned up immediately upon expiry - there is a separate task devoted to each broadcast message for that purpose.
--
function Intercom:broadcast( msg, lifetime )
    self:_prepareToSend(    -- does not encode to-dir
        msg,                -- message
        "broadcast",        -- to address
        nil,                -- time
        nil                 -- expire time (interval in seconds) is not used, but doesn't hurt.
    )
    local dir = LrPathUtils.child( self.bcastDir, msg.from )
    local file = LrPathUtils.child( dir, msg.filename )
    self:_send( msg, file )
    app:call( Call:new{ name="broadcast msg", async=true, guard=nil, main=function( call ) -- specifically re-entrant.
        app:sleepUnlessShutdown( lifetime or self.broadcastLifetime )
        LrFileUtils.delete( file )
    end } )
end



--- Optional method to initialize a fresh message for replying.<br>
--  The other possibility is just to reuse the received message for replying.
--
--  @param msg message which is being replied to.
--
--  @return message structure (with 'from', 'filename', 'comment', but no 'to'..).
--
function Intercom:createReply( msg )
    return { from=msg.from, filename = msg.filename, comment=str:fmt( "this is a reply" ) }
end



--- Send message to specified plugin and wait for reply.
--
--  @usage must be called from a task.
--
--  @param msg message being sent, required fields: 'name'.
--  @param to "to" address (plugin toolkit ID).
--  @param tmo response timeout in seconds, default is 10.
--  @param fromName name of sending entity, to be suffix of plugin-id for final from address.
--
--  @return reply (table) or nil if no reply
--  @return errm (string) error message if no reply.
--
function Intercom:sendAndReceive( msg, to, tmo, fromName )
    if tmo == nil then
        tmo = 10
    else
        app:callingAssert( type( tmo ) == 'number', "tmo must be number, not: ^1", type( tmo ) )
    end
    -- content is optional.
    local from
    if fromName then
        from = _PLUGIN.id.."."..fromName
    end
    local reply, errm
    local s, m = app:pcall{ name="send and receive", async=false, main=function( call )
        local time = LrDate.currentTime()
        self:_prepareToSend( msg, to, time, tmo, from ) -- time + tmo ) -- if from is nil, it defaults to _plugin-id.
        local dir = LrPathUtils.child( self.inDir, to )
        local file = LrPathUtils.child( dir, msg.filename )
        self:_send( msg, file )
        local replyPath
        if fromName then
            replyPath = LrPathUtils.child( self.replyDir.."."..fromName, msg.filename )
        else
            replyPath = LrPathUtils.child( self.replyDir, msg.filename )
        end
        --dbgf( "Expecting reply at: ^1", replyPath ) -- note: this leaves no wiggle room for different versions to have different filenames. ###
        local seqNumLogd
        local othLogd
        while not shutdown do
            app:sleep( self.pollingInterval )
            --[[ *** for testing: accept any message as reply.
            for file in LrFileUtils.files( LrPathUtils.parent( replyPath ) ) do
                if replyPath == file then
                    break
                else
                    --Debug.pause( replyPath, file )
                end
            end
            --]]
            if fso:existsAsFile( replyPath ) then
                --dbgf( "Reply received at: " .. replyPath )
                local rcv, err = self:_getMessage( replyPath ) -- will not return an expired message.
                --Debug.pause( s, m )
                if rcv then -- received
                    if rcv.seqNum == msg.seqNum then -- note: since seq-num is built into filename which must match, this statement is redundent. ###
                        --Debug.pause( rcv.seqNum )
                        reply = rcv
                        fso:deleteFileConfirm( replyPath )
                        --app:logV( "Deleted reply: ^1 - ^2", replyPath, not fso:existsAsFile( replyPath ) ) -- this gets a little much when there's a lot of comm.
                        return
                    else
                        Debug.pause( "seq-num snafu", rcv.name, rcv.seqNum, msg.seqNum )
                        --LrFileUtils.delete( replyPath ) - could be deleted, but should die a natural death (tmo) even if not deleted.
                        if not seqNumLogd then
                            app:logV( "Message received, but sequence number not matching, was: ^1, expected: ^2 (message discarded)", rcv.seqNum, msg.seqNum )
                            seqNumLogd = true
                        end
                        LrTasks.sleep( 1 ) -- must not look again at same message too soon. (could use same __seen mechanism as for broadcasts).
                        -- reminder, theoretically reply could be for another task, so presumptuous to delete.
                    end
                elseif rcv == nil then -- expired (and therefore auto-deleted) - won't be seeing it again.
                    Debug.pauseIf( err ~= "expired" )
                    app:logV( "Message received that might have been considered a reply, but it was expired." )
                    LrTasks.sleep( .1 ) -- not necessary, theoretically, but it comforts me.
                else -- some other problem (I've seen this once - when exiting following backup).
                    --Debug.pause( "?" ) -- note: it seems this function should whether all storms until it either gets a valid message or times out.
                    if not othLogd then
                        app:logW( "Problem with message received as ^1 - ^2", replyPath, err )
                        othLogd = true
                    end
                    app:sleep( 1 )
                    --errm = m
                    --app:error( "bad (or no) reply received: ^1", replyPath )
                end
            else
                local t2 = LrDate.currentTime()
                if t2 - time > tmo then -- elapsed time exceeds tmo interval.
                    -- app:error( "Timed out after ^1 seconds", tmo ) -- reminder: finale function is required for this to propagate "silently" (unless debug enabled) to return code.
                    errm = str:fmtx( "Timed out after ^1 seconds", tmo ) -- this since not really error.
                    break
                end
            end
        end
        if shutdown then
            errm="plugin shutdown or reloaded"
        end
    end, finale=function() end }
    if s then
        if reply then
            return reply, errm
        else
            --Debug.pauseIf( errm ~= "plugin reloaded", "no reply", errm )
            Debug.pauseIf( errm == nil, "no reply, no errm" )
            return nil, errm or "no additional info"
        end
    else
        Debug.pauseIf( m == nil, "no m" )
        return nil, m
    end
end



--- Send message that is the reply to an inbound (unsolicited "command" message).
--
--  @param msg (table, required) 'name' is only required member, but 'content' may be nice...
--  @param to (string, required) destination plugin id - often msg.from
--
--  @usage Maybe best to recompute message content, then resend original message (since it already has some members assigned as needed) - but its your call...
--  @usage presently throws error if problems sending, but that may change - note: need not be called from task, although typically is.
--
function Intercom:sendReply( msg, to )

    -- Note: seq-num is not bumped when sending reply, only new messages.
    if to then
        if msg.from then
            assert( to == msg.from, "why not reply to sender?" )
        else
            dbgf( "No from field in message, must be a newly created message." )
        end
    else
        if msg.from then
            to = msg.from
        else
            app:callingError( "Dunno who to send reply to." )
        end
    end
    local dir = LrPathUtils.child( self.mainDir, "Replies" )
    local replyDir = LrPathUtils.child( dir, to )
    self:_prepareToSend( msg, to )
    local path = LrPathUtils.child( replyDir, msg.filename )
    self:_send( msg, path )

end



--- Send message to destination (unsolicited-inbox), and do not expect nor wait for reply.
--
--  @param msg (table, required) 'name' is only required member, but 'content' may be nice...
--  @param to (string, required) destination plugin id.
--
--  @usage Not for internal use - use private methods instead.
--
--  @return status (boolean) true => sent.
--  @return message (string) error message if not sent.
--
function Intercom:sendMessage( msg, to )
    local s, m = app:call( Call:new{ name="send message", async=false, main=function( call )
        self:_prepareToSend( msg, to ) -- fill in the message blanks (e.g. version), including "filename".
        local dir = LrPathUtils.child( self.inDir, to )
        local file = LrPathUtils.child( dir, msg.filename )
        self:_send( msg, file )
    end } )
    return s, m
end



--  Private method for listening to messages from specified plugins.
--
--  @param functionOrMethod (function, required) callback function, or object method.
--  @param objectOrNil (Class instance object, optional) if provided, the aforementioned callback will be called as object method.
--  @param fromList (table as set, default = accept from anyone including self) keys are plugin ids from who unsolicited messages will be accepted, values must evaluate to boolean true.
--  @param dir (string, required) inbox dir - typically to-me-dir or broadcast-dir.
--  @param ival (number, optional) polling interval. Often coarser for broadcast messages, since response time tends to be less critical.
--
--  @usage returns immediately after starting task, which runs until shutdown.
--  @usage technically speaking, if not listening for broadcasts, and not planning on stopping the listener, object/method calling is not required,
--         <br>(i.e. could be function with no object) but its not really supported either.
--
function Intercom:_listen( functionOrMethod, objectOrNil, fromList, dir, ival )
    ival = ival or self.pollingInterval
    local listener
    local broadcast = (dir == self.bcastDir) 
    local objectName = str:to( objectOrNil )
    if broadcast then -- broadcast listener
        if ival > ( ( self.broadcastLifetime / 2 ) - .4 ) then
            ival = ( self.broadcastLifetime / 2 ) - .4 -- min bcast lifetime is 1, min bcast ival is .1
        end
        listener = objectName .. "_broadcast" -- must match stop-listen method.
    else
        listener = objectName -- ditto.
    end
    self.listeners[listener] = true
    app:pcall{ name="Intercom listener", async=true, guard=nil, main=function( call )
        --local s, m = app:call( Call:new{ name="Intercom message processor", async=false, main=function( call )
        Debug.logn( str:fmt( "listening object: ^1", listener ) )
        Debug.logn( str:fmt( "listening dir: ^1", dir ) )
        Debug.lognpp( "listening from-list", fromList )
        local function listen()
            while not shutdown and self.listeners[listener] do
                for file in LrFileUtils.recursiveFiles( dir ) do
                    repeat
                        local now = LrDate.currentTime()
                        local filename = LrPathUtils.leafName( file )
                        if broadcast then -- non-broadcast messages are deleted after first seen.
                            if objectOrNil then
                                if not objectOrNil.__seen then
                                    objectOrNil.__seen = {}
                                elseif objectOrNil.__seen[file] then
                                    --Debug.logn( "Message seen: " .. filename )
                                    break
                                else
                                    -- Debug.logn( "Message being marked as seen: " .. filename .. ", file: " .. file)
                                end
                                objectOrNil.__seen[file] = true
                            else
                                --Debug.logn( "Intercom incoming (no object): " .. filename )
                                app:error( "broadcast requires object, no?" )
                            end
                        else
                            --Debug.logn( "Intercom incoming message: " .. filename )
                        end
                        local split = str:split( filename, " " )
                        local from
                        if #split > 1 then
                            from = split[1]
                        end
                        if not str:is( from ) then
                            app:logError( "Invalid message received" )
                            Debug.pause( file )
                            break
                        end
                        if tab:is( fromList ) then                        
                            if from == _PLUGIN.id then
                                --Debug.logn( "Ignoring message from self: " .. _PLUGIN.id )
                                break
                            elseif not fromList[from] then
                                --Debug.logn( "Ignoring message from " .. from )
                                break
                            -- else from somebody on list
                            end
                        -- else - no list: messages are accepted from anyone, including self.
                        end
                        local msg, err = self:_getMessage( file, now )
                        if msg then -- received/unexpired.
                            if msg.version ~= nil then
                                if broadcast then
                                    dbgf( str:to( objectOrNil ), file )
                                    dbgf( str:fmt( "Broadcast message accepted: ^1", filename ) ) -- from address came from filename, so is redundent.
                                else
                                    dbgf( str:fmt( "Incoming message accepted: ^1", filename ) ) -- ditto
                                end
                                -- the following is not true for replies, but this is for listening to unsolicited "command" messages,
                                -- in which case from address in messages should match filename.
                                if msg.from then
                                    if from ~= msg.from then
                                        Debug.logn("\n")
                                        Debug.lognpp( from, file )
                                        Debug.lognpp( msg.from, msg )
                                        Debug.logn("\n")
                                        app:error( "from address mixup, filename: ^1, msg: ^2", from, msg.from )
                                    else
                                        --
                                    end
                                else
                                    app:error( "No from address" )
                                end
                                if msg.filename then
                                    if filename ~= msg.filename then
                                        app:error( "Bad filename in message" )
                                    else
                                        -- ok
                                    end
                                else
                                    app:error( "no filename in message" ) -- @msg v1, all "proper" channels for msg prep are including filename as message member.
                                end
                                if objectOrNil then -- call function as method.
                                    functionOrMethod( objectOrNil, msg )
                                else
                                    functionOrMethod( msg )
                                end
                            else
                                app:logError( "Message missing version: ^1", msg )
                            end
                        elseif err == 'expired' then
                            dbgf( "msg expired - was discarded" )
                        else
                            dbgf( "No message gotten - ^1", err )
                        end
                    until true
                    if not broadcast then
                        LrFileUtils.delete( file ) -- it is OK to delete file being iterated.
                    end
                end  -- end-of for loop
                app:sleepUnlessShutdown( ival )
                --[[for k, v in pairs( objectOrNil.__seen ) do
                    if not fso:existsAsFile( k ) then
                        objectOrNil.__seen[k] = nil
                    end
                end ###3 - not sure what this was about now, but it's been this way for several months now @10/Oct/2012. - delete in 2016...
                --]]
            end -- while not shutdown etc.
        end -- end of listen task function
        repeat
            local s, m = LrTasks.pcall( listen ) -- perform task function, unless normal (or abnormal/erroneous) termination.
            if s then -- no error thrown - i.e. normal termination
                Debug.pauseIf( not call:isQuit(), "how term? (not quit)" )
                if broadcast then
                    app:logVerbose( "^1 stopped listening to broadcasts.", objectName )
                else
                    app:logVerbose( "^1 stopped listening to messages.", objectName )
                end
                break
            else -- error thrown - this can happen due to Lightroom bug (presumably), e.g. command-desc error.
                app:alertLogE( "Intercom listening error: '^1'. Taking a moment..", m )
                app:sleepUnlessShutdown( 3 )
            end
        until false
    end }
end



--- Listen to messages from specified plugins, to me.
--
--  @param method (function, required) callback function - must be method.
--  @param object (Class instance object, optional) object containing callback method. - must not be closed object, or must contain __seen member table.
--  @param fromList (table as set, default = accept from anyone including self) keys are plugin ids from who unsolicited messages will be accepted, values must evaluate to boolean true.
--  @param ival (number, optional) polling interval, else accept default.
--
--  @usage returns immediately after starting task, which runs until shutdown.
--  @usage object may be nil, and method may be function, as long as plugin will never try to stop listening.
--
function Intercom:listen( method, object, fromList, ival, toName )
    self:_listen( method, object, fromList, self.toMeDir..(toName and ("."..toName) or ""), ival )
end



--- Listen to broadcast messages from specified plugins, to anyone.
--
--  @param method (function, required) callback function - must be method.
--  @param object (Class instance object, optional) object containing callback method. - must not be closed object, or must contain __seen member table.
--  @param fromList (table as set, default = accept from anyone including self) keys are plugin ids from who unsolicited messages will be accepted, values must evaluate to boolean true.
--  @param ival (number, optional) polling interval, else accept default.
--
--  @usage returns immediately after starting task, which runs until shutdown.
--
function Intercom:listenForBroadcast( method, object, fromList, ival )
    if object == nil then
        app:callingError( "Object must not be nil when listening for broadcast messages." )
    end
    self:_listen( method, object, fromList, self.bcastDir, ival )
end



--- Stop listener tied to specified object.
--
--  @param object Must be same object as passed to listen function.
--
function Intercom:stopListening( object )
    local listener = str:to( object )
    if self.listeners[listener] ~= nil then
        self.listeners[listener] = nil
    else
        app:logVerbose( "^1 is not listening.", listener )
    end
end



--- Stop broadcast listener tied to specified object.
--
--  @param object Must be same object as passed to listen-for-broadcast function.
--
function Intercom:stopBroadcastListening( object )
    local listener = str:to( object ) .. "_broadcast"
    if self.listeners[listener] ~= nil then
        self.listeners[listener] = nil
    else
        app:logVerbose( "^1 is not listening for broadcasts.", str:to( object ) )
    end
end



-- Optional: use Listener as base class for listening callback object.
-- Doesn't do much except assure listener has a unique name via to-string method
-- so multiple listeners in the same plugin won't conflict.
local Listener = Object:newClass{ className="IntercomListener", register=false }
function Listener:newClass( t )
    return Object.newClass( self, t )
end
function Listener:new( t )
    local o = Object.new( self, t )
    if not str:is( o.name ) then
        o.name = LrUUID.generateUUID() -- listener must have unique name if more than one object will be listening simultaneously.
    end
    return o
end
function Listener:toString()
    return self.name
end



return Intercom, Listener


