--[[
        EmbeddedPreviews.lua

        Represents interface for obtaining embedded previews from raw (or dng) files.
--]]


local EmbeddedPreviews, dbg, dbgf = Object:newClass{ className="EmbeddedPreviews", register=true }



--- Constructor for extending class.
--
function EmbeddedPreviews:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function EmbeddedPreviews:new( t )
    local this = Object.new( self, t )
    return this
end



--  @usage Metadata to transfer is specified in local prefs: exifMeta (read using exiftool), lrMeta (read via SDK), lrSpecialMeta (e.g. keywordTags, keywordTagsForExport, copyrightStat). 
--  @usage Derived from NxToo's transferLrMetadata function.
--  @usage Some metadata will be read using SDK, some via exiftool, but all is written using exiftool (target is to-path, not to-photo).
--  @usage e.g. used by catalog/previews get-image function. note: *not* used for recovery, since source file would be required, but is used for exporting (via the previews--get-image func).
--  @usage This method is required if target may not be photo in catalog (but file on disk). see also: LrMetadata:transfer (if target is photo in catalog) and Xmp:transferMetadata.
--  @param fmtMeta (table, optional) batch aquired metadata to be transferred (read using SDK, written using exiftool), *if* specified by 'lrMeta' pref.

--- Get embedded preview from specified photo, as dictated by params..
--
--  @usage  Could be adapted to extract from file which is not represented by a photo in catalog, but so far, only photos in catalog, due to metadata considerations..
--
--  @param params named parameter table, with members:
--      <br>    photo (LrPhoto): if not passed, file (path) had better be.
--      <br>    xfrMeta (boolean, default=true) whether to transfer metadata or not.
--      <br>    profile (string or boolean, optional) sRGB, AdobeRGB, ProPhotoRGB, or true (to have auto-figured). If specified, said profile will be assigned.
--      <br>    jpgPath (string, required) path for extracted jpg file.
--      <br>    cache (Cache, optional) if passed, ###1.
--      <br>    fmtMeta (table) source of formatted metadata for transfer - batch acquired.
--      <br>    NYI: ets (exif-tool session, optional) not working with true session, so either pass nil, or pass exif-tool as ets (et emulating ets is working).
--
--  @return status  true iff successful.
--  @return message string even if successful, but can be ignored or logged in that case.
--
function EmbeddedPreviews:getEmbeddedPreview( params )

    -- app:assert( gbl:getValue( 'exifTool' ), "exif-tool global must be initialized" ) - not actually required, as long as a session object is passed.
    local cache = params.cache -- or nil (do without cached metadata if not provided by calling context).
    local rawPhoto = params.photo or app:callingError( "pass photo param" )
    local fmt = lrMeta:getRaw( rawPhoto, 'fileFormat', cache )
    if fmt ~= 'RAW' and fmt ~= 'DNG' then
        return nil, str:fmtx( "Can not get embedded preview from '^1' file", fmt )
    end
    local rawPath = lrMeta:getRaw( rawPhoto, 'path', cache )
    local jpgPath = params.jpgPath or app:callingError( "pass jpg-path" )
    local xfrMeta = bool:booleanValue( params.xfrMeta, true ) -- if default is true, 'or' syntax can not be used.
    local fmtMeta = params.fmtMeta -- or nil.
    local profile = bool:booleanValue( params.profile, true ) -- if default is true, 'or' syntax can not be used.
    local ets = params.ets
    if ets then
        app:callingAssert( ets==gbl:getValue( 'exifTool' ), "not working with true session - pass nil or et as ets." )
    else
        ets = gbl:getValue( 'exifTool' ) or error( "exiftool required" )
    end
   
    local sts
    local mbuf = {}
   
    local function extract()
        
        local cfg = LrPathUtils.child( _PLUGIN.path, "ExifTool_Config.txt" )
        local params = '-config "'..cfg..'" -BigImage -b' -- works, when using exif-tool proper.

        if fso:existsAsFile( jpgPath ) then LrFileUtils.delete( jpgPath ) end -- ###1

        local cmdOrErr, rslt        
        sts, cmdOrErr, rslt = exifTool:executeCommand( params, rawPath, jpgPath )

        if sts then
            app:assert( fso:existsAsFile( jpgPath ), "After a supposedly successful extraction, there is still no jpg file at expected path: '^1'", jpgPath )
            if fso:getFileSize( jpgPath ) > 0 then
                mbuf[#mbuf + 1] = str:fmtx( "Extracted size-large preview via command: ^1", cmdOrErr )
            else
                sts = false
                mbuf[#mbuf + 1] = str:fmtx( "Extraction yielded 0-byte file - something wrong.. - command: ^1", cmdOrErr )
            end
        elseif str:is( cmdOrErr ) then
            mbuf[#mbuf + 1] = str:fmtx( "Unable to extract embedded preview due to error - ^1", cmdOrErr )
        else
            Debug.pause( rslt )
            mbuf[#mbuf + 1] = str:fmtx( "No extraction - no reason." )
        end
    end

    -- reminder: depends on 'exifMeta', 'lrMeta', & 'lrSpecialMeta' prefs.
    local function transferMetadata()
        assert( rawPath, "no raw path" )
        assert( jpgPath, "no jpg path" )
        local image, mal = Image:new{ file=jpgPath }
        if not image then
            mbuf[#mbuf + 1] = str:fmtx( mal or "bad" )
            sts = false
        end
        local s, m = image:transferMetadata {
            fromPhoto = rawPhoto,
            fromPath = rawPath,
            profile = profile,
            toPath = jpgPath,
            fmtMeta = fmtMeta, -- contains batch-acquired metadata to be transferred - which items is governed by lr-meta pref.
            ets = ets, -- ###1 test
        }
        if s then
            mbuf[#mbuf + 1] = "Metadata was transferred from raw source photo/file to extracted jpg file."
        else
            mbuf[#mbuf + 1] = m
            sts = false
        end
    end
    
    extract()
    if sts then
        if xfrMeta then
            transferMetadata()
        end
    end
    
    local msg = table.concat( mbuf, "\n" ) -- there is always at least one string describing operational status..
    return sts, msg
end



-- return ep-object:
return EmbeddedPreviews
-- the end.
