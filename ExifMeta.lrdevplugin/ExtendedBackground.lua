--[[
        ExtendedBackground.lua
--]]

local ExtendedBackground, dbg, dbgf = Background:newClass{ className = 'ExtendedBackground' }



--- Constructor for extending class.
--
function ExtendedBackground:newClass( t )
    return Background.newClass( self, t )
end



--- Constructor for new instance.
--
function ExtendedBackground:new( t )
    local interval
    local minInitTime
    local idleThreshold
    if app:getUserName() == '_RobCole_' and app:isAdvDbgEna() then
        interval = .1
        idleThreshold = 1
        minInitTime = 3
    else
        -- initially (2009), these were set very conservatively, but a half decade later, machines have more juice on average,
        -- and since nothing gets done if no need, there really isn't much CPU taken even when re-checking 10 per second.
        -- Note: I've been using .1/1 "forever" (as -rob-cole-) without any problem..
        interval = .1 -- changed 5/Sep/2014 (v5.7) from .3 to .1 seconds.
        idleThreshold = 1 -- changed 5/Sep/2014 (v5.7) from 3 to 1, so every cycle now instead of once per second.
        -- minInitTime = nil - use default
    end    
    local o = Background.new( self, { interval = interval, minInitTime = minInitTime, idleThreshold=idleThreshold } ) -- default min-init-time is 10-15 seconds or so.
     -- OK to check for changes fairly frequently, since its strictly using dates for update check.
     -- note: if all-photos or selected are also being done, this can still influence CPU significantly.
    o.newItems = {}
    return o
end



--- Initialize background task.
--
--  @param      call object - usually not needed, but its got the name, and context... just in case.
--
function ExtendedBackground:init( call )
    if app:getUserName() == "_RobCole_" and app:isAdvDbgEna() then
        self.allPhotosIndex = 4299 -- ***
    end
    self.initStatus = true
end



function ExtendedBackground:idleProcess( target, call )
    assert( target ~= nil, "dont call idle process with nil target" )
    self:process( call, target )
end



--- Background processing method.
--
--  @param      call object - usually not needed, but its got the name, and context... just in case.
--
function ExtendedBackground:process( call, target )

    local photo
    if not target then -- normal periodic call
        photo = catalog:getTargetPhoto() -- most-selected.
        if photo == nil then
            self:considerIdleProcessing( call )
            return
        end
    else
        photo = target
    end
    
    call.nChanged = 0
    call.nUnchanged = 0
    call.nAlreadyUpToDate = 0
    call.nMissing = 0
    -- call-total-new not updated by update-photo (single).
    call.autoUpdate = true -- just a little flag to keep update-photo from logging a metadata-same message.
    
    local sts, nNewOrErrm = LrTasks.pcall( Common.updatePhoto, photo, call, self.newItems, false, true ) -- updates last-update-time if successful; false => not forced update; true => called from bg.
    if sts then
        if call.nAlreadyUpToDate == 1 then -- nothing much was done, and no new items.
            assert( nNewOrErrm == 0, "new exif metadata for already up2date photo?" )
            if not target then
                self:considerIdleProcessing( call )
            end
            return
        end
        if nNewOrErrm > 0 then
            local totalNew = tab:countItems( self.newItems )
            app:log( "^1 found by auto-check so far.", str:plural( totalNew, " new item" ) )
        else
            -- dbg( "no new items" )
        end
    else
        app:logV( "*** " .. nNewOrErrm ) -- could use display-error app method, except there is an error just about every time a photo is moved or deleted - too many false alarms.
        -- And this used to be an error log, but has changed to a "pseudo-verbose" error for like reason - enable verbose logging if you want to find problems not other-wise evident...
        app:sleepUnlessShutdown( .5 ) -- take a moment, but not too long...
    end
    
end



return ExtendedBackground
