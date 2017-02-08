--[[
        Call.lua
        
        A glorified pcall, which uses cleanup handlers, and assures at least default error handling.
        
        Benefits include extensibility for calls that go beyond the simplest case, wrapping
        
        basic functionality with more elaborate start / cleanup code (see 'Service' class as example).
--]]


local Call, dbg, dbgf = Object:newClass{ className = "Call" }



--- Constructor for class extension.
--
function Call:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance objects.
--      
--  <p>Table parameter elements:</p><blockquote>
--      
--          - name:         (string, required) operation name, used for context debugging and as guard key.<br>
--          - async:        (boolean, default false) true => main function runs as asynchronous task. false => synchronous.<br>
--          - guard:        (number, default 0) 0 or nil => no guard, 1 => silent, 2 => vocal. Hint: Use App constants; App.guardSilent and App.guardVocal.<br>
--          - object:       (table, default nil) if main (and finale if applicable) is method, object is required, else leave blank to call main (and finale if applicable) as static function.<br>
--          - main:         (function, required) main function or method.<br>
--          - finale:       (function, default nil) pass finale function if something to do after main completes or aborts.</blockquote>
--
--  @param  t               Table holding call paramaters.
--
function Call:new( t )
    
    -- assume t is table.
    t.main = t.main or t[1] -- main function is named or is first un-named param.
    t.finale = t.finale or t[2] -- finale function is named or second un-named param.
    if not t.name then
        error( "Call constructor requires name in parameter table." ) -- @5/Feb/2014 - only necessary if guarded, but may not be a bad idea to have for debugging in the future..
    elseif not t.main then
        error( "Call requires main function in parameter table." )
    end
    if app:isAdvDbgEna() then -- make sure its unwrapped if not debugging, since finale handlers depend on it.
        t.main = Debug.showErrors( t.main )
    end
    local o = Object.new( self, t )
    o.abortMessage = ''
    o.cancelMessage = nil
    return o
end



--- Constructor for a call-like object that just keeps a set of stats, without being "performed" (no main function...).
--
function Call:newStats( names )
    local o = Object.new( self )
    o:initStats( names )
    return o
end



---  Initialize call stats - optional, but recommended - to avoid nagging when debug is enabled.
--
function Call:initStats( names )
    self.stats = {}
    self.used = {}
    for i, name in ipairs( names ) do
        self.stats[name] = 0
    end
end



---  Initialize call stats - optional, but recommended - to avoid nagging when debug is enabled.
--
function Call:assureStats( names )
    if self.stats == nil then
        self:initStats( names )
        return
    end
    for i, name in ipairs( names ) do
        if self.stats[name] == nil then
            self.stats[name] = 0
        -- else stat already defined.
        end
    end
end



--- Increment a call stat: may or may not be initialized.
--
function Call:incrStat( name, amt )
    if not str:is( name ) then
        app:callingError( "no name" )
    end
    if self.stats == nil then
        self.stats = {}
        self.used = {}
        Debug.pause( "stats not init before incr of", name )
    end
    if self.stats[name] == nil then
        Debug.pause( "stat does not for incr:", name )
        self.stats[name] = 0
    end
    self.stats[name] = self.stats[name] + (amt or 1)
    self.used[name] = true
end



--- get stat value, 0 if undefined.
--
function Call:getStat( name )
    if not str:is( name ) then
        app:callingError( "no name" )
    end
    if self.stats == nil then
        Debug.pause( "stats not init for get of", name )
        return 0
    end
    if self.stats[name] == nil then
        Debug.pause( "stat does not exist for getting:", name )
        return 0
    end
    self.used[name] = true
    return self.stats[name]
end



--- get stat value, 0 if undefined.
--
function Call:setStat( name, val )
    if not str:is( name ) then
        app:callingError( "no name" )
    end
    if self.stats == nil then
        Debug.pause( "stats not init for seting", name )
        self.stats = {}
    elseif self.stats[name] == nil then
        Debug.pause( "stat has not been defined/init:", name )
    end
    self.used[name] = true
    self.stats[name] = val
end



--- Determine if any stats have not been used (only does something if (adv) debug mode enabled).
--
--  @usage unsused means not set, incr'd, nor gotten. (it does NOT mean it couldn't have been set, incr'd, or gotten, given another program path).
--
function Call:closeStats()
    if not Debug.enabled then return end
    local unused = 0
    for name, value in pairs( self.stats ) do
        if not self.used[name] then
            Debug.logn( "Stat not used:", name )
            unused = unused + 1
        end
    end
    if unused > 0 then
        Debug.pause( unused, "stats not used - see debug log." )
    else
        Debug.logn( "All stats were used." )
    end
end



--- Abort call or service.
--
--  @usage Note: Do not call base class abort method here.
--
function Call:abort( message, ... )
    if str:is( message ) then
        self.abortMessage = str:fmtx( message, ... ) -- serves as boolean indicating "is-aborted" as well as providing the message.
    else
        Debug.pause()
        self.abortMessage = "unable to ascertain reason for abort"
    end
end



--- Cancel call or service.
--
--  @usage      cancelation means don't bother user again.
--
function Call:cancel( message )
    if message == nil then
        self.cancelMessage = self.name .. " was canceled."
    else
        self.cancelMessage = message -- empty string for cancelation without message.
    end
end



--- Determine if a call was canceled.
--
--  @usage      cancelation means don't bother user again.
--
--  @return cancel-message which serves as boolean (if not nil) and optional message (if not the empty string).
--
function Call:isCanceled()
    return self.cancelMessage ~= nil -- (note: unlike abort, it is legal to cancel with an empty message).
end



--- Determine if call has been aborted.
--
function Call:isAborted()
    return str:is( self.abortMessage )
end



--- Determine if call has quit due to cancelation or abortion.
--
--  @usage      Does not check for scope canceled, nor scope done.
--
function Call:isQuit( scope )
    if self:isCanceled() or self:isAborted() or _G.shutdown then
        return true
    else
        if scope == nil then
            scope = self.scope
        end
        if scope ~= nil and scope:isCanceled() then
            self:cancel()
            return true
        elseif self.quit then
            return true
        else
            return false
        end
    end
end



--- Used by background task so it can be canceled, but not stay canceled forever.
--
function Call:unQuit()
    self.abortMessage = ''
    self.cancelMessage = nil
end



-- Get abort message for display.
--
-- @return empty string if not aborted.
--
function Call:getAbortMessage()
    return self.abortMessage or ''
end



-- Don't call without context.
-- what is optional as is what.title and what.caption
function Call:createScope( what )
    if self.scope then -- already exists - create new/replacement.
        self.scope:done() -- so scopes don't build up in UI.
    end
    what = what or {}
    local cap = what.caption or "Please wait..."
    self.scope = LrProgressScope {
        title = what.title or str:fmtx( "^1 - ^2", app:getShortAppName(), self.name ),
        functionContext = self.context,
        caption = cap,
    }
    self.cap = cap
end



--- Assure progress scope is created.
--
function Call:assureScope( what )
    if self.scope then return
    else self:createScope( what ) end
end



--- Assure there is NO progress scope.
--
function Call:killScope()
    if self.scope then
        self.scope:done()
    end
    self.scope = nil
end



--- Set a caption on a progress indicator.
--
--  @usage normally pre-created, but will create default scope on demand if need be.
--
--  @return previousCaption (string, always) for restoring after..
--  @return portionSoFar (number, always) dont remember purpose.
--  @return portionTotal (number, always) dont remember purpose.
--
function Call:setCaption( fmt, ... )
    if self.context then
        local prevCap = self.cap or ""
        local cap
        if fmt then
            self.cap = str:fmtx( fmt, ... )
            cap = self.cap
        else
            cap = ""
        end
        if not self.scope then
            --self:_createDefaultScope( self.cap ) - this till 21/Nov/2012 0:34 (hope nobody depending on it). Not a good idea: too many cases where if there is no scope, I don't want a rogue one going up.
        elseif not self.scope:isCanceled() then -- must be allowed even on done scopes.
            self.scope:setCaption( cap )
        -- else - ignore incoming captions on canceled scopes (must be allowed even on done scopes).
        end
        return prevCap, self.amt or 0, self.ttl or 1
    else
        app:callingError( "Call not active." )
    end
end



--- Get caption, usually for subsequent restoral.
--
--  @return caption (string, always) or empty, never nil.
--
function Call:getCaption()
    return self.cap or ""
end



--- Convenience function for setting portion complete on encapsulated scope.
--
--  @param      amt     (number, required) number completed.
--  @param      ttl     (number, default=1) out of total.
--
function Call:setPortionComplete( amt, ttl )
    if self.context then
        self.amt = amt or 0
        self.ttl = ttl or 1
        if not self.scope then
            --self:_createDefaultScope( "Please wait..." ) - this til 21/Nov/2012 0:35...
            --self.scope:setPortionComplete( self.amt, self.ttl )
        elseif not self.scope:isCanceled() then -- must be allowed even on done scopes.
            self.scope:setPortionComplete( self.amt, self.ttl )
        -- else - ignore incoming progress on canceled scopes
        end
    else
        app:callingError( "Call not active." )
    end
end
    


--- Call (perform) main function.
--
--  @usage          Normally no need to override - pass main function to constructor instead.
--  @usage          Called as static function if object nil, else method.
--  @usage          Errors thrown in main are caught by App and passed to finale.
--
function Call:perform( context, ... )

    _G.service = 'started' -- used to support debug-script, which waits a short time for this, and if seen, waits forever for the finale to set 'done' state.
    -- dbg( "Doin service: ", self:getFullClassName() )

    if self.progress ~= nil then
        local typ = type( self.progress )
        if typ == 'boolean' then
            if self.progress then
                self.cap = "Please wait..."
                self.scope = LrProgressScope {
                    title = str:fmtx( "^1 - ^2", app:getShortAppName(), self.name:gsub( "&&", "&" ) ),
                    functionContext = context,
                    caption = self.cap, -- change this if you want.
                    -- can cancel
                }
            else
                self.scope = nil
            end
        elseif typ == 'string' then -- self.progress interpreted as title.
            self.cap = "Please wait..."
            self.scope = LrProgressScope {
                title = str:fmtx( "^1 - ^2", app:getShortAppName(), self.progress ),
                functionContext = context,
                caption = self.cap, -- change this if you want.
                -- can cancel
            }
        elseif typ == 'table' then -- required to specify custom caption (or title without app prefix).
            self.cap = self.progress.caption or "Please wait..."
            if self.progress.modal then
                self.scope = LrDialogs.showModalProgressDialog{
                    title = self.progress.title or str:fmtx( "^1 - ^2", app:getShortAppName(), self.name:gsub( "&&", "&" ) ),
                    caption = self.cap,
                    functionContext = context,
                    cannotCancel = self.progress.cannotCancel, -- or false (i.e. default: *can* cancel).
                }
            else
                self.scope = LrProgressScope {
                    title = self.progress.title or str:fmtx( "^1 - ^2", app:getShortAppName(), self.name:gsub( "&&", "&" ) ),
                    caption = self.cap,
                    functionContext = context,
                    cannotCancel = self.progress.cannotCancel, -- or false (i.e. default: *can* cancel).
                }
            end
        -- else hope for the best...
        end
    -- else no scope.    
    end
    
    if self.preserve ~= nil then
        if self.preserve.selPhotos then
            self.selPhotos = cat:saveSelPhotos() -- and view filter.
        end
    end

    --self.canceled = false -- until 29/Oct/2011 2:48
    self.cancelMessage = nil -- after 29/Oct/2011 2:48
    self.abortMessage = ''
    self.context = context
    
    if self.object then
        -- self.object.call = self -- this is tempting, but presumptious: if user defined a call member it would stomp on it.
        self.returned = { self.main( self.object, self, ... ) } -- call main function as a method of specified object.
    else
        self.returned = { self.main( self, ... ) } -- changed 12/Aug/2013 17:05 to store main returned values in call object.
    end
end



--- "Cleanup" function called after main function, even if main aborted due to error.
--
--  <p>I'm not real crazy about the term "cleanup", but the big deal is that its guaranteed to be called
--  regardless of the status of main function execution. "cleanup" activities can include things like
--  clearing recursion guards, logging results, and displaying a successful completion or error message.</p>
--
--  @usage          Normally no need to override - pass finale function to constructor instead.
--  @usage          App calls this in protected fashion - if error in cleanup function, default error handler is called.
--
function Call:cleanup( status, message )
    if str:is( self.abortMessage ) then
        app:log( "'^1' aborted: ^2", self.name, self.abortMessage )
    elseif str:is( self.cancelMessage ) then
        app:log( self.cancelMessage )
    end
    if self.selPhotos then
        local s, m = cat:restoreSelPhotos( self.selPhotos )
        if not s then
            app:log( "*** Photo selection etc. not restored - ^1", m ) -- should be mandatory, as option anyway? ###2
        end
    end
    if self.finale then
        if self.object then
            self.finale( self.object, self, status, message )
        else
            self.finale( self, status, message )
        end
    elseif status then
        -- no finale func/method, but main func executed without error - good enough...
    elseif not self:isQuit() then
        App.defaultFailureHandler( false, message ) -- for user.
    end
    if self:getClassName() == 'Call' then
        _G.service = 'done' -- supports debug-script @2/Sep/2011.
    -- else let derived type do it when totally done.
    end
    self.quit = true
end



function Call:log( m, ... )
    if gbl:getValue( 'background' ) and self==background.call then
        app:logVerbose( "info: "..( m or "no message" ), ... ) -- in background task, make normal logging verbose, but distinguiushed as "not normally verbose".
    else
        app:log( m, ... )
    end
end
function Call:logV( m, ... )
    if gbl:getValue( 'background' ) and self==background.call then
        app:logVerbose( "verbose: "..( m or "no message" ), ... ) -- same as non-verbose, except disginguished as verbose.
    else
        app:logV( m, ... )
    end
end
function Call:logW( m, ... )
    if gbl:getValue( 'background' ) and self==background.call then
        app:alertLogW( m, ... )
    else
        app:logW( m, ... )
    end
end
function Call:logW( m, ... )
    if gbl:getValue( 'background' ) and self==background.call then
        app:alertLogE( m, ... )
    else
        app:logW( m, ... )
    end
end

return Call