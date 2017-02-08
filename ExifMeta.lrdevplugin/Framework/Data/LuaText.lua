--[[
        LuaText.lua
        
        Object with methods to serialize / deserialize lua objects or data tables for storage / retrieval.
        
        Originally motivated by the neeed to store develop settings of virtual copies as pseudo-xmp, without having to write special handling
        for tabular adjustments like point curve and locals.
        
        But could be used to create lua objects that save state on disk.
--]]


local LuaText, dbg, dbgf = Object:newClass{ className = 'LuaText', register = true }



--- Constructor for extending class.
--
function LuaText:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function LuaText:new( t )
    return Object.new( self, t )
end



--  Serialize lua data table t, recursively.
--
--  Acknowlegement: This method based on John Ellis' Debug.pp function.
--
function LuaText:_serialize( value, indent )

    if not indent then indent = 4 end
    local maxLines = 50000 -- for sanity.
    --local maxChars = maxLines * 200 -- 10MB
    
    local s = {}
    local line = ""
    local tableLabel = {}
    local nTables = 0    

    local function addNewline (i)
        if #s >= maxLines then return true end
        if indent > 0 then
            s[#s + 1] = line
            line = string.rep (" ", i)
        end
        return false
    end

    local function isSDKObject (x)
        if type (x) ~= "table" then
            return false
        elseif app:lrVersion() < 4 then
            return type (getmetatable (x)) == "string"
        else
            local success, value = pcall (getmetatable, x)
            return not success or type (value) == "string"
        end
    end

    local function pp1 (x, i)
        if type (x) == "string" then
            line = line .. string.format ("%q", x):gsub ("\n", "n")
            
        elseif type (x) ~= "table" then
            line = line .. tostring (x)

        elseif isSDKObject(x) then
            line = line .. tostring (x)
            
        else
            if tableLabel [x] then
                -- s = s .. tableLabel [x] 
                return false
                end
            
            local isEmpty = true
            for k, v in pairs (x) do isEmpty = false; break end
            if isEmpty then 
                line = line .. "{}"
                return false
                end

            nTables = nTables + 1
            local label = "table: " .. nTables
            tableLabel [x] = label
            
            line = line .. "{" 
            -- if indent > 0 then s = s .. "--" .. label end
            local first = true
            for k, v in pairs (x) do
                if first then
                    first = false
                else
                    line = line .. ", "
                end
                if addNewline (i + indent) then return true end 
                if type (k) == "string" and k:match ("^[_%a][_%w]*$") then
                    line = line .. k
                else
                    line = line .. "["
                    if pp1 (k, i + indent) then return true end
                    line = line .. "]"
                end
                line = line .. " = "
                if pp1 (v, i + indent) then return true end
            end
            line = line .. "}"
        end

        return false
    end
    
    local v = pp1 ( value, 0 )
    s[#s + 1] = line
    return table.concat( s, "\n" )

end



--  Private method to deserialize previously serialized lua data table from.
function LuaText:_deserialize( s, name )
    local func, err = loadstring( s, name ) -- returns nil, errm if any troubles: no need for pcall (short chunkname required for debug).
    if func then
        local result = {}
        result[1], result[2] = func() -- throw error, if any.
        if result[2] ~= nil then
            error( "Custom lua deserializer only supports a value" )
        else
            return result[1]
        end
    else
        --return nil, "loadstring was unable to load contents returned from: " .. tostring( file or 'nil' ) .. ", error message: " .. err -- lua guarantees a non-nil error message string.
        local x = err:find( name )
        if x then
            err = err:sub( x ) -- strip the funny business at the front: just get the good stuff...
        elseif err:len() > 77 then -- dunno if same on Mac
            err = err:sub( -77 )
        end
        return nil, err -- return *short* error message
    end
end



--- Serialize lua data object, typically a table.
--
--  @param t the lua table or simple variable to be serialized.
--
--  @usage excludes the dressing needed to use said table upon deserialization, so make sure you precede it with a "return " or "myTbl = " or something.
--
--  @return serialized lua code or nil (never empty string).
--
function LuaText:serialize( t )
    local s = self:_serialize( t, 4 ) -- starting indent = 4 (at the moment, I'm not sure why this isn't zero).
    if str:is( s ) then -- probably worked.
        return s
    else -- definitely didn't (assuming t was some actual lua code).
        return nil
    end
end



--- Deserialize previously serialized lua data table from s, and optionally: assign to object o.
--
--  @param  s       the lua format string to deserialize.
--  @param  name    optional chunk name in case of error.
--  @param  o       optional table to receive deserialized key/values (I can no longer remember the reason for this).
--
--  @return lua table object
--
function LuaText:deserialize( s, name, o )
    if not str:is( name ) then
        if o ~= nil then
            name = str:to( o )
        else
            name = "unknown chunk"
        end
    end
    local t, err = self:_deserialize( s, name )
    if t ~= nil then
        if not o then
            return t
        else -- why not just always return t, and let calling context do add-items if called for (either something important I no longer remember, or I didn't understand something when I wrote this..).
            for k, v in pairs( t ) do
                o[k] = v
            end
            return o
        end
    else
        return nil, err
    end
end



return LuaText
