--[[
        Logger.lua
        
        Provides logging functionality.

        Wraps lr-logger, so additional functionality can be added.
--]]

local LogFile = Object:newClass{ className = 'LogFile', register = false } -- too much of logger is used by debug functions, best to debug independently to avoid infinite recursion.

LogFile.VERBOSE = true -- convenience var for specifying verbose info being logged. Duplicated in App class for further convenience.


--- Constructor to extend class.
--
function LogFile:newClass( t )
    return Object.newClass( self, t )
end



--- Constructs a not-yet-enabled logger.
--      
--      <p>Initialization parameters:</p><blockquote>
--
--          - verbose<br>
--          - overwrite</blockquote>
--
--  @param      t       Initialization parameter table.
--
function LogFile:new( t )

    local o = Object.new( self, t )
    o.message = ''    -- start of continued log-line.
    o.verbose = o.verbose or false -- or error( "no verb" )
    if o.overwrite == nil then
        o.overwrite = true
    end
    return o

end



--- Get path to log file.
--
--  @return     The path, or nil if logger not enabled for logging to file.
--
function LogFile:getLogFilePath()
    return self.logFilePath
end



--- Get contents of log file.
--
--  <p>Normally this is not required, since there is a show-log-file method in the app interface.
--  The motivation for this function is to support a klugy send-log-file feature that involves
--  the user copying the log contents from an edit field to the clipboard and pasting it in an email.</p>
--
function LogFile:getLogContents()
    if self.logFilePath then
        if fso:existsAsFile( self.logFilePath ) then
            local contents, orExcuse = fso:readTextFile( self.logFilePath )
            return contents, orExcuse
        else
            return nil, "Log file does not exist: " .. self.logFilePath
        end
    else
        return nil, "No Log file."
    end
end



--- Clear contents of log file.
--
--  <p>It does this by simply deleting it.</p>
--  <p>App clears warning & error counters when calling.</p>
--      
function LogFile:clear()

    if self.logFilePath then
        if LrFileUtils.exists( self.logFilePath ) then
            local s, m = fso:moveToTrash( self.logFilePath )
            if s then
                app:show{ info="Log file cleared, deleted ^1",
                    subs = self.logFilePath,
                    actionPrefKey = "Log file cleared",
                }
            else
                app:show{ warning="Unable to clear log file - ^2", -- note: errm is comprehensive.
                    subs = { self.logFilePath, m },
                }
            end
        else
            app:show{ info="Log file does not exist to clear: ^1",
                subs = self.logFilePath,
                actionPrefKey = "Log file does not exist to clear",
            }
        end
    else
        app:show{ info="Log file has not been initialized, unable to clear." }
    end
    
end


--- Enables the logger for logging.
--
--  <p>###2 To Do: resurrect ability to route debug-trace messages to debugger instead of log file.</p>
--
function LogFile:enable( t )

    self.message = ''
    if t then
        if t.verbose ~= nil then
            self.verbose = t.verbose
        end
        if t.overwrite ~= nil then
            self.overwrite = t.overwrite
        end
    end
    
    local logName = _PLUGIN.id -- extension of .log should be sufficient to identify as log file.
    assert( prefs, "no prefs" )
    local logDir = prefs.logDir or prefs._global_logDir -- give user pref priority over Lr default.
    -- ###2 Note: this is dangerous pref handling: really need to make sure plugin that previously did not use managed preferences does not block version that does, and vice versa.
    if logDir == nil or logDir == "" then
        -- Debug.init( true ) - *** required for debug pausing - but don't forget to comment out afterward.
        for i, v in ipairs{ 'documents', 'home', 'appData', 'pictures', 'desktop', 'temp' } do -- 'documents' first for backward compat.
            logDir = LrPathUtils.getStandardFilePath( v )
            if logDir ~= nil then
                if LrFileUtils.isWritable( logDir ) then -- ok for testing
                    --Debug.pause( "writable", logDir )
                    break
                else
                    Debug.pause( "not writable", logDir )
                end
            else
                Debug.pause( "no user dir", v )
            end
        end
    end
    if logDir == nil then -- some (Mac) systems don't return a documents folder for some reason.
        error( 'Unable to access any of the standard user folders for storing logs, i.e. "Documents", "Home", "AppData", "Pictures", "Desktop", "Temp".' )
    end
    local logFileName = LrPathUtils.addExtension( logName, "log" ) -- Note: doc says its .txt, but experience dictates its .log.
    
    self.logFilePath = LrPathUtils.child( logDir, logFileName )
    
    if LrFileUtils.exists( self.logFilePath ) then
        if self.overwrite then
            LrFileUtils.delete( self.logFilePath ) -- delete unconditionally - ignore return code.
            -- LrDialogs.message( "deleted" )
        else
            -- LrDialogs.message( "not overwriting: " .. self.logFilePath )
        end
    else
        -- LrDialogs.message( "not existing" )
        LrFileUtils.createAllDirectories( logDir )
        assert( LrFileUtils.exists( logDir ) == 'directory', "unable to create/assure log directory exists: " .. logDir )
    end
    self.logger = LrLogger( logName )
    local function logToFile( msg )
        local f = io.open ( self.logFilePath, "a" )
        if f == nil then 
            Debug.pause( "can't open log file", self.logFilePath )
            return
        end
        f:write ( LrDate.timeToUserFormat( LrDate.currentTime(), "%Y-%m-%d %H:%M:%S"), " ", msg, '\n' )
        f:close ()
    end
    if self.verbose then
        --self.logger:enable( 'logfile' ) -- enable everything to log file.
        self.logger:enable( logToFile )
    else
        local actions = {
            -- debug output is suppressed when not logging verbosely
            trace = logToFile,
            info = logToFile,
            warn = logToFile,
            error = logToFile,
            fatal = logToFile,
        }
        self.logger:enable( actions ) -- suppress trace & debug.
    end
end



--- Logs a message segment, no EOL output.
--
--  @usage      No-op if logger not open.
--
function LogFile:logInfoStart( message, verbose )
    if self.logger == nil then return end
    self.message = self.message .. message
end



--- Logs a message line, or end-of-line - EOL output after message.
--
--  @usage      No-op if logger not open.
--
function LogFile:logInfo( message, verbose )
    if self.logger == nil then return end
    if not message then
        message = ''
    end
    message = self.message .. message
    if verbose then
        self.logger:debug( message )
    else
        self.logger:info( message )
    end
    self.message = ''
end



--- Logs a warning line with a warning prefix that includes index number, and counts it.
--
--  @usage      No-op if logger not open.
--  @usage      Warnings are never considered verbose.
--
function LogFile:logWarning( num, msg )
    if self.logger == nil then return end
    self.logger:warn( str:format( "****** WARNING #^1: ^2", num, str:to( msg ) ) )
end



--- Logs an error line with an error prefix that includes index number, and counts it.
--
--  @usage      No-op if logger not open.
--  @usage      Errors are never considered verbose.
--
function LogFile:logError( num, msg )
    if self.logger == nil then return end
    self.logger:error( str:format( "****** ERROR #^1: ^2", num, str:to( msg ) ) )
end



--- Disables the log file - no more logs will be accepted after this is called.
--      
--  <p>Presently, this shan't be called, since a plugin either includes log file support or it doesn't. (not true @2010-11-22, but may be @some.)</p>
--
--  <p>User doesn't have a say. Still, just in case...</p>
--
function LogFile:disable()
    self.logger = nil
end




return LogFile


