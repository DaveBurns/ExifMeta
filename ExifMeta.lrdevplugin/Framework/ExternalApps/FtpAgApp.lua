--[[
        FtpAgApp.lua
        
        Interface to FTP Aggregator (Java) App.
--]]


local FtpAgApp, dbg, dbgf = Object:newClass{ className = 'FtpAgApp', register = true }



--- Constructor for extending class.
--
function FtpAgApp:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage pass pref-name, win-exe-name, or mac-pathed-name, if desired, else rely on defaults (but know what they are - see code).
--
function FtpAgApp:new( t )
    local o = Object.new( self, t )
    app:assert( gbl:getValue( 'Ftp' ), "global Ftp class needed for password query." )
    app:assert( gbl:getValue( 'encoder' ), "global encoder required." )
    local ad, er = fso:getAppDataDir() -- system/user app-data dir
    if ad then
        ad = LrPathUtils.child( ad, "com.robcole" )
        ad = LrPathUtils.child( ad, "FTPAggregator" ) -- hard-coded - companion app just needs to hard-code to same thing.
    else
        app:error( "no app-data dir: ^1", er )
    end
    o.rootDir = ad
    o.srvcDir = LrPathUtils.child( o.rootDir, "FtpServices" )
    -- note: it's a tad presumptuous for ftp-app i/f to assume there will be a background process, but hey - we're all friends here, right? ;-}.
    o.comm = Intercom:new{ dir=ad, simpleXml=true, pollingInterval=1, addlNames=o.addlNames } -- used for communication with ftp aggregator app.
    -- I suppose cleanup could be built into intercom, but, well, it's not..
    -- note: we're cleaning up for entities we're sending *to*, in case they're not running healthily (to avoid excessive expired messages..)
    o.comm:scheduleCleanup( { 'com.robcole.FtpAggregatorApp' }, 60 ) -- cleanup messages sent to ftp-aggragator that might not otherwise get cleaned up. 60 is the default,
        -- this could probably be much larger, since receiver shouldn't respond to expired messages, and does it's *own* cleanup if it's running..
    o.comm:listen ( 
        o.processMessage, -- callback func
        o, -- callback obj - default is this object, but could be object of callers choice.
        nil, -- from-addr-list
        1 -- listen polling interval.
    )
    return o
end



--- Set custom callback for unsolicited messages.
--
--  @usage Be careful to handl all possbilities, and try not to stomp on other callbacks..
--
--  @param callbackFuncOrMeth -- function (or method) to call (required) - passing message object as only parameter.
--  @param callbackObj -- object (optional) in which case the previously mentioned will be called as object method.
--
--  @return previous callback func-or-meth (nil if none).
--  @return previous callback obj(ect) (nil if none).
--
function FtpAgApp:setMessageCallback( callbackFuncOrMeth, callbackObj )
    local func = self.callbackFuncOrMeth
    local obj = self.callbackObj
    self.callbackFuncOrMeth, self.callbackObj = callbackFuncOrMeth, callbackObj
    return func, obj
end



--- Processor for incoming (unsolicited) messages.
--
--  @usage simply logs received comment unless error - which gets alert/log treatment.
--  @usage calling context can set it's own callback
--
--  @param msg message
-- 
function FtpAgApp:processMessage( msg )
    --Debug.pause( msg.name, msg )
    if self.callbackFuncOrMeth then
        if self.callbackObj then
            self.callbackFuncOrMeth( self.callbackObj, msg ) -- meth
        else
            self.callbackFuncOrMeth( msg ) -- func
        end
    else
        if msg.name == 'synced' then
            app:log( msg.comment )
        elseif msg.name == 'uploaded' then
            app:log( msg.comment )
        elseif msg.name == 'error' then
            app:alertLogE( msg.comment )
        else
            Debug.pause( msg )
        end
    end
end



function FtpAgApp:getServiceDir()
    return self.srvcDir
end



--  Initialize persistent ftp service, given full service name (service-type + service-instance-name), and ftp-settings.
--  password will be obtained from user if not already in settings or encrypted store.
--  return job-num, msg.
function FtpAgApp:initService( _srvcSettings, _ftpSettings, _ftpPropertyMap )
    local srvcName = _srvcSettings.serviceName
    app:log( "Initializing FTP service: ^1", srvcName )
    local localPath = _srvcSettings.localRootPath or app:callingError( "Need local-root-path in service settings." )
    -- warning: query-func assumes standard mapping for server, username, and password fields ###1.
    local ok = Ftp.assurePassword( _ftpSettings, _ftpPropertyMap ) -- installs password in place in whatever table is passed. ###2 (maybe should just return password, then calling context can handle as desired).
    if not ok then
        return nil, "No password"
    end
    local pwEnc = encoder.encode( _ftpSettings.password )
    local ftpSettings = tab:copy( _ftpSettings )
    ftpSettings.password = nil
    local path = LrPathUtils.child( self.srvcDir, srvcName )
    app:logV( "Service directory: ^1", path )
    local jobsDir = LrPathUtils.child( path, "jobs" )    
    local s, m = fso:assureDir( jobsDir )
    if not s then
        return nil, m
    end
    local maxJobNum = 0
    for de in LrFileUtils.directoryEntries( jobsDir ) do
        if LrFileUtils.exists( de ) == 'directory' then
            local dirName = LrPathUtils.leafName( de )
            local splt = str:split( dirName, " " )
            if splt == 2 and splt[2] == "job" then
                local jobNum = num:numberFromString( splt[1] )
                if jobNum > maxJobNum then
                    maxJobNum = jobNum
                end
            else
                app:logV( "Bogus dir in with the jobs: ^1", dirName )
            end
        end
    end
    local srvcSettings = {
        serviceName = srvcName,
        localRootPath = localPath,
        ftpSettings = ftpSettings,
    }
    path = LrPathUtils.child( path, "service_settings.txt" )
    local ser = simpleXml:serializeLua( "serviceConfig", srvcSettings )
    local s, m = fso:writeAtomically( path, ser )
    if not s then
        --app:error( m )
        return nil, m
    end
    local ftpPassword = { -- not real crazy about replicating server & username, but maybe it's not bad to have belt along with suspenders..
        server = ftpSettings.server,
        username = ftpSettings.username,
        --decoded={password="mypassword"}, -- works (companion excepts password in either encoded or decoded form).
        encoded = { password=pwEnc }, -- works too (and after testing, passwords should be encoded only).
    }
    path = LrPathUtils.child( self.rootDir, "FtpPasswords" )
    path = LrPathUtils.child( path, ftpSettings.server.."_"..ftpSettings.username..".txt" )
    local ser = simpleXml:serializeLua( "ftpPassword", ftpPassword )
    local s, m = fso:writeAtomically( path, ser )
    if not s then
        return nil, m -- app:error( m )
    end
    return maxJobNum + 1
end



function FtpAgApp:initJob( srvcName, jobNum )
    local dir
    dir = LrPathUtils.child( self.rootDir, "FtpServices" )
    dir = LrPathUtils.child( dir, srvcName )
    dir = LrPathUtils.child( dir, "jobs" )
    dir = LrPathUtils.child( dir, str:fmtx( "^1 job", string.format( "%03u", jobNum ) ) )
    return fso:assureDir( dir )
end



-- logs progress/status, so wrap in a service externally.
--
function FtpAgApp:clearJobs( srvcName, props )
    local dir
    dir = LrPathUtils.child( self.rootDir, "FtpServices" )
    dir = LrPathUtils.child( dir, srvcName )
    dir = LrPathUtils.child( dir, "jobs" )
    app:logV( "Service jobs directory: ^1", dir )
    local cleared = true
    if fso:existsAsDir( dir ) then
        app:logv( "Jobs dir exists: ^1", dir )
        for path in LrFileUtils.directoryEntries( dir ) do
            if LrFileUtils.exists( path ) == 'directory' then
                local leaf = LrPathUtils.leafName( path )
                local splt = str:split( leaf, " " )
                local jobNum
                if #splt == 2 and splt[2] == "job" then
                    jobNum = num:getNumberFromString( splt[1] )
                    if jobNum ~= nil then -- its definitely a job directory.
                        if fso:isDirEmpty( path ) then
                            app:log( "Deleting empty job directory: ^1", path )
                            local s, m = LrFileUtils.delete( path ) -- deletes even non-empty trees, from the sound of the doc.
                            if not s then
                                app:logErr( m or str:fmtx( "Unable to delete empty job directory: ^1", path ) )
                                cleared = false
                            end
                        else
                            app:log( "Deleting non-empty job directory: ^1", path )
                            local s, m = LrFileUtils.delete( path ) -- deletes even non-empty trees, from the sound of the doc.
                            if not s then
                                app:logErr( m or str:fmtx( "Unable to delete non-empty job directory: ^1", path ) )
                                cleared = false
                            end
                        end
                    else
                        app:logWarning( "Non-job folder in jobs directory shouldn't be there, but \"I\" shan't delete it, but maybe you should: ^1", path ) 
                        cleared = false
                    end
                end
            elseif LrFileUtils.exists( path ) == 'file' then
                app:logWarning( "Unexpected file found in jobs directory which shouldn't be there, but \"I\" shan't delete it, but maybe you should: ^1", path ) 
                cleared = false
            else
                app:logWarning( "Directory entry disappeared: ^1", path )
                -- cleared = false - probably shouldn't affect 'cleared' status, but makes me nervous.
            end
        end
        -- leave jobs dir in place so app doesn't croak.
    else
        app:log( "Jobs dir does not exist (^1) - nothing to clear.", dir )
    end
    
    if cleared then
        app:log( "All jobs are cleared." )
        --self.jobNum = 0
        --cat:setPropertyForPlugin( "jobNum", self.jobNum, true ) -- true => validate.
        -- service finale message suffices.
    else
        -- warnings and errors already logged.
    end
    
    return cleared
    
end



function FtpAgApp:quit( tmo )
    local msg = {
        name = "quit",
        comment = "please",
    }
    local to = "com.robcole.FTPAggregatorApp" -- hardcoded (maybe should be a "literal" ###2).
    tmo = tmo or 10
    local reply, errm = self.comm:sendAndReceive( msg, to, tmo )
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
function FtpAgApp:getPresence( tmo, fromName )
    local msg = {
        name = "areYouReady?",
    }
    --local to = "com.robcole.FTPAggregator" -- for testing.
    local to = "com.robcole.FTPAggregatorApp" -- hardcoded (make "literal" ###2).
    tmo = tmo or 30 -- pass a shorter tmo if presence expected by now..
    local reply, errm = self.comm:sendAndReceive( msg, to, tmo, fromName )
    if reply then
        local twoChars = LrStringUtils.lower( ( reply.comment or "" ):sub( 1, 2 ) )
        if twoChars == 'on' then
            return true, 'online', "Online - FTP is enabled"
        elseif twoChars == 'of' then
            return true, 'disabled', "Running, but FTP is disabled (offline)"
        else
            Debug.pause( reply.comment )
            return true, 'wonky', "Running, but not replying as expected - hmm..."
        end
    else
        Debug.pauseIf( not str:is( errm ), "no errm" ) -- ###2 (I think it's still possible for no errm, but since root problem solved, not seeing this any more).
        local status = app:getGlobalPref( 'ftpAppStatus' ) -- ###2 probably does not need to be global pref anymore.
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
function FtpAgApp:_startRunning( appPath )
    app:pcall{ name="FtpAgApp_startRunning", async=true, guard=App.guardSilent, function( call )
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
                    -- FTP Agg app is downloaded and installed in standard, NetBeans fashion: in user-local-app-data location.
                    local ad, er = fso:getAppDataDir( "Local" ) -- e.g. C:\Users\Rob\AppData\Local
                    if ad then
                        local appDir = LrPathUtils.child( ad, "FtpAgg" ) -- hard-coded.
                        if LrFileUtils.exists( appDir ) == 'directory' then
                            local appFile = LrPathUtils.child( appDir, "FtpAgg.exe" )
                            if fso:existsAsFile( appFile ) then
                                command = appFile
                                -- no params, no target.
                            else
                                app:logW( "*** FTP Aggregator App executable is missing: '^1', will try to run built-in java app, but such is not the recommended configuration on Windows - to eliminate this warning, specify path to executable explicitly, or re-install FTP Aggregator application.", appFile )
                                tryJar = true
                            end
                        else
                            app:logW( "*** FTP Aggregator App is not installed (in '^1' directory) - will try to run jar via java, but such is not the recommended configuration on Windows - to eliminate this warning, specify path to executable explicitly, or install FTP Aggregator application.", appDir )
                            tryJar = true
                        end
                    else
                        app:logW( "*** Can not find local app-data directory in which FTP Aggregator App was expected (err-msg: ^1) - will try to run jar via java, but such is not the recommended configuration on Windows - to eliminate this warning, specify path to executable explicitly, after installing FTP Aggregator application.", er )
                        tryJar = true
                    end
                else -- Mac
                    app:logV( "Will try to run built-in java app for FTP services." )
                    tryJar = true
                end
            else -- development mode - get ftp app from local dev dir. - tested on Windows.
                target = LrPathUtils.child( "X:\\Dev\\AppsJava\\FtpAgg\\dist", "FtpAgg.jar" ) -- Executor is smart enough to detect string vs. array.
                isJar = true
            end
        end
        if tryJar then -- not already commited to jar, but ready to try it.
            Debug.pauseIf( isJar, "oops" ) -- this never happens.
            local appDir = LrPathUtils.child( _PLUGIN.path, "FtpAggApp" )
            if fso:existsAsDir( appDir ) then
                local appFile = LrPathUtils.child( appDir, "FtpAgg.jar" )
                if fso:existsAsFile( appFile ) then
                    isJar = true -- defines command and parameters.
                    target = appFile
                else
                    app:logE( "FTP Aggregator app not in expected location: ^1", appFile )
                    app:show{ error="FTP Aggregator app not in expected location: ^1", appFile }
                    return                    
                end
            else
                app:logE( "FTP Aggregator app not in expected location: ^1", appDir )
                app:show{ error="FTP Aggregator app not in expected location: ^1", appDir }
                return                    
            end
        -- else nada here.
        end
        local argBuf = {}
        local verbose = fprops:getPropertyForPluginSpanningCatalogs( 'com.robcole.FtpAggregator', 'ftpAppVerbose' )
        local online = fprops:getPropertyForPluginSpanningCatalogs( 'com.robcole.FtpAggregator', 'ftpAppOnline' )
        local dateTol = fprops:getPropertyForPluginSpanningCatalogs( 'com.robcole.FtpAggregator', 'ftpAppDateTol' )
        --Debug.pause( verbose, online, dateTol )
        if verbose then
            argBuf[#argBuf + 1] = "--log=v" -- erbose
        -- else default is normal.
        end
        if not online then
            argBuf[#argBuf + 1] = "--online=off" -- line
        -- else default is online.
        end
        if dateTol ~= nil then
            argBuf[#argBuf + 1] = "--dateTol="..dateTol -- % (10's of seconds).
        else
            Debug.pause( "Date tolerance not specified." )
        end
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
            app:assert( command, "Jar required for FTP not found with plugin " )
            params = args
            app:log( "Starting via executable: ^1, params: ^2", command, ( str:is( params ) and params or "none" ) )
        end
        local s, m = app:executeCommand( command, params, target ) -- note: java is a blocking call.
        if s then
            app:logV( "ftp-app finished execution, happily" )
        else
            app:log( "*** ftp-app finished execution, with qualification - ^1", m )
        end
    end }
end



--  start if not already started
--  return s, m
function FtpAgApp:assureRunning( appPath )
    if not str:is( appPath ) then
        appPath = app:getPref( 'ftpAggApp' ) -- try for standard pref if not passed.
    end
    --Debug.pause( java:isUsable() )
    local status, message
    local started
    local jUsable, jIsnt
    local s, m = app:pcall{ name="FtpAgApp_assureRunning", async=false, function( call )
        for try = 1, 4 do
            -- give it a little extra first time around, to reduce potential for erroneous
            -- startup in case it's just being a little slow on the uptake..
            local replied, appStatus, descr = self:getPresence( 7 ) -- note: app has a dedicated thread to "are-you-ready" messages, so should be able to respond fairly promptly if running.
            if replied then -- a reply assures running, regardless of app-status or descr.
                status = true
                message = nil
                return
            elseif not started then -- seems not to be running.
                app:log( "ftp-agg app not responding yet, attempted to start it." )
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
                app:log( "ftp-agg app still not responding, should already be started." )
                app:sleep( 3 ) -- just for the heck of it..
            end
        end
        -- after retries, still not online.
        status = false
        message = "*** Cant start ftp app - consider checking/deleting lock file and/or killing existing process."
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



function FtpAgApp:_assureJobDir( srvcName, jobNum, justGet )
    local jobNumPadded = string.format( "%03u", jobNum )
    
    local dir
    dir = LrPathUtils.child( self.rootDir, "FtpServices" )
    dir = LrPathUtils.child( dir, srvcName )
    --app:logV( "Service directory: ^1", path )
    dir = LrPathUtils.child( dir, "jobs" )
    dir = LrPathUtils.child( dir, str:fmtx( "^1 job", jobNumPadded ) )
    if justGet then return dir end
    local s, m = fso:assureDir( dir )
    if s then
        return dir
    else
        return nil, m or "no m"
    end
end



--- Upload a file as part of job distinguished by directory.
--
--  @param file (string, required) path to local file to upload.
--  @param jobDir (string, required) path to jobdir to place "ref" file.
--  @param index (number, required) command sequence number.
--
function FtpAgApp:uploadFile( srvcName, file, jobNum, taskNum )

    app:callingAssert( taskNum, "no task num" )

    local dir, err = self:_assureJobDir( srvcName, jobNum )
    if dir then
        -- 
    else
        return false, err
    end
    
    local _path = LrPathUtils.child( dir, string.format( "%03u upload_file.txt", taskNum ) )
    local path = LrFileUtils.chooseUniqueFileName( _path )
    
    if path == _path then -- task filename was unique already.
        -- good
    else -- shouldn't happen under normal circumstances, but does sometimes happen during debug, if things are wonked.
        local c, m = fso:readFile( _path )
        if str:is( c ) then
            if c == file then
                app:logWarning( "upload of said file already scheduled at index: ^1", taskNum )
                return true -- for purpose of calling context, all is well.
            else
                app:logWarning( "upload of already specified at index: ^1", taskNum )
                -- go-ahead and schedule one with uniqueness suffix.
            end
        elseif str:is( m ) then -- error
            app:logWarning( "unable to read upload control file for confirmation - ^1", m )
            -- write the new file with unique name, keeping the old one, for now.
        else -- no error, just empty file.
            path = _path -- overwrite empty file.
        end
    end
    
    local s, m = fso:writeAtomically( path, file )
    if s then
        app:logVerbose( "File to upload (^1), written to ^2", file, path )
        return true
    else
        return false, m
    end

end



--- Determine what job dir is or would be without actually creating it, yet.
--
function FtpAgApp:getJobDir( srvcName, jobNum )
    return self:_assureJobDir( srvcName, jobNum, true ) -- just get
end



--- Purge a file as part of job distinguished by directory.
--
--  @param file (string, required) path to local file to upload.
--  @param jobDir (string, required) path to jobdir to place "ref" file.
--  @param index (number, required) command sequence number.
--
function FtpAgApp:purgeFile( srvcName, file, jobNum, taskNum )

    app:callingAssert( taskNum, "no task num" )

    local dir, err = self:_assureJobDir( srvcName, jobNum )
    if dir then
        -- 
    else
        return false, err
    end
    
    local _path = LrPathUtils.child( dir, string.format( "%03u purge_file.txt", taskNum ) )
    local path = LrFileUtils.chooseUniqueFileName( _path )
    
    if path == _path then -- task filename was unique already.
        -- good
    else -- shouldn't happen under normal circumstances, but does sometimes happen during debug, if things are wonked.
        local c, m = fso:readFile( _path )
        if str:is( c ) then
            if c == file then
                app:logWarning( "purge of said file already scheduled at index: ^1", taskNum )
                return true -- for purpose of calling context, all is well.
            else
                app:logWarning( "file purge already specified at index: ^1", taskNum )
                -- go-ahead and schedule one with uniqueness suffix.
            end
        elseif str:is( m ) then -- error
            app:logWarning( "unable to read file-purge control file for confirmation - ^1", m )
            -- write the new file with unique name, keeping the old one, for now.
        else -- no error, just empty file.
            path = _path -- overwrite empty file.
        end
    end
    
    local s, m = fso:writeAtomically( path, file )
    if s then
        app:logVerbose( "File to purge (^1), written to ^2", file, path )
        return true
    else
        return false, m
    end

end



--- Purge a folder as part of job distinguished by directory.
--
--  @param file (string, required) path to local file to upload.
--  @param jobDir (string, required) path to jobdir to place "ref" file.
--  @param index (number, required) command sequence number.
--
function FtpAgApp:purgeFolder( srvcName, file, jobNum, taskNum )

    app:callingAssert( taskNum, "no task num" )

    local dir, err = self:_assureJobDir( srvcName, jobNum )
    if dir then
        -- 
    else
        return false, err
    end
    
    local _path = LrPathUtils.child( dir, string.format( "%03u purge_folder.txt", taskNum ) )
    local path = LrFileUtils.chooseUniqueFileName( _path )
    
    if path == _path then -- task filename was unique already.
        -- good
    else -- shouldn't happen under normal circumstances, but does sometimes happen during debug, if things are wonked.
        local c, m = fso:readFile( _path )
        if str:is( c ) then
            if c == file then
                app:logWarning( "purge of said folder already scheduled at index: ^1", taskNum )
                return true -- for purpose of calling context, all is well.
            else
                app:logWarning( "folder purge already specified at index: ^1", taskNum )
                -- go-ahead and schedule one with uniqueness suffix.
            end
        elseif str:is( m ) then -- error
            app:logWarning( "unable to read purge-folder control file for confirmation - ^1", m )
            -- write the new file with unique name, keeping the old one, for now.
        else -- no error, just empty file.
            path = _path -- overwrite empty file.
        end
    end
    
    local s, m = fso:writeAtomically( path, file )
    if s then
        app:logVerbose( "Folder to purge (^1), written to ^2", file, path )
        return true
    else
        return false, m
    end

end



--- End job distinguished by directory.
--
--  @param jobDir (string, required) path to jobdir to place "ref" file.
--  @param index (number, required) command sequence number.
--
function FtpAgApp:endOfJob( srvcName, jobNum, taskNum )

    app:callingAssert( taskNum, "no task num" )
    
    local jobNumPadded = string.format( "%03u", jobNum )
    
    local dir
    dir = LrPathUtils.child( self.rootDir, "FtpServices" )
    dir = LrPathUtils.child( dir, srvcName )
    --app:logV( "Service directory: ^1", path )
    dir = LrPathUtils.child( dir, "jobs" )
    dir = LrPathUtils.child( dir, str:fmtx( "^1 job", jobNumPadded ) )
    if not LrFileUtils.exists( dir ) then
        return true -- yes: if no such job dir, then end-of-job func is a no-op (it means start-job wasn't successful or some such thing.
    end
    
    local _path = LrPathUtils.child( dir, string.format( "%03u end_of_job", taskNum ) )
    local path = LrFileUtils.chooseUniqueFileName( _path )
    
    if path == _path then -- dir was unique already.
        -- good
    else
        app:logWarning( "end-of-job already specified at index: ^1", taskNum )
        -- since contents are a dont care, no point in re-writing an end_of_job file.
        return true
    end
    
    local s, m = fso:writeAtomically( path, "X" ) -- data is a dont care.
    if s then
        app:logVerbose( '"end-of-job" written to ^1', path )
        return true
    else
        return false, m
    end
end


-- methods that don't required service setup (on-the-fly / one shots):
-- (for example plugin-generator release.lua, or ftp-aggregator plugin's ad-hoc upload facility)


function FtpAgApp:xUploadFile( settings, file, tmo )
    local s, m = self:assureRunning() -- pref may be nil - will try to start in default way if need be.
    if not s then
        return false, m
    end
    local msg = {}
    msg.name = 'uploadFile'
    msg.localPath = file
    msg.ftpSettings = tab:copy( settings )
    local pwDec = msg.ftpSettings.password
    msg.ftpSettings.password = nil -- passwords must be separate entity.
    msg.ftpSettings.remoteDirPathForFtpUploadTest = nil -- not supported on far end (and causes it to choke).
    local pwEnc = encoder.encode( pwDec )
    msg.ftpPassword = {
        server = settings.server,
        username = settings.username,
        encoded = {
            password = pwEnc,
        }
    }
    local to = "com.robcole.FTPAggregatorApp"
    tmo = tmo or 10
    local reply, errm = self.comm:sendAndReceive( msg, to, tmo ) -- initial reply comes pronto (prior to uploading).
    -- when uploading is complete, ftp-agg (app) will send an "unsolicited" completion message, which can be fielded
    -- by the client plugin, or not, as it sees fit.
    if reply then
        return true
    else
        return false, "no reply - "..(errm or "no errm")
    end
end


function FtpAgApp:xSyncDir( settings, dir, purgeToo, tmo )
    local s, m = self:assureRunning() -- pref may be nil - will try to start in default way if need be.
    if not s then
        return false, m
    end
    local msg = {}
    msg.name = 'syncDir'
    msg.localPath = dir
    if purgeToo then
        msg.comment = 'fullSync'
    else
        msg.comment = 'noPurge'
    end
    msg.ftpSettings = tab:copy( settings )
    local pwDec = msg.ftpSettings.password
    msg.ftpSettings.password = nil -- passwords must be separate entity.
    msg.ftpSettings.remoteDirPathForFtpUploadTest = nil -- not supported on far end (and causes it to choke).
    local pwEnc = encoder.encode( pwDec )
    msg.ftpPassword = {
        server = settings.server,
        username = settings.username,
        encoded = {
            password = pwEnc,
        }
    }
    local to = "com.robcole.FTPAggregatorApp"
    tmo = tmo or 10
    local reply, errm = self.comm:sendAndReceive( msg, to, tmo )
    if reply then
        return true
    else
        return false, "no reply - "..(errm or "no errm")
    end
end


return FtpAgApp
