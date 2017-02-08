--[[
        Gate.lua
        
        Permits one-at-a-time entry to code, provided not too many in line already.
--]]


local Gate, dbg, dbgf = Object:newClass{ className = "Gate", register=false }



--- Constructor for class extension.
--
function Gate:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance objects.
--
function Gate:new( t )
    local o = Object.new( self, t )
    o.max = o.max or 1 -- simple mutex if max == 1.
    o.cnt = 0
    o.sts = nil
    o.ival = math.min( o.ival or .1, 1 ) -- max 1 second polling interval, so won't sleep too long in the face of shutdown. - not using app-sleep, for efficiency reasons.
    return o
end



--- Enter immediately, if possible, else wait for those ahead, if not too many.
--
function Gate:enter()
    app:callingAssert( LrTasks.canYield(), "Gates are for async tasks only" )
    if self.blocked then
        return nil, "gate is temporarily blocked - should be passable shortly.." -- note: nil => temporary blockage, false => permanent.
    end
    if self.cnt >= self.max then
        return false, "try again later..."
    end
    self.cnt = self.cnt + 1
    while self.sts and not shutdown do -- callers responibility to assure those who enter also exit.
        LrTasks.sleep( self.ival )
    end
    if shutdown then return false, "shutdown" end
    if self.blocked then
        return nil, "gate entry revoked due to blockage - should be passable shortly.." -- note: nil => temporary blockage, false => permanent.
    end
    self.sts = true
    return true
end



--- Release hold for next in line to enter.
--
function Gate:exit()
    if self.cnt > 0 then
        self.cnt = self.cnt - 1
    end
    self.sts = nil
end



--- Determine if any body is in, or trying to get in the gate or not.
--
function Gate:isIdle()
    return self.sts == nil and self.cnt == 0
end



--- Get number of tasks that've entered or are trying to enter the gate.
--
function Gate:getEntryCount()
   return self.cnt
end



-- Hopefully this method will not need to be called from external context.
--
function Gate:waitForIdle()
    local sanity = 10000
    while not self:isIdle() do
        LrTasks.yield() -- release one if not all.
        sanity = sanity - 1
        if sanity == 0 then
            Debug.pause( "insane" )
        elseif sanity == -1048575 then -- -2**20 + 1
            error( "mega-crazy" )
        end
    end
end



--- Block the gate.
--
--  @usage useful for denying changes best ignored whilst things are done that would otherwise result in unwanted change processing.
--  @usage make sure unblocking happens despite errors.
--
--  @param revokeExistingEntries (boolean, default=false) i.e. default is to send existing waiters packing.
--
function Gate:block( revokeExistingEntries )
    self.blocked = true -- assert blockage.
    if revokeExistingEntries then
        LrTasks.yield() -- open the gate for releasing entries.
        self:waitForIdle() -- assure all are released.
    -- else only revoke new entries.
    end
end



--- Unblock the gate.
--
--  @usage to resume normal passage.
--  @usage make sure unblocking happens despite errors.
--  @usage since Lua is non-preemptive, and gating/blocking applies to other running tasks, the blocking task must yield between blocking and unblocking or it won't do any good - consider passing true, to assure such is the case.
--
--  @param revokeExistingEntries (boolean, default=false) i.e. default is to send accrued waiters packing before clearage.
--
function Gate:unblock( revokeExistingEntries )
    if revokeExistingEntries then
        LrTasks.yield() -- open the gate for releasing entries.
        self:waitForIdle() -- assure all are released.
    -- else allow existing entries through once blockage is cleared.
    end
    self.blocked = false -- clear blockage.
end


return Gate