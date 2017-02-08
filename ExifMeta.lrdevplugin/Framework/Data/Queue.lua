--[[================================================================================

        Queue.lua
        
        Object with methods optimized for treating lua table as a queue.
        
        Keeps track of item count, read-index, and write-index - that's about it (and items themselves of course).

================================================================================--]]


local Queue, dbg, dbgf = Object:newClass{ className = 'Queue', register = false }



--- Constructor for extending class.
--
function Queue:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @param t initial table with optional members: 'max' (maximum number of items) - default is "infinite".
--
function Queue:new( t )
    local o = Object.new( self, t )
    o.items = {}
    o.readIndex = 1
    o.writeIndex = 1
    o.count = 0
    if o.max == nil then
        o.max = math.huge
    end
    return o
end



--- Put item in queue.
--
--  @return status true iff item queued.
--  @return message error message if unable to put in queue (because no room).
--
function Queue:put( item )
    if self.count < self.max then
        self.items[self.writeIndex] = item
        self.writeIndex = self.writeIndex + 1
        self.count = self.count + 1
        return true
    else
        return false, "No room in queue, max is: " .. str:to( self.max )
    end
end



--- Return next item in queue without removing it.
--
function Queue:peek()
    if self.count > 0 then
        local item = self.items[self.readIndex]
        return item
    else
        return nil, "Queue is empty."
    end
end



--- Get (and remove) "front" item from queue.
--
function Queue:get()
    if self.count > 0 then
        local item = self.items[self.readIndex]
        self.readIndex = self.readIndex + 1
        self.count = self.count - 1
        return item
    else
        return nil, "Queue is empty."
    end
end



--- Remove all items from queue.
--
function Queue:clear()
    self.items = {}
    self.count = 0
    self.readIndex = 1
    self.writeIndex = 1
end



--- Get number of items in queue.
--
function Queue:getCount()
    return self.count
end



return Queue