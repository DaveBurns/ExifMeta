--[[
        Notes.lua
        
        Concept: Ability to make notes, then have them in a scroller for user to see.
        
        Features
            * Auto-width / length calculations (so it knows how wide to make the horizontal and vertical edit-field dimensions.
            * Assures not too many notes - adds 1 "buffer overflow" note instead if no more room.
--]]

local Notes, dbg, dbgf = Object:newClass{ className='Notes', register=false }



--- Constructor for extending class.
--
function Notes:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Notes:new( t )
    local this = Object.new( self, t )
    this.max = this.max or 100
    this:clear()
    return this
end



--- Dump current notes and re-initialize for adding new ones.
--
function Notes:clear()
    self.buf = {}
    self.width = 10
end



--- Add a note.
--
function Notes:note( fmt, ... )
    if #self.buf < self.max then
        local ent = str:fmtx( fmt, ... )
        self.width = math.max( self.width, #ent )
        self.buf[#self.buf + 1] = ent
    else
        self.buf[#self.buf] = "...other notes were discarded."
    end
end



--- Determine if any notes have been "logged".
--
function Notes:is()
    return #self.buf > 0
end



--- Get array of view items.
--
-- @return (array) of view-items: currently a 1 element array containing a scroller.
--
function Notes:getViewItems( params )
    app:callingAssert( params, "no params" )
    local call = app:callingAssert( params.call, "no call in params" )
    if not tab:isArray( self.buf ) then return nil end
    local lines = #self.buf -- max ###1
    local evi = params.editViewOptions or {}
    local svi = params.scrollViewOptions or {}
    local strng = table.concat( self.buf, "\n" )
    local props = params.props or LrBinding.makePropertyTable( call.context )
    props.notes = strng
    local tf = vf:edit_field( tab:mergeSets( {
        value = binding:bind( props, 'notes' ),
        width_in_chars = self.width + 1, -- 'snuff? ###1
        height_in_lines = lines
    }, evi ) )
    return { vf:scrolled_view( tab:mergeSets( {
        tf,
        width = 400,
        height = 200,
    }, svi ) ) }
end



return Notes
