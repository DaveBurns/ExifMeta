--[[
        ScrollView.lua
        
        The magic of the scroll view is in the binding.
--]]

local ScrollView, dbg = Object:newClass{ className = 'ScrollView' }


ScrollView.down = false
ScrollView.up = true



--- Constructor for extending class.
--
function ScrollView:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @param      t       Parameter table:
--                      <ul>
--                      <li>global (boolean, required) governs whether global or local pref bindings are used.
--                      <li>pageSize (number, default: nil) set in constructor, or further on down the road, but do set.
--                      <li>dataSize (number, default: nil) set in constructor, or further on down the road, but do set.
--                      </ul>
--
--  @usage      wraps a row view for scrolling or paging.
--
function ScrollView:new( t )
    assert( t.global ~= nil, "scroll-view needs global param." )
    local o = Object.new( self, t )
    o.pos = 1
    return o
end



--- Set number of rows in a page.
--
--  @param      nRows       (number, required) Number of items in a page.
--
--  @usage      If set in constructor, this method is not necessary, otherwise it is.
--  @usage      Designed with rows in mind, but could just as easily be columns, or even sprinkled about.
--
function ScrollView:setPageSize( nRows )
    self.pageSize = nRows
end



--- Set total number of rows to be scrolled or paged.
--
--  @param      nRows       (number, required) Number of items total.
--
--  @usage      If set in constructor, this method is not necessary, otherwise it is.
--  @usage      Designed with rows in mind, but could just as easily be columns, or even sprinkled about.
--
function ScrollView:setDataSize( nRows )
    self.dataSize = nRows
end



--  Set scroll position, which must be in range.
--
function ScrollView:_setPos( pos )
    self.pos = pos -- change all at once so bindings dont jump around.
    --[[ OBS: if self.global then
        app:setGlobalPref( '__upd__', not app:getGlobalPref( '__upd__' ) ) -- trigger a redraw
    else
        app:setPref( '__upd__', not app:getPref( '__upd__' ) ) -- trigger a redraw
    end--]]
end



--- Get actual scroll position.
--
function ScrollView:getScrollPos()
    return self.pos
end



--- Compute new scroll position, if necessary, to assure position is in range.
--
function ScrollView:confineScrollPos( pos )
    -- keep bounded:    
    if pos < 1 then
        pos = 1
    else
        if (self.pageSize < self.dataSize) then
            if (pos > self.dataSize - self.pageSize + 1) then
                pos = self.dataSize - self.pageSize + 1
            end
        else
            pos = 1
        end
    end
    return pos
end



--- Scroll or page the view.
--
--  @param up (boolean, required) true => scroll one upward (pass true in response to up(1) button).
--  @param num (number, default one page) 1 => scroll one row. nil means scroll one page. Huge => all the way.
--
--  @usage call in response to scroll buttons.
--
function ScrollView:scroll( up, num )
    self:_setPos( self:computeScrollPos( up, num ) )
end



--- Compute new scroll position, given specified adjustment.
--
--  @param up (boolean, default nil) true => scroll upward, false => scroll one downward, nil => just update scroll position by confining.
--  @param num (number, default one page) 1 => scroll one row. nil means scroll one page. Huge => all the way. Ignored if up is nil.
--
--  @usage call in response to scroll buttons.
--
function ScrollView:computeScrollPos( up, num )

    assert( self.dataSize, "need total rows" )
    assert( self.pageSize, "need page size" )

    local amount
    if num == nil then
        amount = self.pageSize
    else
        amount = num
    end
    
    local pos
    
    if up == nil then
        pos = self.pos
    elseif up == true then
        pos = self.pos - amount
    elseif up == false then
        pos = self.pos + amount
    end        
        
    return self:confineScrollPos( pos )
    
end



--- Iterator: delivers visible row indexes 1 - N,
--  where N is between nil and number of rows on a page.
--  Its short when there isn't enough data to fill the page (based on item count).
--  visible index is paired with data item index.
--  @usage call data-indexes followed by fill-indexes.
--
function ScrollView:dataIndices()
    self.propIndex = 1
    self.row = self.pos
    return function()
        if self.row <= self.dataSize and self.propIndex <= self.pageSize then
            self.row = self.row + 1
            self.propIndex = self.propIndex + 1
            return self.propIndex - 1, self.row - 1
        else
            return nil, nil
        end
    end
end



--- Returns iterator that returns prop index only, to fill balance of a page with nil for when data is short of a page.
--
function ScrollView:fillIndices()
    return function()
        if self.propIndex <= self.pageSize then
            self.propIndex = self.propIndex + 1
            return self.propIndex - 1
        else
            return nil
        end
    end
end



--- Get pref index for specified prop index.
--
--  @usage      This allows calling context to lookup the proper preference to set based on preference index when a scrollable property changes.
--
function ScrollView:getPrefIndex( propIndex )
    return propIndex + self.pos - 1
end



--- Set scroll position to specified value.
--
--  @param pos (number, required) row number for page top - will be confined if necessary to valid range.
--
--  @return actualPos (number) actual scroll position, after possible adjustment.
--
function ScrollView:setScrollPos( pos )
    pos = self:confineScrollPos( pos )
    self:_setPos( pos )
    return pos
end



--[=[ *** save for posterity: the binding method of scrolling was quite effective but majorly confusing to me.

--   B I N D S -  O B S ? ? ?


--  Get a global pref binding as specified in parameter table.
--
--  @param      t       parameter table
--                      <ul>
--                      <li>keys (table of strings, required) array of all keys for this data item.
--                      <li>index (number, required) row index this binding applies to.
--                      </ul>
--
function ScrollView:_getGlobalBinding( t )
    assert( t.bindingKeys, "no binding keys" )
    assert( t.prefKeys, "no pref keys" )
    assert( t.index, "no index" )
    local binding = {}
    if t.bindingKeys[#t.bindingKeys] ~= app:getGlobalPrefKey( "__upd__" ) then
        t.bindingKeys[#t.bindingKeys + 1] = app:getGlobalPrefKey( "__upd__" )
    end
    binding.keys = t.bindingKeys
    binding.bind_to_object = prefs
    binding.transform = function( value, toUi )
        local i = self.pos + t.index - 1
        local key = t.prefKeys[i]
        if toUi then
            return app:getGlobalPref( key )
        else
            app:setGlobalPref( key, value )
            return value
        end
    end
    return bind( binding )
end



--  Get a pref binding as specified in parameter table.
--
--  @deprecated         Use non-binding technique instead.
--
--  @param      t       parameter table
--                      <ul>
--                      <li>keys (table of strings, required) array of all keys for this data item.
--                      <li>index (number, required) row index this binding applies to.
--                      </ul>
--
function ScrollView:_getNonGlobalBinding( t )
    assert( t.bindingKeys, "no binding keys" )
    assert( t.prefKeys, "no pref keys" )
    assert( t.index, "no index" )
    local binding = {}
    if t.bindingKeys[#t.bindingKeys] ~= app:getPrefKey( "__upd__" ) then
        t.bindingKeys[#t.bindingKeys + 1] = app:getPrefKey( "__upd__" )
    end
    binding.keys = t.bindingKeys
    binding.bind_to_object = prefs
    binding.transform = function( value, toUi )
        local i = self.pos + t.index - 1
        local key = t.prefKeys[i]
        if toUi then
            return app:getPref( key )
        else
            app:setPref( key, value )
            return value
        end
    end
    return bind( binding )
end



--- Get a pref binding as specified in parameter table.
--
--  @param      t       parameter table
--                      <ul>
--                      <li>keys (table of strings, required) array of all keys for this data item.
--                      <li>index (number, required) row index this binding applies to.
--                      </ul>
--
function ScrollView:getBinding( t )
    if self.global then
        return self:_getGlobalBinding( t )
    else
        return self:_getNonGlobalBinding( t )
    end
end
--]=]


return ScrollView
