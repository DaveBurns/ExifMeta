--[[
        Service.lua
        
        A service is an operation with an associated log file.
--]]

local Service, dbg, dbgf = Call:newClass{ className = "Service" }



--- Constructor for extending class.
--
function Service:newClass( t )
    return Call.newClass( self, t )
end



--- New instance constructor.
--      
--  @param      t   Parameter table whose elements are:
--                  <ul>
--                  <li>name: (string, required)<br>
--                  <li>object: (table) instance of class with main and finale methods - optional.<br>
--                  <li>main: (function, required)<br>
--                  <li>async: (boolean, default false) true => asynchronous, false => synchronous.<br>
--                  <li>progress: (boolean or string, default false) true => default progress scope, string => scope with custom title, false => set scope to nil.<br>
--                  <li>finale: (function, default nil) executed after main if provided, regardless of whether main errors out.<br>
--                  <li>guard:  (number, default zero) nil or zero => reentrant, App.guardSilent => silent, App.guardVocal => vocal.</ul>
--
--  @usage      see Call class for more info.
--
--  @return     service object suitable for passing to app:call method.
--
function Service:new( t )
    
    local o = Call.new( self, t )
    if o.logFilePath == nil then
        o.logFilePath = _PLUGIN.id .. ".LogFile.txt"
    end
    return o
end



--- Register a mandatory message to be displayed in final dialog box.
--  Note: this assures final dialog box is displayed (overriding action-pref-key, and regardless of warning/error statuses).
--
function Service:setMandatoryMessage( f, ... )
    self.mandatoryMessage = str:fmtx( f, ... )
end



--- Initiate and perform main service function, excluding the finale.
--
--  <p>See Call parent class for more info.</p>
--
--  @param  context     function-context, in case you need to create a property table, hopefully thats the only use for it...
--  @param  ...         Passed to main.
--
function Service:perform( context, ... )

    self.startTime = LrDate.currentTime()
    local dateTimeFormat = '%Y-%m-%d %H:%M:%S'
    local startTimeFormatted = LrDate.timeToUserFormat( self.startTime, dateTimeFormat )
    
    self.startErrors = app:getErrorCount()
    self.startWarnings = app:getWarningCount()

    if app:isLoggerEnabled() then

        app:logInfo()
        app:logInfoToBeContinued( str:format( "'^1' started ^2", self.name, startTimeFormatted ) )
        if app:isTestMode() then
            app:logInfoToBeContinued( " IN TEST MODE\n- TEST MODE: Theoretically no files were actually created, modified, or deleted." )
        elseif app:isTestMode() == false then
            app:logInfoToBeContinued( " IN REAL MODE\n- REAL MODE: Theoretically, files were actually created, modified, or deleted, as indicated." )
        else
            app:logInfoToBeContinued( " in normal mode." )
        end
    
        if app:isAdvDbgEna() then
            app:log()
            if app:getGlobalPref( 'classDebugEnable' ) then
                app:log( "*** Advanced debug is enabled - class restrictions are in force." )
            else
                app:log( "*** Advanced debug is enabled - no class restrictions.." )
            end
            app:log()
        end
        
        if app:isVerbose() then
            app:log()
            app:logInfo( "Logging verbosely." )
            app:logInfo( "Lightroom Version: " .. LrApplication.versionString() )
            app:logInfo( "Plugin Name: " .. app:getPluginName() )
            app:logInfo( "Plugin ID: " .. _PLUGIN.id )
            app:logInfo( "Plugin Version: " .. app:getVersionString() )
            app:logInfo( "Plugin Enabled: " .. str:to( _PLUGIN.enabled ) )
            app:logInfo( "Platform: " .. app:getPlatformName() )
            app:logInfo( "Compatibility: " .. app:getCompatibilityString() )
    
            -- app no longer supports "support files". - Leaving in for nostalgia...
            --[[app:logInfo( "Support files may be specified absolutely or relative to these places, tried in this order:" )
            app:logInfo( "Catalog: " .. LrApplication.activeCatalog().path )
            app:logInfo( "Plugin parent: " .. LrPathUtils.parent( _PLUGIN.path ) )
            app:logInfo( "Plugin proper: " .. _PLUGIN.path )
            -- 'home', 'documents', 'appPrefs', 'desktop', 'pictures': must match order in app class.
            app:logInfo( "Home: " ..  LrPathUtils.getStandardFilePath( 'home' ) )
            app:logInfo( "Documents: " ..  LrPathUtils.getStandardFilePath( 'documents' ) )
            app:logInfo( "Application Preferences: " ..  LrPathUtils.getStandardFilePath( 'appPrefs' ) )
            app:logInfo( "Desktop: " ..  LrPathUtils.getStandardFilePath( 'desktop' ) )
            app:logInfo( "Pictures: " ..  LrPathUtils.getStandardFilePath( 'pictures' ) )--]]
            -- *** My experience has been the default directory would actually be c:/windows/system32 yet the default directory is
            -- being shown as '/'. Since this is misleading, and only reluctantly supported (will return file relative to
            -- default if found but accompanied by a warning), suppress logging of default dir.
        else
            app:log()
            app:logInfo( "Logging non-verbosely." )
        end
    
        app:logInfo()
        app:logInfo("Plugin path: " .. _PLUGIN.path .. '\n' )
       
    end
    
    app:assurePrefSupportFile( self.preset ) -- load changed backing file of current (or specified) preset.
    Call.perform( self, context, ... )
    
end



--- Call at any time (or set flag upon construction).
function Service:skipFinalDialogIfOk()
    self.skipFinalDialogIfNoIssues = true
end



--- Permit skipping final dialog even if NOT ok.
--
--  @param apk action-pref-key to enable; nil to disable.
--
function Service:enableSuppressionOfFinalDialogBoxDespiteErrorsAndWarnings( apk )
    self.finalDialogBoxActionPrefKey = apk
end



--- Perform finale...
--
--  <p>See Call parent class for more info.</p>
--
--  @param      status      boolean: true iff execution completed without an error being thrown.
--  @param      message     string: error message corresponding to error if thrown.
--
function Service:cleanup( status, message )

    -- Call.cleanup( self, status, message ) - calls regstered finale method. commented out 17/Oct/2011 since it seems like service cleanup should be protected.
        -- call cleanup is no longer protected so errors can be propagated out of nested calls.
        
    self.nErrors = app:getErrorCount() - self.startErrors -- number of app errors logged while this service was processing.
    self.nWarnings = app:getWarningCount() - self.startWarnings -- ditto - warnings.
    
    local cleanupStatus, cleanupMessage = LrTasks.pcall( Call.cleanup, self, status, message ) -- calls regstered finale method.
    
    local function failureHandler( _false, m )
        App.defaultFailureHandler( _false, "Unable to complete service due to a bug in the framework's service cleanup method, error message: " .. m )
    end

    LrFunctionContext.callWithContext( "service cleanup finish", function( context )
        context:addFailureHandler( failureHandler )

        if cleanupStatus then
            if status then
                -- dbg( "cleanup good" )
            else
                app:logErr( "^1 terminated prematurely due to an error - ^2", self.name, message or "Unknown error." ) -- log service error message - reminder: no error is logged in base class (call) cleanup method.
                self:abort("Aborted due to error.") -- but continue to display log footer / status.
            end
        else
            app:logError( "Unable to complete '^1' service due to error in cleanup/finale function, error message: ^2", self.name, cleanupMessage )
            self:abort("Aborted due to cleanup/finale error.") -- but continue to display log footer / status.
            status = false -- not presently looked at past here, but...
            if not str:is( message ) then
                message = cleanupMessage -- ditto.
            end
        end

        self.stopTime = LrDate.currentTime()
        local elapsedTimeFormatted = date:formatTimeDiff( self.stopTime - self.startTime )
        self.startTime = nil -- closes the service/export so end-service can be called redundently with impunity.
        
        local nErrors = app:getErrorCount() - self.startErrors -- number of app errors logged while this service was processing.
        local nWarnings = app:getWarningCount() - self.startWarnings -- ditto - warnings.
    
        local dateTimeFormat = '%Y-%m-%d %H:%M:%S'
        local stopTimeFormatted = LrDate.timeToUserFormat( self.stopTime, dateTimeFormat )
    
        app:logInfo( '\n' )
        app:logInfo( str:format( "'^1' finished at ^2 (^3 seconds).\n\n\n\n\n", self.name, stopTimeFormatted, elapsedTimeFormatted ) )
    
        if shutdown then
            -- note: if service is honor of export filter, and 'reload each export' is checked, shutdown may already be under way if export filter lingers.
            app:log( "Aborting service finale (^1) due to shutdown", self.name )
            return
        elseif self:isCanceled() then
            app:logv( "Returning from service (^1) due to cancelation", self.name ) -- cancel message? ###2
            return
        elseif self.skipFinalDialogIfNoIssues then
            if nErrors == 0 and nWarnings == 0 then
                return
            end
        end
        
        -- present final dialog box message:
        local msg = nil
        local prefix = ''
        prefix = self.name .. ' '
        if not self:isAborted() then
            if nErrors == 0 then
                msg = prefix .. ' - all done (no errors).\n'
            else
                msg = prefix .. " - done, but " .. str:plural( nErrors, "error" ) ..".\n" 
            end
        else
            -- progress scope has been cancelled.
            if nErrors == 0 then
                msg = prefix .. ' - quit early (but no errors). Reason: ' .. self:getAbortMessage() .. '\n'
            else
                msg = prefix .. " - quit early, and " .. str:plural( nErrors, "error" ) ..".\n" 
            end
        end
        if nWarnings > 0 then
            msg = msg .. str:plural( nWarnings, "warning" ) ..".\n" 
        end
    
    	if app:isLoggerEnabled() then
    		msg = msg .. str:format( "\nSee log file for details: ^1", app:getLogFilePath() )
    	else
    		msg = msg .. str:format( "\nNo log file was created." )
    	end
    	
    	if str:is( self.mandatoryMessage ) then
    	    msg = msg .. "\n \n" .. self.mandatoryMessage
    	end
    
        -- present final dialog box.
        local actionPrefKey
        local buttons = nil
        -- note: final-dialog-box-action-pref-key has been added for cases when calling context must allow suppression even if errors/warnings (e.g. auto-publishing environment).
        if self.finalDialogBoxActionPrefKey or ( nErrors == 0 and nWarnings == 0 and app:isRealMode() and not str:is( self.mandatoryMessage ) ) then
            if not self:isAborted() then
                actionPrefKey = ( nErrors ~= 0 or nWarnings ~= 0 ) and self.finalDialogBoxActionPrefKey or ( self.name .. " - view logs" )
            -- else do not permit "do not show" functionality if service was aborted.
            end
            if app:isLoggerEnabled() then
                buttons = { { label="View Log File", verb='ok' }, { label="Skip Log File", verb='cancel', memorable=true } }
            end
        else
            -- no action-pref-key
            if app:isLoggerEnabled() then
                -- Note: no action-pref-key, so "memorable" is pretty-much-of-a don't care, still - to make a point I guess..
                buttons = { { label="View Log File", verb='ok', memorable=false }, { label="Skip Log File", verb='cancel', memorable=false } }
            end
        end
        
        if self.scope then -- might as well kill the scope before putting up the final dialog box - if any...
            if status then
                -- self.scope:done() -- commented out 27/Oct/2011 16:59
                self.scope:setCaption( "Finished - see dialog box for results..." ) -- added 27/Oct/2011 17:00
                    -- if scope already canceled, this message will not appear, or if dialog box not displayed it will be too quick to see.
            else
                self.scope:setCaption( "Error: " .. app:parseErrorMessage( message ) ) -- this is the touch I was after in case service concludes due to an uncaught error.
            end
        end
            
        local answer = app:show{ info=msg, buttons=buttons, actionPrefKey=actionPrefKey } -- no longer using error/warning specific dialog boxes for final presentation
            -- in honor of view-log-file upgrade.
        if answer =='ok' then -- seems like this used to die if left hand was nil, but it doesn't die now.
            if app:isLoggerEnabled() and LrFileUtils.exists( app:getLogFilePath() ) then
                app:showLogFile()
            else
                app:show( "no log" )
                --dbg( "no log" )
            end
        elseif answer == 'skip' then
           -- dbg( "notokforlogs" )
        elseif answer == 'cancel' then
            -- same as skip, except cancel can't be remembered.
        else
            app:show{ error="bad answer to question about viewing or skipping log file: ^1", str:to( answer ) }
        end

        -- note: if service scope is tied to service context, then it will be 'done' upon return from this function.
        -- if it was tied to some other context (highly unusual), then the calling context must determine when scope is done.
        if self.scope then
            self.scope:setCaption( "" ) -- just in case scope context is not service context - don't want it to say a dialog box still up.
        end
        service = 'done'    -- call or service sets this to 'started', then 'done' - used to synchronize call/services with debug-script: this is still being used @19/Aug/2011.

    end )
end



return Service