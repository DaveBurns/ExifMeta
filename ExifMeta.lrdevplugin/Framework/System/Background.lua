--[[
        Background.lua
        
        Background task - designed to be extended.
        
        Instructions:
        
            - Extend this background class to do something useful.
              - Override init method to do special initialization, if desired.
              - Override process method to do special processing.
            - Create (extended) background object and start background task in init.lua, perhaps conditioned by pref.
--]]

local Background, dbg, dbgf = Object:newClass{ className = 'Background' } -- only one error id used by base class. derived classes can have additional error IDs if desired.



--- Constructor for extending class.
--
function Background:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage      *** interval is overridden by pref named 'backgroundPeriod'.
--
--  @param      t       initialization table, including:
--                      <br>interval (number, default: 1 second) process frequency base-rate. Recommend .2 as normal minimum, .1 if process is quick and fast response is necessary.
--                      <br>minInitTime (number, default: 10 seconds), but recommend setting to 15 or 20 - so user has time to inspect startups in progress corner, or set to zero to suppress init progress indicator altogether.
--
function Background:new( t )
    if str:is( t.enableCheckName ) then
        Debug.pause( "background task no longer needs enable-check-name" )
    end
    local o = Object.new( self, t )
    o.interval = o.interval or 1 -- polling interval
    o.initStatus = false
    o.done = false -- stop command flag, not state var.
    o.started = false -- state var, to avoid having to try and figure it out from the various transient states.
    o.minInitTime = o.minInitTime or 10
    o.idleThreshold = o.idleThreshold or 1 -- default to idle processing every idle cycle.
    o.idleCounter = 0
    o.state = 'idle'
    return o
end



--- Background init function.
--
--  @param      call object - usually not needed, but its got the name, and context... just in case.
--
--  @usage      override to do special initialization, if desired.
--              <br>Try not to throw errors in init, but instead set initStatus to true or false depending on whether successful or not.
--              <br>no need to call this method from extended class, yet.
--
--  @usage      if init is lengthy, check for shutdown sometimes and abort(return) if set - initStatus a dont care in that case.
--
function Background:init( call )
    self.initStatus = true
end



--  Set state if changed, and pref to match, and log appropriately.
--
function Background:_setState( state, verbose )
    if self.state == state then
        return
    end
    self.state = state
    app:setGlobalPref( 'backgroundState', state )
    if verbose then
        app:logVerbose( "Background state changed to: " .. state )
    else
        app:log( "Background state changed to: " .. state )
    end
end



--- Wait for asynchronous initialization to complete.
--
--  @param tmo - initial timeout in seconds - default is half second.
--  @param ival - recheck interval if not finished initializing upon initial timeout - return immediately and do not prompt user if nil or zero. Ignored if tmo is zero.
--
--  @usage Untested @2011-01-08 ###2
--
--  @return status - true iff init completed successfully.
--  @return explanation - if status false, is error message. if status true, indicates some waiting was required.
-- 
function Background:waitForInit( tmo, ival )

    tmo = tmo or .5
    if self.initStatus then
        return true -- init complete - no waiting.
    elseif tmo == 0 then
        return false, "initialization incomplete"
    else -- wait loop
        ival = ival or 0
    end
    local time = LrDate.currentTime() + tmo
    repeat
        LrTasks.sleep( .1 )
        if shutdown then return end -- this line added 25/Jan/2014 16:38.
        if self.initStatus then
            break
        end    
        if LrDate.currentTime() > time then -- either initial or interval timeout
            if ival > 0 then
                if dia:isOk( "^1 is not ready yet. Wait another ^2 seconds?", app:getAppName(), ival ) then
                    time = LrDate.currentTime() + ival
                else
                    return false, "wait for initialization was canceled"
                end
            else
                return false, "initialization timed out"
            end
        -- else keep checking.
        end
    until false
    return true, "had to wait for a while..." -- init complete, after waiting for a while.

end



--- Background process function.
--
--  @param      call object - usually not needed, but its got the name, and context... just in case.
--
function Background:process( call )
    error( "background process must be overridden." )
end



--- Display background error as progress scope.
--
--  @usage *** deprecated in favor of displayErrorX method (which does the about same thing, but with a different calling sequence).
--
--  @param      errm - unparsed error message
--  @param      id - any ID which must be used to clear too.
--  @param      immediate (boolean, default = false) - display immediately, else holdoff until error not clearing.
--  @param      promptWhenUserCancels (boolean, default=false) - if true, prompt for log file viewing upon scope "cancellation" (acknowledgement).
--
--  @usage      base class uses "genericBackgroundErrorId" for generic background error id. Derived classes may define additional error IDs for special purposes...
--
function Background:displayError( errm, id, immediate, promptWhenUserCancels )

    app:callingAssert( str:is( errm ), "errm should be string" )

    local call = self.call
    call.errorId = call.errorId or {}
    if id then
        call.errorId[id] = true
    end

    if call.nErrorsDisplayed == nil then
        call.nErrorsDisplayed = 1
        call.context:addCleanupHandler( function()
            LrTasks.pcall( call.errScope.cancel, call.errScope )
            call.errScope = nil
        end )
    else
        call.nErrorsDisplayed = call.nErrorsDisplayed + 1
    end
    if call.nErrorsDisplayed > 1 then
        -- Debug.pause( "*** ERROR: background error", errm ) -- pseudo error. 
        app:logv( "*** ERROR: background error - ^1", errm ) -- pseudo error. 
        local altErrm = str:fmtx( "^1 total", str:nItems( call.nErrorsDisplayed, "errors" ) )
        if call.errScope ~= nil then
            call.errScope:setCaption( altErrm )
            return
        else
            Debug.logn( "There is no error scope, despite multiple errors logged - error will not be displayed: " .. altErrm )
            Debug.pause( "No error scope despite multiple errors being displayed:", call.nErrorsDisplayed )
        end
    end
    LrTasks.startAsyncTask( function()
        if immediate then
            call.errScope = LrProgressScope {
                title = str:fmtx( "^1 - background error", app:getShortAppName() ),
                caption = app:parseErrorMessage( errm ),
                functionContext = call.context,
            }
        else
            call.errScope = DelayedProgressScope:new { -- changed to delayed-scope 22/Oct/2012 14:20, so fleeting errors don't cause a stir (e.g. when a photo is deleted).
                title = str:fmtx( "^1 - background error", app:getShortAppName() ),
                caption = app:parseErrorMessage( errm ),
                functionContext = call.context,
                delaySecs = self.interval <= 1 and 3 or self.interval * 3,  -- the idea here is that if it fails on interval one, but passes on interval two, then all is well.
                updateSecs = self.interval,                                 -- the ramification, is that errors may not be displayed for a loooong time if interval is long. ###1
                -- @22/Oct/2012 14:55, default is non-modal.
            }
        end
        app:sleep( math.huge, .1, function()
            if call.errScope then
                if call.errScope:isCanceled() then
                    call.nErrorsDisplayed = 0
                    return true -- wake up.
                -- else return nil
                end
            else
                return true -- no point continuting to sleep if no err-scope.
            end
        end )
        -- this added 2/Jun/2014 0:56:
        if not shutdown and promptWhenUserCancels and call.errScope and call.errScope:isCanceled() then
            local button = app:show{ confirm="View log file now?",
                buttons = dia:btns( "YesNo" ),
                actionPrefKey = "Background error acknowledgment - view log file",
            }
            if button == 'ok' then
                app:showLogFile()
            else
                app:logV( "User opted not to view log file upon background error acknowledgment." )
            end
        end        
    end )
    
end



--- Display error, named options first, so remainder can be used for formatting & params.
--
--  @param options options table:
--      <br>    id (string) - error ID - remember to clear error too.
--      <br>    immediate (boolean, default=false) - it true, do not suppress error until next background interval.
--      <br>    promptWhenUserCancels (boolean, default=false) - or just 'prompt' for short. set true to have prompt for log file display when scope is canceled - best if there is something useful in log file for user to see, e.g. non-verbose pseudo-warning log.

--      
function Background:displayErrorX( options, fmt, ... )
    options = options or {}
    self:displayError( str:fmtx( fmt, ... ), options.id, options.immediate, options.promptWhenUserCancels or options.prompt )
end



--- Clear error display (progress scope)
function Background:clearError( id )
    local call = self.call
    if call.errorId and id then
        call.errorId[id] = nil
    end
    if tab:isEmpty( call.errorId ) then
        call.nErrorsDisplayed = 0
        call.errorId = nil
        if call.errScope then
            LrTasks.pcall( call.errScope.cancel, call.errScope )
            call.errScope = nil
        end
    end
end



--[[
        Note: Its up to the extended class to keep track of last-edit-date if desired,
        and whatever else. This class is merely going to feed photos from selection or
        catalog alternately, forever, as long as main process function remembers to call it,
        preferrably when it didn't have anything better to do.
        
        The idea is to continue to keep up-2-date whatever this plugin updates.
        For example dev-meta (if ported), exif-meta (hardly needs it, but...), and change-manager.
--]]



local _firstTime = true
--- Background process for processing next photo or video in the catalog.
--
--  @usage      Called when nothing else to do in background process.
--
function Background:considerIdleProcessing( call )

    -- step -1 init on demand:
    if self.phase == nil then
        if self.photoIndex == nil then
            self.photoIndex = 1 -- target photo index
        end
        if self.allPhotosIndex == nil then
            self.allPhotosIndex = 1
        end
        if self.filmstripPhotosIndex == nil then
            self.filmstripPhotosIndex = 1
        end
        self.lastEditTime = 0
        self.targetTimes = {}
        self.lastPhoto = nil
        self.lastTargets = {}
        self.allPhotoCount = 0
        self.filmstripPhotoCount = 0
        self.phase = 0
    end
    
    local target
    
    -- step 0: see if preferences are specifying any background processing.
    local doTargetPhotos = app:getPref{ name="processSelectedPhotosInBackground", default=app:getPref( "processTargetPhotosInBackground" ) }
    local doAllPhotos = app:getPref( "processAllPhotosInBackground" )       -- meaning "whole catalog".
    local doFilmstripPhotos = app:getPref{ name="processVisiblePhotosInBackground", default=app:getPref( "processFilmstripPhotosInBackground" ) }
    if doFilmstripPhotos then
        if _firstTime then
            app:logV( "*** Processing visible photos in background is deprecated." )
            Debug.pause( "processing visible photos in background is deprecated" )
            _firstTime = false
        end
    end
    if not doTargetPhotos and not doAllPhotos and not doFilmstripPhotos then
        dbgf( "No idle processing is enabled." )
        return
    end

    -- step 1: check that Lightroom is in a steady state
    -- in order to minimize load when Lr/user is busy.
    
    local targetPhoto = catalog:getTargetPhoto()
    if targetPhoto ~= self.lastPhoto then -- may be nil
        self.lastPhoto = targetPhoto
        -- self.photoIndex = 1 -- when target changes, idle processing re-starts at the beginning, since new target could be used
        -- to sync other targets.
        -- self.phase = 0
        dbg( "photo changed" )
        return
    end
    
    local targetPhotos
    if app:getPref( 'processSelectedPhotosInBackground' ) ~= nil then
        targetPhotos = cat:getSelectedPhotos()
    else
        targetPhotos = catalog:getTargetPhotos()
    end
    if #targetPhotos ~= #self.lastTargets then -- may be zero
        self.lastTargets = targetPhotos
        -- self.photoIndex = 1 -- when targets change, idle processing re-starts at the beginning.
        -- self.phase = 0
        dbg( "target count changed" )
        return
    elseif #targetPhotos == 1 then
        if not doFilmstripPhotos then
            dbgf( "Single photo selected - not included in idle-processing, should be explicitly processed." )
            return
        -- else filmstrip photos can do unselected photos too.
        end
    elseif #targetPhotos > 1 then -- counts are equal
        if targetPhotos[1] ~= self.lastTargets[1] or targetPhotos[#targetPhotos] ~= self.lastTargets[#targetPhotos] then -- rough check for
                -- selection content change despite same number selected.
            self.lastTargets = targetPhotos
            -- self.photoIndex = 1 -- when targets change, idle processing re-starts at the beginning.
            -- self.phase = 0
            dbg( "target selection changed" )
            return
        end
    end
    
    
    local allPhotos = catalog:getAllPhotos()
    if #allPhotos ~= self.allPhotoCount then -- may be zero
        self.allPhotoCount = #allPhotos
        -- self.allPhotosIndex = 1 - all photos index just keeps on trucking regardless of new photos added to catalog
        -- if user selects any of the new photos, it'll be picked up.
        dbg( "catalog photo count changed" )
        return
    else
        --
    end
    
    -- this may be very time consuming, so don't do unless necessary.
    local filmstripPhotos
    if doFilmstripPhotos then -- ###2 deprecated, since get-filmstrip method is too expensive, and subject to prefs which may not even be exposed..
        --if app:getPref( 'processVisiblePhotosInBackground' ) ~= nil and false then - *** unacceptable..
        --    filmstripPhotos = cat:getVisiblePhotos() -- *** unacceptable in background task, since it results in 'Undo Select' ad infinitum in the undo menu.
        --else
            filmstripPhotos = cat:getFilmstripPhotos( app:getPref( "includeSubfolders" ), app:getPref( "ignoreIfBuried" ) ) -- yuck.
        --end
        if #filmstripPhotos ~= self.filmstripPhotoCount then -- may be zero
            self.filmstripPhotoCount = #filmstripPhotos
            -- self.allPhotosIndex = 1 - all photos index just keeps on trucking regardless of new photos added to catalog
            -- if user selects any of the new photos, it'll be picked up.
            dbg( "filmstrip photo count changed" )
            return
        else
            --
        end
    end
    
    -- targets same as last time, which may be none or zero.
    if #allPhotos == 0 then -- dont die if its a new catalog.
        self.allPhotoCount = 0
        dbg( "catalog photo count zero" )
        return
    end
    
    -- fall-through => there is at least one photo in the catalog, and all targets are same as last time.
    if targetPhoto then
        local lastEditTime = targetPhoto:getRawMetadata( 'lastEditTime' )
        if lastEditTime > self.lastEditTime then -- let changes to most selected photo be handled by auto-update
            self.lastEditTime = lastEditTime
            -- self.phase = 0
            dbg( "Most selected photo edited, since last idle check, better pass on idle processing." ) -- (most-sel photo always gotten by auto-update non-idle processing)
            return
        end
    end
    
    local edge = app:getPref{ name="idleThreshold", expectedType='number' } -- may be nil.
    if edge == nil then
        edge = self.idleThreshold
    end
    --Debug.pause( edge )
    self.idleCounter = self.idleCounter + 1
    if self.idleCounter < edge then
        return
    else
        self.idleCounter = 0
    end
    
    if self.phase == 0 then
        if doTargetPhotos then
            dbg( "Phase 0:", self.photoIndex )
        else
            dbg( "Phase 0 but not doing target photos." )
        end
    elseif self.phase == 1 then
        if doAllPhotos then
            dbg( "Phase 1:", self.allPhotosIndex, "total in catalog:", #allPhotos )
        else
            dbg( "Phase 1 but not doing all photos." )
        end
    elseif self.phase == 2 then
        if doFilmstripPhotos then
            dbg( "Phase 2:", self.filmstripPhotosIndex, "total in filmstrip:", #filmstripPhotos )
        else
            dbg( "Phase 1 but not doing all photos." )
        end
    else
        error( "invalid phase" )
    end

    -- step 2: compute potential target
    
    if doTargetPhotos and self.phase == 0 then
        if #targetPhotos > 0 then
            if self.photoIndex <= #targetPhotos then
                target = targetPhotos[self.photoIndex]
                self.photoIndex = self.photoIndex + 1
            else
                target = targetPhotos[1]
                self.photoIndex = 2
            end
        end
    end

    if doAllPhotos and self.phase == 1 then
        if #allPhotos > 0 then
            if self.allPhotosIndex <= #allPhotos then
                target = allPhotos[self.allPhotosIndex]
                self.allPhotosIndex = self.allPhotosIndex + 1
            else
                target = allPhotos[1]
                self.allPhotosIndex = 2
            end
        end
    end
    
    if doFilmstripPhotos and self.phase == 2 then
        if #filmstripPhotos > 0 then
            if self.filmstripPhotosIndex <= #filmstripPhotos then
                target = filmstripPhotos[self.filmstripPhotosIndex]
                self.filmstripPhotosIndex = self.filmstripPhotosIndex + 1
            else
                target = filmstripPhotos[1]
                self.filmstripPhotosIndex = 2
            end
        end
    end
    
    if self.phase == 0 then
        if doAllPhotos then
            self.phase = 1
        elseif doFilmstripPhotos then
            self.phase = 2
        end
    elseif self.phase == 1 then
        if doFilmstripPhotos then
            self.phase = 2
        elseif doTargetPhotos then
            self.phase = 0
        end
    elseif self.phase == 2 then
        if doTargetPhotos then
            self.phase = 0
        elseif doAllPhotos then
            self.phase = 1
        end
    else
        app:error( "Bad background phase: ^1", self.phase )
    end

    if target then
        if target ~= catalog:getTargetPhoto() then -- most selected photo processing is not handled by idle processor.
            dbg( "idle processing", target:getRawMetadata( 'path' ) )
            if self.idleProcess then
                Debug.logn( "*** deprecation warning: implement process-photo method instead." )
                self:idleProcess( target, call ) -- may do nothing, may do something... - obsolete/deprecated: left in for backward compatibility.
            elseif self.processPhoto then
                self:processPhoto( target, call, true ) -- preferred - the new way @22/Jan/2012 14:28. Implement one or the other of these but not both! true => called by idle task.
            else
                app:error( "No photo processor implemented for background task." )
            end
        else
            dbg( "most selected photo, skipped: ", target:getRawMetadata( 'path' ) )
        end
    else
        dbg( "No target" )
    end
    
end



--- Start's background initialization, followed by periodic background processing - if desired.
--
--  @usage      Generally called from init module if background auto-start is enabled.
--              also called from plugin manager for start/stop on demand.
--
function Background:start()
    local BackgroundCall = Call:newClass{ className="BackgroundCall", register=false }
    function BackgroundCall:isQuit()
        if Call.isQuit( self ) then
            return true
        else
            return background.state == 'pausing' -- or self.done...? (comment added 26/Jan/2014 20:15).
        end
    end
    local status, message = app:call( BackgroundCall:new { name='Background Task', async=true, guard=App.guardSilent, object=self, main=self.main, finale=self.finale } )
    if status == nil then -- guarded - already running...
        return false -- so not started
    else
        self.done = false -- do this outside async task, just in case quit is called before this task gets underway, it won't be ignored.
        return true
    end
end



--- call/called when background initialization is complete (after init hold-off time expires).
function Background:initDone( call )
end



--- Background initializer and optional main loop.
--
function Background:main( call )

    self.call = call
    self:_setState( 'starting' ) -- and set pref, and log normal.
    call.scope = LrProgressScope {
        title = app:getAppName() .. " Starting Up",
        caption = "Please wait...",
        functionContext = call.context,
    }
    local scope = call.scope -- convenience
    local startTime = LrDate.currentTime()
    app:sleep( 1 ) -- without this ya cant see the startup progress bar. ###1 - a longer delay helps keep from completely max'ing out memory consumption
        -- during startup, but with all my plugins enabled - it's still pushing the limit..
    if shutdown then return end
    self:init( call ) -- errors will cause permanent failure.
    if self.initStatus then
        while not self.done and not shutdown and not scope:isCanceled() and (LrDate.currentTime() < (startTime + self.minInitTime)) do -- why not using app-sleep method? - comment added 25/Jan/2014 16:39 ###2.
            LrTasks.sleep( .2 ) -- coarse sleep timer OK for responding to status change while initializing.
        end
        self:initDone( call )
        scope:done()
        call.scope = nil
    else
        scope:setCaption( "Initialization failed." )
        repeat
            app:sleep( .5 ) -- coarse is ok - takes a bit for cancellation to be acknowleged anyway.
            if scope:isCanceled() then
                error( "Unable to initialize background task." )
            elseif shutdown then
                scope:done()
                call.scope = nil
            end
        until scope:isDone()
    end
    if self.initStatus then
        app:logInfo( "Asynchronous initialization completed successfully." )
        self:_setState( 'running' ) -- and set pref, and log normal.
        local consecErrors = 0
        while not shutdown and not self.done do
            repeat
                if not app:isPluginEnabled() then
                    app:setGlobalPref( 'backgroundState', '*** Plugin Disabled' ) -- pseudo state: not used interally - for user only.
                    app:sleep( .5 ) -- disable holdoff. changed from Lr-tasks sleep to app-sleep 25/Jan/2014 16:41.
                    break
                else
                    local interval = app:getPref{ name="backgroundPeriod", expectedType='number' } -- may be nil.
                    if interval == nil then
                        interval = self.interval
                    end
                    --Debug.pause( interval )
                    app:sleep( interval, interval / 5, function() -- wakes up upon shutdown
                        return self.done or self.wakeUp -- or if stopped or woken while asleep.
                    end ) -- return upon shutdown
                    if shutdown or self.done then
                        break
                    else
                        self.wakeUp = false
                    end
                end
                -- fall-through => enabled and not quitting and not shutting down.
                if self.state == 'pausing' then
                    self:_setState( 'paused', App.verbose ) -- and set pref, and log verbose.
                elseif self.state == 'paused' then
                    -- dont do anything
                else -- if not pausing or paused, then run if possible...
                    --dbg( "processing" )
                    local status, message = LrTasks.pcall( self.process, self, call ) -- errors in processing must not terminate the task.
                    --dbg( "process status/message:", status, message )
                    if status then -- executing process without error is the definition of "running" I think.
                    
                        if app:getGlobalPref( 'backgroundState' ) ~= 'running' or self.state ~= 'running' then
                            if self.state ~= 'pausing' then
                                -- app:log("setting running after process return, previous state: " .. self.state )
                                -- self:_setState( 'running' ) - dont use this method, since it will return if state is running, even if pref isnt.
                                -- (misses the plugin disable/reenable transition which does not set the state to non-running).
                                app:setGlobalPref( 'backgroundState', 'running' )
                                self.state = 'running'
                            else
                                dbg( "Went into pausing state asynchronously while processing." )
                            end
                        else
                            -- dbg( "already running" )
                        end
                        
                        consecErrors = 0
                        self:clearError() -- clear background error (no ID => clears all ID-less errors).
                        
                    else
                        message = str:to( message )
                        -- anomalies are common when photos are deleted.
                        if app:isVerbose() or app:isAdvDbgEna() then
                            app:logVerbose( "*** Anomaly in background task (expected when most selected photo is deleted, or if background task updates catalog and its not accessible due to another plugin hogging it or something), error message: ^1", message )
                                -- ###3 check for type of anomaly = catalog prob?
                            dbg( "*** Anomaly in background task (expected when most selected photo is deleted, or if background task updates catalog and its not accessible due to another plugin hogging it or something), error message:", message )
                                -- ###3 check for type of anomaly = catalog prob?
                            app:setGlobalPref( 'backgroundState', "*** Anomaly: see log file." )
                        else
                            -- this is a very normal thing, when photos deleted from disk or removed from collection... - so no reason to even mention: it should clear.
                            -- If it does not clear, then user can see that here, and turn verbose logging on to find out what's happening...
                            app:logVerbose( "*** ^1", message ) 
                            app:setGlobalPref( 'backgroundState', "*** Anomaly: should clear (enable verbose logging and view log file - top section)" )
                        end
                        self:displayError( message ) -- display background error in dedicated progress scope (uses ID-less mode). Derived classes should pass IDs if they don't want them auto-cleared upon first background processing success.
                        consecErrors = consecErrors + 1
                        if consecErrors > 11 then
                            consecErrors = 11 -- clamp for sleep computation purposes.
                        end
                        app:sleep( .8 + ( .2 * consecErrors ) ) -- institute an error hold-off, so as not to overrun the logger...
                            -- don't hold off too long though, or background processing takes too long to resume after a deleted photo.
                            -- dont hold off too short, or background my resume before its time. Presently 1 - 3 seconds.
                    end -- end of processing-status clauses
                end -- end of run-state clauses
            until true
        end
    end
end



--- Background call finale.
--
--  @usage      If overriding, you MUST set state to idle, or just call this from extended class method.
--
function Background:finale( call )
    self:_setState( 'idle' ) -- and set pref, and log normal.
    if call.status then
        app:logInfo( "Background/init task terminated without error." )
    else
        app:logError( "Background task aborted due to error: " .. ( call.message or 'nil' ) )
        app:show{ error="Background task aborted due to error: ^1", call.message or 'nil' }
    end
end



--- Signal background task to quit.
--
--  @usage Need not be called from task - does not wait for confirmation.
--
function Background:quit()
    if self.state ~= 'quitting' and self.state ~= 'idle' then
        app:logVerbose( "Background task is quitting" )
        self:_setState( 'quitting', App.verbose ) -- and set pref, and log verbose (normal state change log when quit state acknowleged).
    else
        app:logVerbose( "Background task cant really quit, state: " .. str:to( self.state ) )
    end
    self.done = true
end



--- Stop background task.
--
--  @param tmo (number, required) - seconds to wait for stop confirmation.
--
--  @usage no-op if already stopped.
--  @usage must be called from task - waits until stopped.
--
--  @return  confirmed (boolean) true iff stoppage confirmed.
--
function Background:stop( tmo )
    assert( (tmo ~= nil)  and (type( tmo ) == 'number') and (tmo > 0), "stop requires non-zero tmo" )
    self:quit()
    self:waitForIdle( tmo )
    return self.state == 'idle'
end



--- Pause background task.
--
--  @usage you must continue in finale method of call or service, lest background task dies forever.
--
function Background:pause( tmo )
    tmo = tmo or 10
    local status
    if self.state == 'starting' then
        while not shutdown do
            local s, m = self:waitForInit( tmo, 3 ) -- wait up to 10 seconds to start with, then another 3 each time after prompting user.
            if s then
                -- give it a chance to run before trying to pause it.
                local count = tmo
                while not shutdown and count > 0 do
                    if self.state == 'running' then
                        break
                    else
                        LrTasks.sleep( 1 )
                        count = count - 1
                    end
                end
                break -- give it a try regardless, background task may not ever run: not a pre-requisite.
            else    
                return false, m
            end
        end
    end
    if self.state == 'pausing' then
        app:logV( "Pausing again (presumably a retry..)." )
    elseif self.state == 'paused' then
        app:logV( "Already paused." )
        return true
    elseif self.state ~= 'running' then
        app:logV( "Background task not running - so it cant be paused, state: " .. str:to( self.state ) )
        return true -- lets not get hung up trying to pause something that is not even running.
    else
        self:_setState( 'pausing', App.verbose ) -- and set pref, and log verbose.
    end
    
    local function wait()
        local count = tmo * 10 -- one second per ten count.
        while not shutdown and (self.state ~= 'paused') and (count > 0) do
            LrTasks.sleep( .1 )
            count = count - 1
            if self.state == 'idle' then return true end -- update function sets done flag, which results in idle state - close enough..
        end
        if count == 0 then
            app:logError( "Unable to pause background task - continuing with state: " .. self.state )
            local m = "background process not pausing"
            if not app:isPluginEnabled() then -- it waits the full tmo before checking disable for fear of spurious disabling which might result in false pause-a-tive (bar-har).
                -- m = m .. " - plugin is disabled." - this removed 26/May/2014 22:15
                app:displayInfo( "Plugin is disabled." ) -- this added 26/May/2014 22:15
                return true -- this added 26/May/2014 22:15 - if function invoked in plugin manager, then it's better to do it, enabled or disabled - note: can't be invoked from menu when plugin disabled.
            end
            return false, m
        elseif not shutdown then
            assert( self.state == 'paused' )
            app:logVerbose( "Background task paused." )
            return true
        else
            return true -- wrong, but keeps wheel turning..
        end
    end
    repeat
        local s, m = wait()
        if s then
            return true
        else
            local button = app:show{ confirm="Hmm - ^1 - try again?",
                subs = m,
                buttons = dia:buttons( "YesNo" ),
            }
            if button == 'ok' then
                app:log( "Trying again to pause background processing..." )
            elseif button == 'cancel' then
                return s, m
            else
                error( "bad button" )
            end
        end
    until false
    error( "how here?" )
    
end



--- Continue background task.
--
--  @usage No-op if not paused.
--
function Background:continue()
    if self.state == 'pausing' or self.state == 'paused' then
        self:_setState( 'running', App.verbose ) -- and set pref, and log verbose.
    else -- else leave state alone.
        app:logInfo( "Cant continue background task, state: " .. str:to( self.state ), App.verbose )
    end
end



--- Rarely used, but helps long-running background tasks to abort if user is trying to pause for foreground purposes.
--
function Background:isPausing()--OrPaused()
    return self.state == 'pausing'-- or self.state == 'paused'
end



--- Wait for background task to finish.
--
--  @usage Dont call unless you know its on its way out, e.g. shutdown for reload.
--
function Background:waitForIdle( tmo )
    tmo = tmo or 30 -- for backward compatibility.
    local startTime = LrDate.currentTime()
    while self.state ~= 'idle' do
        LrTasks.sleep( .1 )
        if (LrDate.currentTime() - startTime) > tmo then
            break
        end
        if shutdown then return end -- this line added 25/Jan/2014 16:44.
    end
    if self.state == 'idle' then
        app:setGlobalPref( 'backgroundState', 'idle' )
        app:logVerbose( "Background task became idle." )
    end
end



return Background