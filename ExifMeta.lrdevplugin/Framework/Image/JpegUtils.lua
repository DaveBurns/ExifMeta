--[[
        Filename:           JpegUtils.lua
        
        Synopsis:           Mostly chgDet-app-specific metadata support.

        Notes:              This module based on jpegdump.c which I got from Handmade Software, Inc.
                            - written by Allan N. Hessenflow. - Not sure how up-to-date it is.
                            
                            - I never got around to robustening this, since I knew its lifespan was going to be brief.
                            - Primarily used for embedding id in target jpegs to support tree sync purge instead of alt-ext.
                            - Was also used for xmp edit, which is now obsolete.

        Public Functions:   - readFile
                            - reWriteFile

        Public Constants:   None.
             

--]]


local JpegUtils = {}



local TEM = 0x01
local SOF = 0xc0
local DHT = 0xc4
local JPGA = 0xc8
local DAC = 0xcc
local RST = 0xd0
local SOI = 0xd8
local EOI = 0xd9
local SOS = 0xda
local DQT = 0xdb
local DNL = 0xdc
local DRI = 0xdd
local DHP = 0xde
local EXP = 0xdf
local APP = 0xe0
local JPG = 0xf0
local COM = 0xfe


local chgDetBlockType = 0xE7 -- presently writes this type - not an app1 tag.
    -- will recognize any app block type - in case future requires the written type to change.
local chgDetMetadataSignature = 'lrdevplugin.jpeg.metadata' -- this will be preceded by FF E7 {len1} {len2}
    -- Note: I could use a regex for matching the prefix too, but I'm not.

local xmpBlockType = 0xE1 -- typical app1 block tag.
local xmpMetadataSignature = 'http://ns.adobe.com/xmp/extension/' .. string.char( 0 ) -- this will be preceded by FF E1 {len1} {len2}
	-- note: there may be more than one of these in the file - I'm hoping the best one is always first - if not, it will need to be fixed.


local rawCount = 0



---     Synopsis:           Read a file containing a block of metadata introduced by a signature at the beginning of the specified block type,
--                          and occupying the entire block.
--      
--      Returns:            The part before the block containing the target metadata as preamble, the part of the block after the metadata signature as metadata string,
--                          and subsequent blocks to end of file as the postamble.
--                          
--      Note:               The block header and metadata signature are missing from the returned data, thus to re-write the file,
--                          the missing data should be re-supplied, i.e. to write previously read file:
--                          
--                          - preamble verbatim
--                          - metadata block header with adjusted length
--                          - metadata signature
--                          - metadata string
--                          - postamble verbatim.
--                          
--      Note:               If metadata is absent, it still returns a preamble and postamble divided at the SOI marker, so file can be re-written even if
--                          metadata was not pre-existing.
--
function JpegUtils.readFileWithMetadata( filePath, metadataSignature, blockType )
    assert( fso:existsAsFile( filePath ), "read-file valid for pre-existing files only, not this: " .. str:to( filePath ) )
    local contents, qualification = fso:readFile( filePath ) -- reads contents regardless of test mode and returns same.
    if contents then
        -- good
    else
        return nil, nil, nil, qualification
    end
    local preamble, metadata, postamble, qualification
    local startAt = 1
    repeat
        local start, stop = string.find( contents, metadataSignature, startAt, true ) -- plain
        if start then
            startAt = stop + 1 -- next time
            if start > 6 then -- may be legal.
                local blockStartChar = str:getChar( contents, start - 4 )
                local blockTypeMarker = str:getChar( contents, start - 3 )
                local blockLen1 = str:getChar( contents, start - 2 )
                local blockLen2 = str:getChar( contents, start - 1 )
                if blockStartChar == string.char( 0xFF ) then
                    if blockTypeMarker == string.char( blockType ) then -- *** if I ever change the block type written, I'll need to change block type detection.
                        local blockLength = string.byte( blockLen1 ) * 256 + string.byte( blockLen2 )
                        local dataLength = blockLength - string.len( metadataSignature ) - 2
                        preamble = string.sub( contents, 1, start - 5 )
                        metadata = string.sub( contents, stop + 1, stop + dataLength )
                        if app:isDebugEnabled() then
                            app:logInfo( "Got RC Metadata: " .. metadata )
                        end
                        postamble = string.sub( contents, stop + dataLength + 1 )
                        break                        
                    else
                        if app:isDebugEnabled() then
                            app:logWarning( "Possibly corrupt jpeg file: " .. filePath .. " - chgDet-meta-data signature found but bad block-type: " .. str:to( blockTypeMarker ) )
                        end
                    end
                else
                    if app:isDebugEnabled() then
                        app:logWarning( "Possibly corrupt jpeg file: " .. filePath .. " - chgDet-meta-data signature found but block start indicator missing, signature offset: " .. str:to( start ) )
                    end
                end
            else
                if app:isDebugEnabled() then
                    app:logWarning( "Possibly corrupt jpeg file: " .. filePath .. " - chgDet-meta-data signature found but too early, offset: " .. str:to( blockTypeMarker ) )
                end
            end
        else
            --[[if app:isDebugEnabled() then
                -- app:logWarning( "No RC Metadata signature in " .. filePath .. ", start: " .. str:to( start) .. ", sig: " .. str:to( metadataSignature ) .. ", len: " .. string.len( contents ) )
            end--]]
            break
        end
    until true -- break to exit.
    if metadata then
        -- preamble, postamble set.
    else
        local start, stop = string.find( contents, string.char( 0xFF ) .. string.char( 0xD8 ), 1, true ) -- SOI
        if start then
            preamble = string.sub( contents, 1, stop )
            postamble = string.sub( contents, stop + 1 )
        else
            return nil,nil,nil,"Invalid Jpeg file (no SOI): " .. filePath
        end
    end
    return preamble, metadata, postamble, qualification
end 



---     Synopsis:       Read a jpeg file in such a way that it identifies chgDet-jpeg-metadata,
--                      and can be re-written with new or modified chgDet-jpeg-metadata with impunity.
--                      
--      Motivation:     To support chgDet-jpeg-metadata, namely photo-uuid for looking up souchgDete photo
--                      in lightroom catalog, and export-change-date which is used to avoid unnecessary
--                      updates and uploads.
--                      
--      Notes:          - Metadata format is a black box to this function.
--                      - signature is considered sacred: will never change.
--                      
--      Initial Application:    Metadata to contain photo-id & exact date/time of last souchgDete mod to support corelation of target to catalog database and change determination.
--                      
--      Returns:        preamble, chgDet-jpeg-metadata - undressed, postamble, nil -- worked: metadata nil if not present.
--                      nil, nil, nil, qualification -- failed.
--
function JpegUtils.readFileWithChgDetMetadata( filePath )
	return JpegUtils.readFileWithMetadata( filePath, chgDetMetadataSignature, chgDetBlockType )
end



---     Synopsis:           Divide jpeg file into pieces - where the most coveted piece contains develop settings.
--      
--      ###:                - maybe this should be in with the xmp-core functions, along with other xmp related functions.
--      
--      Pieces:             - jpeg preamble: includes start of file through end of block without settings
--                          - settings block header: 4 byte app1 block header.
--                          - settingsPreamble: block content following header preceding selected settings attributes.
--                          - settingsString: attributes string containing selected settings.
--                          - settingsPreamble: block content following settings to end of app1 block.
--                          - jpegPostamble: remainder of jpeg file.
--
function JpegUtils.parseJpegFileToPieces( contents )
	local startAt = 1
	local blocklist = {} -- misnomer (not jpeg blocks proper) - holds white-listed (potentially containing active settings) and black-listed sections between saved-setting parameters.
	repeat
        local start, stop = string.find( contents, "<crss:Parameters", startAt, true )
        if start then -- close white block
            local block = {}
            block.type = 1
            block.start = startAt
            block.stop = start - 1
            blocklist[#blocklist + 1] = block
            local start2, stop2 = string.find( contents, "</crss:Parameters>", stop + 2, true )
            if start2 then
                local block = {}
                block.type = 0
                block.start = start
                block.stop = stop2
                blocklist[#blocklist + 1] = block
                startAt = stop2 + 1
            else
                assert( false, "crssp mismatch" )
            end
        else
            break 
        end
	until false
    local block = {}
    block.type = 1
    block.start = startAt
    block.stop = string.len( contents )
    blocklist[#blocklist + 1] = block
    
    local setStart, setStop
    
	for i,v in ipairs( blocklist ) do
        if v.type == 1 then -- white list
	        local start, stop = string.find( contents, "crs:Version", v.start, true )
            if start and start < v.stop then 
	            local start2, stop2 = string.find( contents, "crs:ConvertToGrayscale", stop + 1, true )
	            if start2 and start2 < v.stop then
	                local start3, stop3 = string.find( contents, ">", stop2 + 1, true )
	                if start3 and start3 < v.stop then
    	                setStart = start -- keep saving settings coordinates
    	                setStop = stop3 - 1
    	                    -- last settings saved win.
    	            else
	                    error( "malformed end-of-settings tag" )
	                end
	            else
	                error( "end of settings tag not found" )
	            end
	        else
                -- ignore white-listed blocks without settings.
            end
        else
            -- ignore black-listed blocks
        end
	end
	
	local contentLen = string.len( contents )
	
	if setStart then -- found settings, and have pointers to last set
	
        local app1 = string.char( 0xFF ) .. string.char( 0xE1 )
       	local len1, len2
    	local blockProper = nil
    	local startAt = 1
    	repeat
            local p1, p2 = string.find( contents, app1, startAt, true )
            if p1 then
            
                len1 = string.byte( str:getChar( contents, p1 + 2 ) )
                len2 = string.byte( str:getChar( contents, p1 + 3 ) )
                local len = (len1 * 256) + len2
                local testChar = str:getChar( contents, p1 + 2 + len )
                if testChar == string.char( 0xFF ) then -- presumably we've got a legal app1 block.
                
                    blockProper = string.sub( contents, p1, p1 + 1 + len )
                    
                    local start, stop = string.find( contents, "crs:Version", startAt, true )
                    if start then
                    
                        if start == setStart and setStop < p1 + 2 + len then
                            -- we've got a winner
                            
                            -- _debugTrace( "sblklen458", "p1: " .. str:to( p1 ) )
                            -- _debugTrace( "setstops", "setstart: " .. str:to( setStart ) .. ", setstop: " .. str:to( setStop ) )
                          
                            local jpegPreamble = string.sub( contents, 1, p1 - 1 )
                            local settingsBlockHeader = string.sub( contents, p1, p1 + 3 ) -- 4 bytes.
                            local settingsPreamble = string.sub( contents, p1 + 4, setStart - 1 )
                            local settingsString = string.sub( contents, setStart, setStop )
                            local settingsPostamble = string.sub( contents, setStop + 1, p1 + 1 + len )
                            local jpegPostamble = string.sub( contents, p1 + 1 + len + 1, contentLen )
                    	    -- _debugTrace( "jpgpreamble", "jpgpreamble: " .. jpegPreamble )
                    	    -- _debugTrace( "jsblkhdr", "jsblkhdr: " .. settingsBlockHeader )
                    	    -- _debugTrace( "jspre", "jspre: " .. settingsPreamble )
                    	    -- _debugTrace( "js", "js: " .. settingsString )
                    	    -- _debugTrace( "jspostamble", "jspostamble: " .. settingsPostamble )
                    	    -- _debugTrace( "jpgpostamble", "jpgpostamble: " .. jpegPostamble )
                    	    local jpreLen = string.len( jpegPreamble )
                    	    local sblkHLen = string.len( settingsBlockHeader )
                    	    local spreLen = string.len( settingsPreamble )
                    	    local ssLen = string.len( settingsString )
                    	    local spstLen = string.len( settingsPostamble )
                    	    local jpstLen = string.len( jpegPostamble )
                    	    local _dt = LOC( "$$$/X=jpre length: ^1, sbh: ^2, spre: ^3, ss: ^4, spost: ^5, jpost: ^6", str:to( jpreLen ), str:to( sblkHLen ), str:to( spreLen ), str:to( ssLen ), str:to( spstLen ), str:to( jpstLen ) )
                    	    -- _debugTrace( "jlens", _dt )
                    	    
                    	    -- local testContents = LOC( "$$$/X=^1^2^3^4^5^6", jpegPreamble, settingsBlockHeader, settingsPreamble, settingsString, settingsPostamble, jpegPostamble ) - this does NOT work!
                    	    local testContents = jpegPreamble .. settingsBlockHeader .. settingsPreamble .. settingsString .. settingsPostamble .. jpegPostamble
                    	    
                    	    local testLen = string.len( testContents )
                    	    if testLen == contentLen then
                    	        -- good
                    		    -- _debugTrace( "chgDettpudifdfekl", "test len match" )
                    		    return jpegPreamble, settingsBlockHeader, settingsPreamble, settingsString, settingsPostamble, jpegPostamble, nil
                    		else
                    		    -- local diffLen, s1rem, s2rem = str:getDiff( testContents, contents )
                    		    -- _debugTrace( "chgDettpudifl", LOC( "$$$/X=Diff Len: ^1, s1rem: ^2, s2rem: ^3", diffLen, s1rem, s2rem) )
                    		    error( "Unable to parse jpeg file to pieces - please report problem (length mismatch)." )
                    		end
                        else -- potential settings are not target settings.
                            -- _debugTrace( "asdf570", "not our settings" )
                        end
                    else
                        -- _debugTrace( "chgDetjpunopotset", "no potential settings in block" )
                    end
   					startAt = p1 + 2 + len
                else
                    -- logWarning( "found app1 tag sequence but apparent not an app1 block" )
                    startAt = p2 + 1
                end
            else
                break
            end
    	until false -- break to exit.
		return nil, nil, nil, nil, nil, nil, "cant find active settings in jpeg file"
	else
		return nil, nil, nil, nil, nil, nil, "jpeg file has no active settings"
	end
end



---		Synopsis:			Reads the contents of specified file, seachgDethes for the block containing xmp/camera-raw-settings, and returns
--							the stuff before the block, stuff after the block, and block contents.
--
--		Note:				xmp-meta data may span multiple blocks, and settings may be specified before and/or after saved settings.
--
--		Limitations:		the active camera-raw-settings must be contained in a single block, thus all other xmp-meta blocks are ignored.
--
--		Returns:			- preamble blocks
--							- settings block preamble 
--							- settings
--							- settings block postamble
--							- postamble blocks.
--							- msg
--
--		Instructions:		Call and save everything for re-write.
--							if settings convert to table.
--							pass saved settings and modified settings as string to rewrite.
--
--
function JpegUtils.readFileWithXmpMetadata( filePath )
    local oLen
	local contents, orNot = fso:readFile( filePath )
	if contents then
		-- good
		oLen = string.len( contents )
	else
		return nil, nil, nil, nil, nil, nil, "nope: " .. orNot
	end
	local jpre, blkhdr, spre, settingsString, spst, jpst, qual = JpegUtils.parseJpegFileToPieces( contents )
	return jpre, blkhdr, spre, settingsString, spst, jpst, qual, oLen
end



---     Rewrite file with metadata.
--
function JpegUtils.reWriteFileWithMetadata( filePath, preamble, metadata, postamble, metadataSignature, blockType )
    local blockLength = string.len( metadataSignature ) + string.len( metadata ) + 2
    
    if str:is( preamble ) and str:is( metadata ) and str:is( postamble ) then
        -- good
    else
        error( "Missing metadata and wrapper for file: " .. str:to( filePath ) )
    end

	local len1 = math.floor( blockLength / 256 )
    local len2 = blockLength - ( len1 * 256 )

	assert( len2 >= 0 and len2 < 256, "len2" )
	local len = len1 * 256 + len2
	assert( len == blockLength, "len" )

    if app:isRealMode() then

        -- local contents = LOC( "$$$/X=^1^2^3^4^5^6^7^8", preamble, string.char( 0xFF ), string.char( blockType ), string.char( len1 ), string.char( len2 ), metadataSignature, metadata, postamble ) - save for reminder:
            -- LOC appears to be unreliable for concatenation of binary data.
            
        local contents = preamble .. string.char( 0xFF ) .. string.char( blockType ) .. string.char( len1 ) .. string.char( len2 ) .. metadataSignature .. metadata .. postamble
        local ok, orNot = fso:writeFile( filePath, contents )
        return ok, orNot
        
        --[[if app:isDebugEnabled() then
            local blocks, qualification = JpegUtils.peruseFile( filePath )
            if blocks and not qualification then
                app:logInfo( LOC( "$$$/X=RC Jpeg Metadata updated in ^1", filePath ) )
                return true
            else
                error( LOC( "$$$/X=RC Jpeg Metadata update failure in ^1, problem: ", filePath, qualification ) )
            end
        else
            return true
        end--]] 
        
    else
        return true, "WOULD re-write with metadata: " .. filePath
    end
end


---     Synopsis:       Write a jpeg file given components previously read and new or updated chgDet-jpeg-metadata.
--      
--      Notes:          Exported photos are always written with fresh souchgDete content, and so dont use this function,
--                      It is only used for video thumbnails, which are to be pre-rendered by the user as jpegs in catalog.
--      
--      Returns:        true, nil: worked - no comment.
--                      true, comment: pretended to work - test-mode.
--                      false, comment: didn't work, and here's why.
--                      
--      Notes:          - Metadata format is a black box to this function.
--                      - signature is considered sacred: will never change.
--
function JpegUtils.reWriteFileWithChgDetMetadata( filePath, preamble, metadata, postamble )
	return JpegUtils.reWriteFileWithMetadata( filePath, preamble, metadata, postamble, chgDetMetadataSignature, chgDetBlockType )
end



---		Synopsis:			Write previously read stuff, and a modified settings block.
--
--		Algorithm:			- compute new block length for settings block as:
--			
--								block length = length of settings preamble + length of settings + length of settings postamble
--							
--							- write preamble blocks
--							- write settings preamble with modified block length
--							- write modified settings
--							- write settings postamble
--							- write postamble blocks
--
function JpegUtils.generateContentWithXmpMetadata( preamble, settingsBlockHeader, settingsPreamble, settings, settingsPostamble, postamble )
	-- local blklen = string.len( settingsPreamble ) + string.len( settings ) + string.len( settingsPostamble ) + 2
	assert( string.len( settingsBlockHeader ) == 4, "settings block header fault" )
	local blklen = 2 + string.len( settingsPreamble ) + string.len( settings ) + string.len( settingsPostamble )
	-- _debugTrace( "blklen", "blklen: " .. str:to( blklen ) )
	if blklen > 65535 then
	    return nil
	end
	local len1, len2
	local len1 = math.floor( blklen / 256 )
    local len2 = blklen - ( len1 * 256 )
	local len = len1 * 256 + len2
	assert( len == blklen, "blklen" )
	assert( len2 >= 0 and len2 < 256, "_len2: " .. str:to( len2 ) )
	assert( len1 >= 0 and len1 < 256, "_len1: " .. str:to( len1 ) )
	-- _debugTrace( "xlen12", "len1: " .. str:to( len1 ) .. ", len2: " .. str:to( len2 ) )
	local first, second
	first = string.sub( settingsPreamble, 1, 1000 )
	second = string.sub( settingsPostamble, 1, 1000 )
	-- _debugTrace( "xlen12", "len1: " .. str:to( len1 ) .. ", len2: " .. str:to( len2 ) )
	-- _debugTrace( "xp1", "first: " .. str:to( first ) )
	-- _debugTrace( "xps", "sets: " .. str:to( settings ) )
	-- _debugTrace( "xp2", "second: " .. str:to( second ) )
	
	-- local blk = LOC( "$$$/X=^1^2^3^4^5^6^7", string.char( 0xFF ), string.char( 0xE1 ), string.char( len1 ), string.char( len2 ), settingsPreamble, settings, settingsPostamble )
	local blk = string.char( 0xFF ) .. string.char( 0xE1 ) .. string.char( len1 ) .. string.char( len2 ) .. settingsPreamble .. settings .. settingsPostamble
	-- _debugTrace( "xblk", "blk: " .. str:to( blk ) )
	
	-- local contents = LOC( "$$$/X=^1^2^3", preamble, blk, postamble )
	local contents = preamble .. blk .. postamble
	return contents
end
function JpegUtils.reWriteFileWithXmpMetadata( filePath, preamble, settingsBlockHeader, settingsPreamble, settings, settingsPostamble, postamble )
	local contents = JpegUtils.generateContentWithXmpMetadata( preamble, settingsBlockHeader, settingsPreamble, settings, settingsPostamble, postamble )
	if contents then
	    return fso:writeFile( filePath, contents )
	else
	    return false, "block overflow" -- one serious potential problem of this technique - fix if adobe no dev set support in lr3.
	end
end



---     Write file with metadata.
--
function JpegUtils.writeFileWithMetadata( filePath, contents, metadata, metadataSignature, blockType )
    local start, stop = string.find( contents, string.char( 0xFF ) .. string.char( 0xD8 ), 1, true ) -- SOI
	local preamble, postamble
    if start then
        preamble = string.sub( contents, 1, stop )
        postamble = string.sub( contents, stop + 1 )
    else
        return false,"Invalid Jpeg file (no SOI): " .. filePath
    end
    return JpegUtils.reWriteFileWithMetadata( filePath, preamble, metadata, postamble, metadataSignature, blockType )
end



---     Synopsis:       Combine metadata with file contents and write to disk.
--      
--      Motivation:     Supports Photooey which needs to write a newly rendered file to target with metadata.
--      
--      Returns:        - true, nil:                worked - no comment.
--                      - true, comment:            pretended to work - test mode qualification.
--                      - false, error-message:     failed.
--                      
--      Notes:          - Since contents comes from rendered file, it won't have metadata to be replaced, so can write as new.
--
function JpegUtils.writeFileWithChgDetMetadata( filePath, contents, metadata )
    return JpegUtils.writeFileWithMetadata( filePath, contents, metadata, chgDetMetadataSignature, chgDetBlockType )
end



---     Synopsis:       Removes APP1 blocks from jpeg content string.
--      
--      Motivation:     APP1 blocks contain changes like render date, that don't really mean the
--                      image has changed in any meaningful way.  This function supports, lax
--                      jpeg file change detection.
--                      
--      Instructions:   Remove app1 blocks from souchgDete & target contents, then compare the results
--                      to decide if there are any meaningful differences.
--
function JpegUtils.removeApp1Blocks( contents )
    local len1, len2
    local startAt = 1
    local app1 = string.char( 0xFF ) .. string.char( 0xE1 )
    local stringBuffer = {}
    -- local app1Buf = {} -- for debug.
    local origLen = string.len( contents )
    local lastStart
    repeat -- until break
        lastStart = startAt
        local p1, p2 = string.find( contents, app1, startAt, true )
        if p1 then
            len1 = string.byte( str:getChar( contents, p1 + 2 ) )
            len2 = string.byte( str:getChar( contents, p1 + 3 ) )
            local len = (len1 * 256) + len2
            local testChar = str:getChar( contents, p1 + 2 + len )
            if testChar == string.char( 0xFF ) then
                stringBuffer[#stringBuffer + 1] = string.sub( contents, startAt, p1 - 1 )
                -- app1Buf[#app1Buf + 1] = string.sub( contents, p1, p1 + 1 + len ) -- accumulate app1 blocks to test.
                startAt = p1 + 2 + len
            else
                -- logWarning( "found app1 tag sequence but apparent not an app1 block" )
                startAt = p2 + 1
            end
        else
            break
        end
    until false -- forever or break
    if #stringBuffer == 0 then
        return contents
    else
        stringBuffer[#stringBuffer + 1] = string.sub( contents, lastStart )
        -- local app1Contents = table.concat( app1Buf, '' )
        -- local app1Len = string.len( app1Contents )
        local newContents = table.concat( stringBuffer, '' )
        -- local newLen = string.len( newContents )
        -- local testLen = app1Len + newLen
        -- if testLen == origLen then
              return newContents
        -- else
        --     log Message Line("Bad")
        --     return contents
        -- end
    end
end





-- *********   STUFF AFTER THIS POINT RESERVED FOR FUTURE OR FOR REFERENCE **********
-- *********   STUFF AFTER THIS POINT RESERVED FOR FUTURE OR FOR REFERENCE **********
-- *********   STUFF AFTER THIS POINT RESERVED FOR FUTURE OR FOR REFERENCE **********



--[[    *** SAVE FOR POSSIBLE FUTURE RESURRECTION: This function properly parsed the jpeg,
        but not in such a way that it could be re-written from its blocks with impunity.
        
        Synopsis:   Reads JPEG file and returns it in blocks.

        Returns:    - preamble(NOT), blockTable, postamble(NOT), qualification: no qualification => no error. Block format:
                      - block type
                      - block length
                      - block data

        Notes:      If this function gets confused, it will return the balance of the file as a single block
                    with a type: "confused".
--] ]
function JpegUtils.peruseFile( filePath )
    assert( fso:existsAsFile( filePath ), "no jpeg file to read." )
    local fileAttributes = LrFileUtils.fileAttributes( filePath )
    local fileSize = fileAttributes.fileSize
    local prefix = ""
    local preamble = ''
    local blocks = {}
    local postamble = ''
    local totalBytesRead = 0
    local file = io.open( filePath, "rb" )
    local byte = nil
    local byte2 = nil
    local marker = nil
    local length = nil
    local originalLength = nil
    local block = nil
    local data = nil
    local done = false
    local qualification = nil

    local aword = nil
    local height = nil
    local width = nil
    local huff = {}

    while (not done) do
        -- if no block open
            -- open a raw block
        repeat -- once
            byte = fso:getByte( file )
            if byte == nil then
                done = true
                break
            end
            rawCount = rawCount + 1
            -- log Message Line( LOC( "$$$/X=^1: ^2", totalBytesRead, byte ) )
            totalBytesRead = totalBytesRead + 1
            if byte ~= 0xFF then
                -- log Message Line( "Not FF" )
                -- store in raw block
                break
            end
            assert( byte == 0xFF, "expected ff - not ff" )
            repeat
                byte = fso:getByte( file )
                if byte == nil then
                    done = true 
                    break
                end
                -- log Message Line( LOC( "$$$/X=^1: ^2", totalBytesRead, byte ) )
                -- and store in raw block
                rawCount = rawCount + 1
                totalBytesRead = totalBytesRead + 1
            until byte ~= 0xFF
            -- remove last byte from raw block
            if byte == nil then
                done = true
                break
            end
            if byte == 0 then
                break
            end
            -- fall-through => got FF/XX marker
            -- close raw block
            rawCount = rawCount - 2
            marker = byte
            length = nil
            originalLength = nil
            data = nil
            ------------------------
            -- process marker blocks
            ------------------------
            if marker == SOI then
                log Message Line( LOC( "$$$/X=^1: SOI", totalBytesRead ) )
                length = 0
                originalLength = 0
            elseif marker == DRI then
                length =fso:getWord( file, true )
                originalLength = length
                assert( length == 4, LOC( "$$$/X=Invalid DRI length: ^1", length ) )
                originalLength = length
                aword = fso:getWord( file, true )
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=DRI (length ^1)\n", length) )
                    log Message Line( LOC("$$$/X=^1 restart interval ^2 MCUs\n", prefix, aword) )
                end
                totalBytesRead = totalBytesRead + 4
                length = length - 4
                data = aword
            elseif marker >= APP and marker <= (APP + 15) then
                length =fso:getWord( file, true )
                originalLength = length
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=APP^1 (length ^2)\n", marker - APP, length ) )
                end
                totalBytesRead = totalBytesRead + 2
                length = length -2
                if marker == APP and length >= 14 then -- jfif?
                    local signature
                    signature = fso:getBytes( file, 5 )
                    totalBytesRead = totalBytesRead + 5
                    length = length - 5
                    if signature == "JFIF" then
                        local dpiX, dpiY, thumbX, thumbY
                        local thumbBytes
                        aword = fso:getWord( file, true )
                        byte = fso:getByte( file )
                        dpiX=fso:getWord( file, true )
                        dpiY=fso:getWord( file, true )
                        thumbX= fso:getByte( file )
                        thumbY= fso:getByte( file )
                        totalBytesRead = totalBytesRead + 9
                        length = length - 9
                        if app:isDebugEnabled() then
                            log Message Line( LOC("$$$/X=^1  JFIF version ^2, ", prefix, aword ) )
                        end
                        thumbBytes = thumbX*thumbY*3
                        length = length - thumbBytes
                        totalBytesRead = totalBytesRead + thumbBytes
                        while thumbBytes > 0 do
                            dummy = fso:getByte( file )
                            thumbBytes = thumbBytes - 1
                        end
                    elseif signature == "JFXX" then
                        local extension
                        local thumbX, thumbY
                        local thumbBytes
                        extension=fso:getByte( file )
                        totalBytesRead = totalBytesRead + 1
                        length = length - 1
                        if extension == 0x10 then
                            if app:isDebugEnabled() then
                                log Message Line( LOC("$$$/X=^1  JFIF extension JPEG thumbnail\n", prefix ) )
                            end
                            while length >0 do
                                dummy = fso:getByte( file )
                                totalBytesRead = totalBytesRead + 1
                                length = length - 1
                            end
                        elseif extension == 0x11 then
                            if app:isDebugEnabled() then
                                log Message Line( LOC("$$$/X=^1  JFIF extension 1 byte/pixel thumbnail\n", prefix ) )
                            end
                            thumbX= fso:getByte( file )
                            thumbY= fso:getByte( file )
                            totalBytesRead = totalBytesRead + 2
                            length = length -2
                            if app:isDebugEnabled() then
                                log Message Line( LOC("$$$/X=^1    thumbnail size ^2 x ^3\n", prefix, thumbX, thumbY ) )
                            end
                            if app:isDebugEnabled() then
                                log Message Line( LOC("$$$/X=^1    palette:\n", prefix ) )
                            end
                            for i = 0, 256, 1 do
                                local red, green, blue
                                red = fso:getByte( file )
                                green = fso:getByte( file )
                                blue = fso:getByte( file )
                                totalBytesRead = totalBytesRead + 3
                                length = length - 3
                                if app:isDebugEnabled() then
                                    log Message Line( LOC("$$$/X=^1      ^2 ^3 ^4\n", prefix, red, green, blue ) )
                                end
                                thumbBytes = thumbX*thumbY
                                length = length -thumbBytes;
                                totalBytesRead = totalBytesRead + thumbBytes
                                while thumbBytes > 0 do
                                    dummy = fso:getByte( file )
                                    thumbBytes = thumbBytes - 1
                                end
                            end
                        elseif extension == 0x13 then
                            if app:isDebugEnabled() then
                                log Message Line( LOC("$$$/X=^1  JFIF extension 3 byte/pixel thumbnail\n", prefix ) )
                            end
                            thumbX= fso:getByte( file )
                            thumbY= fso:getByte( file )
                            totalBytesRead = totalBytesRead + 2
                            length = length -2
                            if app:isDebugEnabled() then
                                log Message Line( LOC("$$$/X=^1    thumbnail size ^2 x ^3\n", prefix, thumbX, thumbY ) )
                            end
                            thumbBytes = thumbX*thumbY*3
                            length = length - thumbBytes
                            totalBytesRead = totalBytesRead + thumbBytes
                            while thumbBytes > 0 do
                                thumbBytes = thumbBytes - 1
                                fso:getByte( file )
                            end
                        else
                            if app:isDebugEnabled() then
                                log Message Line( LOC("$$$/X=^1  JFIF extension $^2\n", prefix, extension ) )
                            end
                        end
                    else -- signature not JFIF nor JFXX
                        
                        -- Unrecognized APP0 marker
                        if app:isDebugEnabled() then
                            log Message Line( LOC("$$$/X=^1  ", prefix ) )
                            for i = 0, i<5, 1 do
                                logMessage( signature[i] )
                            end
                        end
                        while length > 0 do
                            byte = fso:getByte( file )
                            if app:isDebugEnabled() then
                                -- logMessage( LOC( "$$$/X=^1", byte ) )
                            end
                            totalBytesRead = totalBytesRead + 1
                            length = length - 1
                        end
                        if app:isDebugEnabled() then
                            log Message Line()
                        end
                    end
                    
                end -- of APP0 and length >= 14

                -- Print any remaining data in the APP marker
                if length > 0 then
                    if app:isDebugEnabled() then
                        log Message Line( LOC("$$$/X=^1  ", prefix ) )
                    end
                    while length > 0 do
                        byte = fso:getByte( file )
                        if app:isDebugEnabled() then
                            -- log Message Line( LOC( "$$$/X=^1", byte ) )
                        end
                        totalBytesRead = totalBytesRead + 1
                        length = length - 1
                    end
                    if app:isDebugEnabled() then
                        log Message Line()
                    end
                end
                
            elseif marker == COM then
                length = fso:getWord( file, true )
                originalLength = length
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=COM (length ^1)\n  ", length ) )
                end
                totalBytesRead = totalBytesRead + 2
                length = length -2
                while length > 0 do
                    byte = fso:getByte( file )
                    if app:isDebugEnabled() then
                        -- logMessage( LOC( "$$$/X=^1", byte ) )
                    end
                    totalBytesRead = totalBytesRead + 1
                    length = length - 1
                end
                if app:isDebugEnabled() then
                    log Message Line()
                end
            elseif (marker >= SOF and marker <= (SOF + 15)) or (marker == DHP) then
                length =fso:getWord( file, true )
                originalLength = length
                if app:isDebugEnabled() then
                   log Message Line( LOC("$$$/X=^1 (length ^2)\n", "SOF or DHP", length ) )
                end
                totalBytesRead = totalBytesRead + 2
                length = length -2
                byte = fso:getByte( file )
                height = fso:getWord( file, true )
                aword=fso:getWord( file, true )
                byte2 = fso:getByte( file )
                totalBytesRead = totalBytesRead + 6
                length = length - 6
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=^1  sample precision ^2\n", prefix, byte ) )
                    log Message Line( LOC("$$$/X=^1  width ^2, height ^3  components ^4\n", prefix, aword, height, byte2 ) )
                end
                while byte2 > 0 do
                    byte2 = byte2 - 1
                    dummy=fso:getByte( file )
                    dummy=fso:getByte( file )
                    dummy=fso:getByte( file )
                    totalBytesRead = totalBytesRead + 3
                    length = length -3
                end
            elseif marker == SOS then
                length =fso:getWord( file, true )
                originalLength = length
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=SOS (length ^1)\n", length ) )
                end
                totalBytesRead = totalBytesRead + 2
                length = length -2
                byte2 = fso:getByte( file )
                totalBytesRead = totalBytesRead + 1
                length = length - 1
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=^1  components ^2\n", prefix, byte2 ) )
                end
                while byte2 > 0 do
                    byte2 = byte2 - 1
                    dummy=fso:getByte( file )
                    dummy=fso:getByte( file )
                    totalBytesRead = totalBytesRead + 2
                    length = length -2
                end
                byte = fso:getByte( file )
                byte2 = fso:getByte( file )
                dummy=fso:getByte( file )
                totalBytesRead = totalBytesRead + 3
                length = length -3
            elseif marker == DQT then
                length = fso:getWord( file, true )
                originalLength = length
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=DQT (length ^1)\n", length ) )
                end
                totalBytesRead = totalBytesRead + 2
                length = length -2
                while length > 0 do
                    local table = nil
                    local cumsf = 0.0
                    local cumsf2 = 0.0
                    local int allones = 1
                    byte = fso:getByte( file )
                    totalBytesRead = totalBytesRead + 1
                    length = length - 1
                    for row = 0, 7, 1 do
                        if app:isDebugEnabled() then
                            log Message Line( LOC("$$$/X=^1    ", prefix ) )
                        end
                        for col = 0, 7, 1 do
                            local val
                            byte = byte / 16
                            if byte > 0 then
                                val=fso:getWord( file, true )
                                totalBytesRead = totalBytesRead + 2
                                length = length -2
                            else
                                val= fso:getByte( file )
                                totalBytesRead = totalBytesRead + 1
                                length = length - 1
                            end
                            if app:isDebugEnabled() then
                                -- log Message Line( LOC("$$$/X=^1 ", val ) )
                            end
                        end
                    end
                end
            elseif marker == DHT then
                length =fso:getWord( file, true )
                originalLength = length
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=DHT (length ^1)\n", length ) )
                end
                totalBytesRead = totalBytesRead + 2
                length = length -2
                while length > 0 do
                    byte = fso:getByte( file )
                    totalBytesRead = totalBytesRead + 1
                    length = length - 1
                end
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=^1  table ^2\n", prefix, byte ) )
                end
                for i=0, i<16, 1 do
                    huff[i]= fso:getByte( file )
                end
                totalBytesRead = totalBytesRead + 16
                length = length - 16
                for i=0, i < 16, 1 do
                    if app:isDebugEnabled() then
                        log Message Line( LOC("$$$/X=^1    bits ^2 (codes=^3) ", prefix, i+1, huff[i] ) )
                    end
                    while huff[i] > 0 do
                        huff[i] = huff[i] - 1
                        byte2 = fso:getByte( file )
                        totalBytesRead = totalBytesRead + 1
                        length = length - 1
                        if app:isDebugEnabled() then
                            -- log Message Line( LOC("$$$/X=$^1 ", byte2 ) )
                        end
                    end
                end
                if app:isDebugEnabled() then
                    log Message Line()
                end
            elseif marker == DAC then
                length =fso:getWord( file, true )
                originalLength = length
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=DAT (length ^1)\n", length ) )
                end
                totalBytesRead = totalBytesRead + 2
                length = length -2
                while length > 0 do
                    byte = fso:getByte( file )
                    byte2 = fso:getByte( file )
                    totalBytesRead = totalBytesRead + 2
                    length = length -2
                    if app:isDebugEnabled() then
                        log Message Line( LOC("$$$/X=^1  id ^2 conditioning ^3\n", prefix, byte, byte2 ) )
                    end
                end
            elseif marker >= RST and marker <= (RST + 7) then
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=RST^1\n", marker - RST ) )
                end
                length = 0
                originalLength = 0
            elseif marker == DNL then
                length =fso:getWord( file, true )
                originalLength = length
                aword = fso:getWord( file, true )
                totalBytesRead = totalBytesRead + 4
                length = length -4
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=DNL (length ^1)\n", length ) )
                    log Message Line( LOC("$$$/X=^1  lines ^2\n", prefix, aword ) )
                end
            elseif marker == EOI then
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=EOI\n") )
                end
                length = 0
                originalLength = 0
            elseif marker == EXP then
                length =fso:getWord( file, true )
                originalLength = length
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=DHP (length ^1)\n", length ) )
                end
                byte = fso:getByte( file )
                totalBytesRead = totalBytesRead + 3
                length = length -3
            elseif marker == TEM then
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=TEM\n" ) )
                end
                length = 0
                originalLength = 0
            else
                length =fso:getWord( file, true )
                originalLength = length
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=marker $^1 (length ^2)\n", byte, length ) )
                end
                totalBytesRead = totalBytesRead + 2
                length = length -2
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=^1  ", prefix ) )
                end
                while length > 0 do
                    byte = fso:getByte( file )
                    totalBytesRead = totalBytesRead + 1
                    length = length - 1
                    if app:isDebugEnabled() then
                        -- logMessage( LOC( "$$$/X=^1", byte ) )
                    end
                end
                if app:isDebugEnabled() then
                    log Message Line()
                end
            end -- of marker conditional
            assert( length ~= nil, LOC( "$$$/X=Length neglected for marker: ^1", marker ) )
            if length > 0 then -- residual length
                if app:isDebugEnabled() then
                    log Message Line( LOC("$$$/X=^1  bad length (residual=^2)\n", prefix, length ) )
                end
                qualification = LOC( "$$$/X=Bad Length reading marker: ^1, original: ^2, residual: ^3", marker, originalLength, length )
                -- return the balance as a single raw block.
                done = true -- we're almost certainly hosed now, return with what we've got and hope for the best.
                break
            else
                block = {}
                block.type = marker
                block.length = originalLength
                block.data = data
                blocks[#blocks + 1] = block
            end
        until false -- once
     end -- while not done
    -- assign last dangling block?
    log Message Line( LOC( "$$$/X=Total bytes read: ^1/^2", totalBytesRead, fileSize ) )
    file:close()
    if qualification ~= nil then
        return blocks, qualification
    else
        return blocks, qualification
        -- local status, qualification = _checkBlocks( blocks, filePath ) -- makes sure I'll be able to write the same file I read.
        -- if status then
        --     return blocks, qualification
        -- else
        --     return nil, qualification
        -- end
    end
end
--]]



--[[    *** SAVE FOR POSSIBLE FUTURE RESURRECTION.

        Synopsis:       Checks if whole image can be re-constructed from its parts.
        
        Motivation:     One way to insert a block of metadata is to deconstruct the image into blocks,
                        insert a block of metadata, the write all the blocks back out. This depends
                        on being able to write the original blocks out without the inserted block
                        with impunity. This function checks whether that's possible.
                        
        Notes:          *** @2009-08-16 this function has never been successful.
--] ]        
local function _checkBlocks( blocks, filePath )
    local file = io.open( filePath, "rb" )
    local fileData = file:read( "*all" )
    file:close()
    local blockDataTable = {}
    for _, block in ipairs( blocks ) do
        blockDataTable[#blockDataTable + 1] = 0xFF
        blockDataTable[#blockDataTable + 1] = block.type
        if block.length == 0 then
            -- just the type
        else
            blockDataTable[#blockDataTable + 1] = block.length
            blockDataTable[#blockDataTable + 1] = 0
            for i = 1, block.length - 2, 1 do
                blockDataTable[#blockDataTable + 1] = 0 -- block.data[i]
            end
        end
    end
    local blockData = table.concat( blockDataTable, '' )
    local blockDataLength = string.len( blockData ) + rawCount
    local fileDataLength = string.len( fileData )
    if blockDataLength == fileDataLength then
        return true, nil
    else
        return false, LOC( "$$$/X=Block data length: ^1, file data length: ^2", blockDataLength, fileDataLength )
    end 
end
--]]



--[[    *** SAVE FOR POSSIBLE FUTURE RESURRECTION. For now, calling context does the work of this function.

        Synopsis:       Read contents, and if chgDet-metadata present, removes it before returning the contents.
        
        Motivation:     Support Photooey which needs to compare newly rendered file against target without the metadata taken into consideration.
   
        Returns:        - contents, nil:        worked - contents sans chgDet-metadata.
                        - nil, error-message:   no-go.
--] ]
function JpegUtils.readFileSansChgDetMetadata( filePath )
    local preamble, metadata, postamble, qualification = JpegUtils.readFileWithChgDetMetadata( filePath )
    if preamble then
        return preamble .. postamble, qualification
    else
        return nil, qualification
    end
end
--]]



--[[*** SAVE FOR POSSIBLE FUTURE RESURRECTION: At the moment, the user is being given the option
        to ignore metadata for change comparison purposes, in which case all app1 data will be
        ignored, thus solving rendering date changes and potentially others as well.
        
        Synopsis:       Removes render date from jpeg rendered in lightroom.
        
        Motivation:     When minimimize-metadata is unchecked in lightroom, it puts the date
                        the jpeg was rendered in the jpeg file. For comparison purposes,
                        it is desirable to remove this date from consideration.
                        
        Notes:          - The result is for comparison purposes only, and should not be saved
                          in a file.
                        - This should only be called on newly rendered temp file if minimize-metadata unchecked, since
                          otherwise the render date is not present - wont hurt but not efficient.
                          Is also called for target, which may have been rendered with max or min metadata - who knows.
        Returns:        - modified-contents, nil:        metadata removed.
                        - original-contents, msg:        metadata not removed.
        
--] ]
function JpegUtils.removeRenderDate( contents )
    local p1, p2 = string.find( contents, "xap:ModifyDate=", 1, true )
    local preamble
    local postamble
    local comment
    if p1 then
        local p3, p4 = string.find( contents, "\n", p2 + 1, true )
        if p3 then
            if ((p4 - p2) > 5) and ((p4 - p2) < 100) then -- reasonability check
                preamble = string.sub( contents, 1, p1 - 1 )
                postamble = string.sub( contents, p4 + 1 )
                return preamble .. postamble
            else
                comment = LOC( "$$$/X=xap-mod date found without reasonable termination: ^1", p4 - p2 )
            end
        else
            comment = "xap-mod date found without termination"
        end
    else
        comment = "Render date not found."
    end
    return contents, comment
end
--]]



return JpegUtils
