--[[
        Xmp.lua
        
        Class of framework's global xmpo object which can be used for xmp-based functionality, including:
        
        * transfer of metadata and/or develop settings which go beyond what is supported via SDK.
--]]


local Xmp, dbg, dbgf = Object:newClass{ className = "Xmp", register = true }



--- Constructor for extending class.
--
function Xmp:newClass( t )
    return Object.newClass( self, t )
end



local devAdjSupport = {
    Crop = true,
    Orientation = true,
}



--- Constructor for new instance.
--
--  @return      new image instance, or nil.
--  @return      error message if no new instance.
--
function Xmp:new( t )
    local o = Object.new( self, t )
    return o
end



--- Determine if xmp file differs significantly from another.
--
--  @usage              both files must exist.
--
--  @return status      ( boolean, always returned ) true => changed, false => unchanged, nil => see message returned for qualification.
--  @return message     ( string, if status = nil or false ) indicates reason.
--
function Xmp:isChanged( xmpFile1, xmpFile2, fudgeFactorInSeconds )

    if fudgeFactorInSeconds == nil then
        fudgeFactorInSeconds = 2
    end

    local t1 = fso:getFileModificationDate( xmpFile1 )
    local t2
    if t1 then
        t2 = fso:getFileModificationDate( xmpFile2 )
        if t2 then
            -- ###3 could use num:isWithin( t1, t2, fudgeFactorInSeconds ) but best to hold off until able to test.
            if t1 > (t2 + fudgeFactorInSeconds) or t2 > (t1 + fudgeFactorInSeconds) then
                -- proceed, to check content.
            else
                return false, "xmp file has not been modified"
            end
        else
            return nil, "file not found: " .. str:to( xmpFile2 )
        end
    else
        return nil, "file not found: " .. str:to( xmpFile1 )
    end
    
    local c1, m1 = fso:readFile( xmpFile1 )
    if str:is( c1 ) then
        -- reminder: raws have elements, rgbs have attributes
        c1 = c1:gsub( 'MetadataDate.-\n', "" )
        local c2, m2 = fso:readFile( xmpFile2 )
        if str:is( c2 ) then
            c2 = c2:gsub( 'MetadataDate.-\n', "" )
            if c1 ~= c2 then
                return true
            else
                return false, str:fmt( "source xmp modification date is ^1 (^2), and destination is ^3 (^4), but there are no significant content changes", t1, LrDate.timeToUserFormat( t1, "%Y-%m-%d %H:%M:%S" ), t2, LrDate.timeToUserFormat( t2, "%Y-%m-%d %H:%M:%S" ) )
            end
        else
            return nil, "No content in file: " .. xmpFile2
        end
    else
        return nil, "No content in file: " .. xmpFile1
    end
        
end



--- Get xmp file: depends on lrMeta, and metaCache recommended.
--
--  @returns    path (string, or nil) nil if xmp-path not supported.
--  @returns    other (boolean, string, or nil) true if path is sidecar, string if path is nil, nil if path is source file.
--
function Xmp:getXmpFile( photo, metaCache )
    assert( photo ~= nil, "no photo" )
    if metaCache == nil then
        app:logv( "No cache" ) -- inefficient. to avoid this message, pass an empty cache.
        -- metaCache = lrMeta:createCache() - create default/empty cache - wont help.
    end
    local isVirt = lrMeta:getRaw( photo, 'isVirtualCopy', metaCache ) -- accept un-cached.
    assert( isVirt ~= nil, "virt?" )
    if isVirt then
        return false, "No xmp file for virtual copy"
    end
    local fmt = lrMeta:getRaw( photo, 'fileFormat', metaCache )
    local path = lrMeta:getRaw( photo, 'path', metaCache )
    assert( str:is( path ), "no path" )
    if fmt == 'RAW' then
        return LrPathUtils.replaceExtension( path, "xmp" ), true
    elseif fmt == 'VIDEO' then
        return nil, "No xmp for videos"
    else
        return path
    end
end



--- Another version of the same - bypasses check for virtual copy, and cache, and..
--
function Xmp:getTargetFile( path )
    local ext = LrPathUtils.extension( path )
    if cat:getExtSupport( ext ) == 'raw' and not str:isEqualIgnoringCase( ext, 'DNG' ) then
        return LrPathUtils.replaceExtension( path, 'xmp' )
    else
        return path
    end
end



--- Get photo path and xmp file (path), if applicable.
function Xmp:getSourceFiles( photo, metaCache )
    local photoFile = lrMeta:getRaw( photo, 'path', metaCache ) -- accept uncached.
    local xmpFile = self:getXmpFile( photo, metaCache )
    return photoFile, xmpFile
end



--- Assure the specified photos have settings in xmp, without changing settings significantly.
--
--  ###3 It seems this function is not being called anywhere - certainly xmp-crop could call it, but isn't (I'm guessing I forgot to retrofit or decided not to or something).
--
function Xmp:assureSettings( photo, xmpPath, ets )
    -- get tag from xmp file.
    local function getItem( itemName )
        local itemValue
        ets:addArg( "-S" ) -- short
        ets:addArg( "-" .. itemName )
        ets:addTarget( xmpPath )
        local rslt, errm = ets:execute()
        if str:is( errm ) then
            app:logErr( errm )
            return nil, errm
        end
        if not str:is( rslt ) then
            return nil
        end
        Debug.lognpp( rslt, errm )
        local splt = str:split( rslt, ":" )
        if #splt == 2 then
            if splt[1] == itemName then
                itemValue = splt[2] -- trimmed.
            else
                app:logErr( "No label" )
                return nil -- , "No label"
                --app:error( "No label" )
            end
        else
            --app:logErr( "Bad response (^1 chars): ^2", #rslt, rslt )
            return nil -- , str:fmt( "Bad response (^1 chars): ^2", #rslt, rslt )
        end
        if itemValue ~= nil then
            app:logVerbose( "From xmp, name: '^1', value: '^2'", itemName, itemValue )
            return itemValue
        else
            return nil -- no err.
        end
    end
    for i = 1, 2 do
        local exp = getItem( 'Exposure2012' ) -- always present if there have been saved adjustments.
        if exp then
            return true, ( i == 2 ) and "after adjustment"
        end
        local exp = getItem( 'Exposure' ) -- always present if there have been saved adjustments.
        if exp then
            return true, ( i == 2 ) and "after adjustment"
        end
        if i == 2 then
            return false, "Unable to see applied adjustments reflected in xmp."
        end
        local dev = { noAdj=true }
        local preset = LrApplication.addDevelopPresetForPlugin( _PLUGIN, "No Adjustment", dev )
        if not preset then error( "no preset" ) end
        local s, m = cat:update( 10, "No Adjustment", function( context, phase )
            -- apply preset
            photo:applyDevelopPreset( preset, _PLUGIN )
        end )
        if s then
            s, m = cat:savePhotoMetadata( photo )
            if s then
                -- loop
            else
                return false, m
            end 
        else
            return false, m
        end
    end
end



--- Transfers "all" develop settings and/or metadata from one image file to another, via xmp.
--
--  @usage *** Calling context MUST assure xmp source file is fresh before calling this function, otherwise data will be lost.
--  @usage *** Likewise, dest xmp file must exist. It need not be so fresh, since it will be mostly redone, but probably a good idea to freshen it too before calling.
--  @usage ###3 It could be that source and/or dest settings need to be pre-assured for dev transfer - not sure atm.
--  @usage The reason this function does not assure-settings is because it's supposed to be callable even if one (or both) photos are not in the catalog - thus only file paths (not photo objects) are available.
--  @usage Does some verbose logging, but offers no captions, so display in calling context, and log result upon return.
--  @usage The code upon which this is based was developed for raw+jpeg plugin. It has since been adapted to (hopefully) cover all file types, and whether files are in catalog or not. But since fresh xmp must be pre-assured, one would need to invoke exiftool to "save metadata" if src or dest file is not photo in catalog.
--
--  @param params (table, required) named parameters:
--      <br>    xmpSrcFile (string, required) source xmp file (will be xmp sidecar or rgb file).
--      <br>    xmpDestFile (string, required) destination xmp file (will be xmp sidecar or rgb file).
--      <br>    xfrDev (boolean, default=true) iff true transfer develop settings.
--      <br>    xfrMeta (boolean, default=true) iff true transfer (other) metadata.
--      <br>    excludeOrientation (boolean, default=false) set true to exclude orientation from xfr'd metadata.
--      <br>    metadataCache (LrMetadata::Cache, optional).
--      <br>    exifToolSession (ExifTool::Session, required) ets.
--
function Xmp:transferMetadata( params )
    local savedXmpFile
    local s, m = app:call( Call:new{ name="Transfer Metadata", main=function( call )

        local srcPhotoFile, destPhotoFile
        local xmpSrcFile, xmpDestFile, xfrDev, xfrMeta, cache, exifToolSession, excludeOrientation -- , orientRawsToo
        if type( params ) == 'table' then
            --assureSettings = bool:booleanValue( params.assureSettings, true )
            exifToolSession = params.exifToolSession or error( "no exiftool session" )
            xfrMeta = bool:booleanValue( params.xfrMeta, true )
            xfrDev = bool:booleanValue( params.xfrDev, true )
            srcPhotoFile = app:assert( params.srcPhotoFile, "no src photo file" )
            destPhotoFile = app:assert( params.destPhotoFile, "no dest photo file" )
            xmpSrcFile = app:assert( params.xmpSrcFile, "no src xmp file" )
            xmpDestFile = app:assert( params.xmpDestFile, "no dest xmp file" )
            --orientRawsToo = bool:booleanValue( params.orientRawsToo, true )
            excludeOrientation = params.excludeOrientation
        else
            app:callingError( "params must be table" )
        end
        
        app:logV( "Transferring develop settings and/or metadata from '^1' to '^2'", xmpSrcFile, xmpDestFile )
    
        local saved
        local srcExt = LrPathUtils.extension( srcPhotoFile ) or "" -- not sure what this returns if no extension.
        local jpgToRaw
        if #srcExt >= 2 then
            local destIsRaw = str:isEqualIgnoringCase( LrPathUtils.extension( xmpDestFile ), 'xmp' ) -- or str:isEqualIgnoringCase( LrPathUtils.extension( srcPhotoFile ), 'dng' )
            if destIsRaw then
                jpgToRaw = str:isEqualIgnoringCase( srcExt:sub( 1, 2 ), 'jp' )
            end
        end
        
        local srcOrient
        local destOrient
        local function saveSrcOrient( srcXmpFile )
            exifToolSession:addArg( "-S" )
            exifToolSession:addArg( "-Orientation" ) -- let exiftool figure out proper interpretation
            exifToolSession:addTarget( srcXmpFile )
            local data, errm, more = exifToolSession:execRead()
            if data then -- text
                srcOrient = exifTool:parseOneShortValue( data, "Orientation" ) -- about the same as get-value-from-pair-S
                if str:is( srcOrient ) then
                    app:logV( "Source orient saved: ^1", srcOrient )
                else
                    app:logV( "No source orient to save" )
                    srcOrient = nil
                end
            else
                app:logV( "No source orient to save" )
                srcOrient = nil
            end        
        end
        local function saveDestOrient( destXmpFile )
            exifToolSession:addArg( "-S" )
            exifToolSession:addArg( "-Orientation" ) -- let exiftool figure out proper interpretation
            exifToolSession:addTarget( destXmpFile )
            local data, errm, more = exifToolSession:execRead()
            if data then -- text
                destOrient = exifTool:parseOneShortValue( data, "Orientation" ) -- about the same as get-value-from-pair-S
                if str:is( destOrient ) then
                    app:logV( "Dest orient saved: ^1", destOrient )
                else
                    app:logV( "No dest orient to save" )
                    destOrient = nil
                end
            else
                app:logV( "No dest orient to save" )
                destOrient = nil
            end        
        end
        local function restoreOrient( orient, file )
            if str:is( orient ) then
                exifToolSession:addArg( "-overwrite_original" )
                exifToolSession:addArg( "-Orientation="..orient )
                exifToolSession:addTarget( file ) -- same as set-target if only one target.
                local s, m = exifToolSession:execWrite()
                if s then
                    app:logV( "Updated orientation in '^1' to '^2'", file, orient )
                else
                    app:error( "Unable to update orientation in '^1' to '^2' - ^3", file, orient, m )
                end
            else
                app:error( "No orientation for updating in '^1'", file )
            end
        end
        local function restoreSrcOrient( destXmpFile )
            if srcOrient then
                restoreOrient( srcOrient, destXmpFile )
            end
        end
        local function restoreDestOrient( destXmpFile )
            if destOrient then
                restoreOrient( destOrient, destXmpFile )
            end
        end
        
        if xfrMeta and xfrDev then -- there should be no reason to exclude orientation, if it's working properly..
            app:logV( "Transfering all develop settings and metadata" )
            exifToolSession:addArg( "-overwrite_original" )
            exifToolSession:addArg( "-all=" ) -- strip all tags from dest file (note: this makes sense if target is xmp sidecar or jpg being sync'd from raw partner, but if one jpg being sync'd from another: only if the other has it all..
            exifToolSession:addArg( "-tagsFromFile" ) -- this introduces the path of file which will be the source of tags to be added back, but says nothing about which tags.
            exifToolSession:addArg( xmpSrcFile ) -- tags from file..
            exifToolSession:addArg( '-xmp' ) -- see comment below - this part required for "unknown" but critical xmp tags, like brush-strokes.
            exifToolSession:addArg( '-all:all' ) -- updates all "known" tags (xmp and non-xmp), perhaps overlap is inefficient - maybe should use P.H.'s options: "-xmp:all>all:all" ??? ###3
            exifToolSession:addTarget( xmpDestFile ) -- target of transfer.
            local s, m = exifToolSession:execWrite()
            if s then
                app:logV( "metadata and dev settings transferred" )
            else
                app:error( "Unable to transfer metadata and dev settings - ^1", m )
            end
        else -- xfring dev *or* meta via xmp (not both).
            -- reminder: saved xmp file is a temp file, not conforming to xmp standards
            savedXmpFile = LrPathUtils.addExtension( xmpDestFile, "xmp" ) -- kinda tacky.
            -- save dest xmp in a file for selective restoral after big-hammer transferral.
            exifToolSession:addArg( "-overwrite_original" )
            exifToolSession:addArg( "-tagsFromFile" )
            exifToolSession:addArg( xmpDestFile )
            exifToolSession:addArg( "-xmp" )
            exifToolSession:addTarget( savedXmpFile )
            local s, m = exifToolSession:execWrite()
            if s then
                assert( fso:existsAsFile( savedXmpFile ), "exiftool was unable to save xmp metadata" )
                --Debug.pause( savedXmpFile, "has orientation?" )
            else
                if LrFileUtils.isWritable( xmpDestFile ) then
                    app:assert( LrFileUtils.isReadable( savedXmpFile ), "Not readable: ^1", savedXmpFile )
                    app:error( "unable to save xmp - ^1", m )
                else
                    app:error( "unable to save xmp - '^1' is not writable", xmpDestFile )
                end
            end
            -- note: saved xmp has dest xmp (pre-mod) as block in it
            if xfrMeta then
                saveDestOrient( xmpDestFile )
                -- replace all tags in destination xmp file with those of source xmp, except for crs and maybe orientation.
                exifToolSession:addArg( "-overwrite_original" )
                exifToolSession:addArg( '-all=' ) -- strips all dest tags including crs and orientation and metadata
                exifToolSession:addArg( '-tagsFromFile' )
                exifToolSession:addArg( xmpSrcFile )
                -- exifToolSession:addArg( "-xmp" ) - can't do this here, or it brings the develop settings too, at least when xfr is raw -> jpg.
                exifToolSession:addArg( "-all:all" ) -- would restore all tags from src, but 
                exifToolSession:addArg( '--xmp-crs:all' ) -- crs tags are excluded
                --exifToolSession:addArg( '--Orientation' ) -- added 10/Dec/2014 6:53 - if xfr'ing metadata not dev, orientation must be excluded too (it's being considered and treated as a develop setting by methods in this module).
                exifToolSession:addTarget( xmpDestFile )
                local s, m = exifToolSession:execWrite()
                if s then
                    app:logV( "xmp updated via exiftool" )
                else
                    app:error( "Unable to update xmp - ^1", m )
                end
                -- restore crs tags
                exifToolSession:addArg( "-overwrite_original" )
                exifToolSession:addArg( '-tagsFromFile' )
                exifToolSession:addArg( savedXmpFile )
                --exifToolSession:addArg( "-xmp" )
                exifToolSession:addArg( '-xmp-crs:all' )
                exifToolSession:addTarget( xmpDestFile )
                local s, m = exifToolSession:execWrite()
                if s then
                    app:logV( "xmp updated" )
                elseif m then -- not updated with reason.
                    app:error( "Unable to update xmp - ^1", m )
                end
                if destOrient then
                    restoreDestOrient( xmpDestFile )
                else
                    app:logV( "*** No orientation to restore." )
                end
            elseif xfrDev then -- can't seem to get orientation jpg->raw correct no matter what I do, so: done for now... ###2
                               -- note: I put that comment there at some point in the past, but @11/Sep/2013 5:35 (Lr5.2RC) orientation is coming from jpg->raw just fine. Hmm..
                saveSrcOrient( xmpSrcFile )
                if not srcOrient then
                    saveDestOrient( xmpDestFile )
                end
                exifToolSession:addArg( "-overwrite_original" )
                exifToolSession:addArg( '-all=' )
                exifToolSession:addArg( '-tagsFromFile' )
                exifToolSession:addArg( xmpSrcFile )
                exifToolSession:addArg( "-xmp" ) -- must be here for unrecognized paint settings..., but stomps on orientation - verified.
                exifToolSession:addArg( '-xmp-crs:all' ) -- orientation is a dont care, since it will be handled via restoral below.
                exifToolSession:addTarget( xmpDestFile )
                local s, m = exifToolSession:execWrite()
                if s then
                    app:logV( "xmp updated" )
                elseif m then
                    app:error( "Unable to update xmp - ^1", m )
                end
                exifToolSession:addArg( "-overwrite_original" )
                exifToolSession:addArg( '-tagsFromFile' )
                exifToolSession:addArg( savedXmpFile )
                -- exifToolSession:addArg( "-xmp" ) -- must not be here, else stomps on odd paints - verified.
                exifToolSession:addArg( '-all:all' )
                exifToolSession:addArg( '--xmp-crs:all' )
                --if excludeOrientation then
                --    exifToolSession:addArg( '--Orientation' ) -- added 10/Dec/2014 6:53, since otherwise, orientation is wiped when doing orientation separately as dev-adj xfr.
                --end
                exifToolSession:addTarget( xmpDestFile )
                local s, m = exifToolSession:execWrite()
                if s then
                    app:logV( "xmp updated via exiftool" )
                elseif m then -- not updated with reason.
                    app:error( "Unable to update xmp - ^1", m )
                end
                if srcOrient then
                    restoreSrcOrient( xmpDestFile )
                elseif destOrient then
                    app:logV( "*** Source orientation is missing, so restoring previous orientation instead - so at least it won't be changed even if not xfr'd.." )
                    restoreDestOrient( xmpDestFile )
                else
                    app:logV( "*** No orientation to restore." )
                end
            else
                app:callingError( "xfr-dev or xfr-meta needs to be set" )
            end            
            
        end -- xfr type clauses.
        
    end, finale=function( call )
        if str:is( savedXmpFile ) then
            if fso:existsAsFile( savedXmpFile ) then
                LrFileUtils.delete( savedXmpFile )
            end
        end
        savedXmpFile = nil
    end } )

    return s, m
        
end -- end of transfer metadata method.



--- Transfers critical develop settings (crop and/or orientation) from one photo (real or virtual) to another (must be real), via xmp.
--
--  @usage If Lr SDK supported crop & orientation, this method would not be necessary - photos must be in catalog.
--  @usage Based on code originally developed in 'Send Metadata Down In Stack' script (not plugin).
--  @usage It would be theoretically possible to implement support for virtual photos ase targets (to-photos), by jockeying settings/xmp around, but @5/Dec/2014 19:40 that's not supported.
--  @usage Do not set either of the metadata-pre-saved flags to false if background process, else you'll get an error. They default to true if bg call.
--  @usage Foreground:
--      <br>    local status, later, snuff
--      <br>    local devAdj = { Crop=true, Orientation=true }
--      <br>    local s, m = cat:update( 15, "xfr xm-based dev-adjs", function( context, phase )
--      <br>        if phase == 1 then
--      <br>            -- do other stuff too if desired..
--      <br>            status, later = xmpo:xfrDevAdj{ call=call, fromPhoto=fromPhoto, toPhotoInfo={{toPhoto}}, devAdjSet=devAdj }
--      <br>            if status and tab:is( later ) then
--      <br>                 return false -- need to do the later stuff
--      <br>            end
--      <br>        else
--      <br>            xmpo:xfrDevAdj{ call=call, xmpLater=later, fromPhoto=fromPhoto, toPhotoInfo={{toPhoto}}, devAdjSet=devAdj } -- note: all is ignored except for call & xmp-later, but must be present to satisfy..
--      <br>        end
--      <br>    end )
--      <br> Background:
--      <br>    status, later, snuff = xmpo:xfrDevAdj{ call=call, fromPhoto=fromPhoto, toPhotoInfo={{toPhoto}}, devAdjSet=devAdj } -- that's it (don't wrap). since not wrapped, xmp-upd will not be deferred for later.
--      <br>        -- 'later' will be nil or empty table, 'snuff' will indicate whether idle-processing should skip a cycle (can be ignored without much if any penalty).
--
--  @param params (table, required) named parameters:
--      <br>    call (Call object, recommended especially if will be called repetitively from background process) if background call, logging will be repressed..
--      <br>    fromPhoto (LrPhoto, required) source photo - real or virtual.
--      <br>    fromPhotoName (string, default = full path, with virtual copy name if applicable).
--      <br>    fromDevSettings (structure, optional) source photo develop settings, if available in calling context.
--      <br>    fromMetadataPreSaved (boolean, default=false) set true to bypass saving of source photo (xmp) metadata. If NOT bg process, do pre-save externally.
--      <br>    toPhotoInfo (array, required) destination (real) photo info, members: photo(required), photoPath(optional), photoName(optional), devSettings(optional).
--      <br>    toMetadataPreSaved (boolean, default=false) set true to bypass saving of destination photo (xmp) metadata. If NOT bg process, do pre-save externally.
--      <br>    devAdjSet (table, required) recommend: { Crop=true, Orientation=true } - set of adjustments to transfer.
--      <br>    metadataCache (LrMetadata::Cache, optional). Must be nil if background process.
--      <br>    exifToolSession (ExifTool::Session, optional) if nil, exiftool in non-session mode will be used.
--
--  @return status true => no problem. if no qualification, then xfr complete, else needs a follow-up phase.
--  @return xmp-later table (if status true) or error message (if status false).
--  @return activity-flag, to support background processing distribution - if set, it's enough (defer idle processing for one cycle).
--
function Xmp:transferDevelopAdjustments( params )

    app:callingAssert( exifTool, "exiftool must be global" )
    local xmpLater = params.xmpLater -- or will be created for to be passed back in if re-called in secondary phase of catalog update.
    local call = params.call or app:callingError( "no call" )
    local bgProcess = _G.background and call and call==background.call
    local fromPhoto = not xmpLater and ( params.fromPhoto or app:callingError( "no from-photo" ) ) or nil
    local fromDevSettings = params.fromDevSettings -- or defer.
    local fromMetadataPreSaved = params.fromMetadataPreSaved -- appropriateness checked below.
    local metadataCache = params.metadataCache -- or nil.
    local fromPhotoName = not xmpLater and ( params.fromPhotoName or cat:getPhotoNameDisp( fromPhoto, true, metadataCache ) ) or nil
    local toPhotoInfo = not xmpLater and ( params.toPhotoInfo or app:callingError( "no to-photo-info)" ) ) or nil
    local toMetadataPreSaved = params.toMetadataPreSaved -- appropriateness checked below.
    local devAdjSet = not xmpLater and ( params.devAdjSet or app:callingError( "no dev-adj-set" ) ) or nil
    local exifToolSession = params.exifToolSession -- or nil.
    local readMetadata = not params.toMetadataPostRead
    local saveMetadata = xmpLater or not fromMetadataPreSaved
    
    if not exifToolSession then
        dbgf( "I recommend using exif-tool session - it's much more efficient." )
    end
    
    if bgProcess then
        if metadataCache then
            app:callingError( "Do not pass metdata cache in background mode, fresh metadata required.." )
        end
    end
            
    if not fromMetadataPreSaved then
        if bgProcess then
            if fromMetadataPreSaved == nil then
                fromMetadataPreSaved = true
            else -- false was passed in from calling context
                app:callingError( "from-metadata-pre-saved should be nil or true if called by background process." )
            end
        end
    else -- will have to be saved herein
        if app:lrVersion() < 5 then
            app:callingError( "from-photo metadata must be pre-saved unless Lr5 or better" )
        -- else fine: will be saved within.
        end
    end
    
    if not toMetadataPreSaved then
        if bgProcess then
            if toMetadataPreSaved == nil then
                toMetadataPreSaved = true
            else -- false was passed in from calling context
                app:callingError( "to-metadata-pre-saved should be nil or true if called by background process." )
            end
        end
    else -- will have to be saved herein
        if app:lrVersion() < 5 then
            app:callingError( "to-photo metadata must be pre-saved unless Lr5 or better" )
        -- else fine: will be saved within.
        end
    end
    
    local noAdjPresetCache = {} -- this module uses a "no-adjustment" preset, which doen't change, but isn't pre-created. if needed here, it will be cached for next time.

    -- local logging functions - they do one thing when executing in foreground mode (standard logging), and another when executing in the background..
    
    local function log( m, ... )
        if bgProcess then
            dbgf( "info: "..m, ... )
        else
            app:log( m, ... )
        end
    end
    local function logV( m, ... )
        if bgProcess then
            dbgf( "verbose: "..m, ... )
        else
            app:logV( m, ... )
        end
    end
    local function logW( m, ... )
        if bgProcess then
            app:alertLogW( m, ... ) -- bg version not appropriate, since it needs an ID, and then to be cleared.. this handling makes for permanent warnings, in log, and user must clear via scope.
        else
            app:logW( m, ... )
        end
    end
    local function logE( m, ... )
        if bgProcess then
            app:alertLogE( m, ... ) -- bg version not appropriate, since it needs an ID, and then to be cleared.. this handling makes for permanent errors, in log, and user must clear via scope.
        else
            app:logE( m, ... )
        end
    end
    
    if not xmpLater then
        if tab:hasItems( devAdjSet ) then
            for id, _ in pairs( devAdjSet ) do
                if not devAdjSupport[id] then
                    app:callingError( "Invalid xmp-adj: ^1", id ) -- force calling context to get it right.
                end
            end
        end
        if devAdjSet.Crop and devAdjSet.Orientation then
            logV( "Adjusting crop and orientation." )
        elseif devAdjSet.Crop then
            logV( "Adjusting crop, not orientation." )
        elseif devAdjSet.Orientation then
            logV( "Adjusting orientation, not crop." )
        else
            app:callingError( "'Crop' and/or 'Orientation' is required in dev-adj-set table." )
        end
    end
    
    local exifToolObject  -- exif-tool proper (as external app), or exiftool session (recommended if called repetitively).
    local activityFlag    -- minor factor for background performance - governs whether idle processing skips a beat or not.
    
    -- apply specified xmp-settings to photo. be careful that applied dev settings have settled (do not call this in same
    -- with-do gate where develop settings have changed, or else develop settings will be lost).
    -- with the above-mentioned proviso, it should do the right thing: save-metadata, boot-strap settings, read-metadata.
    local function xmpNow( photo, xmpSettings, targetFile )
        app:callingAssert( tab:hasItems( xmpSettings ), "no xmp settings" )
        assert( exifTool, "no exif-tool" ) -- initialized below.
        local saved, andThenSome
        if saveMetadata then
            saved, andThenSome = cat:saveXmpMetadata( photo ) -- save metadata and assure it's saved.
            Debug.pauseIf( andThenSome~=targetFile, "?" )
        else
            saved = true
        end
        if saved then
            exifToolObject:addArg( "-overwrite_original" ) -- since only orientation and crop tags of *xmp* (in sidecar or image file), it should be reasonably safe to overwrite originals.
            for k, v in pairs( xmpSettings ) do
                exifToolObject:addArg( str:fmtx( '-^1=^2', k, v ) ) -- no need for quotes around value in session mode, nor emulation mode.
            end
            exifToolObject:setTarget( targetFile )
            local s, m = exifToolObject:execWrite()
            if s then
                if readMetadata then
                    photo:readMetadata() -- just "queues" a read metadata request, but if command executed without error, assume the best (all pre-reqs were met).
                -- else calling context promises to read upon return.
                end
                activityFlag = true
                return true
            else
                logE( m )
            end
            
        else
            logErr( andThenSome )
        end
    end
    
    -- note: errors thrown in pcall map to false, error-message returned to caller.
    local s, m = app:pcall{ name="Xmp - Transfer Develop Adjustments", function( icall )

        if exifToolSession then -- good
            exifToolObject = exifToolSession
        else -- if must..
            exifToolObject = exifTool -- assured above.
            dbgf( "Exiftool session recommended for best performance." )
        end
        
        if tab:isArray( xmpLater ) then -- follow-up phase callback.
            -- no need for from-photo etc..
            logV( "Doing deferred xmp updating." )
            for i, xmpRec in ipairs( xmpLater ) do
                xmpNow( xmpRec.photo, xmpRec.xmpSettings, xmpRec.targetFile ) -- ignore status, problems are logged within..
            end
            xmpLater = nil
            return
        else
            if #toPhotoInfo == 0 then error( "No recipient photos" ) end -- return false, error-message to calling context.
            logV( "Transferring xmp-based develop settings from '^1' to ^2", fromPhotoName, str:pluralize( #toPhotoInfo, "recipient photo" ) )
        end
        
        local fromIsCropped   -- boolean. from crop settings are in dev-settings and will be replicated in xmp-settings.
        local fromOrientation -- serves as boolean too for "do still sync orientation..".
        
        if devAdjSet.Crop then
            fromIsCropped = lrMeta:getRaw( fromPhoto, 'isCropped', metadataCache )
            fromDevSettings = fromDevSettings or fromPhoto:getDevelopSettings()
        end
        
        if devAdjSet.Orientation then
            local fromPhotoPath = lrMeta:getRaw( fromPhoto, 'path', metadataCache ) -- reminder: no cache in bg mode.
            local fromTargetFile
            local s
            if not fromMetadataPreSaved then
                s, fromTargetFile = cat:saveXmpMetadata( fromPhoto ) -- return status and path to file containing xmp, which has been validated (changed in response to save-xmp command).
                if s then
                    assert( str:is( fromTargetFile ), "no from-target-file" ) -- This used to test that value returned by save-xmp-metadata matched value computed here in calling context - they do match, so it's no longer being computed here too.
                else
                    if devAdjSet.Crop then -- try for crop 1/2 better than 0/2, hopefully.
                        logW( "Can't sync orientation - ^1", fromTargetFile ) -- ftf is errm.
                    else
                        error( "Can't sync orientation - ^1", fromTargetFile ) -- ditto.
                    end
                end
            else -- only set the pre-saved flag if metadata save confirmed externally prior to calling.
                fromTargetFile = self:getTargetFile( fromPhotoPath ) -- source of from xmp info.
                s = true
            end                    
            if s then
                -- could add '-S' arg here, but doesn't matter much, and I like seeing the difference in log file when from-photo is being read versus to-photo(s), which use '-S'.
                exifToolObject:addArg( "-Orientation" )
                exifToolObject:setTarget( fromTargetFile )
                --fromOrientation = "Horizontal (normal)" -- values are textual, but reading from one and writing to another is working so far.
                local rsp, err, cmd = exifToolObject:execRead()
                if rsp then
                    fromOrientation = exifTool:getValueFromPairS( rsp )
                    if str:is( fromOrientation ) then
                        logV( "From-photo orientation: ^1", fromOrientation )
                    else
                        fromOrientation = nil -- in case from-O is empty string - this assures we don't try and write orientation to photos.
                        if devAdjSet.Crop then -- try for crop 1/2 better than 0/2, hopefully.
                            logW( "Can't sync orientation - metadata not present in source photo." )
                        else
                            error( "Can't sync orientation - metadata not present in source photo.." )
                        end
                    end
                else
                    if devAdjSet.Crop then
                        logW( "Can't sync orientation - ^1", err )
                    else
                        error( "Can't sync orientation - unable to obtain source orientation using exiftool: ^1", err )
                    end
                end
            -- else assure from-orientation stays nil/false.
            end
        end
        
        if not devAdjSet.Crop and not fromOrientation then -- neither
            return
        end
        
        -- syncing crop and/or orientation.
        
        for i, toInfo in ipairs( toPhotoInfo ) do
            repeat
                local toPhoto = toInfo.photo or error( "no to-photo" )
                local toPhotoName = toInfo.photoName or cat:getPhotoNameDisp( toPhoto, true, metadataCache )
                logV( "Recipient #^1: ^2", i, toPhotoName )
                if lrMeta:getRaw( toPhoto, 'isVirtualCopy', metadataCache ) then
                    logW( "Virtual copies can not be recipient of xmp-based metadata." )
                    break -- try next photo
                end
                local toPhotoPath = toInfo.photoPath or lrMeta:getRaw( toPhoto, 'path', metadataCache )
                local toDevSettings = toInfo.devSettings or toPhoto:getDevelopSettings() -- relatively expensive, so minimize calls.
                
                -- reminder: dev-settings have crop settings, but not has-crop value, so they don't necessarily mean it's currently cropped (or maybe they do - dunno..).
                -- more robust to check is-cropped metadata - that should be a reliable indicator.
                
                local doCrop        -- or uncrop..
                local doOrient      -- or unorient..
                    -- whether to do-orient depends on value in xmp, but from-orientation is only non-nil if need to check and then maybe do orientation xfr.
                local toIsCropped   -- reminder: from-is-cropped initialized above
                
                if devAdjSet.Crop then -- sync crop, nothing can prohibit it, if specified.
                    toIsCropped = lrMeta:getRaw( toPhoto, 'isCropped', metadataCache ) -- trust this
                    if fromIsCropped then
                        if toIsCropped then
                            if toDevSettings.CropLeft == fromDevSettings.CropLeft and toDevSettings.CropLeft == fromDevSettings.CropLeft and toDevSettings.CropTop == fromDevSettings.CropTop and toDevSettings.CropBottom == fromDevSettings.CropBottom then
                                logV( "to-photo crop settings are same as from-photo, so no crop transfer" )
                                doCrop = false
                            else
                                doCrop = true
                            end
                        else -- to is not cropped, but from is cropped
                            doCrop = true
                        end
                    else -- from-photo is not cropped
                        if toIsCropped then -- to-photo is
                            doCrop = true
                        else -- neither is to-photo
                            doCrop = false -- they agree.
                        end
                    end
                else -- dont sync crop
                    doCrop = false
                end
                
                if not doCrop and not fromOrientation then
                    --Debug.pause( "No need to check crop nor orientation - to-photo is in harmony with from-photo, in terms of specified criteria." )
                    break -- next to-photo
                end
                
                -- doing the crop (or uncrop) and/or considering orientation (determination to be based on reading to-photos xmp).
                
                local targetFile
                
                if not toMetadataPreSaved then
                    local saved  
                    saved, targetFile = cat:saveXmpMetadata( toPhoto ) -- save metadata and assure it's saved - uses the new Lr5 method (fingers crossed).
                    if saved then
                        assert( str:is( targetFile ), "no target file" ) -- used to check target-file computed in save-metadata method, but it's proved itself so..
                        logV( "xmp of to-photo successfully saved" )
                    else
                        logE( targetFile )
                        break
                    end
                else
                    targetFile = self:getTargetFile( toPhotoPath ) -- same value for target-file as computed by save-xmp-metadata.
                    logV( "Calling context promises to-metadata pre-saved" ) -- as long as finding is consistent, this will not be challenged.
                end

                -- xmp should represent currently active settings (but NOT those applied in same with-do clause).                
                -- *** reminder: one does not need to read all crop settings from xmp, just has-crop.
                
                -- step 0: assure photo has adjustments in xmp.
                exifToolObject:addArg( "-S" )
                if doCrop then -- it is already known that crop settings are not in sync, whether xmp has been saved or not.
                    -- It seems I can't tell the difference between no-crop and no-settings without checking all. In case of jpg anyway (not raw)
                    -- it seems Lr is pulling all default settings (folling a reset anyway) and just saving those that have been modified.
                    -- I don't think the raw behaves the same way, although I'm beginning to question..
                    exifToolObject:addArg( "-HasCrop" ) -- note: @Lr5.7, crop stuff is removed if no crop, i.e. has-crop is never false, but be prepared for every possibility.
                end
                -- note: there is no way to know whether orientation requires sync without exiftooling to photo(s).
                if fromOrientation then
                    -- orientation is NOT (always anyway) a crs:tag.
                    exifToolObject:addArg( "-Orientation" )
                end
                exifToolObject:setTarget( targetFile )
                
                local rsp, err, cmd = exifToolObject:execRead() -- note: rsp is unparsed string, or nil if no response (e.g. bad exit code).
                
                local doLater
                
                if rsp then -- executed without failure, doesn't mean exiftool returned any metadata.
                    logV( "Exiftool executed a read: ^1 bytes", #rsp )
                
                    local resp = exifTool:parseShorty( rsp ) -- resp is name/text-value table.
                
                    if doCrop then -- we already know catalog values differ somehow (either one cropped one not, or both cropped but not same).
                        assert( toIsCropped ~= nil, "?" )
                        if str:is( resp.HasCrop ) then
                            logV( "'HasCrop' is in xmp: ^1, so no need to defer cropping til later.", resp.HasCrop )
                        else
                            if toMetadataPreSaved then -- xmp has not been saved in here.
                                logV( "'HasCrop' is not in xmp, but xmp has not been saved in here, so crop will be deferred, just in case." ) -- not a user friendly message but I might remember what this means..
                                doLater = true
                            else
                                logV( "'HasCrop' is not in xmp, which was recently saved in here, so presumably to-photo is not cropped - cropping will be done pronto." )
                            end
                        end
                    -- else there is no need to crop/uncrop - 'nuff said..
                    end -- end of check-crop clause.
                    
                    if fromOrientation then
                        if resp.Orientation ~= nil then -- parsed
                            logV( "to-photo orientation: ^1", resp.Orientation )
                            local toOrientation = resp.Orientation
                            if toOrientation == fromOrientation then
                                --Debug.pause( fromOrientation )
                                doOrient = false
                            else
                                --Debug.pause( fromOrientation, toOrientation )
                                doOrient = true
                            end
                        else
                            Debug.pause( "no to-photo orientation metadata" ) -- I think this field is tiff:orientation initially, but could be another field if.. - so far, exiftool is always doing the right thing regardless.
                            doLater = true
                        end
                    end
                    
                else -- no rsp
                    logE( err or "?" )
                    break -- next to-photo
                end

                if not doCrop and not doOrient then
                    logV( "Not doing crop nor orientation." ) -- to recipient photo, implied.
                    break
                end
                
                -- fall-through => do-crop and/or do-orient (note: do-crop may mean remove crop if from-photo not cropped).
                
                local xmpSettings = {} -- which members are populated will vary depending on to-photo, member values depend only on from-photo.

                if doCrop then -- whether now or later
                    if fromIsCropped then
                        xmpSettings.CropLeft = fromDevSettings.CropLeft
                        xmpSettings.CropRight = fromDevSettings.CropRight
                        xmpSettings.CropTop = fromDevSettings.CropTop
                        xmpSettings.CropBottom = fromDevSettings.CropBottom
                        xmpSettings.CropAngle = fromDevSettings.CropAngle
                        xmpSettings.HasCrop = true -- required.
                    else
                        xmpSettings.HasCrop = false -- so far this suffices to kill the crop.
                    end
                end
                if doOrient then -- whether now or later, not do-orient will not be set if from-orientation is not initialized.
                    xmpSettings.Orientation = fromOrientation
                end
                
                if doLater then
                    --Debug.pause( "doing later - already wrapped?", catalog.hasWriteAccess )
                    assert( tab:hasItems( xmpSettings ), "no xmp settings??" )
                    local preset
                    if not noAdjPresetCache[_PLUGIN] then
                        preset = LrApplication.addDevelopPresetForPlugin( _PLUGIN, "No adjustment", { NoOp=true } ) -- no-op preset will be recreated once each plugin run.
                        noAdjPresetCache[_PLUGIN] = preset
                    else
                        preset = noAdjPresetCache[_PLUGIN] -- actually could be just a single value for current plugin, since this module has a separate local variable dataspace in each plugin.
                    end
                    if preset then
                        if catalog.hasWriteAccess then -- never true in background process, but may be true in foreground.
                            toPhoto:applyDevelopPreset( preset, _PLUGIN ) -- will be "applied" upon exit from with-do gate.
                            xmpLater = xmpLater or {}
                            xmpLater[#xmpLater + 1] = { photo=toPhoto, xmpSettings=xmpSettings, targetFile=targetFile } -- defer xmp adjustment until after "no-op" develop setting change is committed.
                        else
                            local s, m = cat:update( bgProcess and -5 or 30, "No-op adjustment", function( context, phase )
                                if phase == 1 then
                                    toPhoto:applyDevelopPreset( preset, _PLUGIN ) -- will be "applied" upon exit from with-do gate.
                                    return false -- not finished upating catalog.
                                else
                                    assert( tab:hasItems( xmpSettings ), "no xmp settings???" )
                                    local xmpd = xmpNow( toPhoto, xmpSettings, targetFile ) -- auto-resaves metadata.
                                    if xmpd then
                                        logV( "xmp'd after no-op preset applied" )
                                    end
                                end    
                            end )
                            if s then
                                log( "adjustments applied" )
                            else
                                logE( m )
                            end
                        end
                    else
                        logE( "Unable to create preset for no-op adjustment." )
                    end
                else -- do one or the other or both (as dictated by xmp-settings), now.
                    -- settings already exist, may as well do it now - 'twill be more efficient if *all* are doable now, but hard to know ahead of time..
                    --Debug.pause( "doing xmp now with these settings", xmpSettings.CropRight )
                    local xmpd = xmpNow( toPhoto, xmpSettings, targetFile ) -- no catalog write access required.
                    if xmpd then
                        logV( "xmpd in first pass" )
                    -- else error already logged
                    end
                end

            until true -- end of photo processing
            -- do next photo
        end -- end of for all to-photo info records.
        
    end }
    
    if s then
        return true, xmpLater, activityFlag -- activity flag essentially means: one or more photos modified via xmp this call.
    else
        return false, m, activityFlag
    end

end -- end of transfer metadata method.
Xmp.xfrDevAdj = Xmp.transferDevelopAdjustments -- function Xmp:xfrDevAdj(...) -- short form.
--

return Xmp
