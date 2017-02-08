--[[
        Previews.lua
        
        Interface object housing utility methods for accessing Lr previews.
        
        Includes methods for lib previews and smart previews.
        
        If not explicitly specified, assume lib (not smart) previews.
--]]


local Previews, dbg, dbgf = Object:newClass{ className = 'Previews' } -- registered by default.



-- conversion tables for use with request-jpeg-thumbnail method.
local levelToWidth = {
    80, 160, 320, 640, 1280, 2560, 99999
}
local levelToHeight = {
    60, 120, 240, 480, 960, 1920, 99999
}



-- local convenience vars:
local catDir
local catName
local pd
local pdb



--- Constructor for extending class.
--
function Previews:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Previews:new( t )
    local o = Object.new( self, t )
    local cp = catalog:getPath()
    local fn = LrPathUtils.leafName( cp )
    catName = LrPathUtils.removeExtension( fn )
    catDir = LrPathUtils.parent( cp )
    local pn = catName .. " Previews.lrdata"
    pd = LrPathUtils.child( catDir, pn )
    pdb = LrPathUtils.child( pd, 'previews.db' )
    -- Note: not an error for previews dir or db to not exist at this point.
    return o
end



--- Get preview database info - presently only supports active catalog.
--
--  @return table with members:
--      <br>catDir - catalog directory
--      <br>catName - catalog name
--      <br>pd - previews .lrdata folder path
--      <br>pdb - previews.db file path.
--
function Previews:getDatabaseInfo()
    return {
        catDir = catDir,
        catName = catName,
        pd = pd,
        pdb = pdb
    }    
end



--- Gets preview info from preview database, corresponding to specified photo.
--
--  @param      photo       lr-photo object.
--  @param      tmo         in seconds, default=30 (for reading database via sqlite).
--
--  @return table with imageId, uuid, digest, and orientation; or nil.
--  @return errm if table nil.
--
function Previews:getPreviewInfo( photo, tmo )
    tmo = tmo or 30
    
    local imageId = cat:getLocalImageId( photo )
    local orientation
    local uuid
    local digest
    
    local r, m
    repeat
        local sql = str:fmtx( "select uuid, digest, orientation from ImageCacheEntry where imageId=^1", imageId ) -- number
        -- function Sqlite:executeQuery( db, sql, cols, sep, tempFile )
        if not fso:existsAsFile( pdb ) then
            return nil, "File does not exist: "..pdb
        end
        r, m = sqlite:query( pdb, sql, 3 )
        if r then
            if #r == 0 then
                Debug.pause( "No image cache entry" )
                if tmo == 0 then
                    return nil, "bad response"
                end
            elseif #r == 1 then
                break -- continue
            else
                Debug.pause( "image cache entries", #r )
                if tmo == 0 then
                    return nil, "preview is in transition"
                end
            end
        elseif tmo == 0 then
            return nil, m
        end
        -- fall-through => retry.
        tmo = tmo - 1
        app:sleep( 1 )
        if shutdown then return nil, "shutdown" end
    until false -- until we get one table element or timeout (or shutdown).

    local v = r[1]
    uuid = v[1]
    digest = v[2]
    orientation = v[3]

    return {
        imageId = imageId,
        uuid = uuid,
        digest = digest,
        orientation = orientation,
    }
end
Previews._getPreviewInfo = Previews.getPreviewInfo -- function Previews:_getPreviewInfo(...) - for backward compatibility: this method started life being private.



-- reminder: previews are not freshened in develop module, so switch to library module
-- before bothering with this function.
function Previews:_isPreviewFresh( photo, tmo )
    local info, msg = self:_getPreviewInfo( photo, tmo ) -- std tmo is 30 seconds. ###1 (30/Apr/2014 2:01) probably too long just for checking if preview is fresh.
    if info then
        if not fso:existsAsFile( pdb ) then
            return nil, "File does not exist: "..pdb
        end
        local sql = str:fmtx( "select fileTimeStamp, quality, croppedWidth, croppedHeight, pyramidFileTimeStamp from Pyramid where uuid='^1' and digest='^2'", info.uuid, info.digest )
        local r2, m2 = sqlite:query( pdb, sql, 5 )
        if not r2 then
            return nil, "no response to pyramid query"
        end
        if #r2 == 0 then
            return nil, "no entry in pyramid table"
        elseif #r2 > 1 then
            return nil, "ambiguous entries in pyramid table"
        end
        local v2 = r2[1]
        local fileTimeStamp = v2[1]
        local quality = v2[2]
        local croppedWidth = v2[3]
        local croppedHeight = v2[4]
        local pyramidFileTimeStamp = v2[5]
        if quality == 'standard' or quality == 'final' then
            return true, quality
        else
            return false, "Preview has only reached "..quality
        end
    else
        return false, msg
    end
end



--- Determines if preview is fresh (accepts either standard or final quality).
--
--  @usage *** previews are not freshened in develop module, so switch to library module
--      <br>before bothering with this function.
--  @usage this function executes "pseudo-synchronously", such that if command-line/sqlite is hung (it unfortunately does happen sometimes), it
--      <br>will be abandoned (eventually hung command tasks will populate the process list...) - not sure what else to do though. ###3
--
--  @param photo lr-photo
--  @param tmo in seconds, default is 7.
--
--  @return s
--  @return m
--
function Previews:isPreviewFresh( photo, tmo )
    tmo = tmo or 7
    if tmo < 7 then tmo = 7 end
    local sts, qual
    LrTasks.startAsyncTask( function()
        sts, qual = self:_isPreviewFresh( photo, tmo - 3 ) -- not exactly allowing full time, but should be enough slack..
    end )
    app:sleep( tmo, .1, function() -- 5 seconds should be more than enough time for sqlite to load, poll preview db, and return a value, but consider passing a larger value if it makes sense (be careful passing smaller values).
        return sts ~= nil or qual ~= nil
    end )
    if sts == nil and qual == nil then
        dbgf("### command execution of sqlite never returned.")
        Debug.pause("### command execution of sqlite never returned.")
        return nil, "command-line execution of sqlite is hung"
    else
        return sts, qual
    end
end



--- Determine if standard preview is fresh.
--
--  @param photo lr-photo
--  @param tmo in seconds, default is 7.
--
--  @return s
--  @return m
--
function Previews:isStandardPreviewFresh( photo, tmo )
    return self:isPreviewFresh( photo, tmo )
end



--- Determine if final (1:1) preview is fresh.
--
--  @param photo lr-photo
--  @param tmo in seconds, default is 7.
--
--  @return s
--  @return m
--
function Previews:isFinalPreviewFresh( photo, tmo )
    local sts, qual = self:isPreviewFresh( photo, tmo )
    if sts then
        if qual == 'final' then
            return true
        elseif str:is( qual ) then
            return false, "still " .. qual
        else
            error( "no qual" )
        end
    else
        return false, qual
    end
end



--- Freshen preview at least as large as specified width/height, or full-size.
--
--  @usage *** Beware: this function only works in limited circumstances - see in-line comments below.
--
--  @param photo - lr-photo
--  @param width - pass 65535 to assure 1:1
--  @param height - pass 65535 to assure 1:1
--  @param tmo in seconds, default = 30.
--
--  @return image data (untagged, and unclear how they should be tagged).
--  @return time it took to get the image data (if very short, it was probably already there).
--
function Previews:freshen( photo, width, height, tmo )
    local tmo = tmo or 30
    local data
    local time = 0
    -- this seems to timeout if user advances photo in full-screen mode, regardless of which preview is being requested.
    local rec = photo:requestJpegThumbnail( width, height, function( image )
        data = image
    end )
    app:sleep( tmo, .1, function( eTime )
        time = eTime
        return ( data ~= nil )
    end )
    return data, time
end



--- Freshen preview at least as large as specified width/height, or full-size.
--
--  @usage *** Beware: this function only works in limited circumstances - see in-line comments in guts method above.
--  @usage width & height required is auto-computed based on width/height of largest display (monitor).
--
--  @param photo - lr-photo
--  @param tmo in seconds, default = 30.
--
--  @return image data (untagged, and unclear how they should be tagged).
--  @return time it took to get the image data (if very short, it was probably already there).
--
function Previews:freshenStandardPreview( photo, tmo )
    if self.stdW == nil then
        local disp = app:getDisplayDimensions()
        self.stdW = disp.max.width
        self.stdH = disp.max.height
    end
    return self:freshen( photo, self.stdW, self.stdH, tmo )
end



--- Freshen 1:1 (full-size) preview.
--
--  @usage *** Beware: this function only works in limited circumstances - see in-line comments in guts method above.
--  @usage width & height are set huge, meaning largest (won't enlarge).
--
--  @param photo - lr-photo
--  @param tmo in seconds, default = 30.
--
--  @return image data (untagged, and unclear how they should be tagged).
--  @return time it took to get the image data (if very short, it was probably already there).
--
function Previews:freshenFinalPreview( photo, tmo )
    return self:freshen( photo, 65535, 65535, tmo ) -- previews are not resized, so just requesting huge returns largest possible (1:1).
end



--- Assure preview freshness prior to embarking on operation that depends on freshness.
--
--  @usage once upon a time this method was automated, however it was not reliable - now it prompts the user with instructions how to tell if preview(s) fresh.
--  @usage could be robustened to allow param for whether already in lib module / grid mode, and whether target module should be assured upon prior to returning.
--  @usage does NOT use request-jpeg-thumbnail to attempt freshening (due to bugs in said method).
--
function Previews:assureFreshness( params )
    --Debug.pause()
    local call = params.call or error( "no call" )
    local photos = params.photos or error( "no photos" )
    local op = params.op or "This operation"
    -- may as well start w/ lib module, since that is sometimes sufficient to coax Lr into updating previews.
    local s, m
    local uiText, uiText2
    if #photos > 1 then
        uiText = ", and then scroll through the selected thumbs. Once all thumbnails are"
        uiText2 = "\n \nTip: if too many to determine via inspection, consider using Library menu -> Previews -> Render Standard Previews and wait for progress completion before proceeding."
        s, m = gui:gridMode( true ) -- mandatory.
        if s then
            app:logv( "Should be in library grid mode now." )
        else
            return false, str:fmtx( "Unable to go to grid mode - ^1", m )
        end
    else -- whatever mode is fine
        uiText = ", and once thumbnail is"
        uiText2 = ""
        s, m = gui:switchModule( 1, true ) -- lib, mandatory.
        if s then
            app:logv( "Should be in library module now." )
        else
            return false, str:fmtx( "Unable to switch modules - ^1", m )
        end
    end
    app:initGlobalPref( "previewsAssureFreshnessDismissTime", 3 )
    local vi = {}
    vi[#vi + 1] = vf:row {
        vf:push_button {
            title="Dismiss dialog box temporarily",
            action=function( button )
                LrDialogs.stopModalWithResult( button, 'dismiss' )
            end,
        },
        vf:static_text {
            title="for",
        },
        vf:edit_field {
            bind_to_object = prefs,
            value = app:getGlobalPrefBinding( 'previewsAssureFreshnessDismissTime' ),
            width_in_digits = 2,
            tooltip = "Number of seconds to dismiss dialog, temporarily.",
            precision = 0,
            min = 1,
            max = 9,
        },
        vf:static_text {
            title="seconds.",
        },
    }
    repeat
        call:setCaption( "Dialog box needs your attention..." )
        local confirm = [[
^1 requires ^2 - unfortunately it doesn't know how to tell if they're fresh or not, so you're going to have to help - here's how:

Click the 'Dismiss dialog box temporarily' button^3 no longer changing, (e.g. "..." is no longer being displayed) and/or no more "loading..." indicator in loupe view, then click one of the 'Yes...' buttons (depending on which module you want to be in afterward).^4

Are all library previews fresh?]]
        local button = app:show{ confirm=confirm,
            subs = { op, str:nItems( #photos, "fresh Library previews" ), uiText, uiText2 },
            buttons = { dia:btn( "Yes - Stay in Library", 'ok' ), dia:btn( "Yes - Go to Develop", 'other' ) },
            viewItems = vi,
            --actionPrefKey = "Dev module upon return, or Lib", - mandatory.
        }
        if button == 'ok' then
            call.moduleUponReturn = 1
            break
        elseif button=='other' then
            call.moduleUponReturn = 2
            break
        elseif button == 'dismiss' then
            --call.moduleUponReturn = nil
            call:setCaption( "Check Library Previews by Inspection" )
            app:sleep( app:getGlobalPref( 'previewsAssureFreshnessDismissTime' ) or 3 )
            if shutdown then return false, "shutdown" end
            -- loop
        elseif button == 'cancel' then
            call:cancel() -- no point in setting caption
            return true -- call is checked first upon return, so this is a don't care.
        else
            error( "bad button" )
        end
    until false
    if call.moduleUponReturn ~= nil then
        local s, m = gui:switchModule( call.moduleUponReturn, false )
        --Debug.pause( s, m )
        if s then
            app:logv( "Should have switched to desired module." )
            call:setCaption( "" )
            return true
        else
            call:setCaption( "" )
            return false, str:fmtx( "Unable to switch modules - ^1", m )
        end
    else
        -- Debug.pause()
        -- return true
        call:setCaption( "" )
        return false, "expected module upon return" -- theoretically, the module upon return was set during func-start, unless call was canceled, in which
        -- case we should not have gotten this far.
    end
    error( "how here?" )
end


--[[ *** save as reminder: this does NOT work - previews are generated internally for view, but are not saved on disk.
-- Assure preview freshness prior to embarking on operation that depends on freshness.
--
function Previews:assureFreshness( args )
    local photos = app:callingAssert( args.photos, "no photos" )
    local call = app:callingAssert( args.call, "no call" )
    local op = args.op or "This operation"
    local thumbView = view:getThumbnailsView{ -- scroller
        photos = photos,
        thumbWidth = 1920, -- ###
        thumbHeight = 1280,
    }
--  @param args (table) containing:<br>
--             - photos (array, required) photos to view. <br>
--             - fmtMetaSpecs (array, optional) formatted metadata keys to accompany thumbnails. <br>
--             - fmtMeta (array, optional) formatted metadata to accompany thumbnails. <br>
--             - clickBack (function, optional) callback function for clickage. <br>
--             - viewWidth <br>
--             - viewHeight <br>
--             - thumbWidth <br>
--             - thumbHeight <br>
--
    local button = app:show{ confirm="^1 requires ^2 - if all are visible and seem fresh enough to you, then click 'OK', otherwise click 'Cancel' to abort operation.",
        subs = { op, str:nItems( #photos, "fresh previews" ) },
        -- buttons = { dia:btn( "Yes", 'ok' ) }, - OK/Cancel is adequate.
        viewItems = { thumbView },
    }
    if button == 'ok' then
        return true
    else
        return false, "canceled by user"
    end
end
--]]



function Previews:_getImageDataFromFile( previewSourcePath, minLevel, prefLevel )
    local imageData = {} -- index is level
    local content
    local status
    status, content = LrTasks.pcall( LrFileUtils.readFile, previewSourcePath )
    if status and content then
        app:logVerbose( "Read content from: ^1", previewSourcePath )    
    else
        return nil, str:fmt( "Unable to read preview source file at ^1, error message: ^2", previewSourcePath, content )
    end
    local level = minLevel
    local p3
    local p4 = 0
    
    local function assureTerm( content )
        local term = string.char( 0xFF ) .. string.char( 0xD9 )
        local endPos
        local begPos = math.max( #content - 2048, 2 )
        for i = #content, begPos, -1 do -- surely there is no more than 2k of padding after termination sequence.
            local c = string.byte( content:sub( i, i ) )
            if c ~= 0 then
                endPos = i
                break
            end
        end
        if endPos then
            if content:sub( endPos - 1, endPos ) == term then
                if endPos == #content then
                    app:logV( "File content is properly terminated - no padding." )
                    return content, 0
                else
                    app:logV( "File content is properly terminated - although padded with ^1 (kept).", str:nItems( #content - endPos, "zero characters" ) )
                    return content, 0
                end
            elseif content:sub( endPos, endPos ) == string.char( 0xFF ) then
                app:logV( "Last char is 0xFF - appending 0xD9 for proper termination." )
                return content .. string.char( 0xD9 ), 1
            else
                if endPos == #content then
                    app:logV( "File content is not properly terminated, appending termination block." )
                    return content .. term, 2
                else
                    app:logV( "File content is not properly terminated - although there are ^1 at the end - termination characters added after trailing zeros.", str:nItems( #content - endPos, "zero characters" ) )
                    return content .. term, 2
                end
            end
        else
            -- probably a bad jpeg
            error( "preview data is invalid" )
        end
    end
    
    while level <= prefLevel do
        local p1, p2 = content:find( "level_" .. str:to( level ), p4 + 1, true )
        if not p1 then
            --Debug.pause( "nada at", level )
            return imageData, level - 1
        end
        local start = p2 + 2 -- jump over level_n\0 to get to start of jpeg image data.
        p3, p4 = content:find( "AgHg", start, true )
        local stop
        if p3 then -- current preview ends before marker (keep going after getting data).
            stop = start + p3 - 1
        else -- current preview goes to end of file.
            stop = content:len() - 1
            prefLevel = 0 -- exit loop after getting data.
        end
        local data, termCount = assureTerm( content:sub( start, stop ) )
        if termCount == 0 then
            app:logV( "Preview terminated as read." )
        elseif termCount == 1 then
            app:logV( "Preview, as read, was only partially terminated." )
        elseif termCount == 2 then
            app:logV( "Preview, as read, was not terminated." )
        else
            error( "bad term count" )
        end
        --Debug.pause( "got data at", level )
        imageData[level] = data
        level = level + 1
    end
    return imageData, level - 1
end



--[[ until 27/May/2013 4:42 (potential problem reported by Jean Chang).
function Previews:______getImageDataFromFile( previewSourcePath, minLevel, prefLevel )
    local imageData = {} -- index is level
    local content
    local status
    status, content = LrTasks.pcall( LrFileUtils.readFile, previewSourcePath )
    if status and content then
        app:logVerbose( "Read content from: ^1", previewSourcePath )    
    else
        return nil, str:fmt( "Unable to read preview source file at ^1, error message: ^2", previewSourcePath, content )
    end
    local level = minLevel
    local p3
    local p4 = 0
    local term = string.char( 0xFF ) .. string.char( 0xD9 )
    while level <= prefLevel do
        local p1, p2 = content:find( "level_" .. str:to( level ), p4 + 1, true )
        if not p1 then
            --Debug.pause( "nada at", level )
            return imageData, level - 1
        end
        local start = p2 + 2 -- jump over level_n\0 to get to start of jpeg image data.
        p3, p4 = content:find( "AgHg", start, true )
        local stop
        if p3 then -- current preview ends before marker (keep going after getting data).
            stop = start + p3 - 1
        else -- current preview goes to end of file.
            stop = content:len() - 1
            prefLevel = 0 -- exit loop after getting data.
        end
        local data
        if content:sub( -2 ) ~= term then -- Lr3 unterminated.
            data = content:sub( start, stop ) .. term -- jpeg's are unterminated in preview pyramid - sometimes causes problems, sometimes not...
        else -- Lr4+ terminated
            data = content:sub( start, stop )
        end
        --Debug.pause( "got data at", level )
        imageData[level] = data
        level = level + 1
    end
    return imageData, level - 1
end
--]]



--- Get a preview image corresponding to specified photo, at the specified level, if possible.
--
--  @param photo (LrPhoto or table of param, required)     specified photo, or table of named parameters (recommended) - same as below including photo=lr-photo:
--  @param photoPath (string, optional)     photo-path if available, otherwise will be pulled from raw-metadata.
--  @param previewFile (string, default=unique-temp-path)     target path to store jpeg - if non-nil value passed and file is pre-existing, it will be overwritten.
--  @param prefLevel (number, required)      appx sizes + intended use:
--      <br>     1 - 80x60     small thumb
--      <br>     2 - 160x120   medium thumb
--      <br>     3 - 320x240   large thumb
--      <br>     4 - 640x480   small image
--      <br>     5 - 1280x960  medium image
--      <br>     6 - 2560x1920 large image
--      <br>     7 - 1:1       full-res
--  @param minLevel (number, default=1) minimum acceptable level.
--  @param freshness (number, default=1) 0 => whatever is handy (no longer supported); 1 => use dates to determine freshness (*** was recommended - no longer supported ***); 2 => freshen regardless of dates; 3 => must be hot off the press.
--  @param icc (string, default='I') determines if icc profile management is desired, 'A' means assign, 'C' means convert, & 'I' or nil means ignore.
--  @param profile (string, default=nil) target profile, if icc is to be assigned or converted. 'sRGB', or 'AdobeRGB'.
--  @param meta (boolean, default=false) determines if metadata transfer is desired.
--  @param orient (boolean, default=false) determines if orientation should be corrected via image mogrification.
--  @param mogParam (string, optional) mogrify-compatible parameter string if desired, e.g. for resizing...
--  @param fmtMeta (table, optional) lightroom formatted metadata obtained en batch.
--
--  @usage file, errm, level = cat:getPreview{ photo=catalog:getTargetPhoto(), level=5 }
--  @usage file, errm, level = cat:getPreview( catalog:getTargetPhoto(), nil, nil, 5 )
--
--  @return image (Image, or nil) preview as image object representing requested preview.
--  @return errm (string, or nil) error message if unable to obtain requested preview (includes path(s)).
--  @return level (number, or nil) actual level read, which may be different than requested level if min-level passed in.
--
function Previews:getImage( photo, photoPath, previewFile, prefLevel, minLevel, freshness, icc, profile, meta, orient, mogParam, fmtMeta, ets, assureDir, dontOverwrite, tryNewLr5WayFirst )
    if photo == nil then
        app:callingError( "no photo or named parameter table" )
    end
    if not photo.catalog then -- not lr-photo
        photoPath = photo.photoPath
        previewFile = photo.previewFile
        -- assert( photo.prefLevel, "no prefLevel in param table" )
        prefLevel = photo.prefLevel
        minLevel = photo.minLevel
        freshness = photo.freshness
        icc = photo.icc
        profile = photo.profile
        meta = photo.meta
        orient = photo.orient
        mogParam = photo.mogParam
        fmtMeta = photo.fmtMeta
        ets = photo.ets
        assureDir = photo.assureDir
        dontOverwrite = photo.dontOverwrite
        tryNewLr5WayFirst = photo.tryNewLr5WayFirst
        photo = photo.photo
        -- assert( photo and photo.catalog, "no lr-photo in param table" )
    end
    if prefLevel == nil then
        app:callingError( "no prefLevel" )
    end
    if minLevel == nil then
        app:callingError( "no minLevel" )
    end
    if prefLevel > 7 then
        app:logWarning( "Max prefLevel is 7" )
        prefLevel = 7
    end
    if minLevel > prefLevel then
        app:logWarning( "Min prefLevel can not exceed preferred prefLevel." )
        minLevel = prefLevel
    end
    if freshness == nil then
        freshness = 2 -- fresh
    end
    if freshness ~= 2 and freshness ~= 3 then
        app:callingError( "bad freshness: ^1", freshness )
    -- else @5/May/2013 17:43 - stale previews are no longer supported.
    end
    if photoPath == nil then
        photoPath = photo:getRawMetadata( 'path' )
    end
    app:logVerbose( "Getting preview image for ^1", photoPath )
    local previewTargetPath
    if previewFile == nil then -- handle virtual copy better? ###2 - perhaps I shoudn't even support getting previews for virtual copies,
        -- although its not a bad feature to have, user does not need to use it, but it may be reasonable thing to have sometimes(?)
        -- not sure if calling context is permitting it though - better try it...
        local previewFilename
        local isVirt = photo:getRawMetadata( 'isVirtualCopy' )
        assert( isVirt ~= nil, "what virt" )
        if isVirt then
            local copyName = photo:getFormattedMetadata( 'copyName' )
            local filename = LrPathUtils.leafName( photoPath )
            local base = LrPathUtils.removeExtension( filename )
            previewFilename = str:fmt( "^1(^2).lrPreview.jpg", base, copyName )
        else    
            -- previewFilename = LrPathUtils.leafName( photoPath ) -- ###4 - how have I gotten by with this - filename should be jpg. 26/Jun/2013 5:15 - delete comment if no issues come 2015.
            previewFilename = LrPathUtils.replaceExtension( LrPathUtils.leafName( photoPath ), "jpg" )
        end
        previewTargetPath = LrPathUtils.child( LrPathUtils.getStandardFilePath( 'temp' ), previewFilename ) -- include extension, since there are separate previews for each file-type.
    else
        if fso:existsAsFile( previewFile ) then
            app:logVerbose( "preview path passed is to existing file to be overwritten" )
        end
        previewTargetPath = previewFile
    end
    if icc == nil or icc == 'A' then
        -- ok
    elseif icc == 'C' then
        if not str:is( profile ) then
            app:callingError( "need target profile" )
        end
    elseif icc == 'I' or icc==false then
        icc = nil
    else
        app:callingError( "bad icc op: ^1", icc )
    end
    
    local rec
    local imageData
    if tryNewLr5WayFirst and app:lrVersion() >= 5 then
        rec = photo:requestJpegThumbnail( levelToWidth[prefLevel], levelToHeight[prefLevel], function( data )
            imageData = data
        end )
        app:sleep ( 30, .1, function() -- ###1 (30/Apr/2014 2:16) seems timeout should be either very short (if just checking), or very long (if determined to wait for rendering).
            -- since this method being used primarily with "Assure Freshness" checkbox, it seems longer would be appropriate. - thus changed from 5 to 30 (and interval from .05 to .1).
            return imageData
        end )
        if shutdown then return nil, "shutdown" end
    end

    local imageId
    local uuid
    local digest
    local orientationCode
    local previewSubdir -- could be declared more locally now, but not hurting here..
    local pDir
    
    if imageData then
        app:logV( "Got preview via new Lr5 way - at preferred level." )
    else
        -- reminder - freshness 0 & 1 were discontinued in May 2013, unfortunately I don't remember the reason (presumably something to do with show-biz? gazoo?? dont think it was for pvw-exp/rec..).
        local tmo = 10 -- note default if unspecified is 30.
        -- if freshness == 0 then tmo = 5 end -- probably should be 0 but I think that is no longer an option - hmm... ###1
        -- if freshness == 1 (no longer supported) or unspecified, leave it set to 10.
        if freshness == 2 then tmo = 15 end
        if freshness == 3 then tmo = 30 end
        local previewInfo, msg = self:_getPreviewInfo( photo, tmo ) -- std tmo = 30 seconds. ###1 (30/Apr/2014 2:02) maybe a little long unless absolute freshness is required or..?
        if msg then
            return nil, msg
        end
        
        imageId = previewInfo.imageId
        uuid = previewInfo.uuid
        digest = previewInfo.digest
        orientationCode = previewInfo.orientation
        
        previewSubdir = str:getFirstChar( uuid )
        pDir = LrPathUtils.child( pd, previewSubdir )
        if fso:existsAsDir( pDir ) then
            -- good
        else
            return nil, "preview letter dir does not exist: " .. pDir
        end
        previewSubdir = uuid:sub( 1, 4 )
        pDir = LrPathUtils.child( pDir, previewSubdir )
        if fso:existsAsDir( pDir ) then
            -- good
        else
            return nil, "preview 4-some dir does not exist: " .. pDir
        end
    end

    -- digest not necessarily "new", but hey...    
    local function createImage( data, newDigest, level )
        local image, errm = Image:new{ file=previewTargetPath, content=data, assureDir=assureDir, dontOverwrite=dontOverwrite }
        if image then
            app:logVerbose( "Wrote preview file: ^1", previewTargetPath )
            
            local sourceProfile
            -- profile is target-profile
            if icc or meta then
                if newDigest == nil then -- new Lr5 way.
                    --Debug.lognpp( rec )
                    --Debug.showLogFile()
                    -- sourceProfile = rec.preview.colorProfile or error( "no color profile" ) - I'd swear this seemed better than hardcoding sRGB on one occasion,
                    -- but certainly most recent test @26/Jun/2013 7:37 shows sRGB being spot on, for assignment anyway.
                    -- ah - problem is: conversion to AdobeRGB is no good if source is considered sRGB - drats.
                    -- ignoring profile seems to be fine in present case.
                    -- so it seems like data is sRGBm since ignoring or assigning srgb looks fine if source is srgb.
                    sourceProfile = 'sRGB' -- ###2 not sure if color-profile is correct or not yet @26/Jun/2013 6:58.
                    sourceProfile = 'AdobeRGB' -- ###1 this is goofed up no matter what, it's like Lr has honked the data so no matter what it's honked..
                    -- interestingly enough, NX2 can display it perfectly as sRGB, but can't save it so ACDSee (nor Lr) can display it quite right - arghh - dunno what's going on..
                else
                    if not fso:existsAsFile( pdb ) then
                        return nil, "File does not exist: "..pdb
                    end
                    app:logVerbose( "querying 'Pyramid' table for profile, uuid: ^1, digest: ^2", uuid, newDigest )
                    local sql = str:fmt( "select colorProfile from Pyramid where uuid='^1' and digest='^2'", uuid, newDigest )
                    local param = '"' .. pdb .. '"'
                    local status, message, content = sqlite:executeCommand( param, { sql }, nil, 'del' )
                    if status then
                        if str:is( content ) then
                            local spa = str:split( content, "\n" ) -- dangling \r\n's are removed as whitespace, I hope.
                            if #spa == 0 then
                                return nil, "Unexpected and unsupported color profile: " .. sourceProfile
                            else
                                local c = 0
                                for i, v in ipairs( spa ) do
                                    if str:is( v ) then
                                        c = c + 1
                                        sourceProfile = v
                                    end
                                end
                                if c == 0 then
                                    return nil, "Missing color profile"
                                elseif c == 1 then -- good
                                else
                                    return nil, "Ambiguous color profile: " .. content
                                end
                            end
                        else
                            return nil, "No content for icc profile."
                        end
                    else
                        return nil, message        
                    end
                end
            end
            
            if meta then
            
                -- do whatever is possible via exif-tool
                local _profile
                if icc == 'A'  then -- Assign
                    _profile = sourceProfile
                    app:logVerbose( "Doing icc profile assignment via exif-tool" )
                    icc = false 
                else
                    app:logVerbose( "Not doing icc assignment via exif-tool" )
                end
                
                image:transferMetadata( photo, photoPath, _profile, previewTargetPath, fmtMeta, ets ) -- do icc sourceProfile along with other metadata if called for.
                
            end
            
            if icc then
                if profile then
                    app:logVerbose( "Doing icc: ^1, from '^2', to: '^3', ets: ^4", icc, sourceProfile, profile, str:to( ets ) )
                else
                    Debug.pauseIf( icc ~= 'A', "icc not 'A'?" )
                    app:logVerbose( "Doing icc: ^1, source profile: '^2', ets: ^3", icc, sourceProfile, str:to( ets ) )
                end
                LrTasks.yield() -- without this yield, transfer of metadata followed by conversion (using et-session) fails. ###3 not sure why.
                image:addColorProfile( icc, sourceProfile, profile, ets )
            else
                app:logVerbose( "May not be doing icc assignment or conversion - check for verbose log above." )
            end
            
            if str:is( mogParam ) then
                image:addMogParam( mogParam )
            end
            
            if orient and orientationCode then -- orientation is specified in calling context, *and* it was obtained via preview db.
                image:addOrientation( orientationCode, ets )
            end

            -- no additional exiftool'n is yet supported ###3
            
            local s, m = image:commit( ets ) -- commit mogrification and exiftooleanization.
            
            if s then
                -- good (see log below).
                Debug.logn( "image commited" )
            else
                return nil, m
            end
            
            --self:_putImageInCache( imageId, prefLevel, image, previewSourceTime )
            app:logVerbose( "image is fresh from preview file" )
            return image, nil, level -- echo level.
            
        else
            return nil, errm
        end
    end

    -- get best image or none at all...
    -- returns image, nil, level
    -- or nil, errm.
    local function getImage()    
        app:logv( "Getting preview, imageID: ^1, previewID: ^2", imageId, uuid )
        local previewFilename = str:fmtx( "^1-^2.lrprev", uuid, digest )
        local previewSourcePath = LrPathUtils.child( pDir, previewFilename )
        if not fso:existsAsFile( previewSourcePath ) then
            return nil, str:fmtx( "Preview file does not exist: ^1", previewSourcePath )
        end
        app:logv( "Getting images from preview file: ^1", previewSourcePath )
        local data, level = self:_getImageDataFromFile( previewSourcePath, minLevel, prefLevel ) -- @6/May/2013 1:08 - the new way actually gets all image data between min and pref levels.
        -- that's less efficient than how it was previously programmed, but at this point, I don't want to go back..
        assert( level <= prefLevel, "image gotten is too big" )
        if level == prefLevel then
            app:logv( "Creating image with matching digest (^1) at preferred level (^2)", digest, level )
            return createImage( data[level], digest, level )
        elseif level >= minLevel then
            app:logv( "Creating image with matching digest (^1) at compromised level (^2) - preferred level: ^3", digest, level, prefLevel )
            return createImage( data[level], digest, level )
        else
            return nil, str:fmtx( "no preview at acceptable level, requested: ^1 - ^2, max found: ^3", minLevel, prefLevel, level )
        end
    end
    
    -- assure freshness at "3". reminder: this is stricter insurance than just checking database, since it assures preview file has been written since last edit.
    -- only problem is, if last edit was due to metadata change, (or Lr is in develop module and not updating previews) this could take a while, or still return stale preview.
    -- consider factoring in new methods developed ~21/Aug/2013 6:38. Note: until problems with new freshening methods are resolved, safer to use old way (worth revisiting this for Gazoo and things depending on ultra-fresh previews. ###1
    local function assureFreshnessAt3()
        local previewFilename = str:fmtx( "^1-^2.lrprev", uuid, digest )
        local previewSourcePath = LrPathUtils.child( pDir, previewFilename )
        app:logv( "Considering freshness based on preview file: ^1", previewSourcePath )

        --app:logVerbose( "querying 'Pyramid' table for times, uuid: ^1, digest: ^2", uuid, digest )
        --local sql = str:fmt( "select fileTimeStamp, pyramidFileTimeStamp from Pyramid where uuid='^1' and digest='^2'", uuid, digest )
        --local status, message, content = sqlite:executeCommand( param, { sql }, nil, 'del' )
        --if status then
        --    Debug.pause( content )
        --end
        local count = 600 -- wait up to 60 seconds.
        local lastEdit = photo:getRawMetadata( 'lastEditTime' ) or error( "no let" ) -- only do this once to maximize probability for success.
        repeat

            --if count == 600 then        
            --    LrShell.revealInShell( previewSourcePath )
            --end
        
            if fso:existsAsFile( previewSourcePath ) then
                app:logVerbose( "Found preview file at ^1", previewSourcePath )
            else
                return nil, str:fmt( "No preview file corresponding to ^1 at ^2", photoPath, previewSourcePath )
            end
            local attr = LrFileUtils.fileAttributes( previewSourcePath )
            if attr == nil then
                return nil, "no preview attrs"
            end
            local previewSourceTime = attr.fileModificationDate
            if previewSourceTime == nil then
                return nil, "no preview date on file"
            end
            
            -- ###2 maybe what I need to do is check time befor issuing the creation command, and then check for newer (than when command issued) file,
            -- instead of checking for better than last-edit. - that would work if creation is unconditional - but it's not.
            
            -- I fear using a fudge factor since it could make it flaky: sometimes it's a new one, sometimes old, sometimes doesn't work... crud.
            if previewSourceTime >= lastEdit then -- there seems to be a race condition or something, sometimes preview source time will differ from last-edit by 19 or 20 seconds, hmm...
                Debug.logn( "preview fresh", count, previewSourcePath, LrDate.timeToUserFormat( previewSourceTime, "%Y-%m-%d %H:%M:%S" ), LrDate.timeToUserFormat( lastEdit, "%Y-%m-%d %H:%M:%S" ), date:formatTimeDiff( previewSourceTime - lastEdit ) )
                return true
            end
            -- compute newest one.
            previewSourceTime = -9999999
            previewSourcePath = nil
            for file in LrFileUtils.files( pDir ) do
                local leafName = LrPathUtils.leafName( file )
                if str:isStartingWith( leafName, uuid, 1, true ) then
                    local stamp = fso:getFileModificationDate( file )
                    if stamp > previewSourceTime then -- newer
                        previewSourceTime = stamp -- will get newest. Note: really, I should be resetting source-photo-path if desired level not found in newest.. or better still, go through all and find biggest, if bigger is better.
                        previewSourcePath = file
                        Debug.logn( "got newer alt", previewSourcePath )
                        -- break
                    else
                        Debug.logn( "not newer", leafName )
                    end
                else
                    Debug.logn( "not starting with", leafName, uuid )
                end
            end
            if previewSourcePath == nil then -- nothing in dir with requisite uuid - fall-back to original to keep conditionals and logs happy.
                previewSourcePath = savedSourcePath
            else
                return true -- added 31/Mar/2013 16:20 - although does not guarantee freshness, it does guarantee fresh-est, such that if we *know* there is a fresh preview in there
                -- somewhere, then this is it. - use in conjunction with forced preview generation / validation (e.g. via UI feedback) and it may be OK.
            end
            Debug.logn( "preview not fresh, yet", count, previewSourcePath, LrDate.timeToUserFormat( previewSourceTime, "%Y-%m-%d %H:%M:%S" ), LrDate.timeToUserFormat( lastEdit, "%Y-%m-%d %H:%M:%S" ), date:formatTimeDiff( previewSourceTime - lastEdit ) )
            if count == 600 then
                --Debug.showLogFile()
            end
            if count == 500 then
                -- LrShell.revealInShell( previewSourcePath )
            end
            count = count - 1
            LrTasks.sleep( .1 )
            if shutdown then return false, "shutdown" end
        until count == 0
        
        return false, "Unable to assure preview is fresh"
    end
    
    -- as specified by id, prefLevel, & freshness
    if freshness == 3 then -- must be *very* fresh.
        local fresh, msg = assureFreshnessAt3()
        if not fresh then
            return nil, msg -- this will keep from retrying at another level.
        end
    end
    if imageData then -- new Lr5 way succeeded
        return createImage( imageData, nil, prefLevel )
    else
        return getImage() -- return biggest acceptable preview (legacy method).
    end
    
end



--- Get smart preview *file* associated with specified photo etc.
--
--  @param params (table, required) with members:
--    <br>photo (LrPhoto, required) photo.
--    <br>photoPath (string, optional) photo path.
--    <br>cache (lr-metadata-cache, optional) with "smart-preview-info" in it, else useless here.
--
--  @return path (string) if obtainable.
--  @return nil, errm if not.
--
function Previews:getSmartPreview( params ) -- the easy way
    if app:lrVersion() < 5 then
        return nil, "Requires Lr5+"
    end
    local cache = params.cache
    app:callingAssert( params ~= nil, "no params" )
    local photo = app:callingAssert( params.photo, "no photo" )
    local spi = lrMeta:getRaw( photo, 'smartPreviewInfo', cache ) -- accepting if uncached is implied when using this method.
    if spi and spi.smartPreviewPath then -- spi is empty table when no sp in Lr5, still: good to check..
        return spi.smartPreviewPath
    else
        return nil, "No smart preview available."
    end
end
--[[ the hard way: *** save for reference..
function Previews:____getSmartPreview( params )
                            app:callingAssert( params ~= nil, "no params" )
                            local photo = app:callingAssert( params.photo, "no photo" )
                            local photoPath = params.photoPath or photo:getRawMetadata( 'path' ) -- cache? ###3
                            local previewInfo, msg = self:_getPreviewInfo( photo )
                            if msg then
                                return nil, msg
                            end
                            local imageId = previewInfo.imageId
                            local cd = previewInfo.catDir
                            local n = previewInfo.catName
                            local pn = n .. " Smart Previews.lrdata"
                            local d = LrPathUtils.child( cd, pn )
                            local uuid = previewInfo.previewId
                            
                            local previewSubdir = str:getFirstChar( uuid )
                            local pDir = LrPathUtils.child( d, previewSubdir )
                            if fso:existsAsDir( pDir ) then
                                -- good
                            else
                                return nil, "preview letter dir does not exist: " .. pDir
                            end
                            previewSubdir = uuid:sub( 1, 4 )
                            pDir = LrPathUtils.child( pDir, previewSubdir )
                            if fso:existsAsDir( pDir ) then
                                -- good
                            else
                                return nil, "preview 4-some dir does not exist: " .. pDir
                            end
                            local previewFilename = uuid .. ".dng"
                            
                            local previewSourcePath = LrPathUtils.child( pDir, previewFilename )
                            if fso:existsAsFile( previewSourcePath ) then
                                app:logVerbose( "Found smart preview file at ^1", previewSourcePath )
                                return previewSourcePath
                            else
                                return nil, str:fmt( "No smart preview file corresponding to ^1 at ^2", photoPath, previewSourcePath )
                            end
end
--]]



return Previews

