--[[
        Filename:           TiffUtils.lua
        
        Synopsis:           Work never completed.

        Notes:              This module based on tiffdump.c which I got from Handmade Software, Inc.
                            - written by Allan N. Hessenflow. - Not sure how up-to-date it is.

        Public Functions:   - readFile
                            - reWriteFile

        Public Constants:   None.
             

--]]


local TiffUtils, dbg, dbgf = Object.register( 'TiffUtils' )








local chgDetBlockType = 0xE7 -- presently writes this type - not an app1 tag.
    -- will recognize any app block type - in case future requires the written type to change.
local chgDetMetadataSignature = 'com.robcole.tiff.metadata' -- this will be preceded by FF E7 {len1} {len2}
    -- Note: I could use a regex for matching the prefix too, but I'm not.

local xmpBlockType = 0xE1 -- typical app1 block tag.
local xmpMetadataSignature = 'http://ns.adobe.com/xmp/extension/' .. string.char( 0 ) -- this will be preceded by FF E1 {len1} {len2}
	-- note: there may be more than one of these in the file - I'm hoping the best one is always first - if not, it will need to be fixed.


local bigEndian = false





function TiffUtils.getIfdTableOffset( file )

    local byte0 = fso:getByte( file )
    local byte1 = fso:getByte( file )
    if byte0 and byte1 then
        -- good
    else
        return nil
    end
    if byte0 == 0x49 and byte1 == 0x49 then
        bigEndian = false
    elseif byte0 == 0x4D and byte1 == 0x4D then
        bigEndian = true
    else
        return "No endian"
    end
    local word1 = fso:getWord( file, bigEndian )
    if word1 == nil then return nil end
    if word1 == 42 then
        local word2 = fso:getWord( file, bigEndian )
        if word2 == nil then return nil end
        local word3 = fso:getWord( file, bigEndian )
        if word3 == nil then return nil end
        return word3 * 65536 + word2 -- assuming ls-word first - test this.
    else
        return "Not tif."
    end
    
end


function TiffUtils.getIfdTable( file )

    local ofs = TiffUtils.getIfdTableOffset( file )
    if ofs == nil then return nil end
    if type( ofs ) == 'number' then
        --
    elseif type( ofs ) == 'string' then
        return nil, ofs
    else
        error( "Program failure - invalid response from get-ifd-offset." )
    end
    
    local sts, erm = file:seek("set", ofs ) -- set file pointer to ifd table.
    if sts ~= nil then
        -- good
    else
        return nil, erm
    end
    
    local num = fso:getWord( file, bigEndian )
    if num == nil then return nil end
    if num > 1 then
        -- good
        if num < 1000 then
            return num
        else
            return nil, "too many ifd"
        end
    else
        return nil, "invalid ifd table"
    end
    
end




function TiffUtils.getIfd( file )
    local ifd = {}
    ifd.tag = fso:getWord( file, bigEndian )
    if ifd.tag == nil then return nil end
    ifd.type = fso:getWord( file, bigEndian )
    if ifd.type == nil then return nil end
    ifd.count = fso:getDouble( file, bigEndian )
    if ifd.count == nil then return nil end
    ifd.valueOffset = fso:getDouble( file, bigEndian )
    if ifd.valueOffset == nil then return nil end
    return ifd
end

--[[function _dumpRemainingBytes( file )
    local s = file:read( "*a" )
    dbg( "len: ", str:to( s:len() ) )
    dbg( "str: ", str:to( s ) )
end--]]
    

function _dumpRemainingBytes( file )
    local char
    local i = 1
    repeat
       char = fso:getByte( file )
       if char == nil then return end
       dbg( "byte ", str:to( i ) .. ": " .. char )
       i = i + 1
    until false
end



function TiffUtils.findMainRGBImage( file )
    local num, msg = TiffUtils.getIfdTable( file )
    if num == nil and not str:is( msg ) then return nil end
    if num then
        -- good
        dbg ( "number of ifds: ", str:to( num ) )
    else
        return nil, "ifd table trouble: " .. str:to( msg )
    end
    
    local ifd = nil
    
    for i = 0, num - 1 do
        ifd = TiffUtils.getIfd( file ) -- 12 bytes returned as table
        if ifd == nil then return nil, "ifd underflow" end
        local m = LOC( "$$$/X=index: ^1, tag: ^2, type: ^3, count: ^4, value-offset: ^5", i, ifd.tag, ifd.type, ifd.count, ifd.valueOffset )
        dbg( "ifd table entry - ", m )
        if ifd.count > 1000000 then -- presently, if block is greater than 10MB its assumed to be the main image! ###5 - this never finished...
            if ifd.count < 10000000 then -- and less than 100MB
                break
            else
                -- return nil, "invalid ifd count: " .. str:to( ifd.count )
                ifd = nil
            end
        else
            ifd = nil
        end
    end
    
    if ifd ~= nil then
        return ifd
    else
        return nil, "no main image"
    end
    
end


function TiffUtils.getMainRGBImage( file )
    local ifd, msg = TiffUtils.findMainRGBImage( file )
    local ofs = nil
    if ifd ~= nil then
        ofs = ifd.valueOffset
    else
        return nil, "no main image: " .. str:to( msg )
    end
    
    return "image at " .. str:to( ofs )
    
end



---     Synopsis:       Reads a tif file and returns a string for printing only.
--
function TiffUtils.replaceMainRGBImage( file, image )

    local adj

    local ofs = getIFDOffest( file )
    if type( ofs ) == 'number' then
        --
    elseif type( ofs ) == 'string' then
        return nil, ofs
    else
        error( "Program failure - invalid response from get-ifd-offset." )
    end
    
    local sts, erm = file:seek("set", ofs ) -- set file pointer to ifd table.
    if sts ~= nil then
        -- good
    else
        return nil, erm
    end
    
    local num = fso:getWord( file, bigEndian )
    if num == nil then return nil end
    if num > 1 then
        -- good
        if num < 1000 then
            -- good
        else
            return nil, "too many ifd"
        end
    else
        return nil, "invalid ifd table"
    end
    
    local ifd
    for i = 0, num - 1 do
        ifd = TiffUtils.getIfd( file ) -- 12 bytes returned as table
        if ifd then
            if ifd.count > 10000000 then -- presently, if block is greater than 10MB its assumed to be the main image!
                break
            else
                ifd = nil
            end
        else
            return nil, "ifd table underflow"
        end
    end
    
    if ifd then
        return ifd
    else
        return nil, "no main image"
    end
        
    
    
end





return TiffUtils
