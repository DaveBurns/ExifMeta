--[[
        Timer.lua
        
        Class for (usually sub-classed) timers, various purposes...
        
        Initial motivation is a restartable timer, so start-time can be bumped by async task will another task is waiting on it.
--]]


local Timer = Object:newClass{ className= 'Timer', register=false }



--- Constructor for extending class.
--
function Timer:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Timer:new( t )
    local o = Object.new( self, t )
    o.startTime = math.huge -- not started.
    o.elapsedTime = o.elapsedTime or 0
    o.incr = math.min( o.incr or .1, 1 )
    -- timer.interval - specify upon construction or before starting.
    return o
end



--- Start timer
--
--  @param interval (number) must be specified either here or upon construction, or both.
--
function Timer:start( interval )
    self.interval = interval or self.interval or error( "No interval specified" )
    self.startTime = LrDate.currentTime()
end



--- Sleep for just a brief moment (.1 to 1 second), as specified by 'incr', typically in constructor.
--
function Timer:nod()
    LrTasks.sleep( self.incr )
end



--- Determine if time interval has elapsed.
--
--  @usage really this needs to determine whether to wake up, whether time has elapsed or not (does not need to take shutdown into consideration, but does need to account for everything else).
--  @usage do not call unless timer is known to have been started, and thus start-time and interval are defined.
--
function Timer:isElapsed()
    return ( LrDate.currentTime() - self.startTime ) >= self.interval
end



return Timer
