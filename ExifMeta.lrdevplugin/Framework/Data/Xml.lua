--[[
        Xml.lua
        
        Based on code published at http://lua-users.org/wiki/LuaXml - thank you.
        
        *** DEPRECATED - Use XmlMutable instead.
--]]

local Xml, dbg, dbgf = Object:newClass{ className = 'Xml', register = false }



--- Constructor for extending class.
--
function Xml:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Xml:new( t )
    return Object.new( self, t )
end



local indentLevel = 0
local indentSpaces = 1
local spaces = ''



--      Synopsis:           Parse a table of attributes from an attribute string.
--      
--      Table Format:       array of items whose format is:
--      
--                              - name
--                              - text
--                              
--
function Xml:_parseAttrs(s)
  local args = {}
  string.gsub(s, "([%w:]+)=([\"'])(.-)%2", function (w, _, a)
    -- _debugTrace( "pa", w )
    local arg = {}
    arg.name = w
    arg.text = a
    args[#args + 1] = arg
  end)
  return args
end



--      Synopsis:               Parse an xml string into a table of nested element tables.
--      
--      Table Element Format:   - ns
--                              - name
--                              - label (=ns:name)
--                              - xarg (see fmt above) - presently array of "name,text" table entries.
--                              - empty = 1, or text.
--
function Xml:_tabularize(s)
  local stack = {}
  local top = {}
  table.insert(stack, top)
  local ni,c,label,xarg, empty
  local i, j = 1, 1
  while true do
    ni,j,c,label,xarg, empty = string.find(s, "<(%/?)([%w:%-_]+)(.-)(%/?)>", i)
    if not ni then break end
    local text = string.sub(s, i, ni-1)
    if not string.find(text, "^%s*$") then
      -- _debugTrace( "xml inserting text ", text )
      table.insert(top, text)
    end
    if empty == "/" then  -- empty element tag
      -- _debugTrace( "xml inserting empty" )
      local a = str:split( label, ':' )
      local ns, nm
      if #a == 2 then
        ns = a[1]
        nm = a[2]
      else
        ns=''
        nm=''
      end   
      table.insert(top, {ns=ns, name=nm, label=label, xarg=self:_parseAttrs(xarg), empty=1})
    elseif c == "" then   -- start tag
      local a = str:split( label, ':' )
      local ns, nm
      if #a == 2 then
        ns = a[1]
        nm = a[2]
      else
        ns=''
        nm=''
      end   
      top = {ns=ns,name=nm,label=label, xarg=self:_parseAttrs(xarg)}
      -- _debugTrace( "xml inserting ", top.label )
      table.insert(stack, top)   -- new level
    else  -- end tag
      local toclose = table.remove(stack)  -- remove top
      top = stack[#stack]
      if #stack < 1 then
        error("nothing to close with "..label)
      end
      if toclose.label ~= label then
        error("trying to close "..toclose.label.." with "..label)
      end
      table.insert(top, toclose)
    end
    i = j+1
  end
  local text = string.sub(s, i)
  if not string.find(text, "^%s*$") then
    table.insert(stack[#stack], text)
  end
  if #stack > 1 then
    error("unclosed "..stack[stack.n].label)
  end
  return stack[1]
end




--      Synopsis:               Convert array of attributes to xml string.
--      
--      Array Item Format:      xarg.name -- attribute ns:name.
--                              xarg.text -- attribute value string.
--                              
--      Note:                   If spaces are being used for indenting, then arguments are put one per line (indented) - just like in an XMP file.
--
function Xml:_serializeAttributes( xarg )
    local args = ''
    for i,v in ipairs( xarg ) do
        args = args .. ' ' .. v.name .. '="' .. v.text .. '"'
        if str:is(spaces) and (i ~= #xarg) then
            args = args .. '\n' .. spaces .. ' '
        end
    end
    return args
end



--		Synopsis:           converts xml table to string, typically for writing to a file upon return.
--		
--		Notes:              - multi-line format, like xmp files.
--		                    - '_' prefixed version recurses itself.
--
function Xml:_serialize( xmlTable, omitDecl )
    local s = ''
    local name = nil
    -- top level elem
    spaces = ''
    if indentLevel > 0 then
        spaces = str:makeSpace( ( indentLevel - 1 ) * indentSpaces )
    end
    if type( xmlTable ) == 'table' then
        if xmlTable.label then
            s = s .. spaces .. "<" .. xmlTable.label
            name = xmlTable.label
        end
        if xmlTable.xarg then
            s = s .. self:_serializeAttributes( xmlTable.xarg )
        end
        if xmlTable.empty then
            s = s .. "/>\n"
            return s
        elseif str:is( s ) then
            s = s .. ">"
            if type( xmlTable[1] ) ~= 'string' then
                s = s .. '\n'
            end
        end
    elseif type( xmlTable ) == 'string' then
        s = s .. xmlTable
    end
    if type( xmlTable ) == 'table' then
        indentLevel = indentLevel + 1
        for i,v in ipairs( xmlTable ) do
            s = s .. self:_serialize( v )
        end
        indentLevel = indentLevel - 1
    end
    if indentLevel < 0 then
        error( "ill-formed document, else bug in parser or serializer" ) -- call in protected mode to trap this error.
    end
    if name then
        if type( xmlTable[1] ) ~= 'string' then
            s = s .. spaces:sub( 1, indentLevel - 1 )
        end
        s = s .. '</' .. name .. '>\n'
    end
    return s
end



--	'_' prefixed version recurses itself.
--
--- Converts xml table to string, typically for writing to a file upon return.
--		
--  @param              xmlTable        As read originally from by parse-xml method.
--  @param              omitDecl        boolean: true iff xml declaration sometimes present on line one is to be omitted.
--
--	@usage              Serializes in multi-line format, like xmp files.
--
function Xml:serialize( xmlTable, omitDecl )
    indentLevel = 0
    return self:_serialize( xmlTable, omitDecl )
end
    


--- Load xml string into xml table.
--
--  @param          xmlString   Typically as read from file, but could be manufactured...
--
--	@usage          Table Entry Format: - type, name, attrs, text.
--  @usage			returned table can be modified, then re-written.
--
--	@return		    tree-structured table with one entry per corresponding xml node.
--
function Xml:parseXml( xmlString )
	local xmlTable = self:_tabularize( xmlString )
	return xmlTable
end



return Xml
