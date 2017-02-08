--[[
        XmlBuffer.lua
        
        Originally based on code published at http://lua-users.org/wiki/LuaXml - thank you.
        
        This module replaces Xml.lua (which is now deprecated).
        
        Note: this module is to be used for xml documents that are well behaved:
            - no funny characters
            - no CDATA
            - xml declaration is presently hardcoded
            (not sure what else...)
            
        Present output format puts attributes on separate lines, unless there is only one, and elements with only text on a single line.
        Indentation can be specified to taste.
        Serialization is deterministic - same document always generates same string and vice versa.
              
        This module will also serialize/de-serialize lua tables - output table will always be exactly same as input table.
--]]

local XmlBuffer, dbg, dbgf = Object:newClass{ className = 'XmlBuffer', register = true }



--- Constructor for extending class.
--
function XmlBuffer:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function XmlBuffer:new( t )
    return Object.new( self, t )
end



--   A T T R I B U T E   C L A S S   ( P R I V A T E   -   O B J E C T   R E T U R N E D   I S   A C C E S S E D   V I A   I T S   M E T H O D S )

local Attributes = Object:newClass{ className='XmlAttributes', register=false }

--- Create an object that represents an xml element's attributes.
--
--  @param attrTable (table, optional) array of items with a name and text member for each attribute, or a name/text lookup table.
--
function Attributes:new( attrTable )
    local o = Object.new( self )
    o.array = attrTable or {}
    o.lookup = {}
    if attrTable then
        for i, v in ipairs( attrTable ) do
            o.lookup[v.name] = v
        end
    end
    return o
end



--- Get specified attribute by name.
--
--  @param name (string, required) attribute name
--
--  @return value (string) attribute value as string, or nil if no attribute with specifed name.
--
function Attributes:getAttrText( name )
    -- return self.lookup[name] - until 18/Mar/2013 4:14
    -- since 18/Mar/2013 4:14 --
    local attr = self.lookup[name]
    if attr then
        return attr.text
    else
        return nil
    end
end



--- Iterates attributes.
--
--  @usage example: for name, text in attrs:iterator() do..
--
function Attributes:iterator()
    local index = 0
    return function()
        index = index + 1
        if index <= #self.array then
            return self.array[index].name, self.array[index].text
        else
            return nil
        end
    end
end



--- Set specified attribute value.
--
--  @param name (string, required) name of attribute.
--  @param value (any, required) any serializable value (serialized by global lua tostring function, tostring method in metatable, or toString class method if available).
--
--  @usage If attribute does not exist, it will be created (changed 18/Mar/2013 4:25 - before that, an error would be thrown) - consider checking usage ###2.
--  @usage There is presently no method to remove attributes. ###3
--
function Attributes:setAttrValue( name, value )
    if value ~= nil then
        local attr = self.lookup[name]
        if not attr then
            local ent = { name=name, text=str:to( value ) }
            self.array[#self.array + 1] = ent
            self.lookup[name] = ent
        else
            attr.text = str:to( value )
        end
    else
        app:callingError( "You can't set attribute values to nil" )
    end
end



--- Get specified attribute (string) value.
--
function Attributes:getAttrValue( name )
    local attr = self.lookup[name]
    if attr then
        return attr.text
    else
        return nil
    end
end



--- Add an attribute as name/value pair.
--
--  @param name (string, required) name of attribute.
--  @param value (any, required) any serializable value (serialized by global lua tostring function, tostring method in metatable, or toString class method if available).
--
--  @usage attribute must NOT already exist, else calling error is thrown.
--
function Attributes:addAttr( name, value )
    if self.lookup[name] then
        app:callingError( "Use set-attr-value to set existing attribute values." )
    else
        local v = str:to( value )
        -- until 18/Mar/2013 4:17
        -- self.lookup[name] = v
        -- self.array[#self.array + 1] = { name=name, text=v }
        -- after 18/Mar/2013 4:18 --
        local ent = { name=name, text=v }
        self.array[#self.array + 1] = ent
        self.lookup[name] = ent
    end
end



--- Serialize attributes.
--
--  @return s (string) blank string if none, else name="value"... (space separated).
--
function Attributes:serialize( ind )
    local b = {}
    -- assert( #self.array == tab:countItems( self.lookup ), "afu" ) - not a problem.
    for i, v in ipairs( self.array ) do
        b[#b + 1] = "\n" .. ind .. v.name .. '="' .. v.text .. '"'
    end
    if #b > 1 then
        return table.concat( b, "" )
    elseif #b == 1 then
        return b[1]:sub( ind:len() + 2 ) -- remove leading line-feed.
    else
        return ""
    end
end



--   E L E M E N T   C L A S S   ( P R I V A T E   -   O B J E C T   R E T U R N E D   I S   A C C E S S E D   V I A   I T S   M E T H O D S )

local Element = Object:newClass{ className = 'XmlElement', register = false }

---  Create an xml element.
--  
--  @param t (table, optional) default members.
--
function Element:new( t )
    local o = Object.new( self, t )
    return o
end



--- Add child element.
--
--  @param elem (Element, required) element to add.
--
function Element:addChild( elem )

    if #self == 0 then
        self[1] = elem
    else
        self[#self + 1] = elem
    end

end



--- Get array of child element nodes.
--
function Element:getChildren()
    return self
end



--- Get number of children.
--
function Element:getChildCount()
    return #self
end



--- Get child element node specified by index.
--
function Element:getChildAtIndex( i )
    return self[i]
end
Element.getChildAt = Element.getChildAtIndex -- function Element:getChildAt(...) -- synonym.



--- Get attributes object.
--
--  @return Attributes.
--
function Element:getAttributes()
    return self.attrs
end



--- Get element name - excluding namespace.
--
function Element:getName()
    if not str:is( self.name ) then
        return self.label
    else
        return self.name
    end
end



--- Get element namespace.
--
function Element:getNamespace()
    return self.ns
end



--- Get textual content, if any.
--
--  @usage      Content may need to be unescaped externally. CDATA not supported.
--
function Element:getText()
    return self.text
end



--- Set textual content.
--
--  @usage      Does not support CDATA, and escaping must be done externally, if required. ###2
--
function Element:setText( text )
    self.text = text
end



--- Serialize element, and all its children.
--
--  @usage      indentation presently hardcoded to start at zero
--
function Element:serialize( initialIndentation, spacesPerIndent )
    local function _serialize( node, indent, spaces ) -- serialize element node
        local ns = node:getNamespace()
        local name
        if str:is( ns ) then
            name = ns .. ':' .. node:getName()
        else
            name = node:getName()
        end
        local s = indent .. '<' .. name
        local sa = node.attrs:serialize( indent .. spaces )
        if str:is( sa ) then
            s = s .. ' ' .. sa
        end
        local t = node:getText()
        if str:is( t ) and #node == 0 then
            s = s .. '>' .. t .. '</' .. name .. ">\n"
        else
            local nodelets = node:getChildren()
            if #nodelets > 0 then
                s = s .. '>\n'
                for i, v in ipairs( nodelets ) do
                    s = s .. _serialize( v, indent .. spaces, spaces )
                end
                if str:is( t ) then
                    s = s .. indent .. spaces .. t .. "\n"
                end
                s = s .. indent .. '</' .. name .. ">\n"
            else
                s = s .. "/>\n"
            end
        end
        return s
    end
    initialIndentation = initialIndentation or ""
    spacesPerIndent = spacesPerIndent or 2
    local spaces = string.rep( " ", spacesPerIndent )
    return _serialize( self, initialIndentation, spaces )    
end
        


--   D O C U M E N T   C L A S S   ( P R I V A T E   -   O B J E C T   R E T U R N E D   I S   A C C E S S E D   V I A   I T S   M E T H O D S )

local Document = Element:newClass{ className='XmlDocument', register=false }

--- Create an xml document, which is essentially just an xml element, plus an optional preamble, and encoding.
--  
--  @param t (table, optional) initial members.
--
function Document:new( t )
    local o = Element.new( self, t )
    return o
end



--- Serialize xml document.
--
function Document:serialize()
    local r = self:getRoot()
    if r then
        local s = r:serialize()
        if self.includePreamble then
            return '<?xml version="1.0"?>\n' .. s
        else
            return s
        end 
    else
        return nil -- watch for it.
    end
end



--- Get xml declaration header as text string.
--
function Document:getDecl()
    return self[1]
end



--- Get root element.
--
function Document:getRoot()
    return self[2]
end



--      Synopsis:           Parse a table of attributes from an attribute string.
--      
--      Table Format:       array of items whose format is:
--      
--                              - name
--                              - text
--                              
--
function XmlBuffer:_parseAttrs(s)
  local args = {}
  string.gsub(s, "([%w:%-_]+)=([\"'])(.-)%2", function (w, _, a)
    -- _debugTrace( "pa", w )
    local arg = {}
    arg.name = w
    arg.text = a
    args[#args + 1] = arg
  end)
  return Attributes:new( args )
end



--      Synopsis:               Parse an xml string into a table of nested element tables.
--      
--      Table Element Format:   - ns
--                              - name
--                              - label (=ns:name)
--                              - attrs (see fmt above) - presently array of "name,text" table entries.
--                              - empty = 1, or text.
--
function XmlBuffer:_tabularize(s)
    local stack = {}
    local top = { Element:new{} }
    stack[1] = top
    local ni, c, label, attrs, empty
    local i, j = 1, 1
    while true do
        ni, j, c, label, attrs, empty = string.find(s, "<(%/?)([%w:%-_]+)(.-)(%/?)>", i)
        if not ni then
            break
        end
        local text = s:sub( i, ni - 1 )
        if not text:find( "^%s*$" ) then
            -- _debugTrace( "xml inserting text ", text )
            top[#top]:setText( text )
        end
        if empty == "/" then    -- empty element tag
            -- _debugTrace( "xml inserting empty" )
            local a = str:split( label, ':' )
            local ns, nm
            if #a == 2 then
                ns = a[1]
                nm = a[2]
            else
                Debug.pause()
                ns=''
                nm=''
            end
            local elem = Element:new{ ns=ns, name=nm, label=label, attrs=self:_parseAttrs(attrs) }
            
            --if ns == "rdf" and nm == "li" and attrs:find( "Gradient" ) then
            --    Debug.lognpp( "Gradient elem", elem )
            --end
            
            local toAdd = stack[#stack]
            toAdd[#toAdd + 1] = elem
            
        elseif c == "" then     -- start tag
            local a = str:split( label, ':' )
            local ns, nm
            if #a == 2 then
                ns = a[1]
                nm = a[2]
            else
                ns=''
                nm=''
            end     
            top = { Element:new{ ns=ns, name=nm, label=label, attrs=self:_parseAttrs(attrs) } }
            -- _debugTrace( "xml inserting ", top.label )
            stack[#stack + 1] = top[1]     -- new level
        else    -- end tag
            local toclose = stack[#stack]
            stack[#stack] = nil    -- remove top
            top = stack[#stack]
            if #stack < 1 then
                app:error( "nothing to close with ^1", label)
            end
            if toclose.label ~= label then
                app:error( "trying to close ^1 with ^2", toclose.label, label)
            end
            top[#top + 1] = toclose
        end
        i = j + 1
    end
    local text = s:sub( i )
    if not text:find( "^%s*$" ) then
        if stack[#stack].setText then
            stack[#stack]:setText( text )
        else
            -- Debug.pause() -- this is happening, but parsing is ok nevertheless.
            -- Debug.lognpp( stack[#stack] ) -- seems to be the whole thang.
            -- app:error( "whatever is at stack top, is not an element: ^1", str:to( stack[#stack] ) )
        end
    end
    if #stack > 1 then
        app:error( "unclosed ^1", stack[#stack].label )
    end
    return stack[1]
end



--      Synopsis:               Convert array of attributes to xml string.
--      
--      Array Item Format:      attrs.name -- attribute ns:name.
--                              attrs.text -- attribute value string.
--                              
--      Note:                   If spaces are being used for indenting, then arguments are put one per line (indented) - just like in an XMP file.
--
function XmlBuffer:_serializeAttributes( attrs )
    local args = ''
    for i,v in ipairs( attrs ) do
        args = args .. ' ' .. v.name .. '="' .. v.text .. '"'
        if str:is(spaces) and (i ~= #attrs) then
            args = args .. '\n' .. spaces .. ' '
        end
    end
    return args
end



--  Only used for lua serializer.
function XmlBuffer:_spaces( level )
    return string.rep( " ", level * self.nSpaces )
end



--  Presently only used for lua serializer, although could be adapted for general use.
--
--  Not a general purpose xml unescaper - one of the nice things about having a limited
--  custom xml parser, is its easy to predict which data characters might foil it.
--  For this parser, just the angle brackets are dangerous, since they could represent
--  a false tag or end-tag marker - the rest should be OK (fingers-crossed).
--  uses custom escaping, so its clear this handling is making no attempt to comply
--  with any standard - for what I think and hope is good reason.
function XmlBuffer:_escape( original )
    if not str:is( original ) then
        return ""
    end
    local escaped = original:gsub( "[<>]", function( c )
        Debug.logn( "Escaping", c )
        local sub
        if c == "<" then
            sub = "${LEFT-ANGLE-BRACKET}"
        elseif c == ">" then
            sub = "${RIGHT-ANGLE-BRACKET}"
        else
            app:logWarning( "Unable to escape '^1' character for xml encoding - returning verbatim and hoping for best...", c )
            sub = c
        end
        return sub
    end )
    return escaped
end



--  Presently only used for lua serializer, although could be adapted for general use.
--
function XmlBuffer:_unescape( escaped )
    if not str:is( escaped ) then
        return ""
    end
    local original = escaped:gsub( '(%${[%w-]-})', function( sub )
        local c
        Debug.logn( "Unescaping", sub )
        if sub == '${LEFT-ANGLE-BRACKET}' then
            c = '<'
        elseif sub == '${RIGHT-ANGLE-BRACKET}' then
            c = '>'
        else
            app:logVerbose( "Unable to unescape '^1' sub while parsing xml - returning verbatim - it is recommended to not use this pattern in your data...", sub )
            c = sub
        end
        return c
    end )
    return original
end



--		Synopsis:           converts lua table to string, typically for writing to a file upon return.
--		
--		Notes:              - multi-line format, like xmp files.
--		                    - recursive.
--
function XmlBuffer:_serializeLua( lua, indentLevel, attrStr )
    local s
    indentLevel = indentLevel or 0
    local sp = self:_spaces( indentLevel )
    if type( lua ) == 'string' then
        s =  str:fmt( '^3<string^2>^1</string>\n', self:_escape( lua ), attrStr, sp )
    elseif type( lua ) == 'number' then
        s = str:fmt( '^3<number^2>^1</number>\n', lua, attrStr, sp )
    elseif type( lua ) == 'boolean' then
        s = str:fmt( '^3<boolean^2>^1</boolean>\n', str:to( lua ), attrStr, sp )
    elseif type( lua ) == 'table' then
        s = str:fmt( '^2<table^1>\n', attrStr, sp )
        for k, v in pairs( lua ) do
            s = s .. self:_serializeLua( v, indentLevel + 1, str:fmt( ' i="^1" t="^2"', str:to( k ), type( k ) ) )
        end
        s = s .. str:fmt( '^1</table>\n', sp )
    else
        app:logVerbose( "Can not serialize type '^1'", type( lua ) )
    end
    return s
end



--- Load xml string into xml table.
--
--  @param          xml (string, optional) Typically as read from file, but could be manufactured, or nil to create blank document.
--
--  @usage			returned table can be modified, then re-written.
--
--	@return		    xmlDocument (Document) xml document instance.
--
function XmlBuffer:newDocument( xml, includePreamble )
    if xml ~= nil then
        if type( xml ) == 'string' then
        	local elem = self:_tabularize( xml ) -- parse
      	    return Document:new( elem )
      	else
      	    app:callingError( "xml must be string, not ^1", type( xml ) )
      	end
    else
        return Document:new{ includePreamble=includePreamble } -- create a blank document, with optional preamble.
    end
end



--- Converts lua table (or simple variable) to string, typically for writing to a file upon return.
--		
--  @param              luaT (lua table, required) actually can be a simple variable too, but in practice is nearly always a table.
--  @param              includeDecl (boolean, default=false) include declaration prefix
--  @param              nSpaces (number, default=2) number of spaces per indent.
--
--	@usage              Serializes in multi-line format, like xmp files.
--
--  @return             xml string, with optional decl sans char encoding, unix-style eol.
--
function XmlBuffer:serializeLua( luaT, includeDecl, nSpaces )
    self.nSpaces = nSpaces or 2
    local s = self:_serializeLua( luaT )
    if includeDecl then
        return '<?xml version="1.0"?>\n' .. s -- default character encoding.
    else
        return s
    end
end



--  Converts serialized xml string to lua table (or simple variable). THIS FUNCTION IS COMMENTED OUT: SAVED FOR NOSTALGIA I GUESS..
--		
--  @param              xmlString (string, required) xml string - if blank returns empty table (if nil returns nil).
--  @param              expectDecl (boolean, default=false) if true, parse fails if no decl.
--
--  @usage              ### *** this method has never been tested - consider lua-text object instead.
--  @usage              does not support generic xml, only as serialized by this module.
--  @usage              reminder: attributes are only used for storing index value & type, and only string and number types are supported,<br>
--                      since the whole point of this exercise is serialization/de-serialization, it hardly makes sense to have a table object as index.
--
--  @return             lua table - sans decl
--[=[
function XmlBuffer:______parseToLua( xmlString, expectDecl )

                    app:callingError( "###2" ) -- I don't think this is being used anymore - replaced by LuaText module. If wrong see ### below.
                
                    local _xt = self:_tabularize( xmlString )
                    if _xt == nil then
                        return nil
                    end
                    if expectDecl then
                        if tab:isEmpty( _xt[1] ) then
                            return false
                        end
                    end
                    if tab:isEmpty( _xt[2] ) then
                        return {}
                    end
                    local xt = _xt[2]
                    Debug.lognpp( xt )
                    Debug.logn( '\n\n' )
                    assert( xt.getName ~= nil, "not elem" )
                    -- convert internal representation to original lua format.
                    -- elem is xml element to be converted
                    -- luaT is lua table to receive converted element.
                    -- index may be key-string or numeric array index, or nil if element is a table item wrapper.
                    local function convertElement( elem, luaT )
                        local name = elem:getName()
                        local lookup = elem:getAttributeLookup() -- ### this method no longer exists.
                        local value
                        local index
                        if not tab:isEmpty( lookup ) then
                            local index_text = lookup['i'] -- ### bug
                            local index_type = lookup['t']
                            if index_type == 'string' then
                                index = index_text
                            elseif index_type == 'number' then
                                index = tonumber( index_text )
                            else
                                app:error( "bad index type: ^1", str:to( index_type ) )
                            end
                        end
                        if name == 'string' then
                            value = self:_unescape( elem:getText() )
                        elseif name == 'number' then
                            value = tonumber( elem:getText() )
                        elseif name == 'boolean' then
                            value = bool:booleanFromString( elem:getText() )
                        elseif name == 'table' then
                            local tbl = {}
                            for i, v in ipairs( elem:getChildren() ) do
                                convertElement( v, tbl )
                            end
                            value = tbl
                        end
                        Debug.lognpp( "index/value", index, value )
                        if index ~= nil then
                            luaT[index] = value
                        else
                            luaT[1] = value
                        end
                    end
                    local t = {}
                    convertElement( xt, t )
                    return t[1]
end
--]=]



--- Parse xml string.
--
--  @param x (string, required) xml string.
--  @param decl (boolean, default=false) expect decl.
--
--  @return xmlDocument (private 'Document' class) accessed via methods.
--
function XmlBuffer:parseXml( x, decl )
    if type( x ) == 'string' then
        return self:newDocument( x, decl )
    else
        app:callingError( "x must be string" )
    end
end



--- Convert xml document to string.
--
--  @usage throws errors if problems.
--
--  @param xdoc (private 'Document' class) initially gotten by parsing xml string - may be since modified.
--  @param initialIndentationSpaceString (string, default = "") spaces to indent root.
--  @param numberOfSpacesPerIndentLevel (number, default = 2) number of additional spaces per nesting level.
--
--  @return s (string) for display or disk storage...
--
function XmlBuffer:serialize( xdoc, initialIndentationSpaceString, numberOfSpacesPerIndentLevel )
    if xdoc.serialize then
        return xdoc:serialize( initialIndentationSpaceString, numberOfSpacesPerIndentLevel )
    else
        app:callingError( "xdoc param must be 'Document' class instance." )
    end
end



return XmlBuffer
