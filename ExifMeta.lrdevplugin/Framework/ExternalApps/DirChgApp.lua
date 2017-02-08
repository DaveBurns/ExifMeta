--[[
        DirChgApp.lua
        
        Interface to Dir File Change Notifier (Java) App.
--]]


local DirChgApp, dbg, dbgf = Object:newClass{ className = 'DirChgApp', register = true }



--- Constructor for extending class.
--
function DirChgApp:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage pass pref-name, win-exe-name, or mac-pathed-name, if desired, else rely on defaults (but know what they are - see code).
--
function DirChgApp:new( t )
    local o = Object.new( self, t )
    local ad, er = fso:getAppDataDir() -- system/user app-data dir
    if ad then
        ad = LrPathUtils.child( ad, "com.robcole" )
        ad = LrPathUtils.child( ad, "DirFileChangeNotifier" ) -- hard-coded - companion app just needs to hard-code to same thing.
    else
        app:error( "no app-data dir: ^1", er )
    end
    o.rootDir = ad
    -- note: it's a tad presumptuous for app i/f to assume there will be a background process, but hey - we're all friends here, right? ;-}.
    o.comm = Intercom:new{ dir=ad, simpleXml=true, pollingInterval=1, addlNames=o.addlNames } -- used for communication with Dir File Change Notifier app.
    -- I suppose cleanup could be built into intercom, but, well, it's not..
    -- note: we're cleaning up for entities we're sending *to*, in case they're not running healthily (to avoid excessive expired messages..)
    o.comm:scheduleCleanup( { 'com.robcole.DirFileChangeNotifierApp' }, 60 ) -- cleanup messages sent to dir-file-change-notifer that might not otherwise get cleaned up. 60 is the default,
        -- this could probably be much larger, since receiver shouldn't respond to expired messages, and does it's *own* cleanup if it's running..
    o.comm:listen ( 
        o.processMessage, -- callback func
        o, -- callback obj - default is this object, but could be object of callers choice.
        nil, -- from-addr-list
        1 -- listen polling interval.
    )
    if o.addlNames then
        for i, name in ipairs( o.addlNames ) do
            o.comm:listen(
                o.processMessage, -- callback func
                o,
                nil,
                1, -- ival
                name -- behaves as plugin-id extension for listening..
            )
        end
    end
    return o
end



--- Set custom callback for unsolicited messages.
--
--  @usage Be careful to handl all possbilities, and try not to stomp on other callbacks..
--
--  @param recipient -- to-address..
--  @param callbackFuncOrMeth -- function (or method) to call (required) - passing message object as only parameter.
--  @param callbackObj -- object (optional) in which case the previously mentioned will be called as object method.
--
function DirChgApp:setMessageCallback( recipient, callbackFuncOrMeth, callbackObj )
    if self.callbackRegistry == nil then
        self.callbackRegistry = {}
    end
    self.callbackRegistry[recipient] = { func = callbackFuncOrMeth, obj = callbackObj }
end



--- Processor for incoming (unsolicited) messages.
--
--  @usage simply logs received comment unless error - which gets alert/log treatment.
--  @usage calling context can set it's own callback
--
--  @param msg message
-- 
function DirChgApp:processMessage( msg )
    --Debug.pause( msg.name, msg )
    local obj
    local func
    if self.callbackRegistry then
        local ent = self.callbackRegistry[msg.to]
        if ent then
            obj = ent.obj
            func = ent.func
        end
    end
    if func then -- not much point in dir-change app if no callback ;-}.
        if obj then
            func( obj, msg ) -- meth
        else
            func( msg ) -- static
        end
    else
        app:logW( "No callback function/method - what's up? - message received from dir-chg app: '^1' to ^2", msg.name, msg.to )
        if msg.name == 'registered' then
            if str:is( msg.comment ) then
                app:log( msg.comment )
            else
                app:log( "registered - no additional info" )
            end
        elseif msg.name == 'notify' then
            if str:is( msg.comment ) then
                app:logV( msg.comment )
            else
                app:logV( "notify message received - no additional (comment) info" )
            end
            app:logV( "Dir/File change notification: '^1' - ^2 (no callback).", msg.path, msg.eventType )
            --Debug.lognpp( msg )
        elseif msg.name == 'error' then
            if str:is( msg.comment ) then
                app:alertLogE( msg.comment )
            else
                app:alertLogE( "dir-chg app reported error sans comment" )
            end
        else
            Debug.pause( msg )
        end
    end
end



function DirChgApp:quit( tmo, fromName )
    local msg = {
        name = "quit",
        comment = "please",
    }
    local to = "com.robcole.DirFileChangeNotifierApp" -- hardcoded (maybe should be a "literal" ###2).
    tmo = tmo or 10
    local reply, errm = self.comm:sendAndReceive( msg, to, tmo, fromName )
    if reply then
        return true
    else
        return false, "no reply"
    end
end



--- Returns lower case string indicative of whether app is responding to "hello" message.
--
--  @return query-status
--  @return app-status
--  @return more-info
--
function DirChgApp:getPresence( tmo, fromName )
    local msg = {
        name = "areYouReady?",
    }
    --local to = "com.robcole.DirFileChangeNotifier" -- for testing.
    local to = "com.robcole.DirFileChangeNotifierApp" -- hardcoded (make "literal" ###2).
    tmo = tmo or 30 -- pass a shorter tmo if presence expected by now..
    local reply, errm = self.comm:sendAndReceive( msg, to, tmo, fromName )
    if reply then -- good
        -- online/offline nyi..
        local twoChars = LrStringUtils.lower( ( reply.comment or "" ):sub( 1, 2 ) )
        if twoChars == 'on' then
            return true, 'online', "Online - notification is enabled"
        elseif twoChars == 'of' then
            return true, 'disabled', "Running, but notification is disabled (offline)"
        else
            --Debug.pause( reply.comment ) - ###3: consider improving someday.
            return true, 'wonky', "Running, but not replying as expected - hmm..."
        end
    else
        Debug.pauseIf( not str:is( errm ), "no errm" ) -- ###2 (I think it's still possible for no errm, but since root problem solved, not seeing this any more).
        local status = app:getGlobalPref( 'dirChgAppStatus' ) -- ###1 probably does not need to be global pref anymore.
        if status == 'online' then
            self.noReplyCount = 0
            dbgf( "Timeout after ^1 seconds. message sent from ^2 to ^3, filename: ^4", tmo, msg.from, msg.to, msg.filename )
            return false, 'notResponding', "No longer responding - please wait.."
        else
            if self.noReplyCount == nil then
                self.noReplyCount = 1
            else
                self.noReplyCount = self.noReplyCount + 1
            end
            if self.noReplyCount >= 3 then
                return false, 'offline', "Not running, or fouled up."
            else
                return false, 'uncertain', "Uncertain - do standby.."
            end
        end
    end
end



-- task
function DirChgApp:_startRunning( appPath )
    app:pcall{ name="DirChgApp_startRunning", async=true, guard=App.guardSilent, function( call )
        -- assumes java is usable if needed - maybe worth a test check in config code..
        local command
        local params
        local target
        local isJar
        local tryJar
        if str:is( appPath ) then -- user/pref-specified app path. - tested on Windows.
            if str:isEqualIgnoringCase( LrPathUtils.extension( appPath ), "jar" ) then
                target = appPath
                isJar = true -- defines command and parameters.
            else -- tested on Windows.
                command = appPath
                -- no params, no target.
            end
        else
            if app:isRelease() then -- this clause has been tested on Windows.
                if WIN_ENV then
                    -- app is downloaded and installed in standard, NetBeans fashion: in user-local-app-data location.
                    local ad, er = fso:getAppDataDir( "Local" ) -- e.g. C:\Users\Rob\AppData\Local
                    if ad then
                        local appDir = LrPathUtils.child( ad, "DirFileChangeNotifier" ) -- hard-coded.
                        if LrFileUtils.exists( appDir ) == 'directory' then
                            local appFile = LrPathUtils.child( appDir, "DirFileChangeNotifier.exe" )
                            if fso:existsAsFile( appFile ) then
                                command = appFile
                                -- no params, no target.
                            else
                                app:logV( "Dir File Change Notifier App executable is missing: '^1', will try to run built-in java app, but such is not the recommended configuration on Windows - to eliminate this warning, specify path to executable explicitly, or re-install Dir File Change Notifier application.", appFile )
                                tryJar = true
                            end
                        else
                            app:logV( "Dir File Change Notifier App is not installed (in '^1' directory) - will try to run jar via java, but such is not the recommended configuration on Windows - to eliminate this warning, specify path to executable explicitly, or install Dir File Change Notifier application.", appDir )
                            tryJar = true
                        end
                    else
                        app:logV( "Can not find local app-data directory in which Dir File Change Notifier App was expected (err-msg: ^1) - will try to run jar via java, but such is not the recommended configuration on Windows - to eliminate this warning, specify path to executable explicitly, after installing Dir File Change Notifier application.", er )
                        tryJar = true
                    end
                else -- Mac
                    app:logV( "Will try to run built-in java app for dir/file change services." )
                    tryJar = true
                end
            else -- development mode - get app from local dev dir. - tested on Windows.
                target = LrPathUtils.child( "X:\\Dev\\AppsJava\\DirFileChangeNotifier\\dist", "DirFileChangeNotifier.jar" ) -- Executor is smart enough to detect string vs. array.
                isJar = true
            end
        end
        if tryJar then -- not already commited to jar, but ready to try it.
            Debug.pauseIf( isJar, "oops" ) -- this never happens.
            local appDir = LrPathUtils.child( _PLUGIN.path, "DirFileChangeNotifierApp" )
            if fso:existsAsDir( appDir ) then
                local appFile = LrPathUtils.child( appDir, "DirFileChangeNotifier.jar" )
                if fso:existsAsFile( appFile ) then
                    isJar = true -- defines command and parameters.
                    target = appFile
                else
                    app:logE( "Dir File Change Notifier app not in expected location: ^1", appFile )
                    app:show{ error="Dir File Change Notifier app not in expected location: ^1", appFile }
                    return                    
                end
            else
                app:logE( "Dir File Change Notifier app not in expected location: ^1", appDir )
                app:show{ error="Dir File Change Notifier app not in expected location: ^1", appDir }
                return                    
            end
        -- else nada here.
        end
        local argBuf = {}
        app:setPref( 'dirChgAppVerbose', nil ) -- kill previous pref, comes from system-settings.
        local verbose = app:getPref( 'dirChgAppVerbose' ) -- fprops:getPropertyForPluginSpanningCatalogs( 'com.robcole.DirFileChangeNotifier', 'dirChgAppVerbose' )
        --local online = app:getPref( 'dirChgApp' ) -- fprops:getPropertyForPluginSpanningCatalogs( 'com.robcole.DirFileChangeNotifier', 'dirChgAppOnline' )
        --local dateTol = fprops:getPropertyForPluginSpanningCatalogs( 'com.robcole.DirFileChangeNotifier', 'dirChgAppDateTol' )
        --Debug.pause( verbose, online, dateTol )
        if verbose then
            argBuf[#argBuf + 1] = "--log=v" -- erbose
        -- else default is normal.
        end
        --[[
        if not online then
            argBuf[#argBuf + 1] = "--online=off" -- line
        -- else default is online.
        end
        if dateTol ~= nil then
            argBuf[#argBuf + 1] = "--dateTol="..dateTol -- % (10's of seconds).
        else
            --Debug.pause( "Date tolerance not specified." )
        end
        --]]
        local args = (#argBuf > 0) and table.concat( argBuf, " " ) or ""
        if isJar then
            if fso:existsAsFile( target ) then
                command = "java"
                app:assert( str:is( target ), "no jar target" )
                params = str:fmtx( '-jar "^1"^2', target, str:is( args ) and (" "..args) or "" ) -- package jar target & cmd-line args as params to avoid ill-placed quotes.
                target = nil -- kill the target (see comment on line above).
                app:log( "Starting via jar: ^1", command .. " " .. params )
            else
                app:logE( "Target jar does not exist: ^1", target )
                return -- reminder, this is run as a task, so status returned would be lost.
            end
        else
            app:assert( command, "Jar required for dir/file change notification not found with plugin " )
            params = args
            app:log( "Starting via executable: ^1, params: ^2", command, ( str:is( params ) and params or "none" ) )
        end
        local s, m = app:executeCommand( command, params, target ) -- note: java is a blocking call.
        if s then
            app:logV( "dir-chg-app finished execution, happily" ) -- ###1 consider notifying concerned plugin (so it can restart or whatever).
        else
            app:log( "*** dir-chg-app finished execution, with qualification - ^1", m )
        end
    end }
end



--  start if not already started
--  return s, m
function DirChgApp:assureRunning( appPath )
    if not str:is( appPath ) then
        appPath = app:getPref( 'dirChgApp' ) -- try for standard pref if not passed.
    end
    --Debug.pause( java:isUsable() )
    local status, message
    local started
    local jUsable, jIsnt
    local s, m = app:pcall{ name="DirChgApp_assureRunning", async=false, function( call )
        for try = 1, 4 do
            -- give it a little extra first time around, to reduce potential for erroneous
            -- startup in case it's just being a little slow on the uptake..
            local replied, appStatus, descr = self:getPresence( 7 ) -- note: app has a dedicated thread to "are-you-ready" messages, so should be able to respond fairly promptly if running.
            if replied then -- a reply assures running, regardless of app-status or descr.
                status = true
                message = nil
                return
            elseif not started then -- seems not to be running.
                app:log( "dir-chg-agg app not responding yet, attempted to start it." )
                self:_startRunning( appPath ) -- async
                app:sleep( 7 ) -- give it a chance to run, in case just starting..
                started = true
            elseif try == 3 then
                if gbl:getValue( "java" ) then
                    jUsable, jIsnt = java:isUsable()
                else
                    app:logV( "Java not global, so not checking if usable." )
                end
            else
                app:log( "dir-chg-agg app still not responding, should already be started." )
                app:sleep( 3 ) -- just for the heck of it..
            end
        end
        -- after retries, still not online.
        status = false
        message = "*** Cant start dir-chg app - consider checking/deleting lock file and/or killing existing process."
        if jUsable then
            message = message.." - java is usable on this machine as configured."
        elseif str:is( jIsnt ) then -- usability reason given
            message = message.." - java is not usable on this machine as configured - "..jIsnt
        -- else verbose log is only indication..
        end
    end }
    if s then
        return status, message
    else
        return s, m
    end
end



-- methods which send messages..



-- records is an array of tables whose members include: 'dir' (path), 'events' (bit-mask), 'notifyAddr' (who to notify).
function DirChgApp:register( records, tmo, fromName )
    local s, m = self:assureRunning() -- pref may be nil - will try to start in default way if need be.
    if not s then
        return false, m
    end
    local msg = {}
    msg.name = 'register'
    --msg.localPath = file
    --msg.ftpSettings = tab:copy( settings )
    --local pwDec = msg.ftpSettings.password
    --msg.ftpSettings.password = nil -- passwords must be separate entity.
    --msg.ftpSettings.remoteDirPathForFtpUploadTest = nil -- not supported on far end (and causes it to choke).
    --local pwEnc = encoder.encode( pwDec )
    --msg.ftpPassword = {
    --    server = settings.server,
    --    username = settings.username,
    --    encoded = {
    --        password = pwEnc,
    --    }
    --}
    msg.records = records
    local to = "com.robcole.DirFileChangeNotifierApp"
    tmo = tmo or 10
    local reply, errm = self.comm:sendAndReceive( msg, to, tmo, fromName ) -- initial reply comes pronto (prior to uploading).
    -- when directory changes, dir-chg (app) will send an "unsolicited" message, which is to be handled by the client plugin.
    if reply then
        return true
    else
        return false, "no reply - "..(errm or "no errm")
    end
end



return DirChgApp
