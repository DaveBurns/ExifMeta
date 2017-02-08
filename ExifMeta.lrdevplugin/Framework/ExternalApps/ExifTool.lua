--[[
        ExifTool.lua
        
        Initial motivation for this extended external-app class dedicated to exif-tool was
        the ability to support multiple simultaneous exif-tool sessions.
        
        Initial application was for preview-exporter which uses preview and image class objects.
        
        It is recommended to have one session per task / service, since if two async tasks
        shared the same session there would be interleaving of arguments...
        
        Examples:
        
            -- initiate persistent background service that uses exiftool.
            app:call( Service:new{ name="My Background Service", async=true, main=function( call )
                local ets = exifTool:openSession( call.name )
                for ever do efficiently
                    wait() -- for timer
                    ets:addArg( "-..." )
                    ets:addArg( "-..." )
                    ets:addTarget( path )
                    local result, errorMessage = ets:execute()
                    -- process result or error message.
                end
                exifTool:closeSession( ets )
            end } )

            -- initiate transient "foreground" service, not to interfere with persistent background service.            
            app:call( Service:new{ name="My Imaging Service", async=true, main=function( call )
                local ets = exifTool:openSession( call.name )
                for awhile do efficiently
                    ets:addArg( "-..." )
                    ets:addArg( "-..." )
                    ets:addTarget( path )
                    local result, errorMessage = ets:execute()
                    -- process result or error message.
                    yc = app:yield( yc )
                end
                exifTool:closeSession( ets )
            end } )
--]]


local ExifTool, dbg, dbgf = ExternalApp:newClass{ className = 'ExifTool', register = true }



--- Constructor for extending class.
--
function ExifTool:newClass( t )
    return ExternalApp.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage pass pref-name, win-exe-name, or mac-pathed-name, if desired, else rely on defaults (but know what they are - see code).
--
function ExifTool:new( t )
    t = t or {}
    t.name = t.name or "ExifTool"
    t.prefName = t.prefName or 'exifToolApp' -- same pref-name for win & mac.
    t.winExeName = t.winExeName or "exiftool.exe" -- if included with plugin - may not be.
    t.macAppName = t.macAppName or "exiftool" -- if included with plugin, also: pre-requisite condition for mac-default-app-path to be used instead of mac-pathed-name, if present on system.
    t.winDefaultExePath = nil -- no default install dir for exiftool on Windows, I don't think (recommend including with plugin anyway).
    t.macDefaultAppPath = "/usr/bin/exiftool" -- @21/Jul/2012, this is the default location for exiftool on Mac. If present there, and not overridden via some other mechanism, use it as last resort, if present on system.
    t.winPathedName = nil -- pathed access to exiftool not supported.
    t.macPathedName = nil -- was t.macPathedName or 'exiftool' until 21/Jul/2012 (RDC) -- hope no plugin was depending on this - default install path should accomplish the same thing.
    local o = ExternalApp.new( self, t )
    o.reg = {} -- session registry
    return o
end



local Session = Object:newClass{ className = 'ExifToolSession', register = false } -- uses module dbg func.



--  Constructor for new instance.
--
function Session:_new( _name )
    local o = Object.new( self, { name=_name } )
    return o
end


--- Determine if session or exiftool proper.
function Session:isSession()
    return true
end



function Session:getVersionString()
    self:addArg( "-ver" )
    local a, b, c = self:execute()
    if a ~= nil and type( a ) == 'string' and a ~= "" then
        return LrStringUtils.trimWhitespace( a )
    else
        Debug.pause( a, b, c ) -- this can happen if reload each export is enabled.
        return nil, "unable to get exiftool version in session mode" -- ###2 probably could return better errm info.
    end
end



--  Initialize newly created session for use.
--
function Session:_open( exe, cfg )
    local dir = LrPathUtils.getStandardFilePath( 'temp' ) -- at the moment cant imagine why standard temp dir wouldn't be perfectly appropriate.
    local iname = str:makeFilenameCompliant( self.name ) .. "_exiftool-argbufile_" -- changed 25/Oct/2014 20:47 to make filename compliant, since name may be "anything".
    local oname = str:makeFilenameCompliant( self.name ) .. "_exiftool-pipeout_" -- ditto.
    self.originalInputFile = LrPathUtils.child( dir, LrPathUtils.addExtension( iname, "txt" ) )
    local ifile = LrFileUtils.chooseUniqueFileName( self.originalInputFile ) -- don't overwrite an existing file.
    self.originalOutputFile = LrPathUtils.child( dir, LrPathUtils.addExtension( oname, "txt" ) )
    local ofile = LrFileUtils.chooseUniqueFileName( self.originalOutputFile ) -- don't overwrite an existing file.
    self.seq = 1
    app:logVerbose( "Exiftool session opening: ^1", self.name )
    local status, result = pcall( io.open, ifile, "wb" ) -- create for writing binary.
    if status then
        assert( result, "not result" )
        self.cmdfile = result
        self.args = {}
        self.targs = {}
        --Debug.pause( exe, ifile )
        local tb = ""
        if str:is( cfg ) then
            if fso:existsAsFile( cfg ) then
                tb = '-config "' .. cfg .. '" '
            else
                app:callingError( "Unable to open exiftool session - requiste config file does not exist: ^1", cfg )
            end
        end
        
        -- start command task:
        app:pcall{ name = "ExifTool command task", async=true, main=function( call )
            local s, m = app:executeCommand( exe, str:fmtx( '^2-stay_open 1 -@ "^1"', ifile, tb ), nil, ofile )
            if s then
                app:logVerbose( "Exiftool command returned from listening to '^1'", ifile )
            else
                app:logVerbose( "Exiftool session '^1' ended.", str:to( self.name ) ) -- with error: ^2", self.name, m ) - it always ends with an error - don't trip...
            end
        end, finale=function( call, status, message )
            if self.cmdfile ~= nil and fso:existsAsFile( ifile ) then
                pcall( self.cmdfile.close, self.cmdfile )
                
                -- added 21/Nov/2012 1:17 ###2 risky, but avoids error, and potential accumulation of cmd (temp) files. Delete comment if no issues come 2016.
                self.cmdfile = nil
                
                --Debug.pause()
                LrFileUtils.delete( ifile )
                self.args = {} -- not being set to nil, since cmdfile isn't.
                self.targs = {} -- ditto
                
                -- ###3 does seem like everything oughta be closed up tight here, but must've been a reason it wasn't (?)
                
            end
        end }
        app:logVerbose( "Exiftool command-task '^1' started with input argbufile '^2' and response output file: ^3", self.name, str:to( ifile ), str:to( ofile ) )
        
        -- start response task:
        app:pcall{ name = "ExifTool response task", async=true, main=function( call )
        
            self.respfile = nil
            while not shutdown do -- checking for shutdown OK unless "reload on export" set.
                self.respfile = io.open( ofile, 'rb' )
                if self.respfile then
                    dbgf( "Got response file open." )
                    break
                else
                    LrTasks.sleep( .01 ) -- response file should be created rather quickly by exiftool.
                end
            end
        
            if self.respfile then
                local resp = ""
                local chunk = 0
                local index = 1
                local rcvd = 0
                while not shutdown and not self.closed do
    
                    --Debug.logn( "Polling for input" )
                    local s, x = self.respfile:read( 10000000 ) -- read up to 10MB, that oughta do it...
                    if s ~= nil then
                        --rcvd = rcvd + x
                        if x ~= nil then
                            Debug.pause( "x is nil" )
                        end
                        --Debug.logn( "read", self.seq, s, x )
                        chunk = chunk + 1
                        -- Note: presumbly works when response is binary too, e.g. with zeros(?)
                        resp = resp .. s
                        local readyStr = str:fmt( "{ready^1}", self.seq ) -- may still need to squirt out a cr and/or lf.
                        local p1, p2 = resp:find( readyStr, index )
                        if p1 then
                            self.rsp = resp:sub( 1, p1 - 1 ) -- response doubles as task sync flag.
                            chunk = 0 -- aesthetic only: so chunk numbers are relative.
                            index = 1
                            rcvd = 0
                            resp = resp:sub( p2 + 1 )
                            --Debug.logn( "Chunk " .. chunk .. ", seq #" .. self.seq .. " - response finished: " .. self.rsp )
                            dbgf( "Chunk " .. chunk .. ", seq #" .. self.seq .. " - response finished." )
                        else
                            --Debug.logn( "response to req #" .. self.seq .. " not finished @chunk #" .. chunk .. ": " .. resp )
                            dbgf( "response to req #" .. self.seq .. " not finished @chunk #" .. chunk )
                            local len = resp:len()
                            local readyLen = readyStr:len()
                            if len > readyLen then
                                index = len - readyLen -- next time look again, but make sure to backtrack enough to ensure getting all of {ready1324567890,,.}, in case last read ended in the middle of it.
                            else
                                index = 1
                            end
                        end
                    else
                        --Debug.logn( "No read" )
                        --break
                    end
                    LrTasks.sleep( .01 )
    
                end
                
                if shutdown and not self.closed then
                    self:_close()
                elseif self.closed then
                    self.respfile:close()
                    LrFileUtils.delete( ofile )
                    -- LrShell.revealInShell( ofile )
                    self.respfile = nil
                end
                
            else
                Debug.logn( "No response file." )
            end
            
            
        end }
        app:logVerbose( "Exiftool response task started '^1', response expected in file: ^2", self.name, ofile )
        app:log( "Exiftool session opened: ^1.", self.name )
    else
        app:error( "Exiftool Argbufile (^1) could not be opened for writing, error message: ^2", str:to( ifile ), str:to( result ) )
    end
end



function Session:getName()
    return self.name or "no name"
end



--- Accumulate argument.
--
function Session:addArg( arg ) -- ###2 I tried to add variable args (for passing to str-fmtx) but it went to hell in a bucket - very strange / no clue.., yet.
    app:callingAssert( type( arg ) == 'string', "arg must be string, not ^1", type( arg ) )
    if arg:find( '""' ) then -- ###2 consider removing this test if no incidents come 2014.
        Debug.pause( "extraneous double quotes?" )
    end
    if self.closed then
        Debug.pause( "session is closed for args" )
        return
    end
    if self.cmdfile then
        local s, m = pcall( self.cmdfile.write, self.cmdfile, arg .. "\n" ) -- for exiftool
        if s then
            self.args[#self.args + 1] = arg -- for calling context
        else
            Debug.pause( "Error writing arg to (presumably closed) cmdfile for session:", self.name )
        end
    end
end



--- Accumulate target.
--
function Session:addTarget( target )
    if self.closed then
        Debug.pause( "session is closed for targets" )
        return
    end
    if self.cmdfile then
        self.cmdfile:write( target .. "\n" ) -- for exiftool.
        self.targs[#self.targs + 1] = target -- for calling context
    end
end



--- Get equivalent argument string.
--
--  @usage excludes quotes around args and targs, so not exactly equivalent, but representative.
--
function Session:getArgumentString()
    if not tab:isEmpty( self.args ) then
        if not tab:isEmpty( self.targs ) then
            return table.concat( self.args, " " ) .. " " .. table.concat( self.targs, " " )
        else
            return table.concat( self.args, " " )
        end
    elseif not tab:isEmpty( self.targs ) then
        return table.concat( self.targs, " " )
    else
        return ""
    end
end



--- Clears the argument string as perceived by outside world.
--
--  @usage      There is no way to revoke arguments already added to a session - they *will* be executed, either by 'execute' or upon closing.
--
function Session:clearArgumentString()
    self.args = {}
    self.targs = {}
end



--- Set target array.
--
function Session:setTargets( targets )
    if self.closed then
        Debug.pause( "session is closed" )
        return
    end
    for k, v in ipairs( targets ) do
        self:addTarget( v )
    end
end



--- Set single target.
--
function Session:setTarget( target )
    self:setTargets{ target }
end



--- Execute accumulated arguments.
--
--  @return response (string) exiftool response, or nil if none.
--  @return message (string) error message if no response.
--  @return equiv (string) equivalent command executed, if it got that far.
--
function Session:execute( tmo )
    if self.closed then
        Debug.pause( "session is closed" )
        return nil, "unable to execute - session is closed"
    end
    tmo = tmo or 30 -- hard to imagine an exifool command taking more than 30 seconds to execute.
    local tm = LrDate.currentTime()
    local msg
    self.rsp = nil
    local equiv
    if self.cmdfile then
        if app:isAdvDbgEna() then
            equiv = 'exiftool '..self:getArgumentString() -- not actual, but should be very close.
            app:logV( "ExifTool session executed equivalent command: ^1", equiv )
        end
        self.cmdfile:write( str:fmt( "-execute^1\n", self.seq ) )
        self.cmdfile:flush()
        self.args = {}
        self.targs = {}
        local count = 1
        while self.rsp == nil do
            app:sleepUnlessShutdown( .01 * count ) -- 10 ms or more (most exif-tool ops take from 1 to a few ticks, although some take several ticks).
            if shutdown then -- OK to check shutdown as long as "reload each export" not checked.
                -- no msg = "shutdown"
                break
            end
            if LrDate.currentTime() - tm > tmo then
                msg = "exiftool execute response timeout"
                break
            else
                count = count + 1 
                if count > 999 then
                    Debug.pause( count )
                end
            end
        end
        self.seq = self.seq + 1
    else
        -- Debug.pause( str:is( self.rsp ) ) - happens sometimes when no real problem, e.g. ottomanic-importer - at tail end of manual import.
        msg = "command file no longer exists" -- race condition?
    end
    -- return self.rsp, msg -- until 28/Sep/2012 5:08
    if self.rsp then
        local resp = str:trimLeft( self.rsp ) -- Lr's trimmer is not binary compatible. @17/Nov/2012 5:06 - no need to trim right.
        --Debug.logn( "Before return: " .. resp )
        return resp, msg, equiv
    else
        return nil, msg, equiv
    end
end



--- Update
--  ###2 not in exiftool proper, which has some problems anyway, e.g. -tagsFromFile only works in session when separate lines, but only works in et sesn emulation when a single param.
--  I need to make session an abstract class, then subclass working session and exiftool proper.
function Session:execWrite( tmo )
    local rslt, errm = self:execute( tmo )
    if str:is( errm ) then
        return false, errm
    elseif str:is( rslt ) then
        -- if rslt:find( "weren't updated due to error" ) then -- check this first
        if rslt:find( "due to error" ) then -- check this first
            return false, "exiftool was unable to update image file due to error"
        --elseif rslt:find( "image files updated" ) then -- this may be present regardless
        elseif rslt:find( "image files" ) then -- this may be present regardless. Note: says image files "...updated" if already existed, but "...created" if not.
            return true, nil
        else
            return false, "unexpected exiftool response - " .. LrStringUtils.trimWhitespace( rslt )
        end
    else
        return false, "there was no response from exiftool"
    end
end



--- Read.
function Session:execRead( tmo )
    local rslt, errm = self:execute( tmo )
    if str:is( errm ) then
        return nil, errm, LrStringUtils.trimWhitespace( rslt or "" ) -- sts=nil/false, err-msg=str, equiv-cmd
    else
        return LrStringUtils.trimWhitespace( rslt or "" ) -- usually, got non-empty response, but under rare circumstances rslt may be nil.
    end
end

-- ###1 move
function ExifTool:execRead( tmo )
    local rslt, errm = self:execute( tmo )
    if str:is( errm ) then
        return nil, errm, LrStringUtils.trimWhitespace( rslt or "" ) -- sts=nil/false, err-msg=str, equiv-cmd
    else
        return LrStringUtils.trimWhitespace( rslt or "" ) -- usually, got non-empty response, dunno if rslt is ever nil, but cheap insurance..
    end
end

-- ###1 move
function ExifTool:execWrite( tmo )
    local rslt, errm = self:execute( tmo )
    if str:is( errm ) then
        return false, errm
    elseif str:is( rslt ) then
        -- if rslt:find( "weren't updated due to error" ) then -- check this first
        if rslt:find( "due to error" ) then -- check this first
            return false, "exiftool was unable to update image file due to error"
        --elseif rslt:find( "image files updated" ) then -- this may be present regardless
        elseif rslt:find( "image files" ) then -- this may be present regardless. Note: says image files "...updated" if already existed, but "...created" if not.
            return true, nil
        else
            return false, "unexpected exiftool response - " .. LrStringUtils.trimWhitespace( rslt )
        end
    else
        return false, "there was no response from exiftool"
    end
end


--  close session
--
function Session:_close()

    if self.cmdfile ~= nil then    
        self:addArg( "-stay_open" )
        self:addArg( "False" )
        self.cmdfile:close() -- just leave it there after closing, so exiftool can take its last shot.
        self.cmdfile = nil
        if self.originalInputFile and LrFileUtils.exists( self.originalInputFile ) then -- and delete next time around.
            LrFileUtils.delete( self.originalInputFile )
        end
        if self.originalOutputFile and LrFileUtils.exists( self.originalOutputFile ) then -- and delete next time around.
            LrFileUtils.delete( self.originalOutputFile )
        end
        self.args = {}
        self.targs = {}
        self.closed = true -- if there is a reason why cmdfile is not simply cleared to indicate session closed, I don't remember what it is @27/Sep/2012 21:47.
        app:log( "ExifTool Session '^1' closed.", self.name ) -- this used to be verbose, until 25/Oct/2014 18:30.
    else
        app:log( "Previous exiftool session has closed: ^1", self:getName() )
    end

end



--- Determine if exiftool is usable. If not (on Mac) offers options for user to take action, if appropriate.
--
--  @usage must be called from async task.
--
function ExifTool:isUsable()
    if WIN_ENV then
        return ExternalApp.isUsable( self )
    end
    -- Mac:
    local usable, qual = ExternalApp.isUsable( self )
    if not usable then
        return false, qual
    end
    assert( str:is( self.exe ), "?" ) -- how can it be usable if no exe string?
    if LrPathUtils.isAbsolute( self.exe ) then
        local exec, neh = fso:isMacFileExecutable( self.exe, 'u' ) -- I *think* it just needs to be executable by user (plugin/Lr).
        --Debug.pause( exec, neh )
        if exec then
            return true
        elseif str:is( neh ) then
            app:log( neh )
        -- else just isn't.
        end
        local a = app:show{ confirm="Exiftool is not executable by 'user' (^1) - want me to correct that for you?\n \nYou can do it yourself using 'Terminal' utility and chmod command. Alternatively, you can download/install a copy which may already be executable.",
            subs = { self.exe },
            buttons={ dia:btn( "Yes - make executable by user only (recommended)", 'ok', false ), dia:btn( "No - try to use as is", 'other', true ), dia:btn( "No - I'll deal with it myself", 'cancel', false ) },
            actionPrefKey = "exiftool is not executable", -- note: only "try to use as is" is memorable, since I've not really tested this: it can be as it were.
        }
        if a == 'ok' then
            return fso:makeMacFileExecutable( self.exe, 'u' )
        elseif a == 'other' then
            return true
        elseif a == 'cancel' then
            return false, "exiftool is not executable"
        else
            app:error( "bad btn: ^1", a )
        end
    else
        return true, qual
    end
end



--- Create a new exiftool execution session.
--
--  @param name (string, required) unique session name (e.g. service name).
--  @param cfg (string, optional) path to exif-tool config file.
--  @param returnExisting (boolean, default=false) if true, return existing session if open with specified name; if false, throw error.
--  @param assureVersion (boolean, default=false) if true, session integrity validated by assureing version number exists; if false, no such assurance.
--      <br>    in future, there may be a comparison to a passed version number (e.g. that the actual version meets or exceeds specified version number).
--
--  @usage creates arg bufile in temp dir, and starts an exiftool task to listen to it (see -stay_open exiftool option).
--
function ExifTool:openSession( name, cfg, returnExisting, assureVersion )

    -- support table parameter passing too:
    if type( name ) == 'table' then
        cfg = name.cfg
        returnExisting = name.returnExisting
        assureVersion = name.assureVersion
        name = name.name
    end

    if not self.reg[name] then
        if returnExisting then
            app:logv( "No existing to return - opening new exiftool session: ^1", name )
        else
            app:logv( "Opening new exiftool session (wouldn't return if existing): ^1", name )
        end
        local sesn = Session:_new( name )
        sesn:_open( self.exe, cfg ) -- will log session open.
        if assureVersion then
            local verStr, afu = sesn:getVersionString()
            if verStr then
                app:logV( "Exiftool version: ^1", verStr )
            else
                app:error( afu )
            end
        end
        self.reg[name] = sesn
        return sesn
    elseif returnExisting then
        app:logv( "Returning existing exiftool session: ^1", name )
        local sesn = self.reg[name]
        if sesn then -- "open" (existing).
            return sesn
        else
            Debug.pause( name )
            return nil
        end
    else
        app:callingError( "Unable to open exiftool session because it's already open: ^1", name )
    end

end



--- Get session, if exists.
--
function ExifTool:getSession( name )
    return self.reg and self.reg[name] -- reg is never nil, but cheap insurance...
end



--- Is session open?
--
function ExifTool:isSessionOpen( name )
    return self:getSession( name )
end



--- Closes (previously opened) exiftool session.
--
function ExifTool:closeSession( session )

    if session == nil or session == self then
        return -- don't error out over nil session.
    end

    if not self.reg[session.name] then
        -- already closed
    else
        self.reg[session.name] = nil -- unregister
        session:_close() -- kill the session.
    end

end



-- ExifTool emulating a session:



--- Exiftool method to emulate exiftool session method of same name.
--
--  @param      arg         argument to add, typically of the form -tag=value, but can be anything. Will wrap with double-quotes, if not already wrapped.
--
--  @usage      so workers can use either a session or exiftool proper to do their jobs.
--  @usage      last argument added must be target file.
--
function ExifTool:addArg( arg )
    if self.args == nil then
        self.args = {}
    end
    if arg ~= nil then
        local splt = str:split( arg, "\n" )
        for i, v in ipairs( splt ) do
            if str:is( v ) then
                self.args[#self.args + 1] = ('"' .. v .. '"'):gsub( '""', '"' ) -- wrap with quotes, but not redundently.
                -- ###3 - maybe should remove all quotes, *then* wrap with quotes.
            end
        end
    else
        Debug.logn( "nil arg - ignored." )
    end
end



--- Accumulate target.
--
function ExifTool:addTarget( target )
    if self.targs == nil then
        self.targs = {}
    end
    self.targs[#self.targs + 1] = target
end



--- Set target array.
--
function ExifTool:setTargets( targets )
    if self.targs == nil then
        self.targs = {}
    end
    for k, v in ipairs( targets ) do
        self.targs[#self.targs + 1] = v
    end
end



--- Set single target.
--
function ExifTool:setTarget( target )
    self:setTargets{ target }
end




--- Get argument string.
--
function ExifTool:getArgumentString()
    if not tab:isEmpty( self.args ) then
        if not tab:isEmpty( self.targs ) then
            return table.concat( self.args, " " ) .. " " .. table.concat( self.targs, " " )
        else
            return table.concat( self.args, " " )
        end
    elseif not tab:isEmpty( self.targs ) then
        return table.concat( self.targs, " " )
    else
        return ""
    end
end



--- Clears the argument string as perceived by outside world.
--
function ExifTool:clearArgumentString()
    self.args = nil
    self.targs = nil
end



--- Exiftool method to emulate exiftool session method of same name.
--
--  @param      tmo         Timeout in seconds before to give up on execution response and return error code.
--
--  @usage      Emulation of session method, so workers can use either a session or exiftool proper to do their jobs.
--
--  @return     response (string or boolean) required.
--  @return     message (string) error message if applicable.
--
function ExifTool:execute( tmo )
    local resp, msg, respFile
    app:call( Call:new{ name="exiftool emul exec", main=function( call )
        if not tab:isEmpty( self.args ) then
            --local target = self.args[#self.args]:sub( 2, -2 )
            --self.args[#self.args] = nil
            -- local params = table.concat( self.args, " " )
            -- Debug.pause( params, target )
            respFile = LrFileUtils.chooseUniqueFileName( LrPathUtils.child( LrPathUtils.getStandardFilePath( 'temp' ), "etsExec" ) )
            local s, m = self:executeCommand( self.args, self.targs, respFile ) -- there may or may not be a response, depending on command, but response is expected by base class if response file handling is specified.
            -- Debug.pause( s, m, c )
            if s then
                if fso:existsAsFile( respFile ) then
                    resp, msg = fso:readFile( respFile )
                    --Debug.pause( resp, msg )
                    --return resp, msg
                else
                    --return true
                    resp = true -- calling context must know whether a real (string) response is warranted, or just a command ack.
                end
            else
                assert( m ~= nil, "no m" )
                msg = m
            end
        else
            msg = "nothing to execute"    
        end
    end, finale=function( call, status, message )
        self.args = nil
        self.targs = nil
        if respFile ~= nil and fso:existsAsFile( respFile ) then
            LrFileUtils.delete( respFile )
        end
        if not status then
            resp = nil
            msg = message
        end
    end } )
    return resp, msg
end



--- Determine if session mode, or exittool proper.
--
function ExifTool:isSession()
    return false
end



--- Exercise exiftool to get version info as table, if usable.
--
function ExifTool:getVersionString()
    local s, m = self:isUsable() -- logs verbosely.
    if s then
        local sts, cmd, rsp = self:executeCommand( "-ver", {}, nil, 'del' )
        if sts then
            return LrStringUtils.trimWhitespace( rsp )
        else
            return nil, m or "executable not configured or not functioning correctly"
        end
    else
        return nil, m
    end
end



function ExifTool:getUpdateStatus( rslt )
    if rslt:find( "weren't updated due to error" ) then -- check this first
        return false, "exiftool was unable to update image file"
    elseif rslt:find( "image files updated" ) then -- this may be present regardless
        return true
    elseif str:is( rslt ) then -- this qualification added 26/Mar/2013 4:265.
        -- return nil -- indeterminate -- this is mostly not being checked for, but should be. - commented out 26/Mar/2013 4:27.
        if #rslt > 500 then
            return false, str:fmtx( "Exiftool response does not indicate image was updated - here's the first part of it: ^1", rslt:sub( 500 ) )
        else
            return false, str:fmtx( "Exiftool response does not indicate image was updated - this is exiftool's response: ^1", rslt )
        end
    else
        return false, "No text in exiftool response => image probably not updated." -- this clause added 26/Mar/2013 4:25.
    end
end



-- Parse -S form of exiftool'd file.
function ExifTool:parseShorty( rslt )
    if not str:is( rslt ) then
        return {}
    end
    local a = str:split( rslt, "\n" ) -- it's actually \r\n on windows, but \r gets trimmed as whitespace.
    local r = {}
    for i, v in ipairs( a ) do
        local p1, p2 = v:find( ": " )
        if p1 then
            local name = v:sub( 1, p1 - 1 )
            local value = v:sub( p2 + 1 )
            r[name] = value
        end
    end
    return r
end



-- Parse unqualified form of exiftool'd file.
function ExifTool:parseLongy( rslt )
    if not str:is( rslt ) then
        return {}
    end
    local a = str:split( rslt, "\n" ) -- it's actually \r\n on windows, but \r gets trimmed as whitespace.
    local r = {}
    for i, v in ipairs( a ) do
        local p1, p2 = v:find( " : " )
        if p1 then
            local name = LrStringUtils.trimWhitespace( v:sub( 1, p1 - 1 ) )
            local value = LrStringUtils.trimWhitespace( v:sub( p2 + 1 ) )
            r[name] = value
        end
    end
    return r
end



-- Convenience method for when only one tag is expected, and it's name is known.
function ExifTool:parseOneShortValue( rslt, name )
    app:callingAssert( str:is( name ), "no name" )
    return self:parseShorty( rslt )[name]
end



function ExifTool:formatDateTime( timeNum )
-- string.format( '-DateTimeOriginal=%04u:%02u:%02u %02u:%02u:%02u'
    return LrDate.timeToUserFormat( timeNum, "%Y-%m-%d %H:%M:%S" )
end



--- Parse date time string *value* (auto-detects subsec or time-zone).
--  @usage you may need to call getValueFromPairS first.
--  @param dts (string, required) format: 'YYYY:MM:DD HH:MM:SS' (e.g. date-time-original).
--  @return timeNumStruct (table) year - second *string* members, maybe subsec or tzHour(may have neg sign) & tzMinute.
--  @return errm (string) if parse problem.
function ExifTool:parseDateTime( dts )
    if not str:is( dts ) then
        return nil, "invalid timestamp - blank/missing"
    end
    local a = str:split( dts, " " )
    if #a ~= 2 then
        return nil, str:fmtx( "unable to split date/time by space in between (^1 obtained) value: ^2", str:nItems( #a, "components" ), dts )
    end
    local d = a[1]
    local t = a[2]
    local a = str:split( d, ":" )
    if #a ~= 3 then
        return nil, "unable to parse date"
    end
    local r = { year=a[1], month=a[2], day=a[3] }
    local b = str:split( t, ":" )
    if #b == 3 then
        local z = str:split( b[3], "." ) -- plain text.
        if #z == 1 then
            r.second = b[3]
        elseif #z == 2 then
            r.second = z[1]
            r.subsec = z[2]
        else
            return nil, "unable to parse second/subsec"
        end
    elseif #b == 4 then -- utc tone-zone comp
        r.tzMinute = b[4]
        local z = str:split( b[3], "-" )
        if #z == 2 then
            r.second = z[1]
            r.tzHour = "-" .. z[2]
        else
            local z = str:split( b[3], "+" )
            if #z == 2 then
                r.second = z[1]
                r.tzHour = z[2]
            else
                return nil, "unable to parse time zone" -- I think it always has exlicit sign(?)
            end        
        end
    else
        return nil, "unable to parse time"
    end
    r.hour = b[1]
    r.minute = b[2]
    return r
end



-- parse function S format (shorty).
--
function ExifTool:getValueFromPairS( s )
    if not str:is( s ) then
        return ""
    end
    local p1, p2 = s:find( ":", 2, true ) -- untrimmed. (one-char label required).
    if p1 then
        return LrStringUtils.trimWhitespace( s:sub( p2 + 1 ) )
    else
        return ""
    end
end



--- parse image *number* from full (or sufficiently populated) -S format parsed exif table (i.e. keys are exif ID, values are string).
--
--  @return number representing image number, or nil if no such item.
--
function ExifTool:getFolderNumber( exif )
    app:callingTypeAssert( exif, "exif", 'table' )
    local m = {}
    local n
    local function getN( id )
        n = tonumber( exif[id] )
        if n then
            return true
        else
            m[#m + 1] = id
        end
    end
    if getN( 'DirectoryNumber' ) then return n end -- e.g. Nikon
    if getN( 'DirectoryIndex' ) then return n end -- e.g. Canon
    -- ###2 add more as more are discovered..
    -- if getN( 'FolderNumber' ) then return n end -- a good guess, but (@18/May/2014 20:56) not confirmed.
    -- if getN( 'FolderIndex' ) then return n end -- a good guess, but (@18/May/2014 20:56) not confirmed.
    return nil, str:fmtx( "Tried: ^1", table.concat( m, ", " ) )
end



--- parse image *number* from multi-item (or sufficiently populated) -S format parsed exif table (i.e. keys are exif ID, values are string).
--
--  @return number representing image number, or nil if no such item.
--
function ExifTool:getImageNumber( exif )
    app:callingTypeAssert( exif, "exif", 'table' )
    local m = {}
    local n
    local function getN( id )
        n = tonumber( exif[id] )
        if n then
            return true
        else
            m[#m + 1] = id
        end
    end
    if getN( 'FileNumber' ) then return n end -- Nikon and older Canons, others?
    if getN( 'FileIndex' ) then return n end -- newer Canons.
    if getN( 'ImageNumber' ) then return n end -- varied models
    -- ###2 add more as more are discovered..
    -- if getN( 'ImageIndex' ) then return n end -- a good guess, but (@18/May/2014 20:56) not confirmed.
    return nil, str:fmtx( "Tried: ^1", table.concat( m, ", " ) )
end



--- Browse for exiftool executable. No default dir, oh well... (###2 could rely on base clas method I think).
function ExifTool:browseForExe( params )
    return dia:selectFile( {
        title = params.title or "Select exiftool executable file",
    },
    params.props,
    params.name or self.prefName
    )
end



return ExifTool
