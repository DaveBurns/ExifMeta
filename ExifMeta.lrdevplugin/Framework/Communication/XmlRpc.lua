--[[
        XmlRpc.lua
        
        Implements an object which supports client-mode xml-rpc (supports send/receive but won't listen) - note: although there is a global xml-rpc instance
        for talking to host server (e.g. for checking updates - I've implemented the server end in cold-fusion, if you want to see it for example, do tell..),
        you can create additional objects tied to target URL for other things, e.g. talking to amazon or google xml-rpc servers..
--]]

local XmlRpc, dbg, dbgf = Object:newClass{ className = 'XmlRpc' }



--- Constructor for extending class.
--
function XmlRpc:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @param      t       parameter table must include (non-nil / non-false) url, but it can be changed later if necessary.
--
function XmlRpc:new( t )
    local o = Object.new( self, t )
    if o.url then
    else
        error( "XmlRpc needs URL" )
    end    
    return o
end



--  Initializer for submission URL, in case not known at construction time.
--
--  @param      t       parameter table to include url.
--
function XmlRpc:_init( t )
    self.url = t.url
end



--- send rpc request, and fetch expected reply.
--
--  @param      t       (table or string, required)
--                      <br>If string, its the remote procedure name, and default timeout is implied.
--                      <br>If table, it must have procName in it, and optional timeout.
--  @param      ...     remote procedure parameters.
--
--  @return     sts         (boolean, always) true iff worked.
--  @return     msgOrValues (string or table) error message or array of return values, properly typed (may be empty table, but wont be nil).
--
function XmlRpc:sendAndReceive( t, ... )

    assert( self.url ~= nil, "Missing XmlRpc Url..." )

    local encodeArray
    local encodeStruct
    -- *** WARNING: No attempt is made to discern if array table has struct elems - struct elems will be ignored if looks like array.
    local function encodeValue( v )
        local val = v
        local typ = type( v )
        Debug.lognpp( "Encoding param: ", typ, val )
        if typ == 'table' then
           if #val > 0 or tab:isEmpty( val ) then -- looks like an array (encode empty tables as array)
               val = encodeArray( v )
               typ = 'array'
           else
               val = encodeStruct( v )
               typ = 'struct'                
           end
        elseif typ == 'string' then
           -- good
        elseif typ == 'number' then
           if num:isInteger( v ) then
               -- typ = 'int'
               typ = 'i4'
           else
               typ = 'double'
           end
        elseif typ == 'boolean' then
            if v then
                val = 1
            else
                val = 0
            end
        else
            error( "type not supported " .. typ )
        end
        return { value = val, type = typ }
    end
    local function encodeKeyValuePair( key, value )
        local kvp = { name = key }
        kvp.value = encodeValue( value )
        return kvp
    end
    local function encodeArray( array ) -- how is this not causing a strict global policy violation?
        Debug.lognpp( "Encoding array: ", array )
        local a = {}
        for i, v in ipairs( array ) do
            a[#a + 1] = encodeValue( v )
        end
        return a
    end
    local function encodeStruct( struct )
        Debug.lognpp( "Encoding struct: ", struct )
        local a = {}
        for k, v in pairs( struct ) do
            a[#a + 1] = encodeKeyValuePair( k, v )
        end
        return a
    end
    
    local name, tmo, params

    if type( t ) == 'table' then
        name = t.procName or error( "need proc-name" )
        tmo = t.timeout or 10
    else
        name = t
        tmo = 10
    end

    Debug.lognpp( "Decoding parameters for remote procedure call: " .. name )

    if name == 'reply' then
        Debug.lognpp( {...} )
    end
    
    -- first translate ... to type/value pairs: just to make the code simpler for now (albeit less efficient).
    params = {}
    for i,v in ipairs{ ... } do
        params[#params + 1] = encodeValue( v )
    end
    
    if name == 'reply' then
        Debug.lognpp( params )
    end

    local bldr = LrXml.createXmlBuilder( false ) -- false => include decl.
    
    local buildStruct
    local buildArray
    local function buildValue( v )
        Debug.lognpp( "building param value", v )
        bldr:beginBlock( "value" )
        if v.type == 'array' then
            buildArray( v.value )
        elseif v.type == 'struct' then
            buildStruct( v.value )
        else
            bldr:tag( v.type, v.value )
        end
        bldr:endBlock()
    end
    local function buildArray( a )
        Debug.lognpp( "building array param", a )
        bldr:beginBlock( "array" )
        bldr:beginBlock( "data" )
        for i, v in ipairs( a ) do
            buildValue( v )            
        end
        bldr:endBlock()
        bldr:endBlock()
    end
    local function buildStruct( a )
        Debug.lognpp( "building struct param", a )
        bldr:beginBlock( "struct" )
        for i, v in ipairs( a ) do
            bldr:beginBlock( "member" )
            bldr:tag( 'name', v.name )
            bldr:beginBlock( "value" )
                bldr:tag( v.value.type, v.value.value )
            bldr:endBlock()
            bldr:endBlock()
        end
        bldr:endBlock()
    end
    
    bldr:beginBlock( "methodCall" )
    bldr:tag( "methodName", name ) -- no attrs
    if params and #params > 0 then
        bldr:beginBlock( "params" )
        for i,v in ipairs( params ) do
            bldr:beginBlock( "param" )
            buildValue( v )
            bldr:endBlock()
        end
        bldr:endBlock()
    end 
    bldr:endBlock()
    
    local xmlReq = bldr:serialize()
    
    dbg( "req:", xmlReq, "url:", self.url, "tmo:", tmo )
    
    
    
    
    local reqHdrs = {}
    reqHdrs[#reqHdrs + 1] = { field='Content-Length', value='' .. xmlReq:len() }
    
    --   S E N D   X M L   R E Q U E S T   A N D   R E C E I V E   R E P L Y
    --local body, hdrs = LrHttp.post( self.url, xmlReq, reqHdrs, "POST", tmo ) -- this would be OK, but status check below for debug...
    local status, body, hdrs = LrTasks.pcall( LrHttp.post, self.url, xmlReq, reqHdrs, "POST", tmo )

    -- dbg( "hdrs: ", #hdrs )
    
    if status then
        if hdrs then
            if hdrs.status ~= nil then
                if hdrs.status ~= 200 then
                    return false, "Web server http response status: " .. hdrs.status
                else
                    -- fall-through to continue 
                end
            else
                Debug.lognpp( "hdrs", hdrs )
                return false, "Web server did not respond to http request (check internet connection)."
            end
        else
            return false, "LrHttp.post did not return header table."
        end
    else
        return false, "Unable to acquire HTTP post response: " .. str:to( body )
    end
    
    local start, stop = body:find( '<?xml', 1, true )
    if start then
        body = body:sub( start )
        dbg( "body: ", body )
    else
        error( "Spec requires xml declaration in response: " .. body:sub( 1, 100 ) )
    end
    
    local xml = LrXml.parseXml( body ) -- xml IS root node.
    if not xml then
        error( "Invalid response from " .. self.url .. " - unparsable xml." )
    end
    
    -- dbg( "root: ", xml:name() )
    if xml:name() ~= 'methodResponse' then
        error( "Invalid xml response from " .. self.url .. " - root node not method-response, is: " .. xml:name() )
    end
    
    local paramNode = xml:childAtIndex( 1 ) 
    if not paramNode then
        error( "Invalid xml response from " .. self.url .. " - no param node." )
    end

    -- note: this implementation requires at least a one-parameter response from the server.
    -- I dunno if the spec also thinks thats a good idea, but I sure do...
    if paramNode:name() == 'params' then

        local values = self:_getParamValues( paramNode )
        return true, values        
        
    elseif paramNode:name() == 'fault' then -- calling context decodes fault response.
    
        local faultStruct = self:_getFaultStruct( xml )
        return false, str:fmt( "RPC Server Fault, fault-code: ^1, fault-string: ^2", str:to( faultStruct.faultCode ), str:to( faultStruct.faultString ) )
        
    else
        error( "Invalid xml response from " .. self.url .. " - param node not recognized: " .. paramNode:name() )
    end
    
end



--  Get response parameter values.
--
--  @param      params      params node.
--
function XmlRpc:_getParamValues( params )

    local index = 0
    local max = params:childCount()
    
    local decodeArray
    local function decodeValue( valueNode )
        local typeNode = valueNode:childAtIndex( 1 )
        if typeNode:name() == 'array' then
            return decodeArray( typeNode:childAtIndex( 1 ) ) -- data node
        else
            local typ = typeNode:name()
            local val = typeNode:text()
            if typ == 'string' then
                -- good to go
            elseif typ == 'int' or typ == 'i4' then
                val = tonumber( val )
            elseif typ == 'boolean' then
                if val == "1" then
                    val = true
                elseif val == "0" then
                    val = false
                else
                    error( "bad boolean" )
                end
            elseif typ == 'double' then
                val = tonumber( val )
            elseif typ == 'array' then
                val = decodeArray( val )
            else
                error( "type not implemented: " .. typ )
            end
            return val
        end
    end
    function decodeArray( dataNode )
        assert( dataNode:name() == 'data', "not data" )
        local a = {}
        local max = dataNode:childCount()
        for i = 1, max do
            a[#a + 1] = decodeValue( dataNode:childAtIndex( i ) )
        end
        return a
    end

    local values = {}
    for index = 1, max do    
        local node = params:childAtIndex( index )
        if node then -- param node
            local valueNode = node:childAtIndex( 1 ) -- value node
            if valueNode:name() == 'value' then
                values[#values + 1] = decodeValue( valueNode )
            else
                error( "Invalid value node name." )
            end
        else
            error( "No param node." )
        end
    end
    return values

end



--  Iterate response parameters, given original xml response.
--
--  @param      xml     (xmlDomInstance) original xml response.
--
--  @return     (table) { faultCode=..., faultString=... }
--
function XmlRpc:_getFaultStruct( xml )

    local fault = xml:childAtIndex( 1 ) -- xml is method-response (root).
    local struct = {}
    
    local valueNode = fault:childAtIndex( 1 )
    if valueNode then -- value node
        local structNode = valueNode:childAtIndex( 1 )
        if structNode:name() == 'struct' then
            local memberNode = structNode:childAtIndex( 1 )
            if memberNode:name() == 'member' then
                local nameNode = memberNode:childAtIndex( 1 )
                if nameNode:name() == 'name' then
                    if nameNode:text() == 'faultCode' then
                        local valueNode = memberNode:childAtIndex( 2 ):childAtIndex( 1 ) -- skipping over the type.
                        if valueNode then
                            local faultCode = num:numberFromString( valueNode:text() )
                            if faultCode then
                                struct.faultCode = faultCode
                            else
                                error( "No fault code" )
                            end
                        else
                            error( "No fault code value node" )
                        end
                    else
                        error( "No fault code name node" )
                    end
                else
                    error( "bogus fault code name" )
                end
            else
                error( "no fault code member" )
            end
            
            memberNode = structNode:childAtIndex( 2 )
            if memberNode:name() == 'member' then
                local nameNode = memberNode:childAtIndex( 1 )
                if nameNode:name() == 'name' then
                    if nameNode:text() == 'faultString' then
                        local valueNode = memberNode:childAtIndex( 2 ):childAtIndex( 1 ) -- skipping over the type.
                        if valueNode then
                            local faultString = valueNode:text()
                            if str:is( faultString ) then
                                struct.faultString = faultString
                            else
                                error( "No fault string" )
                            end
                        else
                            error( "No fault string value node" )
                        end
                    else
                        error( "No fault string name node" )
                    end
                else
                    error( "bogus fault string name" )
                end
            else
                error( "no fault string member" )
            end
            
        else
            error( "no fault struct" )
        end
    else
        error( "no fault value node" )
    end

    return struct                        

end



return XmlRpc