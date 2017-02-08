--[[
        Catalog.lua
--]]

local Catalog, dbg, dbgf = Object:newClass{ className = 'Catalog' }


local extSupport = {
    -- raw files, from wikipedia, upper case:
    ["3FR"] = 'raw',
    ["ARI"] = 'raw',
    ["ARW"] = 'raw',
    ["A7R"] = 'raw', -- new @Lr5.3
    ["BAY"] = 'raw',
    ["CRW"] = 'raw',
    ["CR2"] = 'raw',
    ["CAP"] = 'raw',
    ["DCS"] = 'raw',
    ["DCR"] = 'raw',
    ["DNG"] = 'raw',
    ["DRF"] = 'raw',
    ["EIP"] = 'raw',
    ["ERF"] = 'raw',
    ["FFF"] = 'raw',
    ["IIQ"] = 'raw',
    ["K25"] = 'raw',
    ["KDC"] = 'raw',
    ["MEF"] = 'raw',
    ["MOS"] = 'raw',
    ["MRW"] = 'raw',
    ["NEF"] = 'raw',
    ["NRW"] = 'raw',
    ["OBM"] = 'raw',
    ["ORF"] = 'raw',
    ["PEF"] = 'raw',
    ["PTX"] = 'raw',
    ["PXN"] = 'raw',
    ["R3D"] = 'raw',
    ["RAF"] = 'raw',
    ["RAW"] = 'raw',
    ["RWL"] = 'raw',
    ["RW2"] = 'raw',
    ["RWZ"] = 'raw',
    ["SR2"] = 'raw',
    ["SRF"] = 'raw',
    ["SRW"] = 'raw',
    ["X3F"] = 'raw',
    
    -- non-raw still-image files:
    ["TIF"] = 'rgb',
    ["TIFF"] = 'rgb',
    ["JPG"] = 'rgb',
    ["JPEG"] = 'rgb',
    ["PSD"] = 'rgb',
    -- ["GIF"] = 'rgb', -- auto-detected and handled via IM/convert in Ottomanic Importer, but not supported natively.
    
    -- video, from http://helpx.adobe.com/lightroom/kb/video-support-lightroom-4-3.html
    ["MOV"] = 'video',
    ["M4V"] = 'video',
    ["MP4"] = 'video',
    ["MPE"] = 'video',
    ["MPEG"] = 'video',
    ["MPG4"] = 'video',
    ["MPG"] = 'video',
    ["AVI"] = 'video',
    ["MTS"] = 'video',
    ["3GP"] = 'video',
    ["3GPP"] = 'video',
    ["M2T"] = 'video',
    ["M2TS"] = 'video',
}
if LrApplication.versionTable().major >= 5 then
    extSupport["PNG"] = 'rgb'
end
-- Note: video supported is that for Lr4+. Plugins supporting video in Lr3 are on their own...



--- Constructor for extending class.
--
function Catalog:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Catalog:new( t )
    local this = Object.new( self, t )
    return this
end



--- Get support type for all or specified extension.
--
--  @param ext extension (not case sensitive).
--
--  @usage make a copy of the returned table if plugin is to change support type strings to tables, or add-on...
--
--  @return supportType (string: 'raw', 'rgb', 'video') or nil, if specified extension is not supported by Lightroom.
--      <br>    DNG is considered raw, even though it could be dng-wrapped jpeg, likewise NEF is considered raw even though it could be rgb internally..
--
function Catalog:getExtSupport( ext )
    if ext then
        return extSupport[LrStringUtils.upper(ext)]
    else
        return extSupport
    end
end



--- Get extensions for specified type.
--
--  @param typ : 'raw', 'rbg', or 'video'.
--
--  @return array of extensions.
--
function Catalog:getSupportedExtensions( typ )
    local memberName = typ.."_ext_arr"
    if self[memberName] == nil then
        self[memberName] = {}
        local rslt = self[memberName]
        for ext, t in pairs( extSupport ) do
            if t == typ then
                rslt[#rslt + 1] = ext
            end
        end
        return rslt
    else
        return self[memberName]
    end
end



--- Get raw photo given base path (absolute path without extension).
--
--  @usage if you want to pre-initialize raw-ext-pri, you can..
--
function Catalog:getRawPhoto( basePath )
    self.rawExtArr = self.rawExtArr or self:getSupportedExtensions( 'raw' )
    self.rawExtPri = self.rawExtPri or { NEF=true, CR2=true, DNG=true } -- a little personal bias - sorry..
    for ext, t in pairs( self.rawExtPri ) do
        local p = catalog:findPhotoByPath( LrPathUtils.addExtension( basePath, ext ) )
        if p then
            return p
        end
    end        
    for i, ext in ipairs( self.rawExtArr ) do
        local p = catalog:findPhotoByPath( LrPathUtils.addExtension( basePath, ext ) )
        if p then
            self.rawExtPri[ext] = true -- for next time.
            return p
        end
    end        
end



--- Get raw file given folder and base filename.
--
--  @usage if you want to pre-initialize raw-ext-pri, you can..
--
function Catalog:getRawFile( folderPath, baseFilename )
    self.rawExtArr = self.rawExtArr or self:getSupportedExtensions( 'raw' )
    self.rawExtPri = self.rawExtPri or { NEF=true, CR2=true, DNG=true } -- a little personal bias - sorry..
    for ext, t in pairs( self.rawExtPri ) do
        local path = LrPathUtils.child( folderPath, LrPathUtils.addExtension( baseFilename, ext ) )
        local f, d = fso:existsAs( path, 'file' )
        if f then
            return path
        -- else ignore
        end
    end        
    for i, ext in ipairs( self.rawExtArr ) do
        local path = LrPathUtils.child( folderPath, LrPathUtils.addExtension( baseFilename, ext ) )
        local f, d = fso:existsAs( path, 'file' )
        if f then
            self.rawExtPri[ext] = true -- for next time.
            return path
        -- else ignore
        end
    end        
end
    
    
    
--- Get lr folder for photo, if possible.
--
--  @param photo (lr-photo, required) photo whose folder is desired.
--  @param photoPath (string, optional) if known in calling context, saves a more expensive call to get-raw-metadata in here.
--
--  @return lr-folder, or nil if no can do.
--
function Catalog:getFolder( photo, photoPath )
    if not photoPath then
        photoPath = photo:getRawMetadata( 'path' )
    end
    return self:getFolderByPath( LrPathUtils.parent( photoPath ) ) -- ###2 bypass cache?
end



--- Initialize folder cache to assure fresh results via (and set mode of) get-folder-by-path.
--
--  @param unInit (boolean, default = false) if false, get-folder-by-path will use cached mode (faster, but results will be stale unless care is taken to init before each "run"..).
--      <br>    if true, get-folder-by-path will use non-cached mode (slower, but results are always fresh).
--
function Catalog:initFolderCache( unInit )
    if unInit then
        self.folderCache = nil
    else
        self.folderCache = {}
    end
end



--- Equivalent to Lr's native method, except works for unmapped network drives too (Lr's doesn't, as of Lr5.4 anyway).
--
--  @usage it is recommended but not required to initialize folder cache before calling the first time.
--  @usage format of unmapped network drive is: \\drv\fldr\file...
--
--  @param folderPath (string, required) path of folder for which corresponding lr-folder object is desired.
--  @param bypassCache (boolean, default=false) set true to force non-cached mode despite initialized cache: useful in case background process too, which can't maintain fresh cache.
--
--  @return folder (lr-folder object) hopefully never nil (assuming valid folder-path), but best to check in calling context.
--
function Catalog:getFolderByPath( folderPath, bypassCache )
    local success, folder = LrTasks.pcall( catalog.getFolderByPath, catalog, folderPath ) -- pcall wrapper added 30/Dec/2014 2:21 due to finding of john ellis: sometimes there is error when top-level folder is funked.
    -- ### set folder=nil to test "finding" below.
    if success and folder then -- mapped drive..
        return folder
    -- else it's a "poison" folder (ref: https://forums.adobe.com/thread/1661278) or unmapped-network/lr-mobile folder (stumbled upon based on user problem report) or something.
    end
    local find
    if not self.folderCache or bypassCache then
        --Debug.pause( "Consider initializing folder cache before first call." )
        find = function( lrFolder )
            local path = lrFolder:getPath()
            if path == folderPath then -- ###2: case sensitive.
                folder = lrFolder
                return true
            elseif path ~= folderPath:sub( 1, #path ) then -- i.e. if not str:isBeginningWith( folderPath, path ) then
                return false
            end
            -- assume find will be fast enough that yielding is not required.
            for j, v in ipairs( lrFolder:getChildren() ) do
                if find( v ) then return true end
            end
            return false
        end
    else -- there is a folder cache and we're not bypassing it.
        folder = self.folderCache[folderPath]
        if folder then
            return folder
        end
        local y = 0
        find = function( lrFolder )
            local path = lrFolder:getPath()
            self.folderCache[path] = lrFolder
            if path == folderPath then -- ###2: ditto.
                folder = lrFolder
                return true
            end
            y = app:yield( y ) -- yield every 20 times, so Lr stays responsive.
            local children = lrFolder:getChildren() -- this should never be nil, but sometimes is, e.g. Lr mobile folder
            if children then
                for j, v in ipairs( children ) do
                    if find( v ) then return true end
                end
            else
                app:logV( "*** Folder '^1' is returning bad info (nil children array), due to a bug in Lightroom. If Lr mobile folder, this bug has already been reported, otherwise please let me know which folders are giving you this problem..", lrFolder:getPath() or "no path obtained" )
            end
            return false
        end
    end
    local allFolders = catalog:getFolders()
    for i, f in ipairs( allFolders ) do
        if find( f ) then break end
    end
    --Debug.pauseIf( folder==nil, "no folder for path: "..folderPath )
    dbgf( "no folder for path: ^1", folderPath )
    return folder
end



--- Get set of folders housing specified photos.
--
--  @usage logs warning(s) if folder(s) not found.
--
--  @param photos (array of lr-photo) required.
--  @param cache just needs 'path' to be useful.
--
--  @return set of lr-folders - maybe empty, but never nil.
--
function Catalog:getFolderSet( photos, cache )
    local folderSet = {}
    for i, photo in ipairs( photos ) do
        local ppath = lrMeta:getRaw( photo, 'path', cache )
        local fpath = LrPathUtils.parent( ppath )
        local folder = cat:getFolderByPath( fpath ) -- method changed 27/May/2014 23:03 ###2
        if folder then
            folderSet[folder] = true
        else
            app:logW( "Unable to get folder for photo: ^1", ppath )
        end
    end
    return folderSet
end



--- Get source name and id/path if special-coll/folder.
--
--  @usage some sources don't have get-name function. this method assures a reasonable name, regardless of source type.
--
--  @param source any source
--
--  @return sourceName (string) never empty, never nil. source name will be invented if no get-name function, or source ID if special source is not "registered" here.
--  @return sourceId (string) if special source - as registered here, or source object type, or to-string of source..
--
function Catalog:getSourceName( source )
    app:callingAssert( source~=nil, "source is nil" )
    if source.getName ~= nil then
        return source:getName(), source.localIdentifier or source:getPath() -- not special: collection or folder.
    end
    if self.specialSourceNames == nil then
        self.specialSourceNames = {
            entire_library = "Special Collection: All Photographs",
            quick_collection = "Special Collection: Quick Collection",
            previous_import = "Special Collection: Previous Import",
            last_catalog_export = "Special Collection: Previous Export as Catalog",
            temporary_images = "Special Collection: Added by Previous Export",
            -- ###2 - there could be others I've yet to have - e.g. error collection...
        }
    end
    local sourceId = str:to( source )
    local sourceName = self.specialSourceNames[sourceId]
    if str:is( sourceName ) then
        return sourceName, sourceId -- is special.
    elseif source == catalog then
        return "Catalog", "LrCatalog"
    else
        Debug.pause( "need special source name added to lookup for:", sourceId )
        app:logV( "*** Need special source name added to lookup: ^1", sourceId )
        return sourceId, sourceId -- very "special".
    end
end



--- get source type, regardless of source.
--
--  @param source any photo/video source, including catalog or special collection.
--
--  @return sourceType (string) same as source--get-type if said method exists, else "lr-catalog" or "special" (never empty, never nil).
--
function Catalog:getSourceType( source )
    if source.type ~= nil then
        return source:type() -- not special
    elseif source == catalog then
        return 'LrCatalog'
    else
        return 'special'
    end
end



--  @20/Dec/2013 13:55, only plugin of mine using this is NxToo
--
--- Refresh display of recently changed photo (externally changed).
--
--  @usage If I remember correctly, this method does not work that well, so don't depend on it.
--      <br>Theoretically, request-jpeg-thumbnail could be used to refresh display, except (as of Lr5.4) it doesn't work well enough either (ugh).
--
function Catalog:refreshDisplay( photo, photoPath )
    if not photoPath then
        photoPath = photo:getRawMetadata( 'path' )
    end
    local p = catalog:getTargetPhoto()
    if p then
        if p:getRawMetadata( 'path' ) == photoPath then -- preview just updated is selected.
            local ps = catalog:getTargetPhotos()
            if #ps > 1 then 
                for k, v in ipairs( ps ) do
                    if v ~= p then
                        catalog:setSelectedPhotos( v, ps ) -- do not call framework version: task yield not necessary, and results in a hitch.
                        catalog:setSelectedPhotos( p, ps )
                        return true
                    end
                end
            else
                local folder = cat:getFolder( photo, photoPath )
                if folder then
                    local ps = folder:getPhotos() or {} -- or {} added 16/Sep/2013 22:32 (in honor of Lr bug).
                    if #ps > 0 then
                        for k, v in ipairs( ps ) do
                            if v ~= p then
                                catalog:setSelectedPhotos( v, ps ) -- do not call framework version: task yield not necessary, and results in a hitch.
                                catalog:setSelectedPhotos( p, { p } )
                                return true
                            end
                        end
                    end
                end                    
            end
        else
            local ps = cat:getSelectedPhotos()
            catalog:setSelectedPhotos( photo, ps )
            return true
        end
    else
        catalog:setSelectedPhotos( photo, { photo } )
        return true -- note: not definitive unless source is being currently viewed.
    end
    return false
end



--- Catalog access wrapper that distinquishes catalog contention errors from target function errors.
--
--  @param              tryCount        Number of tries before giving up, at a half second per try (average).
--  @param              func            Catalog with-do function.
--  @param              catalog         The lr-catalog object.
--  @param              p1              First parameter which may be a function, an action name, or a param table.
--  @param              p2              Second parameter which will be a function or nil.
--  @param              ...             Additional function parameters
--      
--  @usage              *** deprecated - use cat update methods instead.
--  @usage              Returns immediately upon target function error. 
--  @usage              The purpose of this function is so multiple concurrent tasks can access the catalog in succession without error.
--                          
--  @return             status (boolean):    true iff target function executed without error.
--  @return             other:    function return value, or error message.
--
function Catalog:withDo( tryCount, func, catalog, p1, p2, ... )
    while( true ) do
        for i = 1, tryCount do
            local sts, qual = LrTasks.pcall( func, catalog, p1, p2, ... )
            if sts then
                return true, qual
            elseif str:is( qual ) then
                local found = qual:find( "LrCatalog:with", 1, true ) or 0 -- return position or zero, instead of position or nil.
                if found == 1 then -- problem reported by with-catalog-do method.
                    local found2 = qual:find( "already inside", 15, true ) -- Lr2&3
                    if found2 == nil then
                        found2 = qual:find( "was blocked", 15, true ) -- Lr4b
                    end
                    if found2 then
                        -- problem is due to catalog access contention.
                        Debug.logn( 'catalog contention:', str:to( qual ) )
                        LrTasks.sleep( math.random( .1, 1 ) ) -- sleep for a half-second or so, then try again.
                    else
                        return false, qual
                    end
                else
                    return false, qual
                end
            else
                return false, 'Unknown error occurred accessing catalog.'
            end
        end
    	local action = app:show{ warning="Unable to access catalog.", buttons={ dia:btn( "Keep Trying", 'ok' ), dia:btn( "Give Up", 'cancel' ) } }
    	if action == 'ok' then
    		-- keep trying
    	elseif action=='cancel' then
    		-- assert( action == 'cancel', "unexpected error action: " .. str:to( action )  )
    		return false, "Gave up trying to access catalog."
    	else
    	    app:logError( "Invalid button" )
    	    return false, "Gave up trying to access catalog (invalid button)."
    	end
    end
    return false, str:format( "Unable to access catalog." )
end



--- Catalog access wrapper that distinquishes catalog contention errors from target function errors.
--
--  @param              tryCount        Number of tries before giving up, at a half second per try (average).
--                      <br>            *** Can be negative to indicate: after retries are exhausted, don't prompt before returning.
--  @param              func            Catalog with-do function.
--  @param              p1              First parameter which may be a function, an action name, or a param table.
--  @param              p2              Second parameter which will be a function or nil.
--  @param              ...             Additional function parameters
--      
--  @usage              *** deprecated - recommend update and/or update-private method instead.
--  @usage              Same as with-do method, except relies on global lr catalog.
--  @usage              Returns immediately upon target function error. 
--  @usage              The purpose of this function is so multiple concurrent tasks can access the catalog in succession without error.
--                          
--  @return             status (boolean):    true iff target function executed without error.
--  @return             other:    function return value, or error message.
--
function Catalog:withRetries( tryCount, func, p1, p2, ... )
    assert( _G.catalog ~= nil, "no catalog" )
    if type( tryCount ) == 'table' then
        func = tryCount.func
        p1 = tryCount.p1
        p2 = tryCount.p2
        tryCount = tryCount.tryCount
    end
    local retAfterTry
    if tryCount < 0 then
        retAfterTry = true
        tryCount = -tryCount
    end
    assert( tryCount >= 1, "bad try count / tmo" )
    while( true ) do
        for i = 1, tryCount do
            local sts, qual = LrTasks.pcall( func, catalog, p1, p2, ... ) -- what other parameters could there be? ###2 8/Apr/2013 21:15, context?
            if sts then
                return true, qual
            elseif str:is( qual ) then
                local found = qual:find( "LrCatalog:with", 1, true ) or 0 -- return position or zero, instead of position or nil.
                if found == 1 then -- problem reported by with-catalog-do method.
                    local found2 = qual:find( "already inside", 15, true )
                    if found2 == nil then
                        found2 = qual:find( "was blocked", 15, true ) -- Lr4b
                    end
                    if found2 then
                        -- problem is due to catalog access contention.
                        Debug.logn( 'catalog contention:', str:to( qual ) )
                        LrTasks.sleep( math.random( .1, 1 ) ) -- sleep for a half-second or so, then try again.
                    else
                        return false, qual
                    end
                else
                    return false, qual
                end
            else
                return false, 'Unknown error occurred accessing catalog.'
            end
        end
        if tryCount == 1 then
            return false, "Only tried once, but could not access catalog."
        elseif retAfterTry then
            return false, str:fmtx( "Tried ^1 times, but could not access catalog.", tryCount )
        end
    	local action = app:show{ warning="Unable to access catalog.", buttons={ dia:btn( "Keep Trying", 'ok' ), dia:btn( "Give Up", 'cancel' ) } }
    	if action == 'ok' then
    		-- keep trying
    	elseif action=='cancel' then
    		-- assert( action == 'cancel', "unexpected error action: " .. str:to( action )  )
    		return false, "Gave up trying to access catalog."
    	else
    	    app:logError( "Invalid button" )
    	    return false, "Gave up trying to access catalog (invalid button)."
    	end
    end
    return false, str:format( "Unable to access catalog." )
end



--[=[ private method:
function Catalog:_isAccessContention( qual )
    local found = qual:find( "LrCatalog:with", 1, true ) or 0 -- return position or zero, instead of position or nil.
    if found == 1 then -- problem reported by with-catalog-do method.
        local found2 = qual:find( "already inside", 15, true )
        if found2 == nil then
            found2 = qual:find( "was blocked", 15, true ) -- Lr4b
        end
        if found2 then
            -- problem is due to catalog access contention.
            Debug.logn( 'catalog contention:', str:to( qual ) )
            return true
        else
            return false
        end
    else
        return false
    end
end
--]=]



-- private method: @25/Aug/2012 17:04, modified to work properly in Lr3 too (previously not working OK in Lr3).
-- note: tmo params were not working correctly in Lr4 (where first introduced), but seem to be ok in Lr5.3 or better
-- I run in debug mode with tmo params, but I've been too chicken to release that way for public consumption.
function Catalog:_update( catFunc, tmo, name, func, ... )
    local t = { ... } -- parameters to pass to func.
    tmo = tmo or 0
    --local tmoTbl = { timeout = tmo } -- until 1/Jun/2014 23:42, but note: in one case, tmo is negative 5 (relative antics), to mean "don't prompt if no go" (for background tasks).
    local tmoTbl = { timeout = math.abs( tmo ) } -- this after 1/Jun/2014 23:42 - timeout should be positive or zero. probably the negative 5 was giving me zero(?)
    local sts, msg
    local phase = 1
    local function _func( context )
        app:logV( "Updating catalog, phase ^1", phase )
        sts, msg = func( context, phase, unpack( t ) ) -- hint: return sts=false with no message to continue next phase.
        if sts == nil then -- protection from inadvertent infinite recursion, and for backward compatibility with previous with-do wrappers.
            sts = true
        end
    end
    local maxPhases = 10000000 -- ten million max, for sanity (used in "emulation" loop as well as the real deal..).
    repeat -- do all phases.
        local s, other
        local lrVerMajor, lrVerMinor = app:lrVersion()
        if lrVerMajor > 5 or ( lrVerMajor == 5 and lrVerMinor >= 3 ) then -- prior to 30/May/2014 this was only done when adv-dbg-ena, now cutting over for all.. ###3: remove warning if no problems come 2015.
            -- Debug.logn( "Catalog with-do access using timeout-param table constraint." )
            if name then
                s, other = LrTasks.pcall( catFunc, catalog, name, _func, tmoTbl ) -- yield within if need be.
            else
                s, other = LrTasks.pcall( catFunc, catalog, _func, tmoTbl ) -- ditto.
            end
            LrTasks.yield() -- Lr5.6 needed this, at least initially, for example, Folder Collections plugin was bringing down the house.. once init is successful, this yield is no longer necessary, but no doubt best to leave it in..
        else -- Lr <= 5.2
            -- ###3 Lr4 timeout handling is buggy - catastrophically in my case, since phasing progression depends on reliable/consistent error handling,
            -- otherwise it gets stuck in a loop continuing to re-call cat access method, when it should be aborting, since internal error is not being trapped...
            local maxTries
            if tmo >= 0 and tmo <= 1 then
                maxTries = 1
            elseif tmo > 0 then
                maxTries = math.ceil( tmo * 2 ) -- convert tmo to integer try-count.
            elseif tmo == -1 then
                maxTries = tmo
            else
                maxTries = math.floor( tmo * 2 ) -- reminder: can be negative
                assert( maxTries < 0, "hmm" ) -- acknowledgement of option for negative max-tries.
            end
            local _s, _m
            if name then
                _s, _m = self:withRetries( maxTries, catalog.withWriteAccessDo, name, _func ) -- handles negative max-tries as advertised.
            else
                _s, _m = self:withRetries( maxTries, catalog.withPrivateWriteAccessDo, _func ) -- ditto.
            end
            --s = true -- bug? - discovered and removed 28/Jan/2013 18:17 - seemed wrong! (it seems I maybe remember doing this because of some problem with a plugin(s) 
            -- maybe background plugins that were passing 1 for tmo - this problem is hopefully fixed now (see above max-tries computation).
            if _s then -- access granted, function completed.
                other = 'executed'
                s = true
            else -- either access error or function error, as dictated by _m.
                assert( str:is( _m ), "no _m" )
                other = _m -- NOT "aborted".
                s = false -- added 28/Jan/2013 18:28 ###4 remove this comment and the above if no problems come 2015.
            end
        end
        assert( s ~= nil, "no s" ) -- cheap insurance for future
        if s then -- no error thrown.
            if str:is( other ) then
                if other == 'executed' then -- access granted, and update function executed sans error.
                    if sts then
                        return true -- all done.
                    elseif str:is( msg ) then -- update function did not throw error, but has reported an issue.
                        return false, "Unable to complete catalog update - " .. msg
                    else
                        -- continue
                        phase = phase + 1
                        -- loop
                    end
                elseif other == 'aborted' then -- only when using tmo-tbl, NOT with-retries - access not granted within alloted time.
                    if tmo <= 1 then -- ok negative or 0 to 1 means return sans prompt: backward compatible and exanded (supports *multiple* retries now, but without no-go prompt).
                        return false, "Catalog unavailable."
                    else
                       	local action = app:show{ warning="Unable to access catalog.", buttons={ dia:btn( "Keep Trying", 'ok' ), dia:btn( "Give Up", 'cancel' ) } }
                    	if action == 'ok' then
                    		-- keep trying
                    		-- tries = maxTries -- reload try count-down.
                    	elseif action=='cancel' then
                    		-- assert( action == 'cancel', "unexpected error action: " .. str:to( action )  )
                    		return false, "Gave up trying to access catalog."
                    	else
                    	    app:logError( "Invalid button" ) -- "never" happens.
                    	    return false, "Gave up trying to access catalog (invalid button)."
                    	end
                    end
                elseif other == 'queued' then -- this should definitely not happen, given current programming.
                    return false, "Unexpected value (queued) returned by Lightroom catalog access method."
                else -- e.g. errm returned by with-retries.
                    --Debug.pause( other, app:getLrVerMajor() )
                    if app:getLrVerMajor() < 4 then
                        return false, other
                    else
                        return false, "Invalid value returned by Lightroom catalog access method: " .. other
                    end
                end
            else
                return false, "No value returned by Lightroom catalog access method."
            end
        else -- by Lr4 definition, it's a function error.
            --Debug.pause( "Catalog access function error: " .. str:to( other ) )
            return nil, "Catalog access function error: " .. str:to( other )
        end
    until phase >= maxPhases
    --Debug.pause( "phased out" )
    return nil, "Program failure"
end



--- Wrapper for named/undoable catalog:withWriteAccessDo method - divide to conquor func.
--
--  @param tmo (number) max seconds to get in. ***note: if > 1, user will be prompted to keep-trying (good for manually initiated ops). if <= 1, returns pronto (good for background processes which gracefully weather errors and retry naturally..).
--      <br>    negative numbers are allowed - interpretation: absolute value is timeout, negative sign means return pronto if no-can-do (no prompting..).
--  @param name (string) undo title.
--  @param func (function) divided catalog writing function( context, phase, ... ): returns sts, msg = true when done; false if to be continued; nil, error message if trouble.
--  @param ... (any) additional parameters passed to func.
--
--  @usage example:<br>
--      <br>local function catUpdate( context, phase )
--      <br>    local i1 = ( phase - 1 ) * 1000 + 1
--      <br>    local i2 = math.min( phase * 1000, #photos )
--      <br>    for i = i1, i2 do
--      <br>        -- do something to photos[i]
--      <br>        -- if trouble, return nil, msg.
--      <br>    end
--      <br>    if i2 == #photos then
--      <br>        return true -- done, no errors.
--      <br>    else
--      <br>        return false -- continue, no errors.
--      <br>    end
--      <br>end
--      <br>local sts, msg = cat:update( 10, "Test", catUpdate )
--      <br>if sts then
--      <br>    -- log successful message.
--      <br>else
--      <br>    -- print error message...
--      <br>end
--
--  @usage phase param can also be used to do things like add keyword (in phase 1), then use keyword (in phase 2).
--
--  @return status (boolean) true iff updated.
--  @return message (string) accompanies un-true status to explain.
--
function Catalog:update( tmo, name, func, ... )
    return self:_update( catalog.withWriteAccessDo, tmo, name, func, ... )
end



--- Wrapper for un-named catalog:withPrivateWriteAccessDo method - divide to conquor func.
--
--  @usage AFAIC (despite Adobe documentation), this method is only good for updating custom plugin metadata (aka photo properties) - all others require full update.
--
--  @usage see catalog--update method for example.
--
--  @param tmo (number) max seconds to get in.
--  @param func (function) divided catalog writing function: returns sts, msg = true when done; false if to be continued; nil, error message if trouble.
--  @param ... (any) passed to func.
--
--  @return status (boolean) true iff updated.
--  @return message (string) accompanies un-true status to explain.
--
function Catalog:updatePrivate( tmo, func, ... )
    return self:_update( catalog.withPrivateWriteAccessDo, tmo, nil, func, ... ) -- no name.
end



--- select one photo, de-select all others - confirm selection.
--
--  @usage      For when photo is likely to be in filmstrip, otherwise use assure-photo-is-selected instead.
--  @usage      Will only select specified photo if not buried in stack, and not filtered out...
--
--  @return     status (boolean, required) true => specified photo is only photo selected - confirmed.
--  @return     message (string or nil) qualification of failure.
--
function Catalog:selectOnePhoto( photo )
    local try = 1
    while try <= 3 do -- retries are based on hope for luck - no real problem being fixed by this...
        catalog:setSelectedPhotos( photo, { photo } )
        if catalog:getTargetPhoto() == photo then
            return true
        else
            LrTasks.sleep( .1 )
            try = try + 1
        end
    end
    local p = photo:getRawMetadata( 'path' )
    local isBuried = cat:isBuriedInStack( photo )
    if isBuried then
        return false, str:fmt( "Unable to select photo (^1) after ^2 tries, probably because its buried in a stack.", p, try - 1 )
    else
        return false, str:fmt( "Unable to select ^1 after ^2 tries", p, try - 1 ) -- not sure why...
    end
end



--- Get photo set from seed photos.
--
--  @usage      To get top photos, and those underneath too...
--  @usage      Not very efficient if there are lots of expanded stacks, and all underneath are already included in seed photos.
--
--  @param      seedPhotos (table, required) An array of photos, often obtained from some catalog source.
--
--  @return     photoSet (table, never nil) keys are photos, values are true.
--
function Catalog:getPhotoSetFromSeedPhotos( seedPhotos, cache )
    local photoSet = {}
    for i, photo in ipairs( seedPhotos ) do
        if not photoSet[photo] then
            if lrMeta:getRaw( photo, 'isInStackInFolder', cache ) then -- and photo:getRawMetadata( 'topOfStackInFolderContainingPhoto' ) then - do not require top of stack, since photo may be in opposite orientation in collection.
                local stackPhotos = lrMeta:getRaw( photo, 'stackInFolderMembers', cache ) -- all in same stack as photo (including photo itself).
                for _, p in ipairs( stackPhotos ) do
                    photoSet[p] = true -- this could happen multiple times, e.g. if expanded stack, it will happen for each selected. ###3: efficiency could be improved.
                end
            else
                photoSet[photo] = true
            end
        -- else it, and all it's other stack members in folder are already accounted for.
        end
    end
    -- return tab:createArrayFromSet( photoSet ) - this can be done externally if need be.
    return photoSet
end



--- Get selected photos.
--
--  @usage Use instead of lr-catalog's get-target-photos method if you don't want the entire filmstrip to be returned when nothing is selected.
--
--  @return empty table if none selected - never returns nil.
--
function Catalog:getSelectedPhotos( photo )
    photo = photo or catalog:getTargetPhoto()
    if not photo then -- nothing selected
        return {} -- target nothing... (get-target-photos targets whole filmstrip if nothing selected).
    else -- one or more photos are selected
        return catalog:getTargetPhotos() -- return them.
    end
end



--  @20/Dec/2013 14:07, none of my plugins are using this.
--
--- Get target photos.
--
--  @param p (table, optional) handling members:<br>
--           * noneSel (string, default=nil) 'allPhotos', 'filmstrip', or nil.<br> 
--           * oneSel (string, default=nil) 'filmstrip', or nil.<br> 
--
--  @usage *** deprecated - may be removed in a future version (or, may not be..).
--
--  @usage If multiple selected, they are returned. What happens when none or one are selected depends on parameter table:<br>
--         if handling member is nil, then selected photos returned without change.
--
--  @return may return empty table, but never returns nil.
--
function Catalog:getTargetPhotos( p )
    local noneSel = p.noneSel -- or "allPhotos"
    local oneSel = p.oneSel -- or "filmstrip"
    local sel = self:getSelectedPhotos()
    if #sel == 0 then
        if noneSel == nil then
            return {}, "selected"
        elseif noneSel == 'allPhotos' then
            return catalog:getAllPhotos(), "whole catalog"
        elseif noneSel == 'filmstrip' then
            return catalog:getTargetPhotos(), "filmstrip"
        else
            app:callingError( "noneSel not supported: ^1", noneSel )
        end
    elseif #sel == 1 then
        if oneSel == nil then
            return sel, "selected"
        elseif oneSel == "filmstrip" then
            return catalog:getMultipleSelectedOrAllPhotos(), "filmstrip"
        else
            app:callingError( "oneSel not supported: ^1", oneSel )
        end
    else
        return sel, "selected"
    end
end



--- Get active sources - same as Lr's version except won't bomb if called during startup (Lr's method throws error if called too soon).
--  @usage can be called at any time, but only has true value when called during startup.
--  @param call (Call, optional but recommended) If call object, then returns when call is quit, otherwise only returns prematurely if global shutdown flag is set.
--  @return activeSources (array) generally not empty, and only nil if premature abortion (quit or shutdown).
function Catalog:getActiveSources( call )
    for try = 1, 30 do
        local sts, activeSources = LrTasks.pcall( catalog.getActiveSources, catalog ) -- assertion failed error when called upon Lr startup, hmm...
        if sts then
            if tab:isArray( activeSources ) then -- check to see there is at least one active source, before returning merrily.
                return activeSources
            else
                app:logV( activeSources and "*** active sources is empty" or "*** active sources is nil" )
                Debug.pause( activeSources and "active sources is empty" or "active sources is nil" ) -- never seen this happen in Windows, but one user reported seeing it on Mac (during startup).
                return activeSources or {} -- make sure to not return nil value to calling context - it *should* handle empty array OK.
            end
        else
            dbgf( "Unable to obtain active sources upon attempt #^1 - ^2", try, activeSources )
            LrTasks.sleep( 1 )
            if call and call:isQuit() or shutdown then return end
        end
    end
    error( "Unable to obtain active sources." ) -- never happens, hopefully.
end



-- Unwrapped internal function for assuring sources (folders) are selected.
-- returns most-selected-photo, new photos array, which is guaranteed to include most-sel-photo. or false, msg.
-- goal is to assure sources (folders really) are selected if need be, in order to assure specified photos can be selected.
function Catalog:_assureSources( photo, photos, metaCache )
    local _photo -- most selected photo - may have to change, if source not selectable.
    local _photos = {}
    local origSources = catalog:getActiveSources()
    local sourceSet = {}
    local sel = {}
    local flg
    for i, __photo in ipairs( photos ) do
        repeat
            local path = lrMeta:getRaw( __photo, 'path', metaCache ) -- accept uncached, if need be.
            local parent = LrPathUtils.parent( path )
            local lrFolder = cat:getFolderByPath( parent ) -- method changed "recently" (say maybe a year before 11/Dec/2014)
            if lrFolder then
                if sourceSet[lrFolder] then
                    --Debug.logn( "Folder already active:", lrFolder:getName() )
                else
                    sourceSet[lrFolder] = true
                end
            else
                app:logWarning( "Parent folder not in catalog, so photo can not be selected: ^1", path )
                break
            end
            if __photo == photo then
                _photo = __photo
            end
            _photos[#_photos + 1] = __photo
        until true
    end
    if not _photo then
        _photo = photo
        _photos[#_photos + 1] = _photo
    end
    local sources = tab:createArrayFromSet( sourceSet )
    if #sources > 0 then
        if tab:isEquiv( sources, origSources ) then --, function( s1, s2 ) return s1 == s2 end ) then - default test is equality.
            dbgf( "No active source change" )
            return _photo, _photos
        else
            --dbgf( "Setting ^1 active sources, ^2 seconds settling time.", #sources, sourceSelectSettlingTime )
            dbgf( "Setting ^1 active sources.", #sources )
            
            local s, m = cat:setActiveSources( sources )
            --catalog:setActiveSources( sources )
            --LrTasks.sleep( sourceSelectSettlingTime ) -- needs at least a moment to settle. Additional settling time must be accomplished upon return.
            if s then
                return _photo, _photos
            else
                return false, m
            end
        end
    else
        Debug.pause( "no sources" ) -- this should "never" happen.
        return false, "No folder sources found corresponding to photos to be selected."
    end
    app:error( "how here?" )
end



--- Try to select photos - return status of attempt (no error message).
--
--  @usage 150msec max if photos not being selected.
--
--  @param photos (array of LrPhoto, required) photos to be selected.
--  @param target (LrPhoto, optional) photo to be most-selected. If passed, must be in photos array; if not passed first photo in array will be most-selected.
--
--  @return status (boolean) true iff selection confirmed with certainty - no message accompaniment if status is true.
--  @return errorMessage (string) explains false status.
--
function Catalog:tryToSelectPhotos( photos, target )
    if #photos == 0 then
        return false, "Can't select zero photos (plugins can not de-select all photos)."
    end
    local status, errmsg
    local mostSel
    local photoSet = tab:createSet( photos )
    if target then
        app:callingAssert( photoSet[target], "Target is invalid - must be in specified photo set." )
        mostSel = target
    else
        mostSel = photos[1]
    end
    local function checkValidity()
        local targetPhotos = catalog:getTargetPhotos()
        if #targetPhotos ~= #photos then
            status = false
            errmsg = str:fmtx( "Commanded Lr to select ^1, but ^2 selected.", #photos, #targetPhotos )
            return
        end
        -- count matches.
        for i, p in ipairs( targetPhotos ) do
            if not photoSet[p] then
                status = false
                if i == 1 then
                    errmsg = str:fmtx( "Commanded Lr to select ^1, but not even the first one is getting selected.", #photos ) -- could log which are selected, but usually it's: "what user sees".
                else
                    errmsg = str:fmtx( "Commanded Lr to select ^1, first ^2 are selected as expected, but selected photo ^3 is not what was expected.", #photos, i-1, i )
                end
                return
            end
        end
        status = true
        errmsg = nil
    end
    -- Try to select specified photos - minimum time: 20msec, maximum time: 150msec.
    local function doSelect()
        for i = 1, 3 do
            catalog:setSelectedPhotos( mostSel, photos )
            LrTasks.sleep( .02 )
            checkValidity()
            if status then
                return
            end
            LrTasks.sleep( .03 ) -- give the new selection a fighting chance of being/becoming valid.
        end
    end
    -- try without changing anything (maybe Lr is just having a slow hair day..).
    doSelect() -- and check validity (loads status and sets or clears errmsg).
    return status, errmsg or "no error message"
end



--- Select specified photos - if at all possible.
--
--  @usage will try for at least 600msec, if not selecting: clears view filter. if still no go and source-change not disallowe, will select parent folders, and as last resort: put specified photos in their own collection and select that.
--  @usage if disallowing source change, max try time will be 300 msec. If you need to disallow changing view filter too, call 'tryToSelectPhotos' method instead.
--  @usage In some cases, all that matters is that photos get selected, in other cases a source change would kill the deal..
--
--  @param photos (array of LrPhoto, required) photos to be selected.
--  @param target (LrPhoto, optional) photo to be most-selected. If passed, must be in photos array; if not passed first photo in array will be most-selected.
--  @param disallowSourceChange (boolean, default=false) pass true if initial attempt is all that is warranted (i.e. do not resort to changing folders or collection..).
--
--  @return status true iff photos selected.
--  @return qual message may accompany true or false status value.
--
function Catalog:assureSelectedPhotos( photos, target, disallowSourceChange )
    target = target or photos[1]
    -- try without changing anything (maybe Lr is just having a slow hair day..).
    local valid, whynot = self:tryToSelectPhotos( photos, target )
    if valid then
        return true -- if happens without changing anything, keep quiet about it.
    end
    -- fall-through => need a bigger hammer (setting and waiting not enough) - try just turning filter off.
    self:clearViewFilter()
    valid, whynot = self:tryToSelectPhotos( photos, target )
    if valid then
        return true, "Had to clear view filter to select specified photos."
    end
    if disallowSourceChange then
        return false, "Unable to select specified photos, or at least not without altering selected sources - "..whynot
    end
    -- fall-through => need a bigger hammer (clearing view filter not enough) - try selecting the folders they're in.
    local folders = {} -- lr-folders: found.
    local folderSet = {} -- folder paths tried.
    for i, p in ipairs( photos ) do
        local folder = LrPathUtils.parent( p:getRawMetadata( 'path' ) )
        if not folderSet[folder] then
            folderSet[folder] = true -- whether found or not..
            local lrFldr = catalog:getFolderByPath( folder ) -- will not work correctly if network or lr-mobile folder. ###2
            if lrFldr then
                folders[#folders + 1] = lrFldr
            else
                logWarn( "Unable to get photo folder: ^1", folder )
            end
        end
    end
    if #folders > 0 then -- got some
        catalog:setActiveSources( folders )
        valid, whynot = self:tryToSelectPhotos( photos, target )
        if valid then
            return true, "Had to select parent folders to select specified photos."
        else
            app:logV( "After parent folders set active, still couldn't select specified photos - "..whynot )
        end
    -- else warnings already logged.
    end
    -- fall-through => need a bigger hammer (setting folder sources not enough) - try putting photos in their own collection.
    local sts, selColl = LrTasks.pcall( Catalog.assurePluginCollection, cat, "Selected Photos" )
    if sts then
        local status = catalog:withWriteAccessDo( "Set 'Selected Photos' Collection Items", function()
            selColl:removeAllPhotos()
            selColl:addPhotos( photos )
        end, { timeout=20 } )
        if status == "executed" then
            --logDbg( "Set script selected-photos collection items" )
        else
            return nil, "Unable to set script collection items"
        end
        catalog:setActiveSources{ selColl }
        valid, whynot = self:tryToSelectPhotos( photos, target )
        if valid then
            return true, "Had to put photos in their own collection to select them."
        else
            return nil, "Unable to set selected photos in collection - "..whynot
        end
    else
        return nil, selColl or "no reason"
    end
    error( "how here?" )
end



--- Set selected photos, and verify selection, with option to select folders if necessary to assure photos will be selected, even if not in filmstrip.
--
--  @usage *** This function is *mostly* deprecated in favor of the one above: "assure-selected-photos", which has the advantage that if folder-selection does not work, it can put all photos in a new collection, where they can be selected.
--  @usage This function will also clear view filter if necessary to select photos - what it won't do is expand stacks.
--  @usage Catalog photo selection may not take until processor is given up for Lightroom to do its thing.<br>
--         If you must be certain selection has settled before continuing with processing, call<br>
--         this method instead.
--  @usage  Do not call this method, unless you know the photos are all in active sources, or if all from folders, set assure-sources.
--          Presently, there is no method for assuring multiple selected photos from diverse (possibly not active) sources.
--  @usage  Will clear lib filter if need be, but will *not* unstack if need be, so stacking to exposes photos for selection must be handled externally, if needed.
--
--  @param photo (LrPhoto, optional) most selected. If nil, then a most-selected photo will be auto-chosen from photos (preferring already selected photo, but if not: photo #1).
--  @param photos (array of LrPhotos, required) the rest, which must include most selected, unless assureSources is true.
--  @param assureFolders (boolean, default=false) pass true to add photo to photos, if need be, and assure requisite sources are selected too - must be folders.
--  @param metaCache (Cache, default=nil) pass a metadata cache to boost performance, if desired: must be populated with raw metadata for 'path' key, or it won't be worth anything.
--
--  @return status (boolean) true iff specified selection validated.
--  @return message (string) error message if status is false.
--
function Catalog:selectPhotos( photo, photos, assureFolders, metaCache )
    local _photos = photos
    local _photo
    if photo == nil then -- prefer presently selected photo, if already a member of photos to select.
        local target = catalog:getTargetPhoto()
        for i, p in ipairs( photos ) do
            if target == p then
                photo = p
                break
            end
        end
        if photo == nil then
            photo = photos[1]
        end
    end
    _photo = photo
    local viewFilterTable
    local reason
    local function valid() -- not robust as it could be ###3
        local ps = catalog:getTargetPhotos()
        if #ps == #_photos then
            -- I could check each and every photo but no guarantee arrays are ordered the same,
            -- and an exhaustive check could be very time consuming.
            if catalog:getTargetPhoto() == _photo then -- at least check most-sel photo.
                return true
            else
                Debug.logn( str:to( catalog:getTargetPhoto() ), str:to( _photo ) )
                Debug.logn( "target photo mismatch" )
                reason = str:fmtx( "desired target photo can not be made most selected: ^1", _photo:getRawMetadata( 'path' ) )
                return false
            end
        else
            Debug.logn( "target photos count mismatch" )
            if app:isAdvDbgEna() then
                local set = tab:createSet( _photos )
                local arr = tab:createArray( set )
                if #arr ~= #_photos then
                    app:callingError( "Duplicate(s) in photos array" )
                end
            end
            reason = str:fmtx( "^1 photos are selected, but ^2 should be", #ps, #_photos )
            return false
        end
    end
    local try = 1
    while try <= 20 do -- try for up to 2 seconds.
        --Debug.pause( #_photos, _photo, _photos[1], _photos[2] )
        catalog:setSelectedPhotos( _photo, _photos )
        --Debug.pause( "selected?" )
        if try == 1 then
            LrTasks.yield() -- necessary for Lightroom to do its thing.
        elseif try == 5 then -- give it a good chance without assuring sources first, since it obviates the need to select individual folder sources in case it's a parental source that is selected.
            -- (since "include subfolders" can not be guaranteed).
            if assureFolders then
                _photo, _photos = self:_assureSources( photo, photos, metaCache ) -- reserves the right to rebuild the photos into an equivalent array.
                if _photo then
                    app:logVerbose( "Assured folder sources." )
                else
                    return false, _photos -- _photos is errm in this case.
                end
            else
                -- Debug.pause( "not assuring sources" )
                --_photos = photos
                --_photo = photo
                LrTasks.sleep( .1 ) -- "yield".
            end
        elseif try == 10 then
            app:log( "Clearing lib filter to improve odds of being able to select specified photos." )
            viewFilterTable = catalog:getCurrentViewFilter()
            cat:clearViewFilter( true ) -- no-yield.
            LrTasks.sleep( .1 )
        else
            LrTasks.sleep( .1 ) -- "yield".
        end
        if valid() then
            -- return true - commented out 11/Jul/2013 16:56
            return _photo -- added 11/Jul/2013 16:56
        end
        try = try + 1
    end
    local s, m = false, str:fmtx( "Unable to select specified photos, reason: ^1", reason or "unknown" )
    local bm = cat:getBatchRawMetadata( _photos, { 'isInStackInFolder', 'stackPositionInFolder', 'stackInFolderIsCollapsed' } )
    for i, p in ipairs( _photos ) do
        if cat:isBuriedInStack( p, bm ) then
            s, m = false, str:fmt( "Unable to select specified photos because at least one of them is buried in a stack (e.g. ^1)", p:getRawMetadata( 'path' ) )
            break
            -- could provide better error message by factoring in active source considerations, but outcome would be the same...
        end
    end
    if viewFilterTable then
        app:log( "Restoring previous view filter, since unable to select photos anyway..." )
        catalog:setViewFilter( viewFilterTable )
    end
    return s, m
end
Catalog.setSelectedPhotos = Catalog.selectPhotos -- synonym. function Catalog:setSelectedPhotos( photo, photos )
    


--- Save metadata for one photo.
--
--  @usage              *** consider using save-xmp-metdata method instead if Lr5+ - it does not have the same side-effect of photo being selected.
--  @param              photo - single photo object to save metadata for.
--  @param              photoPath - photo path (optional).
--  @param              targ - path to file containing xmp for save validation (optional).
--  @param              call - if a scope in call it will be used for captioning.
--  @param              noVal - don't validate that metadata is saved.
--  @param              oldWay - don't use buggy Lr5.2RC method.
--
--  @usage              Windows + Mac (its the *read* metadata that's not supported on mac).
--  @usage              If you've just done something that needs settling before save, call sleep(e.g. .1) before this method to increase odds for success on first try.
--  @usage              Library mode is not necessary to save single photo metadata.
--  @usage              *** Side-effect of single photo selection - be sure to save previous multi-photo selection to restore afterward if necessary.
--  @usage              Will cause metadata conflict flag if xmp is read-only, so make read-write before calling, if desired.
--  @usage              Uses keystroke emission to do the job.
--
--  @return             true iff metadata saved.
--  @return             error message if metadata not saved.
--
function Catalog:savePhotoMetadata( photo, photoPath, targ, call, noVal, oldWay )

    -- Note: new (single-photo) method will be called below if Lr5+.

    local mode = app:getPref( 'saveMetadataMode' ) -- Note: consider separating mode for batch vs. onezie (or just ignoring mode if Lr5/onezie), since auto-mode for onezie should work fine on Mac in Lr5.
    if mode == 'manual' then
    end
    -- otherwise, auto is default mode - proceed...

    if photo == nil then
        app:callingError( "need photo" )
    end

    if photoPath == nil then
        photoPath = photo:getRawMetadata( 'path' )
    end
    
    local isVirt = photo:getRawMetadata( 'isVirtualCopy' )
    if isVirt then
        return false, "Can't save metadata of virtual copy"
    end
    
    if targ == nil then
        local fmt = photo:getRawMetadata( 'fileFormat' )
        if fmt == 'RAW' then -- raw not dng. Beware, if you don't want to save metadata for cooked nefs (which are considered "raw")..., then check before calling.
            targ = LrPathUtils.replaceExtension( photoPath, "xmp" )
        elseif fmt == 'VIDEO' then
            return false, "Can't save metadata of video"
        else
            targ = photoPath
        end
    end
    if fso:existsAsFile( targ ) then
        if not LrFileUtils.isWritable( targ ) then
            if targ ~= photoPath then
                local photoName = LrPathUtils.leafName( photoPath )
                return false, str:fmtx( "Unable to save metadata for '^1' because '^2' is not writable.", photoName, targ )
            else
                return false, str:fmtx( "Unable to save metadata for '^1' because it's not writable.", photoPath )
            end
        -- else nada
        end
    else
        if targ ~= photoPath then
            local targName = LrPathUtils.leafName( targ )
            app:logVerbose( "Saving metadata of '^1', to '^2' which does not yet exist.", photoPath, targName )
        else
            return false, str:fmtx( "'^1' does not exist.", photoPath )
        end
    end

    local done = false -- cancel flag
    
    -- Side effect: selection of single photo to be saved. @6/Dec/2014 21:34, this side effect is not always acceptable, so save-xmp-metadata invented to for such contexts.
    -- local s, m = cat:selectOnePhoto( photo ) - commented out 13/Sep/2011 16:47
    local s = cat:assurePhotoIsSelected( photo, photoPath ) -- added 13/Sep/2011 16:47
    -- dunno if this is necessarily an Lr5 bug, so.. ###2
    --    LrTasks.sleep( 1 ) -- attempting save-metadata Lr5-style too soon after selecting photo to be saved results in unknown file i/o error.
    -- Note: this seems true even if pausing for complete settling before-hand.
    -- reminder: .1 seconds is not enough.
    -- Note: I'm not having this problem all the time, but certainly I am in case of newly imported jpg... (as per DxOh import feature).
    if s then
        app:logVerbose( "Photo selected for metadata save: ^1", photoPath )
    else
        return false, str:fmt( "Unable to select photo for metadata save (see log file for details), path: ^1", str:to( photoPath ) )
            -- no way it'll work if cant select it.
    end
    
    local window = app:getPref{ name='fsTimeTolerance', default=2 } -- A little slack reduces potential for intermittent (erroneous) save errors.
    
    local time, time2, tries
    local m
    if call and call.scope then
        call.scope:setCaption( str:fmt( "Waiting for 'Save Metadata' confirmation..." ) ) -- only visible after the save metadata operation is complete.
        -- calling context needs to put something else up upon return if desired.
    end
    tries = 1
    local code = app:getPref( 'saveMetadataKeyChar' ) or 's'
    local saveStarted
    local function isSaved( time2, time )
        if time2 == nil then return false end -- no file time yet - not saved.
        if time2 > time then return true end -- file time exceeds command time - saved.
        if num:isWithin( time2, time, window ) then -- file time not too far behind (within reasonable window given file-system) - saved.
            return true
        else -- file time still not updated since command issued.
            return false
        end
    end
    repeat
        if not saveStarted then
            if not oldWay and app:lrVersion() >= 5 then
                -- Note: there was a bug in Mac version until 3/Sep/2013 10:24 when not saving old-way in Lr5, since math-floor was not what was being recorded for time (see clause below). ###1 all plugins doing metadata save on Mac should be re-released.
                if WIN_ENV then
                    -- time = LrDate.currentTime() -- windows file times are high-precision and haven't needed a fudge factor so far. ###2 watch for metadata timeout on Windows too.
                    -- I just had log report from a win 7 system (business edition) where file times are integer, so I guess @21/Oct/2013 1:48, Windows will be done like Mac.
                    -- Truth is the window of vulnerability is so small the odds anything significant slips through are pretty small.
                    time = math.floor( LrDate.currentTime() ) -- windows file times are high-precision and haven't needed a fudge factor so far. metadata timeout was happening on Windows sometimes too.
                else -- note: I couls also subtract a second to be sure of success, although that opens the window of vulnerability a little further.
                    time = math.floor( LrDate.currentTime() ) -- file-attrs seem to be nearest second on Mac - make sure this does not appear to be in the future.
                end                
                -- worth noting: this command will fail (it's disabled) if photo is on a card.
                photo:saveMetadata() -- new Lr5 method - guaranteed to initiate metadata saving, but returns before complete.
                -- potential risk: this method fails if photo is a virtual copy where-as send-keys won't, so hopefully virtual copy is checked before calling.
                -- and virtual copy *is* checked at top of this function, granted it will be handled as an error at that point.
                saveStarted = true
            else
                local keys
                if WIN_ENV then
                    time = math.floor( LrDate.currentTime() ) -- windows file times are (usually) high-precision and haven't needed a fudge factor so far (until 21/Oct/2013). metadata timeout occuring on some Windows systems too.
                    keys = str:fmt( "{Ctrl Down}^1{Ctrl Up}", code )
                    s, m = app:sendWinAhkKeys( keys ) -- Save metadata - for one photo: seems reliable enough so not using the catalog function which includes a prompt.
                else -- MAC_ENV
                    time = math.floor( LrDate.currentTime() ) -- file-attrs seem to be nearest second on Mac - make sure this does not appear to be in the future.
                    keys = str:fmt( "Cmd-^1", code )
                    s, m = app:sendMacEncKeys( keys )
                end
                if s then
                    app:logVerbose( "Issued keystroke command '^1' to save metadata for ^2", keys, photoPath ) -- just log final results in normal case.
                    saveStarted = true
                else
                    return false, str:fmt( "Unable to save metadata for ^1 because ^2", photoPath, m )
                end
            end
        else
            -- don't keep doing it.
        end
        time2 = LrFileUtils.fileAttributes( targ ).fileModificationDate
        local count = 50 -- give a few seconds or so for the metadata save to settle, in case Lr is constipated on this machine, or some other process is interfering temporarily...
        while count > 0 and not isSaved( time2, time ) do
            LrTasks.sleep( .1 )
            count = count - 1
            time2 = LrFileUtils.fileAttributes( targ ).fileModificationDate
        end
        --Debug.pause( window, time, time2, num:isWithin( time2, time, window ) )
        if isSaved( time2, time ) then
            app:logVerbose( "^1 metadata save validated.", photoPath )
            return true
        elseif time2 == nil then
            if tries == 1 then
                app:log( "*** Unable to save metadata for ^1 because save validation timed out, unable to get time of xmp file: ^2.", photoPath, targ )
            elseif tries == 2 then
                app:logWarn( "Unable to save metadata for ^1 because save validation timed out, unable to get time of xmp file: ^2.", photoPath, targ )
            -- else return value will be logged as error if user gives up.
            end
        else -- got time2 but hasn't advanced.
            if tries == 1 then -- first time is considered "normal" (although not optimal).
                app:log( "*** Unable to save metadata for ^1 because save validation timed out, xmp file (^2) time: ^3, save metadata command time: ^4.", photoPath, targ, time2, time )
            elseif tries == 2 then -- second time it should have taken.
                app:logWarn( "Unable to save metadata for ^1 because save validation timed out, xmp file (^2) time: ^3, save metadata command time: ^4.", photoPath, targ, time2, time )
            -- else return value will be logged as error if user gives up.
            end
        end
        if tries >= 5 then -- after 5th and subsequent tries, involve the user.
            if noVal then
                return true -- pretend like it worked, even thought it didn't in the hope that it's a "pseudo" problem (there will still be the warning logged).
            end
            repeat
                local answer = app:show{ warning="Unable to save metadata for ^1 - try again?",
                    buttons={ dia:btn( "Yes", 'ok' ), dia:btn( "Give Me a Moment", 'other' ) },
                    subs=photoPath }
                if answer == 'ok' then
                    saveStarted = false
                    break
                    -- go again
                elseif answer == 'other' then
                    app:sleepUnlessShutdown( 3 )
                elseif answer == 'cancel' then
                    done = true -- can't cancel the call because it may be the background process call, and there is nothing to un-cancel it.
                        -- not only that, but call param is optional, and sometimes is not passed.
                    break -- quit
                else
                    app:error( "bad answer" )
                end
            until done or shutdown
        end
        if not done then
            tries = tries + 1
        -- else exit loop below.
        end
    until done or shutdown
    if time2 == nil then
        return false, str:fmt( "Unable to save metadata for ^1 because save validation timed out, unable to get time of xmp file: ^2.", photoPath, targ )
    else
        return false, str:fmt( "Unable to save metadata for ^1 because save validation timed out, xmp file (^2) time: ^3, save metadata command time: ^4.", photoPath, targ, time2, time )
    end
    
end



--- Save one or more photo's xmp metadata, if Lr5+.
--
--  @usage used to have potential for trouble on Mac in Lr5.2RC. @6/Dec/2014 19:30 in Windows it's working perfectly - not sure what to say, except test well..
--  @usage may not work if jpeg photo recently imported - see http://feedback.photoshop.com/photoshop_family/topics/lightroom_5_2_sdk_photo_savemetadata_sometimes_has_unknown_file_i_o_error_when_it_shouldnt
--  @usage sloooow if multiple photos, unless/until Adobe improves..
--
--  @param photoOrPhotos lr-photo or array of them.
--  @param otherStuff table of options, defined so far:
--      <br>    noVal - omit the validation that metadata saving has completed successfully.
--      <br>    tmo - if not 'noVal' the validation timeout - defaults to 30 + .3 second per photo.
--      <br>    cache - metadata cache.
--
--  @return status true => success.
--  @return err-msg if status false, the reason, else if not no-val, the target path (1-photo), or parallel array of xmp-target-paths (multi-photo).
--
function Catalog:saveXmpMetadata( photoOrPhotos, otherStuff )
    app:callingAssert( app:lrVersion() >= 5, "requires Lr5+" )
    otherStuff = otherStuff or {}
    local photos
    local targetFiles
    local fileTimeLookup
    if photoOrPhotos.getRawMetadata then -- it's an lr-photo
        photos = { photoOrPhotos }
    else
        photos = photoOrPhotos
    end
    if not otherStuff.noVal then
        targetFiles = {}
        fileTimeLookup = {}
        local cache = otherStuff.cache
        for i, photo in ipairs( photos ) do
            local path = lrMeta:getRaw( photo, 'path', cache )
            local file = xmpo:getTargetFile( path )
            local attrs = LrFileUtils.fileAttributes( file )
            targetFiles[#targetFiles + 1] = file
            if attrs then -- file exists
                fileTimeLookup[file] = { photo=photo, time=math.floor( attrs.fileModificationDate or math.huge ) } -- if no file-mod-date (never happens), make sure it will never validate.
            else
                return false, "target file is missing, so save-metadata can not be validated"
            end
        end
    end
    for i, photo in ipairs( photos ) do
        photo:saveMetadata() -- queue up the request to save.
    end
    if not otherStuff.noVal then
        local tmo = otherStuff.tmo or 30
        for i = 1, 3 do
            LrTasks.sleep( .1 ) -- give save-metadata a half a chance..
            local now = LrDate.currentTime()
            local tooLate = now + ( tmo / 3 + #photos * .1 )
            local ambig
            repeat
                local allGood = true -- and all targets exist initially.
                local remove = {} -- set of files to be removed (because they've gone missing or have already been validated).
                ambig = {}
                for file, rec in pairs( fileTimeLookup ) do
                    local fileTime = rec.time
                    assert( fileTime ~= nil, "?" ) -- it's my understanding that iterator will skip it if nil.
                    local attrs = LrFileUtils.fileAttributes( file )
                    if not attrs then -- file was present, but isn't anymore.
                        app:logW( "xmp target file disappeared" ) -- probably better to not let this be a deal killer (e.g. user deletes file whilst bg processing..).
                        remove[file] = true -- remove missing file.
                    else
                        local fileTime2 = math.ceil( attrs.fileModificationDate or -math.huge ) -- mod-date is always there if attrs are there, but just in case, assure it won't validate.
                        if fileTime2 > fileTime then -- clearly has changed since save.
                            remove[file] = true
                        elseif fileTime2 == fileTime then -- usually means it hasn't changed yet, but could mean it changed so quickly that it got reported as the same time.
                            ambig[rec.photo] = file
                            allGood = false
                        else -- clearly has not changed yet.
                            allGood = false
                        end
                    end
                end
                if allGood then
                    return true, #photos == 1 and targetFiles[1] or targetFiles
                elseif LrDate.currentTime() > tooLate then
                    break
                else
                    tab:removeItems( fileTimeLookup, remove )
                    LrTasks.sleep( .1 )
                end
            until false -- until exit within.
            if i == 1 then
                Debug.pause( "metadata save not validated after try #1" )
                app:logV( "*** Metadata save not validated after try #1" )
            elseif i == 2 then
                app:logW( "Metadata save not validated after try #2" )
            else
                return false, "Metadata read could not be validated in alotted time."
            end
            for photo, file in pairs( ambig ) do
                photo:saveMetadata()
            end
        end
        error( "how here?" )
    else
        return true
    end
end



--- Read one or more photo's xmp metadata, if Lr5+.
--
--  @usage Lr5 only.
--  @usage Advantages: photos do not have to be selected, and hence can be buried in stack, also does not require keyboard stuffing.
--  @usage Disadvanges: sloooow if multiple photos, unless/until Adobe improves.., also it's not released, and requires user be in library module - may not work as well on Mac (where it's less tested) as in Windows (where it seems fine, as long as in library module).
--
--  @param photoOrPhotos lr-photo or array of them.
--  @param otherStuff table of options, defined so far:
--      <br>    noVal - omit the validation that metadata saving has completed successfully.
--      <br>    tmo - if not 'noVal' the validation timeout - defaults to 30 + .3 seconds per photo.
--      <br>    cache - metadata cache.
--
--  @return status true => success.
--  @return err-msg if status false, the reason.
--
function Catalog:readXmpMetadata( photoOrPhotos, otherStuff )
    app:callingAssert( app:lrVersion() >= 5, "requires Lr5+" )
    otherStuff = otherStuff or {}
    local photos
    local editTimeLookup
    if photoOrPhotos.getRawMetadata then -- it's an lr-photo
        photos = { photoOrPhotos }
    else
        photos = photoOrPhotos
    end
    if not otherStuff.noVal then
        editTimeLookup = {}
        local cache = otherStuff.cache
        for i, photo in ipairs( photos ) do
            local editTime = lrMeta:getRaw( photo, 'lastEditTime', cache ) -- it's fine if initial value comes from cache, as long as subsequent checks use fresh data.
            if editTime then -- always present..
                editTimeLookup[photo] = editTime
            else
                return false, "target edit-time is missing, so read-metadata can not be validated"
            end
        end
    end
    for i, photo in ipairs( photos ) do
        photo:readMetadata() -- queue up the request to read.
    end
    if not otherStuff.noVal then
        local tmo = otherStuff.tmo or 30
        for i = 1, 3 do -- 3 tries
            LrTasks.sleep( .1 ) -- give save-metadata a half a chance..
            local now = LrDate.currentTime()
            local tooLate = now + ( tmo / 3 + #photos * .1 )
            local ambig
            repeat
                local allGood = true -- and all targets exist initially.
                local remove = {}
                ambig = {}
                for photo, editTime in pairs( editTimeLookup ) do
                    assert( editTime ~= nil, "?" ) -- it's my understanding that iterator will skip it if nil.
                    local editTime2 = photo:getRawMetadata( 'lastEditTime' )
                    if not editTime2 then
                        app:logW( "photo disappeared or something (no edit-time metadata)" )
                        remove[photo] = true
                    else
                        if editTime2 > editTime then -- unambiguously modified and so presumably (if not due to asynchronous mod), metadata has been read and incorporated in catalog.
                            remove[photo] = true
                        elseif editTime2 == editTime then -- usually it hasn't changed yet, but sometimes it means it changed fast and timestamp won't budge no matter how long wait.
                            ambig[photo] = true
                            allGood = false
                        else
                            allGood = false
                        end
                    end
                end
                if allGood then
                    return true
                elseif LrDate.currentTime() > tooLate then
                    break
                else
                    tab:removeItems( editTimeLookup, remove )
                    LrTasks.sleep( .1 )
                end
            until false -- until exit within.
            if i == 1 then
                Debug.pause( "metadata read not validated after try #1" )
                app:logV( "*** Metadata read not validated after try #1" )
            elseif i == 2 then
                app:logW( "Metadata read not validated after try #2" )
            else
                return false, "Metadata read could not be validated in alotted time."
            end
            for photo in pairs( ambig ) do
                photo:readMetadata() -- if not all photos are appearing modified, re-invoke, which should do it. Probably would only need 1 retry, but give a 3rd just for the heck.
            end
        end
        error( "how here?" )
    else
        return true
    end
end



--- Save metadata for (multiple) specified photos.
--
--  @param              photos - photos to save metadata for, or nil to do all target photos.
--  @param              preSelect - true to have specified photos selected before saving metadata, false if you are certain they are already selected.
--  @param              restoreSelect - true to have previously photo selections restored before returning.
--  @param              alreadyInGridMode - multiple photos requires grid mode, if already in it, for sure, set this to true.
--  @param              service - if a scope in here it will be used for captioning.
--
--  @usage              *** consider using save-xmp-metdata method instead if Lr5 or better - if it works, then it avoids the hoops inherent in this method.
--  @usage              Windows + Mac (its the *read* metadata that's not supported on mac).
--  @usage              Switch to grid mode first if desired, and select target photos first if possible.
--  @usage              Cause metadata conflict for photos that are set to read-only, so make read-write before calling, if desired.
--  @usage              Uses keystroke emission to do the job.
--  @usage              User will be prompted to first make sure the "Overwrite Settings" prompt will no longer appear.
--
--  @return             true iff metadata saved.
--  @return             error message if metadata not saved.
--
function Catalog:saveMetadata( photos, preSelect, restoreSelect, alreadyInGridMode, service )

    if photos == nil then
        app:callingError( "photos must not be nil" )
    end
    
    --[[ *** 15/Jun/2013: too slow (save as reminder) - it may be OK for doing a half-dozen photos, but any more than that and it is prohibitively slow.
    if app:lrVersion() >= 5 then
        for i, photo in ipairs( photos ) do
            if not photo:getRawMetadata( 'isVirtualCopy' ) then
                photo:saveMetadata() -- error if virtual copy
            else
                Debug.pause( "Can't save metadata of virtual copies." )
            end
        end
        return true
    end
    --]]
    
    if #photos < 1 then
        app:callingError( "photo count can not be zero" )
    end
    
    -- reminder: if mode is manual, then this method is called for saving only one photo too.

    local selPhotos = self:saveSelPhotos()

    if preSelect then
        local photoToBe
        if selPhotos.mostSelPhoto then
            for i, photo in ipairs( photos ) do
                if photo == selPhotos.mostSelPhoto then
                    photoToBe = photo
                    break
                end
            end
        end
        if not photoToBe then
            photoToBe = photos[1]
        end
        local s, m = cat:setSelectedPhotos( photoToBe, photos ) -- make sure the photos to have their metadata saved are the ones selected.
        if s then
            app:logVerbose( "Photos selected for metadata save." )
        else
            return false, str:fmt( "Unable to select photos for metadata save, error message: ^1", m )
        end
    end

    local status = false
    local message = "unknown"

    -- mode dependent behavior:
    local mode = app:getPref( 'saveMetadataMode' ) or 'auto'
    local code = app:getPref( 'saveMetadataKeyChar' ) or 's'
    
    -- auto & manual modes:
    if not alreadyInGridMode then    
        local s, m = gui:gridMode( false ) -- attempt to put in grid mode. Although grid-mode is mandatory, consider it not mandatory, so special handling can be done in this context instead.
        if s then
            app:logv( "switched to grid mode" )
        else
            if mode == 'auto' then
                app:show{ warning="Unable to switch to grid mode automatically (error message: '^1'). Metadata save will therefore use manual mode this time. To avoid this prompt in the future, switch to manual mode permanently.",
                    m or "unspecified",
                }
                mode = 'manual'
            else
                app:logv( "unable to switch to grid mode. good thing save-metadata is in manual mode anyway..." )
            end
        end
    else
        app:logv( "Supposedly, library module is already in grid mode for the metadata save." )
    end
    
    if mode == 'auto' then -- default mode is auto.

        if service and service.scope then
            service.scope:setCaption( str:fmt( "Waiting for 'Save Metadata' button click..." ) ) -- only visible after the save metadata operation is complete.
        end
        -- Note: this prompt is optional, but the confirmation prompt is not:
        local m = {}
        m[#m + 1] = "Metadata must be saved to ensure this operation is successful."
        m[#m + 1] = "After you click 'Save Metadata', you should see an extra \"Operation\" pop up in the upper left corner of Lightroom's main window - be looking for it... (if no other operations are in progress, it will say 'Saving Metadata')"
        m[#m + 1] = "If you are in grid mode, and there are no other dialog boxes open, then click 'Save Metadata' to begin. If there are other Lightroom/plugin dialog boxes open, then click 'Let Me Close Dialogs' and do so (close them). If you are not in grid mode, or cant get the dialog boxes to stay closed, then you must click 'Cancel', and try again after remedying..."
        m[#m + 1] = "Click 'Save Metadata' when ready."
        m = table.concat( m, '\n\n' )
    
        local answer
        repeat
            answer = app:show{ info=m,
                buttons={ dia:btn( "Save Metadata", 'ok' ), dia:btn( "Let Me Close Dialogs", 'other', false ) },
                actionPrefKey="Save metadata"
            }
            if answer == 'other' then
                LrTasks.sleep( 3 )
            elseif answer == 'cancel' then
                return false, "User canceled."
            else
                break
            end
        until false
        repeat
            if answer == 'ok' then
                if service and service.scope then
                    service.scope:setCaption( str:fmt( "Waiting for 'Save Metadata' confirmation..." ) ) -- only visible after the save metadata operation is complete.
                end
                if WIN_ENV then
                    local keys = str:fmt( "{Ctrl Down}^1{Ctrl Up}", code )
                    status, message = app:sendWinAhkKeys( keys ) -- include post keystroke yield.
                else
                    local keys = str:fmt( "Cmd-^1", code )
                    status, message = app:sendMacEncKeys( keys )
                end
                if status then
                    -- nada
                else
                    break
                end
                --local m = "Has the 'Save Metadata' operation completed?\n \nYou can tell by the upper left-hand corner of the main Lightroom window: the 'Save Metadata' operation that was started there will disappear when the operation has completed."
                local m = "Wait for the 'Save Metadata' operation to complete, then click 'Save Metadata is Complete'.\n \nYou can tell when its complete by looking in the upper left-hand corner of the main Lightroom window: it will say \"Waiting for 'Save Metadata' confirmation...\" when the operation has completed (or in any case, the progress bar will have stopped progressing and/or an operation will have dropped out)."
                local answer2 = app:show{ info=m, buttons={ dia:btn( "Save Metadata is Complete", 'ok' ), dia:btn( "Save Metadata Never Started", 'other' ) } }
                if answer2 == 'ok' then -- yes
                    status = true
                elseif answer2 == 'cancel' then -- no
                    status, message = false, "Apparently, metadata was not saved - most often caused by dialog box interference. Try to eliminate interfereing dialog boxes, then attempt again..."
                elseif answer2 == 'other' then -- dunno
                    status, message = nil, "Metadata must be saved. Hint: to tell if it gets saved, watch the progress indicator in the upper left-hand corner of the main Lightroom window."
                end
            elseif not answer or answer == 'cancel' then -- answer is coming back false for cancel - doc says cancel => nil for prompt-for-action-with-do-not-show...
                -- 'cancel' is returned by other lr-dialog methods, so test for it left in here as cheap insurance / reminder...
                status, message = nil, "User canceled."
            else
                error( "invalid answer: " .. str:to( answer ) )
            end
        until true
        
    else -- assume manual metadata save mode.
        if service and service.scope then
            service.scope:setCaption( str:fmt( "Saving metadata using manual mode" ) ) -- only visible after the save metadata operation is complete.
        end
        local tb = ""
        if not alreadyInGridMode then
            tb = "assure you are in grid mode, then "
        end
        local m = {}
        local otherButton = 'ok'
        local otherButtonText = "Let Me Save Metadata Manually"
        local buttons = { dia:btn( otherButtonText, otherButton, false ) }
        --local actionPrefKey = nil
        -- initial prompt message:
        m[#m + 1] = "Metadata must be saved to ensure this operation is successful."
        m[#m + 1] = "Manual mode is being used, which means in a moment, you will have to press ^1 to save metadata manually."
        m[#m + 1] = "After clicking the '^2' button below, ^3press '^1' on your keyboard to save metadata."
        m = table.concat( m, '\n\n' )
        local subs = { app:getCtrlKeySeq( code ), otherButtonText, tb }
    
        local delayTime = app:getPref( 'delayForManualMetadataSaveBox' ) or 3
        local answer
        repeat
            answer = app:show{ info=m,
                subs = subs,
                buttons=buttons,
                --actionPrefKey=actionPrefKey,
            }
            -- actionPrefKey = "Save Metadata (Manually) confirmation" - seems like both prompts are required. ###3 I could conceivably have a "no-validate" parameter,
            -- for when this method isn't critical, but presently it is always critical, or it isn't done, e.g. change-manager, raw+jpg.
            if answer == otherButton then
                app:sleep( delayTime )
                if shutdown then return false, "shutdown" end
                -- subsequent prompt message:
                local tb = ""
                if not alreadyInGridMode then
                    tb = "assure you are in grid mode, "
                end
                m = {}
                m[#m + 1] = "Verify Lightroom initiated and completed saving metadata."
                m[#m + 1] = "You can tell Lightroom initiated saving of metadata by looking at the progress area on left side of the top panel where progress bars are displayed - another operation gets started with a progress bar."
                m[#m + 1] = "Once complete, the progress bar associated with the metadata save operation will disappear."
                m[#m + 1] = "Wait until Lightroom has completed saving metadata, then click '^3' to proceed. If the metadata save operation never started, or you are uncertain whether it completed, click '^2', ^4then press '^1'."
                m = table.concat( m, '\n\n' )
                subs = { app:getCtrlKeySeq( code ), otherButtonText, "Metadata Has Been Saved", tb }
                otherButton = 'other'
                buttons = { dia:btn( "Metadata Has Been Saved", 'ok' ), dia:btn( otherButtonText, otherButton, false ) }
            elseif answer == 'ok' then
                status, message = true, nil
                break
            elseif answer == 'cancel' then
                status, message = false, "Metadata save was canceled by user."
                break
            end
        until false
        
    end
    
    if restoreSelect then
        cat:restoreSelPhotos( selPhotos )
    end
    return status, message

end



-- private function to support metadata reading on mac or windows systems configured for manual mode.
function Catalog:_readMetadataManual( service, manualSubtitle )
    manualSubtitle = manualSubtitle or str:fmt( "^1 needs metadata to be read", app:getAppName() ) -- assure at least minimal prompt text for window, in case generic prompt is OK.
    local delay = app:getPref( 'timeRequiredToReadMetadataOnMac' ) or 7 -- misnomer but still applicable for windows boxes that use manual read mode.
    local otherButton = str:fmt( "Dismiss Dialog Box for ^1 Seconds", delay )
    local okButton = "Metadata Has Been Read"
    if delay < 3 then
        delay = 3
    elseif delay > 30 then
        delay = 30
    end
    
    local take = 1
    
    repeat
        local subtitle = manualSubtitle
        local main = {}
        local prompt
        local buttons
        if take == 1 then
            subtitle = manualSubtitle
            prompt = "You need to use Lightroom's Metadata Menu and select 'Read Metadata From File' now."
            main[#main + 1] = vf:spacer { height = 10 }
            main[#main + 1] =
                vf:row {
                    vf:static_text {
                        title = prompt,
                    },
                }
            main[#main + 1] = vf:spacer { height = 20 }
            main[#main + 1] =
                vf:row {
                    vf:static_text {
                        title = str:fmt( "Click '^1' when you're ready...", otherButton ),
                    },
                }
            buttons = { dia:btn( otherButton, 'ok' ) }
        else
            if take > 2 then -- on take 2, just the message & button changes suffice.
                subtitle = manualSubtitle .. " - take " .. ( take - 1 ) -- let "take" mean number of retries *after* 2nd take dialog box first displayed.
            else
                subtitle = manualSubtitle
            end
            prompt = "Mission accomplished? If not, you need to use Lightroom's Metadata Menu and select 'Read Metadata From File' now."
            main[#main + 1] = vf:spacer { height = 10 }
            main[#main + 1] =
                vf:row {
                    vf:static_text {
                        title = prompt,
                    },
                }
            main[#main + 1] = vf:spacer { height = 20 }
            main[#main + 1] =
                vf:row {
                    vf:static_text {
                        title = str:fmt( "Click '^1' when mission accomplished, or click '^2' again to retry.", okButton, otherButton ),
                    },
                }
            buttons = { dia:btn( otherButton, 'other' ), dia:btn( okButton, 'ok' ), }
        end
        local answer = app:show{ confirm = "^1",
            subs = { subtitle },
            viewItems = main,
            buttons = buttons,
        }
        if take == 1 then
            if answer == 'ok' then
                answer = 'other'
            end
        end
        if answer == 'ok' then
            return true
        elseif answer == 'other' then
            app:sleepUnlessShutdown( delay )
            if shutdown then
                service:cancel()
                return false, "shutdown"
            end
            take = take + 1
        else
            service:cancel()
            return false, "User canceled."
        end
    until false
end



--- Read metadata for one photo.
--
--  @param              photo - single photo object to read metadata for.
--  @param              photoPath - photo path.
--  @param              alreadyInLibraryModule - true iff library module has been assured before calling.
--  @param              service - if a scope in here it will be used for captioning.
--  @param              manualSubtitle - a tidbit for the prompt, if omitted it will be "this plugin needs metadata to be read".
--
--  @usage              Not reliable in a loop without user prompting in between (or maybe lengthy delays).
--  @usage              Switch to grid mode first if necessary.
--  @usage              *** Side-effect of single photo selection - be sure to read previous multi-photo selection to restore afterward if necessary.
--  @usage              Ignores photos that are set to read-only, so make read-write before calling, if desired.
--  @usage              Uses keystroke emission to do the job.
--  @usage              Will not work on virtual copy (returns error message), so check before calling.
--
--  @return             true iff metadata read
--  @return             error message if metadata not read.
--
function Catalog:readPhotoMetadata( photo, photoPath, alreadyInLibraryModule, service, manualSubtitle )

    -- new read-metadata method introduced in Lr5 will be used below, if compatible Lr version.

    if not str:is( photoPath ) then
        photoPath = photo:getRawMetadata( 'path' )
    end

    local mode
    local newWay = ( app:lrVersion() >= 5 ) and not app:getPref( 'readMetadataTheOldWay' )
    if WIN_ENV or newWay then -- mac supports read-metadata via sdk in Lr5+. Unlike save-metadata, the new fn seems to be reliable / working.
        mode = app:getPref( 'readMetadataMode' ) or 'auto'
    else
        mode = 'manual'
    end
    local keySeq = app:getPref( 'readMetadataKeySeq' ) or (WIN_ENV and 'mr') -- no default on Mac.
    
    if mode == 'manual' then
        local tb
        if MAC_ENV then
            tb = "on Macs"
        else
            tb = 'on Windows machines when plugin scripting is prohibited'
        end
        app:show{ info="I have some good news and some bad news.\n \nThe bad news is that Lightroom's \"Read Metadata\" function is not supported (programmatically) ^2.\n \nThe good news is that you can do it for ^1. Its a little tricky because you have to click a button to dismiss the dialog box for a moment, then invoke the function yourself, then click another button to confirm - detailed instructions will be provided.",
            subs = { app:getAppName(), tb },
            actionPrefKey = "Manual requirements for reading Lr metadata",
        }
    end
   
    -- Side effect: selection of single photo to be read.
    -- local s, m = cat:selectOnePhoto( photo ) - commented out 13/Sep/2011 16:47
    if app:lrVersion() <= 4 or mode == 'manual' or not newWay then
        local s = cat:assurePhotoIsSelected( photo, photoPath ) -- added 13/Sep/2011 16:47
        if s then
            app:logVerbose( "Photo selected for metadata read: ^1", photoPath )
        else
            --return false, str:fmt( "Unable to select photo for metadata read, error message: ^1", m ) -- m includes path.
                -- no way it'll work if cant select it.
            return false, str:fmt( "Unable to select photo for metadata read (see log file for details), path: ^1", str:to( photoPath ) )
                -- no way it'll work if cant select it.
        end
    else
        -- no need to pre-select photo if Lr5-auto.
    end
    
    local time
    if service and service.scope then
        service.scope:setCaption( str:fmt( "Waiting for 'Read Metadata' confirmation..." ) ) -- only visible after the save metadata operation is complete.
    end
    
    -- must be as sure as possible we're in library module, view mode does not matter.
    if mode == 'auto' and not alreadyInLibraryModule and not newWay then
        local s, m = gui:switchModule( 1, true ) -- because read-metadata keystroke not available in dev module, or not same.
        if s then
            app:logVerbose( "Issued command to switch to library module for ^1", photoPath ) -- just log final results in normal case.
        else
            return false, str:fmt( "Unable to switch to library module for ^1 because ^2", photoPath, m )
        end
    end
    time = LrDate.currentTime() -- windows file times are high-precision and haven't needed a fudge factor so far.
    if mode == 'auto' then
        if newWay then
            photo:readMetadata() -- may not be reliable - jury still out (set old-way to true if probs..).
        else
            local s, m = app:sendWinAhkKeys( str:fmt( "{Alt Down}^1{Alt Up}", keySeq ) ) -- Read metadata - for one photo: seems reliable enough so not using the catalog function which includes a prompt.
            if s then
                app:logVerbose( "Issued command to read metadata for ^1", photoPath ) -- just log final results in normal case.
            else
                return false, str:fmt( "Unable to read metadata for ^1 because ^2", photoPath, m )
            end
        end
    else
        local s, m = self:_readMetadataManual( service, manualSubtitle )
        if s then
            app:logVerbose( "User confirmed that metadata for '^1' has been read.", photoPath ) -- just log final results in normal case.
        else
            return false, str:fmt( "Unable to read metadata for '^1' - ^2", photoPath, m )
        end
    end
    
    -- fall-through => one photo selected in library, and command issued to read metadata.
    
    local time2 = photo:getRawMetadata( 'lastEditTime' )
    local count = 50 -- give 5 seconds or so for the metadata read to settle, in case Lr is constipated on this machine, or some other process is interfering temporarily...
    while count > 0 and (time2 ~= nil and time2 < time) do -- see if possible to not have a fudge factor here. ###2
        LrTasks.sleep( .1 )
        count = count - 1
        time2 = photo:getRawMetadata( 'lastEditTime' )
    end
    if time2 ~= nil and time2 >= time then
        return true
    elseif time2 == nil then
        return false, str:fmt( "Unable to read metadata for ^1 because read validation timed out (never got a read on last-edit-time).", photoPath )
    else
        local isVirt = photo:getRawMetadata( 'isVirtualCopy' ) -- this is deferred for efficient performance in the normal case.
        if isVirt then
            local copyName = photo:getFormattedMetadata( 'copyName' ) -- this is deferred for efficient performance in the normal case.
            return false, str:fmt( "Unable to read metadata for ^1 (^2) because its a virtual copy", photoPath, copyName )
        else
            return false, str:fmt( "Unable to read metadata for ^1 because read validation timed out (last-edit-time never updated).", photoPath )
        end
    end
end



--  Read metadata for selected photos.
--
--  @param              photos - photos to save metadata for, or nil to do all target photos.
--  @param              preSelect - true to have specified photos selected before reading metadata, false if you are certain they are already selected.
--  @param              restoreSelect - true to have previously photo selections restored before returning.
--  @param              alreadyInGridMode - multiple photos requires grid mode, if already in it, for sure, set this to true.
--  @param              service - if a scope in here it will be used for captioning.
--
--  @usage              Until 9/Dec/2011 was only supported on Windows platform - works now in rough fashion on Mac (relies on user action).
--  @usage              Switch to grid mode first if desired, and pre-select target photos.
--  @usage              Uses keystroke emission to do the job.
--  @usage              Includes optional user pre-prompt (before issuing read-metadata keys), and mandatory user post-prompt (to confirm metadata read).
--
--  @return             true iff metadata saved.
--  @return             error message if metadata not read.
--
function Catalog:readMetadata( photos, preSelect, restoreSelect, alreadyInGridMode, service )

    if not photos then
        error( "read-metadata requires photos" )
    end
    
    --[[ 15/Jun/2013: too slow - need batch version
    if app:lrVersion() >= 5 then
        for i, photo in ipairs( photos ) do
            if not photo:getRawMetadata( 'isVirtualCopy' ) then
                photo:readMetadata() -- error if virtual copy
            else
                Debug.pause( "Can't read metadata of virtual copy." ) -- ###2 - remove after assurance that all photos are not virtual copies.
            end
        end
        return true
    end
    --]]
    
    if #photos < 1 then
        error( "check photo count before calling read-metadata" )
    end
    
    local mode
    if WIN_ENV then
        mode = app:getPref( 'readMetadataMode' ) or 'auto'
    else
        mode = 'manual'
    end
    local keySeq = app:getPref( 'readMetadataKeySeq' ) or (WIN_ENV and 'mr') -- no default on Mac - shouldn't be used.
    
    local selPhotos = self:saveSelPhotos()

    if preSelect then
        local photoToBe
        if selPhotos.mostSelPhoto then
            for i, photo in ipairs( photos ) do
                if photo == selPhotos.mostSelPhoto then
                    photoToBe = photo
                    break
                end
            end
        end
        if not photoToBe then
            photoToBe = photos[1]
        end
        local s, m = cat:setSelectedPhotos( photoToBe, photos ) -- make sure the photos to have their metadata read are the ones selected.
        if s then
            app:logVerbose( "Photos selected for metadata read." )
        else
            return false, str:fmt( "Unable to select photos for metadata read, error message: ^1", m )
        end
    end


    local status = false
    local message = "unknown"
    
    if not alreadyInGridMode then    
        local s, m = gui:gridMode( false ) -- attempt to put in grid mode. Although grid-mode is mandatory, consider it not mandatory, so special handling can be done in this context instead.
        if s then
            app:logv( "switched to grid mode" )
        else
            if mode == 'auto' then
                app:show{ warning="Unable to switch to grid mode automatically (error message: '^1'). Metadata read will therefore use manual mode this time. To avoid this prompt in the future, switch to manual mode permanently.",
                    m or "unspecified",
                }
                mode = 'manual'
            else
                app:logv( "unable to switch to grid mode. good thing read-metadata is in manual mode anyway..." )
            end
        end
    else
        app:logv( "Supposedly, library module is already in grid mode for the metadata read." )
    end
    
    if service and service.scope then
        service.scope:setCaption( str:fmt( "Waiting for 'Read Metadata' button click..." ) ) -- not seen if optional prompt is bypassed (confirmation is not optional and scope will be updated at that point).
    end

    local m = {}
    m[#m + 1] = "Metadata must be read to ensure this operation is successful."
    m[#m + 1] = "After you click 'Read Metadata', you should see an extra \"Operation\" pop up in the upper left corner of Lightroom's main window - be looking for it... (if no other operations are in progress, it will say 'Reading Metadata')"
    m[#m + 1] = "If you are in grid mode, and there are no other dialog boxes open, then click 'Read Metadata' to begin. If there are other Lightroom/plugin dialog boxes open, then click 'Let Me Close Dialogs' and then do so (close them).  If you are not in grid mode, or you cant get dialogs to stay closed, then you must click 'Cancel', and retry again after remedying..."
    m[#m + 1] = "Click 'Read Metadata' when ready."
    m = table.concat( m, '\n\n' )
    
    local answer
    repeat
        answer = app:show{ info=m, actionPrefKey="Read metadata", buttons={ dia:btn( 'Read Metadata', 'ok' ), dia:btn( "Let Me Close Dialogs", 'other', false ) } }
        if answer == 'other' then
            LrTasks.sleep( 3 )
        else
            break
        end
    until false
    repeat
        if answer == 'ok' then
            if service and service.scope then
                service.scope:setCaption( str:fmt( "Waiting for 'Read Metadata' confirmation..." ) ) -- only visible after the save metadata operation is complete.
            end
            if mode == 'auto' then
                status, message = app:sendWinAhkKeys( str:fmt( "{Alt Down}^1{Alt Up}", keySeq ) ) -- makes photo look changed again.
                if status then
                    -- enough messages already logged...
                end
            else
                status, message = self:_readMetadataManual( service ) -- ideally the read confirmation would be built in to this method, to avoid double-prompting in the Mac case. ###3
                if status then
                    app:log( "Metadata read - initiated by user." )
                end
            end
            if not status then
                break
            end
            local m = "Wait for the 'Read Metadata' operation to complete, then click 'Read Metadata is Complete'.\n \nYou can tell when its complete by looking in the upper left-hand corner of the main Lightroom window: it will say \"Waiting for 'Read Metadata' confirmation...\" when the operation is complete (or in any case, the progress bar will have stopped progressing and/or an operaton will have dropped out)."
            local answer = app:show{ info=m,
                buttons={ dia:btn( "Read Metadata is Complete", 'ok' ), dia:btn( "Read Metadata Never Started", 'other' ) }
            }
            if answer == 'ok' then -- yes
                status = true
            elseif answer == 'cancel' then -- no
                status, message = false, "Apparently, metadata was not read - most often caused by dialog box interference. Try to eliminate dialog boxes, then attempt again..."
            elseif answer == 'other' then -- dunno
                status, message = nil, "Metadata must be read. Hint: to tell if it gets read, watch the progress indicator in the upper left-hand corner of the main Lightroom window."
            end
        elseif answer == 'cancel' then
            status, message = nil, "User canceled."
        else
            error( "invalid answer: " .. answer )
        end
    until true
    
    if restoreSelect then -- not restored upon program failure.
        cat:restoreSelPhotos( selPhotos )
    end
    return status, message    

end



--- Save selected photos, and related info/settings, for restoral later.
--
--  @usage     call if photo selection will be changed temporarily by plugin.
--             <br>- restore in cleanup handler.
--
--  @return    black box to pass to restoral function.
--
function Catalog:saveSelPhotos()
    -- return { mostSelPhoto = catalog:getTargetPhoto(), selPhotos = catalog:getTargetPhotos() }
    return { mostSelPhoto = catalog:getTargetPhoto(), selectedPhotos = self:getSelectedPhotos(), sources=catalog:getActiveSources(), filterTable=catalog:getCurrentViewFilter() } -- ignore filter name,
        -- since it can't be restored - restoral by name depends on uuid...
end



--- Restore previously saved photo selection and related settings.
--
--  @usage     call in cleanup handler if photo selection was changed temporarily by plugin.
--  @usage     cant deselect photos, so if nothing was selected in filmstrip before restoral, then restoral will just be a no-op.
--
--  @param selPhotos black box, as saved by save-sel-photos (yes: includes selected photos ;-}).
--
function Catalog:restoreSelPhotos( selPhotos )
    if selPhotos == nil then
        return
    end
    local s, m = LrTasks.pcall( function()
        app:logv()
        if selPhotos.sources and #selPhotos.sources > 0 then
            catalog:setActiveSources( selPhotos.sources ) -- restore original sources
            local sources = catalog:getActiveSources()
            if #sources == #selPhotos.sources then
                app:logVerbose( "Active sources restored, should be: " )
                for i, src in ipairs( selPhotos.sources ) do
                    local srcName = self:getSourceName( src )
                    app:logVerbose( srcName )
                end
            else -- some sources were dropped, probably took folders over collections, probably need the opposite.
                app:logWarning( "Unable to restore all active sources." )
                local newSources = {}
                local fldrs = {}
                local colls = {}
                local misc = {}
                for i, src in ipairs( selPhotos.sources ) do
                    local srcName = self:getSourceName( src )
                    local srcType = self:getSourceType( src )
                    app:logVerbose( srcName )
                    if srcType == 'LrFolder' then
                        fldrs[#fldrs + 1] = src
                    elseif srcType == 'LrCollection' then
                        colls[#colls + 1] = src
                    else
                        misc[#misc + 1] = src
                    end
                end
                if #colls > 0 then
                    catalog:setActiveSources( colls )
                    local srcs = catalog:getActiveSources()
                    if #srcs == #colls then
                        if #fldrs > 0 then
                            app:logVerbose( "Folders were dropped." )
                        end
                        if #misc > 0 then
                            app:logVerbose( "Other sources were dropped." )
                        end
                        app:logVerbose( "Collections only are now selected." )
                    else
                        app:logWarning( "Not all previous collection sources could be restored." )
                    end
                else
                    app:logVerbose( "no collections to favor..." )
                end
            end
        end
        if selPhotos.selectedPhotos and #selPhotos.selectedPhotos > 0 then
            self:setSelectedPhotos( selPhotos.mostSelPhoto, selPhotos.selectedPhotos, false, nil ) -- restore remaining selected photos.
            -- not sure what to do if original photos can not be restored, so...
            app:logV( "Selected photos (^1) have been restored.", #(selPhotos.selectedPhotos or {}) )
        end
        if selPhotos.filterTable then
            catalog:setViewFilter( selPhotos.filterTable ) -- restore table values, even if same as before - table may have been recreated with same values,
                -- so its either blind restore, or element-by-element compare...
            app:logVerbose( "Previous lib filter table restored." )
        else
            app:logVerbose( "No previous lib filter table to restore." )
        end
    end )
    return s, m
end



--- Make specified photo most selected, without changing other selections if possible.
--
--  @usage      photo source must already be active, or this won't work.
--  @usage      @3/May/2014 20:50, only plugin (of mine) using this method is SnapTrash.
--
--  @return status true if successful.
--  @return message error message if unsuccessful.
--
function Catalog:selectPhoto( photo )
    local selPhotos = cat:getSelectedPhotos()
    local incl = false
    for i, _photo in ipairs( selPhotos ) do
        if _photo == photo then
            incl = true
            break
        end
    end
    if not incl then
        selPhotos[ #selPhotos + 1 ] = photo
    end
    return cat:setSelectedPhotos( photo, selPhotos )
end



--- Determine if specified photo is buried in collapsed stack in folder of origin.
--
--  @usage *** BEWARE: if source is collection, a photo could still be buried in a stack, and there is no way to detect it.
--
--  @param photo lr-photo in question.
--  @param bm batch (raw) metadata - optional.
--
function Catalog:isBuriedInStack( photo, bm )
    local isStacked = self:getRawMetadata( photo, 'isInStackInFolder', bm ) 
    if not isStacked then
        return false
    end
    -- photo in stack.
    local stackPos = self:getRawMetadata( photo, 'stackPositionInFolder', bm )
    if stackPos == 1 then -- top of stack
        return false
    end
    -- photo in stack, not at top
    local collapsed = self:getRawMetadata( photo, 'stackInFolderIsCollapsed', bm )
    return collapsed -- buried if collapsed.
end



--[[   *** Save as reminder: John Ellis says he's having problem, but I can't reproduce.
--
-- Catalog:getActiveSources()
--
--  @usage same as LrCatalog method, except swaps erroneous entries if present:
--      <br>    catalog.kTemporaryImages and catalog.kLastCatalogExport
--      <br>    see 'http://feedback.photoshop.com/photoshop_family/topics/sdk_catalog_setactivesources_catalog_klastcatalogexport_broken' for more info.
--
function Catalog:getActiveSources()
    local sIn = catalog:getActiveSources()
    local sOut = {}
    for i, v in ipairs( sIn ) do
        if v.getName == nil then -- special
            if v == catalog.kTemporaryImages then
                sOut[i] = catalog.kLastCatalogExport
            elseif v == catalog.kLastCatalogExport then
                sOut[i] = catalog.kTemporaryImages
            else
                sOut[i] = v
            end
        else
            sOut[i] = v
        end
    end
    return sOut
end
--]]



--- Set active sources, and verify all were properly set.
--
--  @usage I think Lr can set any source which it can read (not sure at the moment), but it may not be able to set computed sources, like catalog and publish service, which act as collection sets in some contexts.
--
--  @param sources array of sources, must be settable via set-active-sources (e.g. catalog won't work, nor publish service - "special" sources should work though).
--
--  @return status true iff all specified sources are active.
--  @return error-message explanation if not.
--
function Catalog:setActiveSources( sources )
    local try = 1
    local sts, msg
    repeat
        sts, msg = true, "Unable to make all specified sources active."
        local lookup = {}
        catalog:setActiveSources( sources ) -- restore original sources
        local asources = catalog:getActiveSources()
        if #asources == #sources then
            for i, src in ipairs( asources ) do
                lookup[src] = true
            end
            app:logVerbose( "Active sources set to: " )
            for i, src in ipairs( sources ) do
                local srcName = self:getSourceName( src )
                if not lookup[src] then
                    sts, msg = false, "Source not settable: " .. srcName
                    break
                end
                app:logVerbose( srcName )
            end
        else -- some sources were dropped, probably took folders over collections, probably need the opposite.
            --app:logWarning( "Unable to restore all active sources." )
            sts = false
        end
        if sts then
            return true
        else
            try = try + 1
            if try <= 3 then
                LrTasks.sleep( .1 )
            else
                break
            end
        end
    until false
    return false, msg
end



--- Clears view filter so all photos will be showing.
--
--  @param  noYield (boolean, default false) if true, will return immediately, but be forewarned: this function probably needs some "settling" time.
--    <br>  if false, this method may yield or sleep as this method deems appropriate.
--
--  @usage  Dunno how to control global lock who-de-kai.
--
function Catalog:clearViewFilter( noYield )
    catalog:setViewFilter{ -- equivalent of 'None'.
        columnBrowserActive = false, -- metadata
        filtersActive = false, -- attributes
        searchStringActive = false, -- text
    }
    if not noYield then
        LrTasks.sleep( .1 ) -- needs a moment to settle in. dunno if yield sufficient, but sleep seems safer. ###2
    end
end



--- Make specified photo the *only* photo selected, whether source is active or not.
--
--  @usage      present implementation satisfies by adding folder to source, if necessary.<br>
--
--  @param      photo (lr-photo, generally required) will be obtained from photo-path if it is passed.
--  @param      photoPath (string, optional) will be obtained from photo metadata if not passed.
--
--  @return     status, but NOT error message - logs stuff as it goes...
--
function Catalog:assurePhotoIsSelected( photo, photoPath )
    if photoPath and not photo then
        photo = catalog:findPhotoByPath( photoPath )
    elseif photo and not photoPath then
        photoPath = photo:getRawMetadata( 'path' )
    end
    if photo then
        
        catalog:setSelectedPhotos( photo, { photo } ) -- note: this will set the photo selection, but it won't necessarily *be* selected (in UI) after calling,
            -- especially, as example, immediately after importing, before Lr has had a chance to fully load, in which case, beware - handle appropriately in calling context.
        if catalog:getTargetPhoto() ~= photo then -- photo not selected (not visible or not in filmstrip).
            local folderPath = LrPathUtils.parent( photoPath )
            local lrFolder = cat:getFolderByPath( folderPath ) -- method changed in 2014, if OK by 2016 - delete comment.
            local found = false
            if lrFolder then
            
                -- Note: No way to assure photo is selected, unless source becomes exclusive.
                
                local s, m = catalog:setActiveSources{ lrFolder } -- Note: calling context must restore active sources if need be.
                if s then                    
                    app:logVerbose( "Set lr-folder as active source: ^1", folderPath )
                else
                    app:logW( "Unable to assure photo is selected - unable to set active source to folder containing photo." )
                    return false -- can't assure photo selected if can't assure source is set.
                end
                catalog:setSelectedPhotos( photo, { photo } )
    			if catalog:getTargetPhoto() ~= photo then -- photo not selected (not visible or not in filmstrip).
    				app:logVerbose( "Unable to select photo (^1) in newly set source folder (^2)", photoPath, lrFolder:getName() ) -- got this error once even though it was selected.
    			    -- may be due to stackage or lib filter.
    			else
    				app:logInfo( "Photo in newly selected source now selected: " .. photoPath )
    				return true
    			end
    			
            else
                app:logW( "Unable to locate folder (in catalog) by path: ^1", folderPath )
                return false
            end
        else -- selected properly already.
            app:logVerbose( "Photo already selected: ^1", photoPath )
            return true
        end
    else
        app:logWarning( "No photo for path: " .. photoPath )
        return false
    end
    -- fall-through => not able to select existing photo.
    local isStacked = photo:getRawMetadata( 'isInStackInFolder' )
    if isStacked then
        local stackPos = photo:getRawMetadata( 'stackPositionInFolder' )
        if stackPos == 1 then
            app:logVerbose( "Unable to select photo that is top of stack: " .. photoPath )
        else
            local collapsed = photo:getRawMetadata( 'stackInFolderIsCollapsed' )
            if collapsed then
                app:logWarning( "Photo can not be selected when buried in collapsed stack: " .. photoPath )
                return false -- impossible to select, despite lib filter setting.
            else
                app:logVerbose( "Unable to select stacked photo despite not being collapsed in folder of origin: " .. photoPath ) -- may still be due to lib filter.
            end
        end
    else
        app:logVerbose( "Unable to select photo that is not in a stack: " .. photoPath )
    end
    -- fall-through => unable to select photo not buried in stack, try for lib-filtering next.
    self:clearViewFilter()
    -- I thought no delay needed in previous Lr versions, but now (@Lr5.2RC) it seems there needs to be a delay.
    local timebase = app:getPref( 'timebase' )
    if timebase then
        dbgf( "Delay (in seconds) after lib filter cleared, in hopes to obtain requisite photo selection: ^1", timebase )
    else
        timebase = .1
        dbgf( "Unable to obtain timebase, from which to derive delay - time to wait lib filter cleared, in hopes to obtain requisite photo selection - using a default delay (based on guess): ^1 second.", timebase )
    end
    LrTasks.sleep( timebase ) -- change text logged above if delay not equal to timebase.
    -- Note: filter should be restored externally after selected photo processed, when appropriate.
    catalog:setSelectedPhotos( photo, { photo } )
	if catalog:getTargetPhoto() ~= photo then -- photo not selected (not visible or not in filmstrip).
		app:logWarning( "Unable to select photo (^1) even without lib filter", photoPath )
		return false
	else
		app:log( "Photo selected by lifting the lib filter: ^1", photoPath )
		return true
	end
end



--- Set catalog metadata property if not already.
--
--  @param      name (string, required) property name
--  @param      value (string | date | number | boolean, required) property value
--  @param      validate (boolean, default=false) if true, will read property back and compare to that which was set (left over from problem times - not necessary now, but won't hurt much either..).
--
--  @usage      *** This is for setting catalog properties, NOT for setting photo properties (use metadata-manager for that).
--  @usage      Will wrap with async task if need be (in which case BEWARE: returns are always nil, and property is not guaranteed).<br>
--              This mode appropriate for calling from plugin init module only.
--  @usage      Will wrap with catalog access if need be.
--  @usage      Reminder: you can only set for current plugin - you can read for any plugin if you have its ID.
--  @usage      No errors are thrown - see status and error message for results.
--  @usage      *** property whose name is photo-uuid is reserved for background task.
--
--  @return     nothing. throws error if problem.
--
function Catalog:setPropertyForPlugin( name, value, validate )

    if self.catKey == nil then
        self.catKey = str:pathToPropForPluginKey( catalog:getPath() )
    end
    local prefName = self.catKey .. "_" .. name
    -- local sts, errm = LrTasks.pcall( app.setGlobalPref, app, prefName, value ) -- ###2 what error might there be?
    app:setGlobalPref( prefName, value ) -- no sense in trapping an error when all you're going to do is re-throw it anyway.
    if validate then -- cheap insurance for critical parameters.
        local _value = app:getGlobalPref( prefName )
        if _value == value then
            -- good
        else
            app:error( "Unable to set catalog property for plugin, name: '^1', value: '^2'" .. str:to( name ), str:to( value ) )
        end
    -- else nuthin'...
    end
    return true -- to satisfy some straggling plugins that are still checking return code.

end



--- Get catalog metadata property.
--
--  @param      name (string, required) property name
--
--  @usage      Gets property for plugin tied to catalog.
--  @usage      Present implementation uses Lightroom preferences and never fails.
--
--  @return     value (any) or nil.
--
function Catalog:getPropertyForPlugin( name )

    if self.catKey == nil then
        self.catKey = str:pathToPropForPluginKey( catalog:getPath() )
    end
    local prefName = self.catKey .. "_" .. name
    return app:getGlobalPref( prefName )

end



--- Get photo name or path which includes copy name when appropriate.
--
--  @usage *** deprecated - use get-photo-name-disp instead (I like the simpler name, but I recommend migrating to a metadata caching scheme).
--
--  @param photo (LrPhoto, required) photo
--  @param fullPath (boolean, default = false) true for full-path, else filename only as base.
--  @param rawMeta (table, optional) batched raw metadata, or metadata cache.
--  @param fmtMeta (table, optional) batched fmt metadata, or nil (cache may include formatted metadata).
--
function Catalog:getPhotoName( photo, fullPath, rawMeta, fmtMeta )

    if rawMeta and rawMeta[photo] then
        rawMeta = rawMeta[photo]
    -- else raw-meta is nil or per-photo already.
    end
    if fmtMeta and fmtMeta[photo] then
        fmtMeta = fmtMeta or fmtMeta[photo]
    -- else fmt-meta is nil or per-photo already.
    end

    local isVirt -- boolean
    if rawMeta then
        isVirt = rawMeta.isVirtualCopy
    end
    if isVirt == nil then
        isVirt = photo:getRawMetadata( 'isVirtualCopy' )
    end
    local photoName = ( rawMeta and rawMeta.path ) or photo:getRawMetadata( 'path' )
    if fullPath then
        -- continue
    else
        photoName = LrPathUtils.leafName( photoName ) -- dunno if fmt-meta file-name is better, but it seems I always have the path so...
    end
    if isVirt then
        local copyName = fmtMeta and fmtMeta.copyName or photo:getFormattedMetadata( 'copyName' )
        photoName = str:fmt( "^1 (^2)", photoName, copyName )
    else
        -- continue
    end
    return photoName

end



--- Get photo name or path which includes copy name when appropriate.
--
--  @param photo (LrPhoto, required) photo
--  @param fullPath (boolean, default = false) true for full-path, else filename only as base.
--  @param metaCache (Cache, optional) Metadata cache.
--
function Catalog:getPhotoNameDisp( photo, fullPath, metaCache )

    local isVirt = lrMeta:getRaw( photo, 'isVirtualCopy', metaCache ) -- accept uncached.
    local photoName = lrMeta:getRaw( photo, 'path', metaCache ) -- ditto.
    if fullPath then
        -- continue
    elseif photoName ~= nil then
        photoName = LrPathUtils.leafName( photoName ) -- dunno if fmt-meta file-name is better, but it seems I always have the path so...
    else
        app:error( "photo has no path" )
    end
    if isVirt then
        local copyName = lrMeta:getFmt( photo, 'copyName', metaCache )
        photoName = str:fmt( "^1 (^2)", photoName, copyName )
    -- else - continue
    end
    return photoName

end



--- Create multiple virtual copies.
--
--  @param params (table) elements:
--      <br>photos (array, default = selectedPhotos) of LrPhoto's.
--      <br>copyName (string, default = "Virtual Copy" if Lr5, else "Copy N").
--      <br>call (Call, required) call with context.
--      <br>assumeGridView (boolean, default = false )
--      <br>cache (LrMetadataCache, default = nil ) cache for base photo metadata.
--      <br>verify (boolean, default = true ) set false to subvert copy verification.
--
--  @return copies (array of LrPhoto) iff success.
--  @return errMsg (string) non-empty iff unsuccessful.
--
function Catalog:createVirtualCopies( params )
    local photos = params.photos or self:getSelectedPhotos()
    if #photos == 0 then
        return nil, "No photos are selected - no virtual copies can be made."
    end
    app:callingAssert( params.copyNames == nil, "copy name must be same for all - pass copyName instead of copyNames." )
    local copyName = params.copyName or "Virtual Copy" -- default copy name differs in Lr5 versus Lr4.
    local call = params.call or error( "no call" )
    local assumeGridView = params.assumeGridView
    local cache = params.cache
    local verify = bool:booleanValue( params.verify, true ) -- as passed, defaulting to true.
    if not assumeGridView and #photos > 1 then -- if only one photo, grid mode is not required.
        local s, m = gui:gridView( true ) -- mandatory, otherwise 
        if s then
            -- good
        else
            return nil, m
        end
    end
    if app:lrVersion() >= 5 then
        local s, m = cat:setSelectedPhotos( nil, photos, true, cache )
        if s then
            local copies = catalog:createVirtualCopies( copyName )
            if verify then
                if #copies == #photos then
                    for i, copy in ipairs( copies ) do
                        if not copy:getRawMetadata( 'isVirtualCopy' ) then
                            return nil, "Expected virtual copies only"
                        end
                    end
                    return copies
                else
                    return nil, "Expected one virtual copy per photo selected"
                end
            else
                return copies -- calling context should verify upon return, if it's smart.
            end
        else
            return nil, m
        end
    else
        local copies = {}
        for i, photo in ipairs( photos ) do
            local copy, errm = self:createVirtualCopy( photo, i == 1 ) -- prompt on first one.
            if copy then
                copies[#copies + 1] = copy
            else
                return nil, errm
            end
        end
        if #copies > 0 and params.copyName then
            local s, m = cat:update( 30, "Set Copy Names (Lr4)", function( context, phase )
                for i, copy in ipairs( copies ) do
                    copy:setRawMetadata( 'copyName', params.copyName )
                end
            end )
            if s then
                app:logv( "Updated copy names" )
            else
                return nil, m            
            end
        end
        return copies
    end
end



--- Creates a virtual copy of one photo.
--
--  @param      photo (LrPhoto, default nil) Photo object to create virtual copy of, or nil to create copy of most selected photo.
--  @param      prompt (boolean, default false) Pass true to prompt user about this stuff, or false to let 'er rip and take yer chances (definitive status will be returned).
--
--  @usage      Note: this is used to create a single virtual copy in both Lr4 and Lr5 implementations. Multiple virtual copies can be created using the new Lr5 method.
--              <br>In Lr4, virtual copy creation itself uses scripting; in Lr5 (and Lr4) switching to grid mode requires scripting (for smooth operation anyway) I did build
--              <br>in some logic for manual user intervention/assurance, but it's testing has gotten less over the years.
--  @usage      Must be called from asynchronous task.
--  @usage      No errors are thrown - check return values for status, and error message if applicable.
--  @usage      Can be used to create multiple copies, by calling in a loop - but is very inefficient for doing multiples like that.<br>
--              if you want multiples, you should code a new method that selects all photos you want copied, then issues the Ctrl/Cmd-'<br>
--              And for robustness, the routine should check for existence of all copies before returning with thumbs up.
--  @usage      Its up to calling context to assure Lightroom is in library or develop modules before calling.
--  @usage      Hint: calling context can restore selected photos upon return, or whatever...
--
--  @return     photo-copy (lr-photo) if virtual copy successfully created.
--  @return     error-message (string) if unable to create virtual copy, nil if user canceled.
--
function Catalog:createVirtualCopy( photo, prompt )
    local photoCopy, msg
    app:call( Call:new{ name="Create Virtual Copy", async=false, main=function( call )
        repeat
            if not photo then
                photo = catalog:getTargetPhoto()
            end
            if not photo then
                error( "No photo to create virtual copy of." )
            end
            local masterPhoto
            local photoPath = photo:getRawMetadata( 'path' )
            local isVirtualCopy = photo:getRawMetadata( 'isVirtualCopy' )
            local copyName = photo:getFormattedMetadata( 'copyName' )
            if isVirtualCopy then
                masterPhoto = photo:getRawMetadata( 'masterPhoto' )
                photoPath = photoPath .. " (" .. copyName .. ")"
            else
                masterPhoto = photo
            end
            
            local copies = masterPhoto:getRawMetadata( 'virtualCopies' )
            local lookup = {}
            for i, copy in ipairs( copies ) do
                lookup[copy] = true
            end

            -- local s, m = cat:selectOnePhoto( photo ) -- no big penalty if its already selected...
            -- highly unlikely this part will fail since it was selected to begin with, but cheap insurance...
            local s = cat:assurePhotoIsSelected( photo, photoPath ) -- can never be to sure...
            if s then
                app:logVerbose( "Photo selected for virtual copy creation: ^1", photoPath )
            else
                --return false, str:fmt( "Unable to select photo for virtual copy creation, error message: ^1", m ) -- m includes path.
                    -- no way it'll work if cant select it.
                return false, str:fmt( "Unable to select photo for virtual copy creation (see log file for details), path: ^1", photoPath )
                    -- no way it'll work if cant select it.
            end
            
            if prompt then
                repeat
                    local answer = app:show{
                        info = "^1 is about to attempt creation of a virtual copy of ^2\n\nFor this to work, there must not be any dialog boxes open in Lightroom, and focus must not be in any Lightroom text field.\n\nClick 'OK' to proceed, and check the 'Don\'t show again' box to suppress prompt in the future, or click 'Give Me a Moment' to hide this dialog box temporarily so you can clear the way, or click 'Cancel' to abort.",
                        subs = { app:getAppName(), photoPath },
                        buttons = { dia:btn( "OK", 'ok' ), dia:btn( "Give Me a Moment", 'other', false ) },
                        actionPrefKey="Create virtual copy" }
                    if answer == 'ok' then
                        break
                    elseif answer == 'other' then
                        app:sleepUnlessShutdown( 5 ) -- 5 seconds seems about right.
                    elseif answer == 'cancel' then
                        call:cancel() -- note: this only cancels this wrapper not calling wrapper.
                        photoCopy, msg = nil, nil
                        return
                    else
                        error( "bad answer: " .. str:to( answer ) )
                    end
                until false
            end
            local count = masterPhoto:getRawMetadata( 'countVirtualCopies' )
            local m
            -- note: since Lr5's new method requires library module to work, which requires sending-keys to assure, it's hardly an improvement to use it, in auto-mode anyway.
            -- that said, it would support a manual mode (user promises it's in library mode, then plugin does the rest) - food for thought (but then again, one could just ask user to create virtual copy instead - limited value..).
            if WIN_ENV then
                s, m = app:sendWinAhkKeys( "{Ctrl Down}'{Ctrl Up}" ) -- include post keystroke yield.
            else
                s, m = app:sendMacEncKeys( "Cmd-'" )
            end
            if not s then
                photoCopy, msg = nil, m
                return
            end
            local newCount = masterPhoto:getRawMetadata( 'countVirtualCopies' )
            local iters = 30 -- allow 3 seconds.
            while newCount <= count and iters > 0 and not shutdown do
                LrTasks.sleep( .1 )
                iters = iters - 1
                newCount = masterPhoto:getRawMetadata( 'countVirtualCopies' )
            end
            local sts = newCount > count
            if sts then
                local newCopies = masterPhoto:getRawMetadata( 'virtualCopies' )
                for i, photo in ipairs( newCopies ) do
                    if not lookup[photo] then
                        photoCopy = photo
                        break
                    end
                end
                if not photoCopy then
                    msg = "Virtual copy created, but it can't be found."
                end
            else
                msg = "Unable to create virtual copy of " .. photoPath .. " for unknown reason (hint: Lightroom should have been in (or gone to) Library or Develop module when the attempt was made).\n \nAlso, if any dialog boxes came up or Lr lost focus - whilst virtual copy was being created - that could very well be the cause of the problem (dialog boxes and lost focus interfere with virtual copy creation, and other like operations)."
            end
        until true
    end, finale=function( call, status, message )
        if not status then
            msg = message
        end
    end } )
    return photoCopy, msg
end



--- Determine if specified metadata columns are active in specified lib view filter.
--
--  @param metaIds array of strings
--  @param filter view filter
--
--  @return true iff is active.
--
function Catalog:isMetadataColumnActive( metaIds, filter )
    filter = filter or catalog:getCurrentViewFilter()
    if filter.columnBrowserActive then -- metadata filtering enabled.
        -- set false if metadata is on list, since must accrue from sources in this case.
        for _, item in ipairs( metaIds ) do
            -- if item matches, then clear exclude-if-filtered.
            for i, t in ipairs( filter.columnBrowserDesc ) do
                local name = LrPathUtils.extension( t.criteria )
                if name == item then
                    if t.criteria:find( _PLUGIN.id ) then -- ###3 probably finding as plain text would be better (dot's being interpreted as "any char"), but afraid to change without more scrutiny/testing..
                        --Debug.logn( "metadata match", item, name )
                        return true
                    else
                        --Debug.logn( "dup name", t.criteria )
                    end
                else
                    --Debug.logn( item, name )
                end
            end
        end
    end
end



--- Be sure to open the cache before a run, so results are cached - more efficient if sources overlap.
function Catalog:openPhotosInSourceCache()
    self.photosInSource = {} -- cached mode implemented mid-Dec/2014 - @22/Dec/2014 19:29 seems to be working as intended.
end

--- Be sure to close cache after a run, so other callers don't end up getting un-fresh cached data.
function Catalog:closePhotosInSourceCache()
    self.photosInSource = nil
end



--- Get array of photos in any specified source.
--  @usage default is to return immediate child photos only, whether top or buried..
--  @param anySource any source.
--  @param assumeSubfoldersToo false => not child sources
--  @param ignoreIfNotTop true => limit to those at top of folder stack.
--  @param ignoreIfBuried true => limit to those not buried in collapsed folder stack.
function Catalog:getPhotosInSource( anySource, assumeSubfoldersToo, ignoreIfNotTop, ignoreIfBuried )
    --if assumSubfoldersToo == nil then assumeSubfoldersToo = false end
    --if ignoreIfNotTop == nil then ignoreIfNotTop = false end
    --if ignoreIfBuried == nil then ignoreIfBuried = false end
    local photosInSourceCached
    if self.photosInSource and self.photosInSource[anySource] then
        photosInSourceCached = self.photosInSource[anySource]
        if app:isAdvDbgEna() then
            -- proceed to get photos in source using other/original means, and compare to cached set.
        else
            assert( #photosInSourceCached == 0 or type( photosInSourceCached[1] ) == 'table', "?" ) -- ###1
            return photosInSourceCached
        end
    -- else compute
    end
    local photoDict = {}
    local function addToDict( source, photos )
        local bm
        if ignoreIfBuried then
            bm = cat:getBatchRawMetadata( photos, { 'isInStackInFolder', 'stackPositionInFolder', 'stackInFolderIsCollapsed' } )
        elseif ignoreIfNotTop then
            bm = cat:getBatchRawMetadata( photos, { 'isInStackInFolder', 'stackPositionInFolder' } ) -- not sure what stack-pos metadata might be if not in stack.
        end
        local photos2 = {}
        for i, photo in ipairs( photos ) do
            if ignoreIfNotTop then
                local isTop
                if bm[photo].isInStackInFolder then
                    isTop = bm[photo].stackPositionInFolder == 1
                else -- not in a stack
                    isTop = true -- for current purpose.
                end
                if isTop then
                    photoDict[photo] = true
                    photos2[#photos2 + 1] = photo
                -- else ignore
                end
            elseif ignoreIfBuried then
                local isBuried = cat:isBuriedInStack( photo, bm )
                if isBuried then
                    --
                else
                    photoDict[photo] = true
                    photos2[#photos2 + 1] = photo
                end
            else
                photoDict[photo] = true
                photos2[#photos2 + 1] = photo
            end
        end
        if self.photosInSource then
            self.photosInSource[source] = photos2
        end
    end
    local function loadPhotosFromSource( source )
        if source.getPhotos then
            if self.photosInSource and self.photosInSource[source] then -- pre-validated photos already in cache for specified source.
                for i, p in ipairs( self.photosInSource[source] ) do -- ###1 perhaps not optimal coding..
                    photoDict[p] = true -- add cached photos to accumulating dictionary.
                end
            else
                local photos = source:getPhotos( assumeSubfoldersToo ) or {} -- ' or {}' added 16/Sep/2013 22:32 (in honor of Lr bug).
                    -- not confident in this method yet, see get-filmstrip-photos. ###3
                addToDict( source, photos ) -- assure no duplication, in case overlapping sources.
            end
        elseif source.getChildren then
            local children = source:getChildren()
            for i, child in ipairs( children ) do
                loadPhotosFromSource( child )
            end
        elseif source.type then
            app:logWarning( "Unrecognized source type: " .. source:type() )
        else
            app:logWarning( "Unrecognized source: " .. str:to( source ) )
        end
    end
    loadPhotosFromSource( anySource )
    local photosInSourceComputed = tab:createArray( photoDict )
    if app:isAdvDbgEna() then
        if photosInSourceCached then
            local eq, x = tab:isEquivalent( photosInSourceCached, photosInSourceComputed )
            if not eq then
                error( x )
            -- else remove this non-sense after proven.###1
            end
        -- else first time computation
        end
    end
    assert( #photosInSourceComputed == 0 or type( photosInSourceComputed[1] ) == 'table', "?" )
    return photosInSourceComputed
end



--  @20/Dec/2013 15:01, I thinks missing-in-action is my only plugin using this method.
--
--- Get list complete list of photos in selected sources, unless buried in stack (optional).
--
--  @usage      Beware: this function *may* not be perfect e.g. may not work if sources are special Lr collections, and not sure about how reliable is the assume-subfolders field, nor ignore-if-buried - you have been warned.
--  @usage      deprecated
--
--  @param      assumeSubfoldersToo (boolean, default = true ) will get folders in subfolders too. Note: this only matches the user's filmstrip if he/she is also viewing subfolders, thus the term "assume".
--  @param      ignoreIfBuried (boolean, default = true ) will exclude photos if not top of stack (or unstacked).
--  @param      metaIds (array of strings, default = nil ) IDs of metadata items in this plugin that if active, means filtered set should be returned (see example plugin: MissingInAction).
--
--  @return      photos (array of LrPhoto objects) - may be empty, but never nil (should not throw any errors).
--  @return      excludeIfFiltered (boolean), not always returned. hmm... ###3
--
function Catalog:getSourcePhotos( assumeSubfoldersToo, ignoreIfBuried, metaIds )
    if assumeSubfoldersToo == nil then
        assumeSubfoldersToo = true -- ###3 departure from get-filmstrip-photos.
    end
    if ignoreIfBuried == nil then
        ignoreIfBuried = true
    end
    local excludeIfFiltered
    if metaIds ~= nil then
        excludeIfFiltered = not self:isMetadataColumnActive( metaIds )
    else
        excludeIfFiltered = true
    end
    if excludeIfFiltered then
        local photo = catalog:getTargetPhoto()
        local photos = catalog:getTargetPhotos()
        if photo == nil or #photos == 1 then
            app:logVerbose( "Returning multiple selected or all photos visible in filmstrip" )
            return catalog:getMultipleSelectedOrAllPhotos()
        else -- proceed
       
        end
    else
        -- proceed to accrue photos from source arrays.
    end
    app:logVerbose( "Accrueing photos from sources." )
    
    local sources = catalog:getActiveSources()
    if sources == nil or #sources == 0 then
        return {}, excludeIfFiltered
    end
    local photoDict = {} -- lookup
    local filmstrip = {} -- array
    local function addToDict( photos )
        local bm
        if ignoreIfBuried then
            bm = cat:getBatchRawMetadata( photos, { 'isInStackInFolder', 'stackPositionInFolder', 'stackInFolderIsCollapsed' } )
        end
        for i, photo in ipairs( photos ) do
            if ignoreIfBuried then
                local isBuried = cat:isBuriedInStack( photo, bm )
                if isBuried then
                    --
                else
                    photoDict[photo] = true
                end
            else
                photoDict[photo] = true
            end
        end
    end
    local function getPhotosFromSource( source )
        if source.getPhotos then
            local photos = source:getPhotos( assumeSubfoldersToo ) or {} -- or {} added 16/Sep/2013 22:32 (in honor of Lr bug).
                -- not confident in this method yet, see get-filmstrip-photos. ###3
            addToDict( photos ) -- assure no duplication, in case overlapping sources.
            return
        elseif source.getChildren then
            local children = source:getChildren()
            for i, child in ipairs( children ) do
                getPhotosFromSource( child )
            end
        elseif source.type then
            app:logWarning( "Unrecognized source type: " .. source:type() )
        else
            app:logWarning( "Unrecognized source: " .. str:to( source ) )
        end
    end
    local sources = catalog:getActiveSources()
    for i, source in ipairs( sources ) do
        getPhotosFromSource( source )                            
    end    
    for k, v in pairs( photoDict ) do
        filmstrip[#filmstrip + 1] = k
    end
    return filmstrip, excludeIfFiltered
end



--- Get list of photos in filmstrip *** DEPRECATED in favor of getVisiblePhotos, which could stand to be augmented with parameters like includeIfBuried... - exclude source would not fit, and perhaps should be handled as special case in 1 plugin using it: MissingInAction.
--                                      consider modifying other plugins to use it.
--
--  @usage *** DEPRECATED.
--  @usage this function *may* not be perfect, and may return photos even if excluded by lib filter or buried in stack.
--      <br>    presently its working perfectly, but I don't trust it, and neither should you!?
--      <br>    *** originally: function Catalog:getFilmstripPhotos( assumeSubfoldersToo, bottomFeedersToo )
--
--  @return      array of photos - may be empty, but never nil (should not throw any errors).
--
function Catalog:getFilmstripPhotos( assumeSubfoldersToo, ignoreIfBuried, excludeSource )
    local subfolders
    if assumeSubfoldersToo == nil then
        -- subfolders = false -- nil means true otherwise.
        subfolders = true -- nil means true otherwise. - true is not a bad default though.
    end
    if ignoreIfBuried == nil then
        ignoreIfBuried = true
    end
    local targetPhoto = catalog:getTargetPhoto()
    if targetPhoto == nil and not excludeSource then
        return catalog:getTargetPhotos()
    end
    local sources = catalog:getActiveSources()
    if sources == nil or #sources == 0 then
        return {}
    end
    local photoDict = {} -- lookup
    local filmstrip = {} -- array
    local function addToDict( photos )
        local bm
        if ignoreIfBuried then
            bm = cat:getBatchRawMetadata( photos, { 'isInStackInFolder', 'stackPositionInFolder', 'stackInFolderIsCollapsed' } )
        end
        for i, photo in ipairs( photos ) do
            if ignoreIfBuried then
                local isBuried = cat:isBuriedInStack( photo, bm )
                if isBuried then
                    --
                else
                    photoDict[photo] = true
                end
            else
                photoDict[photo] = true
            end
        end
    end
    local function getPhotosFromSource( source )
        if source.getPhotos then
            local photos = source:getPhotos( subfolders ) or {} -- or {} added 16/Sep/2013 22:32 (in honor of Lr bug).
                -- reminder: nil parameter behaves as true, not false.
            --local photos = source:getPhotos() -- At the moment, this function is doing exactly what I want: returning the photos as they contribute to filmstrip,
            -- and excluding bottom feeders - its ignoring the "include-children" parameter. I could have sworn it was previously attending to said parameter as documented.
            -- Although I'm glad it is behaving as it is, I fear problems that go away by themselves will return by themselves. ###3 - good for now I guess...
            addToDict( photos ) -- assure no duplication, in case overlapping sources.
            return
        elseif source.getChildren then
            local children = source:getChildren()
            for i, child in ipairs( children ) do
                getPhotosFromSource( child )
            end
        elseif source.type then
            app:logWarning( "Unrecognized source type: " .. source:type() )
        else
            app:logWarning( "Unrecognized source: " .. str:to( source ) )
        end
    end
    local sources = catalog:getActiveSources()
    -- local sc = 0
    for i, source in ipairs( sources ) do
        -- sc = sc + 1
        if excludeSource and source == excludeSource then
            -- Debug.logn( cat:getSourceName( source )
        else
            getPhotosFromSource( source )                            
        end
    end    
    for k, v in pairs( photoDict ) do
        filmstrip[#filmstrip + 1] = k
    end
    return filmstrip
end




--- Get photos visible in filmstrip (as filtered, as stacked, ... ).
--
--  @usage without disturbing users's present selection.
--  @usage *** BEWARE: adds 'Undo Select' item to undo stack, so DO NOT call from background task.
--
--  @param params parameter table:
--      <br>    selectedPhoto (LrPhoto, default=nil) catalog:getTargetPhoto() - in case already available in calling context.
--      <br>    selectedPhotos (array of LrPhoto, default=nil) catalog:getTargetPhotos() - ditto.
--      <br>    metadataCache (LrMetadata::Cache, optional) metadata cache (see code below for expected members).
--      <br>    includeIfBuried (boolean, default=false) visible only? or those underneath in collapsed stacks too.
--
--  @return visiblePhotos (array) never nil, but may be empty (e.g. virgin catalog)
--
function Catalog:getVisiblePhotos( params )
    -- works in Lr3+4+5/win7; ###1 test on Mac.
    params = params or {}
    local selectedPhoto = params.selectedPhoto or catalog:getTargetPhoto()
    local selectedPhotos = params.selectedPhotos or catalog:getTargetPhotos()
    local visiblePhotos
    if selectedPhoto then
        catalog:setSelectedPhotos( selectedPhoto, {} )
        local allVisiblePhotos = catalog:getMultipleSelectedOrAllPhotos()
        catalog:setSelectedPhotos( selectedPhoto, selectedPhotos )
        --Debug.pause( #allVisiblePhotos, #selectedPhotos, #selectedPhotos == #catalog:getTargetPhotos() ) 
        visiblePhotos = allVisiblePhotos
    else
        visiblePhotos = selectedPhotos
    end
    if not params.includeIfBuried or #visiblePhotos == 0 then
        return visiblePhotos
    end
    -- fall-through => include underlings.
    local cache = params.metadataCache or lrMeta:createCache{ photos=visiblePhotos, rawIds={ 'isInStackInFolder', 'stackInFolderIsCollapsed', 'stackInFolderMembers', } }
    local buriedPhotos = {}
    for i, photo in ipairs( visiblePhotos ) do
        repeat                
            if not lrMeta:getRaw( photo, 'isInStackInFolder', cache ) then
                break
            end
            -- photo is in stack
            if not lrMeta:getRaw( photo, 'stackInFolderIsCollapsed', cache ) then
                break
            end
            -- stack is collapsed, therefore it is top of stack (actually, that is only true if source is folder - viewing collection, one could view underlings of collapsed folder stacks).
            local stack = lrMeta:getRaw( photo, 'stackInFolderMembers', cache )
            --assert( stack[1] == photo, "tos?" ) - invalid assertion (see comment above).
            for j, stackedPhoto in ipairs(stack) do
                if photo ~= stackedPhoto then
                    buriedPhotos[#buriedPhotos + 1] = stackedPhoto
                end
            end
        until true
    end
    tab:appendArray( visiblePhotos, buriedPhotos ) -- returns promptly if no buried photos.
    return visiblePhotos
end



--  @20/Dec/2013 15:04, only used internally.
function Catalog:getCollectionSet( name, parent )
    parent = parent or catalog
    local children = parent:getChildCollectionSets()
    local _name = LrStringUtils.lower( name )
    for i, set in ipairs( children ) do
        if LrStringUtils.lower( set:getName() ) == _name then -- note: collection sets always have a get-name method.
            return set
        end
    end
end



--- Get collection *or* smart collection of specified name in specified parent, if it exists.
--
function Catalog:getCollection( name, parent )
    parent = parent or catalog
    local children = parent:getChildCollections()
    local _name = LrStringUtils.lower( name )
    for i, coll in ipairs( children ) do
        local collName = cat:getSourceName( coll )
        if LrStringUtils.lower( collName ) == _name then
            return coll
        end
    end
end



--- Case insensitve version of like-named lr-catalog method.
--
function Catalog:createCollectionSet( name, parent, returnExisting )
    local existing = self:getCollectionSet( name, parent )
    if existing then
        if returnExisting then
            return existing
        -- else return nil
        end
    else
        return catalog:createCollectionSet( name, parent, returnExisting )        
    end
end



--- Case insensitve version of like-named lr-catalog method.
--
function Catalog:createCollection( name, parent, returnExisting )
    local existing = self:getCollection( name, parent ) -- returns collection if one already exists with matching name (case insensitively).
    if existing then
        if not existing:isSmartCollection() then
            if returnExisting then
                return existing
            else
                return nil -- as specified in SDK api doc - this means "can't create since already created".
            end
        else -- exists, but not a normal collection.
            -- the documentation is not clear what to do if collection exists with same name, but different type.
            local existingName = cat:getSourceName( existing )
            app:error( "Can not create regular collection with specified name (^1), since smart collection already exists with that name (^2)", name, existingName )
            -- I assume there is gonna be an error at some point no matter, so may as well be clear up front what the problem is.
        end
    else
        return catalog:createCollection( name, parent, returnExisting )
    end
end



--- Case insensitve version of like-named lr-catalog method.
--
function Catalog:createSmartCollection( name, smarts, parent, returnExisting )
    local existing = self:getCollection( name, parent )
    if existing then
        if existing:isSmartCollection() then
            if returnExisting then
                return existing
            else
                return nil -- as specified in SDK api doc - I think this means can't create since already created.
            end
        else -- exists as normal collection.
            -- the documentation is not clear what to do if collection exists with same name, but different type.
            local existingName = cat:getSourceName( existing )
            app:error( "Can not create smart collection with specified name (^1), since regular collection already exists with that name (^2)", name, existingName )
            -- I assume there is gonna be an error at some point no matter, so may as well be clear up front what the problem is.
        end
    else
        return catalog:createSmartCollection( name, smarts, parent, returnExisting )
    end
end



--- Assures collections are created in plugin set.
--
--  @param names (variable, required) if array of strings, then sub-collection names to be created in plugin collection set.
--      <br>if 'string', then name of single plugin collection.
--      <br>if array of structures, then elements are: 'name', and 'searchDesc' - intended for defining smart collection(s).
--  @param tries (number, default = 20) maximum number of catalog access attempts before giving up.
--  @param doNotRemoveDevSuffixFromPluginName (boolean, default = false) pass 'true' if you want to keep the ' (Dev)' suffix in the development version of the collection set.
--
--  @usage NOT be called from a with-write-access-gate.
--
--  @return collections or throws error trying.
--
function Catalog:assurePluginCollections( names, tries, doNotRemoveDevSuffixFromPluginName, pluginName )
    local specs = {}
    if type( names ) == 'string' then
        -- specs = { name=names } -- was until 24/May/2012 1:05
        specs = { { name=names } } -- this must be better(?)
    elseif type( names[1] ) == 'string' then
        for i, v in ipairs( names ) do
            specs[#specs + 1] = { name=v }
        end
    else
        specs = names -- specs: name, searchDesc (so type is 'smart' )
    end
    pluginName = pluginName or app:getPluginName()
    if not doNotRemoveDevSuffixFromPluginName then
        if str:isEndingWith( pluginName, " (Dev)" ) then -- remove dev identification suffix if present - documented in plugin generator default pref backer file. ###4
            pluginName = pluginName:sub( 1, pluginName:len() - 6 )
        end
    end
    local colls = {}
    local set
    local function assure( context, phase )
        if phase == nil then
            app:error( "no phase" )
        end
        if phase == 1 then -- assure plugin collection set.
            set = self:createCollectionSet( pluginName, nil, true )
            if set then
                if #specs == 1 and not str:is( specs[1].name ) then
                    colls[1] = set -- cheating...
                    app:logVerbose( "Assured plugin collection set, no sub-collections specified." )
                    return true
                else
                    app:logVerbose( "Plugin collection set is created" )
                    return false -- not done yet: continue with next phase.
                end
            else
                app:error( "Unable to create plugin collection set - unknown error." )
            end
        elseif phase == 2 then
            for i, spec in ipairs( specs ) do
                local name = spec.name
                assert( name ~= nil, "no name" )
                local searchDesc = spec.searchDesc
                local collection
                if not searchDesc then
                    collection = self:createCollection( name, set, true ) -- ###4 not sure what the roughness was about.
                else
                    assert( type( searchDesc ) == 'table', "search-desc should be table" )
                    collection = self:createSmartCollection( name, searchDesc, set, true ) -- ###4 ditto.
                end
                if collection then
                    app:logVerbose( "Plugin collection is created: ^1", name )
                    colls[#colls + 1] = collection
                else
                    app:error( "Unable to create plugin collection - unknown error." )
                end
            end
            return true -- same as returning nil.
        else
            app:error( "Catalog update phase out of range: ^1", phase )
        end
    end
    app:log( "Assuring plugin collections for ^1", app:getPluginName() ) 
    local s, m = self:update( tries or 20, "Create plugin collections", assure )
    if s then
        if #colls == 1 and colls[1] == set then
            app:log( "Assured plugin collection set, but no collections created yet." )
        else
            app:log( "Created ^1", str:plural( #specs, "plugin collection", true ) )
        end
    else
        app:error( m )
    end
    assert( set, "no plugin coll set" )
    colls[#colls + 1] = set
    return unpack( colls )
end



--- Assures collection is created in plugin set.
--
--  @param name (string, required) the collection name.
--  @param tries (number, optional) cat access tmo.
--  @param pluginName (string, optional) defaults to app--get-plugin-name()
--
--  @usage Must NOT be called from a with-write-access-gate.
--
--  @return collection or throws error trying.
--
function Catalog:assurePluginCollection( name, tries, pluginName )
    return self:assurePluginCollections( { name }, tries, nil, pluginName )
end



--- Assures collection set is created for plugin.
--
--  @usage Must NOT be called from a with-write-access-gate.
--
--  @param tries (number, optional) cat access tmo.
--
--  @return collection or throws error trying.
--
function Catalog:assurePluginCollectionSet( tries )
    return self:assurePluginCollections( {{}}, tries )
end



--- Similar in purpose to lr-catalog method of same name, except takes virtual copy status into consideration.
--
--  @usage And one day it will not be case sensitive.
--  @usage Hopefully to be replaced by a version which uses metadata cache instead of raw/fmt-meta params.
--
--  @param file path
--  @param copyName virtual copy name, if not wanting master photo.
--  @param rawMeta batch of..
--  @param fmtMeta batch of..
--
function Catalog:findPhotoByPath( file, copyName, rawMeta, fmtMeta )
    local realPhoto = catalog:findPhotoByPath( file ) -- ###2 - not robust: should be retrofitted with logic from tree-sync or photooey web-photos.
    if not str:is( copyName ) then
        return realPhoto
    elseif not realPhoto then
        return false
    end
    -- get virtual copy
    local vCopies = self:getRawMetadata( realPhoto, 'virtualCopies', rawMeta )
    if (vCopies ~= nil) and #vCopies > 0 then
        for i, vCopy in ipairs( vCopies ) do
            local cName = self:getFormattedMetadata( vCopy, 'copyName', fmtMeta )
            if cName == copyName then
                return vCopy
            end
        end
    end
    return nil
end
Catalog.isFileInCatalog = Catalog.findPhotoByPath -- function Catalog:isFileInCatalog( ... )



--- Get raw metadata, preferrable from that read in batch mode, else from photo directly.
--
--  @usage *** deprecated - use metadata cache instead.
--
--  @param photo (lr-photo, required) the photo.
--  @param name (string, required) raw metadata item name.
--  @param rawMeta (table, optional) raw metadata table read using batch mode.
--
function Catalog:getRawMetadata( photo, name, rawMeta )
    local data
    if rawMeta ~= nil then
        data = rawMeta[photo]
        if data ~= nil then
            return data[name]
        else -- could try for metadata in lr-photo object in this case, but there would be a performance penalty.
            return nil
        end
    else
        return photo:getRawMetadata( name )
    end
end
        
        
            
--- Get formatted metadata, preferrable from that read in batch mode, else from photo directly.
--
--  @param photo (lr-photo, required) the photo.
--  @param name (string, required) raw metadata item name.
--  @param fmtMeta (table, optional) formatted metadata table read using batch mode.
--
--  @usage *** deprecated - use metadata cache instead.
--
function Catalog:getFormattedMetadata( photo, name, fmtMeta )
    local data
    if fmtMeta ~= nil then
        data = fmtMeta[photo]
        if data ~= nil then
            return data[name]
        else
            return nil
        end
    else
        return photo:getFormattedMetadata( name )
    end
end



--- Set collection photos.
--
--  @usage auto-wrapped with cat-accessor if need be.
--  @usage removes all photos from collection, then adds specified photos.
--  @usage throws error if problem.
--
--  @param coll (lr-collection object, required)
--  @param photos (array of lr-photos, required) may be empty, but may not be nil.
--  @param tmo (number, optional) cat access tmo.
--
--  @return nAdded - number added.
--  @return nRemoved - number removed.
--
function Catalog:setCollectionPhotos( coll, photos, tmo )

    local typ = self:getSourceType( coll ) -- will return a string or throw an error.
    app:callingAssert( typ:sub( -3 ) == "ion", "Not lr-collection object: ^1", str:to( coll ) ) -- must be collection or published collection.
    app:callingAssert( photos ~= nil and type( photos ) == 'table', "Not array of photos: ^1", str:to( photos ) ) -- may be empty, but shouldn't be nil.
    -- note: up until 26/Jun/2014 20:01, the entire collection was emptied, then repopulated,
    -- but since I had a strange anomaly (publish service collection disappeared), I've switched
    -- to a smaller hammer solution: only add those not already in it, and only remove those that need to be.
    -- it may be slower in some cases, but hopefully more reliable, especially if target is a publish collection.
    local photosToBeInColl = {}
    local photosInCollArr = coll:getPhotos()
    local photosInCollSet = tab:createSet( photosInCollArr )
    local photosToAdd = {}
    local photosToRmv = {}
    for i, p in ipairs( photos ) do
        photosToBeInColl[p] = true
        if not photosInCollSet[p] then
            photosToAdd[#photosToAdd + 1] = p
        end
    end
    for i, p in ipairs( photosInCollArr ) do
        if not photosToBeInColl[p] then
            photosToRmv[#photosToRmv + 1] = p
        end
    end
    local function setCollPhotos()
        -- these two functions do not need to be in separate phases:
        if #photosToAdd > 0 then
            coll:addPhotos( photosToAdd )
        end
        if #photosToRmv > 0 then
            coll:removePhotos( photosToRmv )
        end
    end
    if #photosToAdd > 0 or #photosToRmv > 0 then
        if catalog.hasWriteAccess then
            setCollPhotos()
        else
            local name = self:getSourceName( coll )
            local s, m = self:update( tmo or 20, str:fmtx( "Setting '^1' collection photos (^2)", name, #photos ), setCollPhotos )
            if not s then
                error( m )
            end
        end
    end
    return #photosToAdd, #photosToRmv
end



--- Get photos in collection set.
--
--  @param theCollSet - the collection set
--  @param smartCollsToo - boolean
--
--  @return array of photos may be empty but never nil.
--
function Catalog:getPhotosInCollSet( theCollSet, smartCollsToo )
    local sco
    if smartCollsToo then
        sco = SmartCollections:new{ noInit=true } -- quick
    end
    local photos = {}
    local function getPhotosInColl( coll )
        if coll:isSmartCollection() then
            if smartCollsToo then
                tab:appendArray( photos, sco:getPhotos( coll, nil ) ) -- default options
            else
                app:logV( "Ignoring photos from smart collection: ^1", coll:getName() ) -- ###1
            end
        else
            tab:appendArray( photos, coll:getPhotos() )
        end
    end
    local function getPhotosInCollSet( collSet )
        for i, coll in ipairs( collSet:getChildCollections() ) do
            getPhotosInColl( coll )
        end
        for i, set in ipairs( collSet:getChildCollectionSets() ) do
            getPhotosInCollSet( set )
        end
    end
    getPhotosInCollSet( theCollSet )
    return photos
end






--- Get any photo in collection set.
--
--  @param theCollSet - the collection set
--  @param smartCollsToo - boolean
--
--  @return an arbitrary photo - used for sampling purposes.
--
function Catalog:getAnyPhotoInCollSet( theCollSet, smartCollsToo )
    local sco
    if smartCollsToo then
        sco = SmartCollections:new{ noInit=true } -- quick
    end
    local photo
    local function getPhotosInCollSet( collSet )
        for i, coll in ipairs( collSet:getChildCollections() ) do
            local photos
            if coll:isSmartCollection() then
                if smartCollsToo then
                    photos = sco:getPhotos( coll, nil ) -- default options
                else
                    app:logV( "Ignoring photos from smart collection: ^1", coll:getName() ) -- ###1
                end
            else
                photos = coll:getPhotos()
            end
            if tab:isArray( photos ) then
                photo = photos[1]
                return
            end
        end
        for i, set in ipairs( collSet:getChildCollectionSets() ) do
            getPhotosInCollSet( set )
            if photo then return end
        end
    end
    getPhotosInCollSet( theCollSet )
    return photo
end



--- Get any photo in folder tree.
--
--  @param folderTreePath - the folder tree path (directory & subdirs..).
--
--  @return an arbitrary photo - used for sampling purposes.
--
function Catalog:getAnyPhotoInFolderTree( folderTreePath, bypassCache )
    local photo
    local function getPhotosInFolder( lrFolder )
        local photos = lrFolder:getPhotos( false )
        if tab:isArray( photos ) then
            photo = photos[1]
            return
        end
        for i, fldr in ipairs( lrFolder:getChildren() ) do
            getPhotosInFolder( fldr )
            if photo then return end
        end
    end
    if bypassCache == nil then bypassCache = true end -- default is to not bypass cache, but in this case, probably no need for caching.
    local rootFolder = self:getFolderByPath( folderTreePath, bypassCache )
    if rootFolder then
        getPhotosInFolder( rootFolder )
    --else
        --Debug.pause( "No folder in catalog corresponding to", folderTreePath )
    end
    return photo
end



--- Get top-level folder corresponding to dir-path or lr-folder
--  @param pathOrLrFolder - dir-path string or lr-folder object.
--  @param bpc - boolean (optional): bypass-cache?
--  @return folder or nil/false.
function Catalog:getTopLevelFolder( pathOrLrFolder, bpc )
    app:callingAssert( pathOrLrFolder ~= nil, "cant be nil" )
    local folder
    local topLevelFolder
    if type( pathOrLrFolder ) == 'string' then
        folder = cat:getFolderByPath( pathOrLrFolder, bpc )
    end
    local sanityCount = 0
    while folder and sanityCount < 1000 do
        topLevelFolder = folder
        folder = folder:getParent() -- doc does not say what happens if parent does not exist, @Lr5.5 - nil is returned.
        sanityCount = sanityCount + 1
    end
    return sanityCount < 1000 and topLevelFolder
end



--- Determine if plugin collection exists, and get it.
--
--  @param collName collection name
--
--  @return collection or nil
--
function Catalog:getPluginCollection( collName )
    local pluginName = app:getPluginName() -- not taking (Dev) into consideration - pretty-much obsolete a.t.p.
    local sets = catalog:getChildCollectionSets()
    local pluginSet
    for i, set in ipairs( sets ) do
        if set:getName() == pluginName then
            pluginSet = set
            break
        end
    end
    if pluginSet == nil then return nil end
    for i, coll in ipairs( pluginSet:getChildCollections() ) do
        local srcName = self:getSourceName( coll )
        if srcName == collName then
            return coll
        end
    end
    return nil
end
       


--- Get local image id for photo.
--
--  @param photo the photo
--
--  @return imageId (string) local database id corresponding to photo, or nil if problem.
--  @return message (string) error message if problem, else nil.
--
function Catalog:getLocalImageId( photo )
    if app:lrVersion() >= 4 then
        return photo.localIdentifier
    end
    local imageId
    local s = tostring( photo ) -- THIS IS WHAT ALLOWS IT TO WORK DESPITE LOCKED DATABASE (id is output by to-string method).
    local p1, p2 = s:find( 'id "' )
    if p1 then
        s = s:sub( p2 + 1 )
        p1, p2 = s:find( '" )' )
        if p1 then
            imageId = s:sub( 1, p1-1 )
        end
    end
    if str:is( imageId ) then
        -- app:logVerbose( "Image ID: ^1", imageId )
        return imageId
    else
        return nil, "bad id"
    end
end        
            


--- Get a photo, any photo (nil means no photo gettable).
--
--  @usage for sample ops..
--
--  @param notMissing set true to assure said photo is not offline (in case sample op is to extract preview, or exiftool it..).
--  @param typeKey (optional) 'raw', 'rgb', 'video'.
--  @param call (optional) for setting caption (in case op may take a while.
--
function Catalog:getAnyPhoto( notMissing, typeKey, call )
    if notMissing or typeKey then
        local cap
        if call then
            if typeKey then
                cap = call:setCaption( "Getting ^1 from catalog", typeKey )
            else
                cap = call:setCaption( "Getting any photo from catalog" )
            end
        end
        local photos = catalog:getTargetPhotos()
        local function getPhoto()
            local photo
            for i, photo in ipairs( photos ) do
                repeat
                    local file = photo:getRawMetadata( 'path' )
                    if typeKey then
                        local fmt = photo:getRawMetadata( 'fileFormat' )
                        if typeKey == 'raw' then
                            if fmt == 'DNG' or fmt == 'RAW' then
                                -- good
                            else
                                break
                            end
                        elseif typeKey == 'rgb' then
                            if fmt == 'DNG' or fmt == 'RAW' or fmt == 'VIDEO' then
                                break
                            else
                                -- good
                            end
                        elseif typeKey == 'video' then
                            if fmt ~= 'VIDEO' then
                                break
                            else
                                -- good
                            end
                        else
                            app:callingError( "bad type key" )
                        end
                    end
                    if notMissing then 
                        if LrFileUtils.exists( file ) then
                            return photo
                        -- else keep looking for one that is not missing.
                        end
                    else
                        return photo
                    end
                until true
            end
        end
        local photo = getPhoto()
        if photo then
            if call then call:setCaption( cap ) end
            return photo
        end
        photos = catalog:getAllPhotos()
        photo = getPhoto()
        if call then call:setCaption( cap ) end
        return photo
    else
        --if call and cap then call:setCaption( cap ) end
        return catalog:getTargetPhoto() or catalog:getTargetPhotos()[1] or catalog:getAllPhotos()[1]
    end
end



--- Get directory containing catalog (just a tiny convenience/reminder function).
--
--  @usage beware: this returns catalog name too as 2nd return value.
--
function Catalog:getCatDir()
    local path = catalog:getPath()
    return LrPathUtils.parent( path ), LrPathUtils.removeExtension( LrPathUtils.leafName( path ) )
end
Catalog.getCatalogDir = Catalog.getCatDir -- function Catalog:getCatalogDir()
Catalog.getCatalogDirectory = Catalog.getCatDir -- function Catalog:getCatalogDirectory()
Catalog.getDir = Catalog.getCatDir -- function Catalog:getDir()
Catalog.getDirPath = Catalog.getCatDir -- function Catalog:getDirPath()



--- Get stack relationship
--
--  @param photo1 first photo
--  @param photo2 second photo
--  @param cache metadata cache (optional).
--
--  @return which is above, nil if not in same stack.
--  @return stack position of photo1, 0 if not in a stack
--  @return stack position of photo2, ditto.
--
function Catalog:getStackRelation( photo1, photo2, cache )
    local top1 = lrMeta:getRaw( photo1, 'topOfStackInFolderContainingPhoto', cache ) -- accept uncached.
    local pos1 = lrMeta:getRaw( photo1, 'stackPositionInFolder', cache )
    local stacked1 = lrMeta:getRaw( photo1, 'isInStackInFolder', cache )
    local top2 = lrMeta:getRaw( photo2, 'topOfStackInFolderContainingPhoto', cache ) -- accept uncached.
    local pos2 = lrMeta:getRaw( photo2, 'stackPositionInFolder', cache )
    local stacked2 = lrMeta:getRaw( photo2, 'isInStackInFolder', cache )
    if stacked1 and stacked2 then
        if top1 == top2 then
            if pos1 < pos2 then -- smaller numbers mean higher in stack.
                return 1, pos1, pos2
            else
                return 2, pos1, pos2
            end
        else
            return nil, pos1, pos2
        end
    elseif stacked1 then
        return nil, pos1, 0
    else
        return nil, 0, 0
    end
end



--- Assure specified metadata column is active in current view filter.
--
--  @param metadataId metadata ID.
--  @param pluginId toolkit ID.
--
--  @usage returns nothing
-- 
function Catalog:assureMetadataColumnInViewFilter( metadataId, pluginId )
    pluginId = pluginId or _PLUGIN.id
    local filter, preset = catalog:getCurrentViewFilter()
    local found
    if filter then
        for i, v in ipairs( filter.columnBrowserDesc ) do
            local p1, p2 = v.criteria:find( pluginId )
            if p1 then
                if v.criteria:find( metadataId, p2 + 1 ) then
                    if filter.columnBrowserActive then
                        return -- assured
                    else
                        filter.columnBrowserActive = true
                        found = true
                        break
                    end
                end
            end
        end
        if not found then
            filter.columnBrowserActive = true
            local a = filter.columnBrowserDesc
            a[#a + 1] = { criteria = str:fmtx( "sdktext:^1.^2", pluginId, metadataId ) }
        end
    else
        Debug.pause( "new" ) -- this has never happened. It seems there is always some kind of filter assigned, even if nothing enabled.
        filter = {
            columnBrowserActive = true, 
            columnBrowserDesc = {
                { criteria = str:fmtx( "sdktext:^1.^2", pluginId, metadataId ) },
            }, 
        }
    end
    catalog:setViewFilter( filter )
end



--- Remove photos from catalog (without deleting them).
--
--  @usage A compromise at best - still..
--
--  @param params table of parameters<br>
--             call (Call, required) call or service...
--             rmvPhotos (array, required) photos to remove.
--             cache (LrMetadataCache, default=nil) more efficient if fields are cached..
--
--  @return status (boolean) true iff photos were removed; false => not. Note: no qualifying message (check call to see if canceled).
--
function Catalog:removePhotos( params )
    local call = params.call or error( "no call" )
    local rmvPhotos = params.rmvPhotos or error( "no rmv-photos" )
    local rmvPhoto = rmvPhotos[1] -- I guess.
    local cache = params.cache -- or nil.
    if not tab:isArray( rmvPhotos ) then
        app:logW( "Array of photos to remove is empty." ) -- check before calling to avoid this warning.
        return true -- I guess, ###1.
    end
    local s, m = gui:gridMode( true ) -- mandatory (actually not necessary if only 1 photos, *but* library module is necessary, so might as well be grid.
    if s then
        app:logV( "Library module should be in grid mode now." )
    else
        app:logE( "Unable to put library module in grid mode - ^1", m )
        return
    end

    for i, s in ipairs( catalog:getActiveSources() ) do
        if cat:getSourceType( s ) ~= 'LrFolder' then
            rmvPhoto, rmvPhotos = cat:_assureSources( rmvPhoto, rmvPhotos, cache )
            if rmvPhoto then
                break
            else
                app:logE( rmvPhotos ) -- errm
                return
            end
        end
    end

    local s, q
    for try=1,2 do
        s, q = cat:assureSelectedPhotos( rmvPhotos, rmvPhoto, false ) -- must not be in collection in this case. Could have used the other deprecated method instead of all this song n' dance, same diff I guess.
        if s then
            break
        elseif try ~= 2 then
            rmvPhoto, rmvPhotos = cat:_assureSources( rmvPhoto, rmvPhotos, cache ) -- reminder: assure-sources only attempted upon entry if any source not folder, but there
            -- is no guarantee that the folder selected houses the target photos, thus this part here..
            if not rmvPhoto then -- probably ain't gonna work, but might as well give another crack and report the selection error instead.
                app:logW( rmvPhotos ) -- warning should be enough in this context.
            end
        -- else, we tried..
        end
    end
    
    if s then
        if q then -- qualifying message.
            app:logV( q )
        end
        local saveXmp = app:getPref( 'saveXmpBeforeRemovingFromCatalog' ) -- ###1 (doc).
        if saveXmp then
            -- Catalo g : s aveMetadata( photos, preSelect, restoreSelect, alreadyInGridMode, service )
            s, m = self:saveMetadata( rmvPhotos, false, false, true, call )
        else
            app:log( "Not saving xmp prior to removal from catalog - to have saved first, set pref: \"save-xmp-before-removing-from-catalog\"." )
        end
    else
        app:logE( "Unable to assure photos to be removed from catalog were selected - ^1", q )
        return
    end
    
    app:log()
    app:log( "^1 to be removed from catalog:", str:pluralize( #rmvPhotos, "photo" ) )
    app:log( "-----------------------------------" )
    local uuids = {}
    for i, photo in ipairs( rmvPhotos ) do
        local uuid = photo:getRawMetadata( 'uuid' )
        local photoName = cat:getPhotoNameDisp( photo, true, cache )
        local tp = catalog:findPhotoByUuid( uuid ) -- cheap insurance..
        if tp == photo then
            uuids[#uuids + 1] = uuid
            --app:log( "Photo to be removed: ^1", photoName )
            app:log( photoName )
        else
            Debug.pause( "?" )
        end
    end
    app:log( "-----------------------------------" )
    app:log()
    if #uuids ~= #rmvPhotos then
        app:logE( "Unable to assure removal from catalog will be successful - removal aborted." )
        return
    end
    
    local uuids = {}
    for i, photo in ipairs( rmvPhotos ) do
        local uuid = photo:getRawMetadata( 'uuid' )
        local tp = catalog:findPhotoByUuid( uuid ) -- cheap insurance..
        if tp == photo then -- ###1?
            uuids[#uuids + 1] = uuid
        else
            Debug.pause( "?" )
        end
    end
    if #uuids ~= #rmvPhotos then
        app:logE( "Unable to assure removal from catalog will be successful." )
        return
    end
    
    local function isRemoved()
        local removed = true
        for i, uuid in ipairs( uuids ) do
            local p = catalog:findPhotoByUuid( uuid )
            if p then
                app:log( "^1 has not been removed yet, maybe others too..", cat:getPhotoNameDisp( p, true ) )
                removed = false
                break
            end
        end
        if removed then -- none remain in catalog.
            app:log( "Photos were removed - as intended.." )
            app:displayInfo( "photos were removed - good.." )
            return true
        else
            app:displayInfo( "photos are not removed yet - try again.." )
        end
    end
    
    app:displayInfo( "^1 photos are to be removed from catalog", #rmvPhotos )
    -- dive straight in to delete key - if in folder not collection, then said key will always bring up an Lr prompt, and so is safe to do without pre-prompt.
    if WIN_ENV then
        --local s, m = app:sendWinAhkKeys( "{Ctrl Down}{Alt Down}{Shift Down}{Del}{Shift Up}{Alt Up}{Ctrl Up}" ) - splat-delete.
        s, m = app:sendWinAhkKeys( "{Del}", 1 ) -- simple delete, note: a lengthy delay needs to be there (.1 is not enough) for optimal performance, so Lr has a chance to present the removal dialog
        -- before return, which holds up the plugin, which then sees photos removed immediately after return - works rather nicely actually. Could take more seconds on some machines (?).
        -- .2 is enough on my machine, but 1 seems safer and plenty in most circumstances - could be that it needs more if lots of thinking required by Lr before initial presentation - oh well,
        -- it still works in that case too, just less spiffily (user has to endure a plugin dialog box, and additional delay..).
    else
        s, m = app:sendMacEncKeys( "Delete", 1 ) -- ###1 test on Mac (not sure if 'Delete' is the correct term).
    end
    
    if s then
        app:log( "Delete key issued, and a moment's delay observed." )
        if isRemoved() then -- awesome.
            return true -- user never even sees a plugin dialog box - yeah now..
        end
    else
        app:logE( m )
        return
    end
    
    app:initPref( 'dismissForRemovingPhotosFromCatalog', 5 )
    assert( #uuids > 0, "no uuids" )
    -- pre-reqs all squared away, now just need to confirm..
    repeat
        local vi = nil--{}
        local ai = {}
        ai[#ai + 1] = vf:row {
            vf:push_button {
                title = "Dismiss for",
                action = function( button )
                    LrDialogs.stopModalWithResult( button, 'other' )
                end,
            },
            vf:edit_field {
                value = app:getPrefBinding( 'dismissForRemovingPhotosFromCatalog' ),
                width_in_digits = 2,
                min = 1,
                max = 99,
                precision = 0,
            },
            vf:static_text {
                title = "seconds",
            },
            vf:spacer { width = 20 },
            vf:push_button {
                title = "Show Log File",
                action = function()
                    app:showLogFile()
                end
            },
        }
        local msg = [[
Dismiss this dialog box long enough to assure initially selected photos (as indicated in log file) have been removed from the catalog, if removed after dismissal time has elapsed, you'll be notified via Lr "bezel" (the black ribbon or emulation of it), and this dialog box won't be displayed again.

If problems, then click 'Cancel' and report to plugin author - thanks.]]
        local a = app:show{ confirm=msg,
            subs=nil,
            buttons=nil,--{ dia:btn( "OK", 'ok', false ) },
            viewItems = vi,
            accItems = ai,
        }
        if a == 'ok' then -- OK
            if isRemoved() then
                return true
            end
        elseif a == 'other' then -- dismiss-for.
            local moment = app:getPref( 'dismissForRemovingPhotosFromCatalog' ) or 3
            app:sleep( moment )
            if shutdown then return end
            if isRemoved() then
                return true
            end
        elseif a == 'cancel' then
            call:cancel()
            return
        else
            app:error( "bad btn: '^1'", a )
        end
    until false
    
end



--- Delete photos (remove photos from catalog AND delete files from disk).
--  @usage *** ASSURE LIST OF FILES TO DELETE HAS ALREADY BEEN LOGGED, OTHERWISE THIS METHOD WILL MAKE A LIAR OUT OF THE CALLING CONTEXT.
--  @usage call to delete photos.
--  @usage depends on prefs: 'preservePicks', 'delayForManualMetadataSaveBox' (used for manual delete box).
--  @usage as of 30/May/2014, will always prompt user before deleting - user can then choose manual or let plugin splatt delete them.
--  @param params table of parameters<br>
--             call (Call, required) call or service...
--             photos (array, required) photos to delete
--             promptTidbit (string, default="Items") e.g. "Snapshot photos"
--             actionPrefKey (string, optional) if nil or false, prompt is mandatory.
--             final (boolean, default=false) only applies if mac atm: means dialog box is to be the final box of the service.
--  @return status (boolean) true iff photos were deleted; false => not. Note: no qualifying message (check call to see if canceled).
function Catalog:deletePhotos( params )
    local call = params.call or error( "no call" )
    local photos = params.photos or error( "no photos" )
    local promptTidbit = params.promptTidbit or "Items"
    local actionPrefKey = params.actionPrefKey or nil
    local final = params.final
    if tab:isEmpty( photos ) then
        app:logW( "Table of photos to delete is empty." ) -- check before calling to avoid this warning.
        return true -- I guess.
    end
    local s, m = gui:gridMode( true ) -- mandatory (actually not necessary if only 1 photos, *but* library module is necessary, so might as well be grid.
    if s then
        app:logVerbose( "Library module should be in grid mode now." )
    else
        app:logErr( "Unable to put library module in grid mode - ^1", m )
        return
    end

    local ppicks = app:getPref( 'preservePicks' ) -- may come from advanced settings, of course. Must this always be *default* preset? ###2
    local pickTidbit
    local pickCount = 0
    local delPhotos
    if ppicks then
        delPhotos = {}
        for i, photo in ipairs( photos ) do
            local ppick = photo:getRawMetadata( 'pickStatus' )
            if ppick == 1 then
                pickCount = pickCount + 1
            else
                delPhotos[#delPhotos + 1] = photo
            end
        end
        if pickCount > 0 then
            pickTidbit = str:fmtx( " - ^1 not subject to deletion", str:nItems( pickCount, "picked photos" ) )
        else
            pickTidbit = ' - none are picks'
        end
    else
        delPhotos = photos
        pickTidbit = ""
    end
    if #delPhotos == 0 then
        return true -- I guess.
    end
    
    local s, m = cat:assureSelectedPhotos( delPhotos, delPhotos[1] )

    if s then
        if m then
            app:logV( m )
        end
        local buttons
        local subs
        local okButton
        local logsButton
        local iDelButton = 'iDel'
        local mDelButton = 'noManualDel'
        local prompt
        local apk
        local tb2
        --if #delPhotos == 1 then
        --    tb2 = ""
        --else
            tb2 = ", and you should be viewing thumbnail grid in Library module"
        --end
        if WIN_ENV then
            buttons = { dia:btn( "Show Log File", 'other' ), dia:btn( "Dismiss Temporarily", 'dismissTemporarily' ), dia:btn( "Yes - Splat-Delete Selected Photos", 'ok' ) }
            prompt = promptTidbit .. " ripe for deletion are now selected (^1^2)^3.\n \nIf all seems right, then click 'Yes - Splat-Delete Selected Photos' to splat delete them, or click 'Show Log File' to have a look at the list of paths in the log file, or click 'Cancel' to quit - you can delete manually if you prefer.\n \n*** Splat delete will only work if there are no other dialog boxes demanding attention - if there are, click 'Dismiss Temporarily' and close the other dialog boxes."
            okButton = 'ok'
            logsButton = 'other'
            apk = actionPrefKey
        elseif final then
            buttons = { dia:btn( "Show Log File", 'ok' ), dia:btn( "Skip Log File", 'cancel' ) }
            prompt = promptTidbit .. " ripe for deletion are now selected (^1^2)^3.\n \nClick 'Show Log File' to have a look at the list of paths in the log file, or click 'Cancel' to quit without showing log file.\n \nUntil splat-delete is tested on Mac, you'll have to delete manually after this dialog box is dismissed."
            okButton = "notOk"
            logsButton = 'ok'
            apk = promptTidbit .. " deletion confirmation" -- ###1 seems a bit wonked - consider usage..
        else
            mDelButton = 'ok'
            buttons = { dia:btn( "Show Log File", 'other' ), dia:btn( "Let Me Delete Manually", 'ok', false ) }
            prompt = promptTidbit .. " ripe for deletion are now selected (^1^2)^3.\n \nClick 'Show Log File' to have a look at the list of paths in the log file, or click 'Cancel' to quit without showing log file.\n \nUntil splat-delete is tested on Mac, you'll have to delete manually - click 'Let Me Delete Manually' to give yourself a few seconds to do so."
            okButton = "notOk"
            logsButton = 'other'
            -- apk = promptTidbit .. " pre-op deletion confirmation"
            apk = actionPrefKey
        end
        local first = true
        repeat
            local vi = {}
            vi[#vi + 1] = vf:checkbox {
                title = "Preserve picks",
                bind_to_object = prefs,
                value = app:getPrefBinding( 'preservePicks' ),
            }
            call:setCaption( "Dialog box needs your attention..." )
            local button = app:show{ confirm=prompt,
                subs = { str:nItems( #delPhotos, "photos" ), pickTidbit, tb2 },
                buttons = buttons,
                actionPrefKey = apk,
            }
            if button == okButton then
                break
            elseif button == logsButton then
                app:showLogFile()
                if MAC_ENV then
                    if final then
                        call:cancel()
                        return
                    -- else keep looping.
                    end
                end
            elseif button == mDelButton then
                app:sleep( app:getPref( 'delayForManualMetadataSaveBox' ) or 3 )
                if shutdown then return end
                if first then
                    prompt = prompt .. "\n \nClick 'I Deleted Them' if you did, in fact, delete them manually (while dialog was temporarily dismissed after you clicked 'Let Me Delete Manually')."
                    buttons[#buttons + 1] = dia:btn( "I Deleted Them", iDelButton )
                    first = false
                end
            elseif button == iDelButton then
                return true
            elseif button == 'dismissTemporarily' then
                app:sleep( 3 )
                if shutdown then return false end
            elseif button == 'cancel' then
                call:cancel() -- I really don't like this presumption, but callers are managing, and depending on it, so until some improved handling, it must remain this way. ###2
                return false
            else
                error( "bad button" )
            end
        until false
        call:setCaption( "Splat deleting ^1...", LrStringUtils.lower( promptTidbit ) )
        if WIN_ENV then
            local s, m = app:sendWinAhkKeys( "{Ctrl Down}{Alt Down}{Shift Down}{Del}{Shift Up}{Alt Up}{Ctrl Up}" )
            if s then
                app:log( "^1 splat-deleted.", str:nItems( #delPhotos, promptTidbit ) )
            else
                app:logError( m )
            end
        else
            error( "pgm fail" ) -- as coded 19/Mar/2013 22:22, it should not reach here, if Mac.
            --call:setCaption( "Dialog box needs your attention..." ) -- never happens.
            --app:show{ warning="Not yet implemented on Mac - please delete manually for now..." }
            -- local s, m = app:sendMacEncKeys( "CmdOptionShift-Delete" ) -- ###1 test on Mac (I believe the modifiers are correct, the 'Delete' part is a guess).
        end
        return true
    else
        app:logError( m )
    end
end



--- Get batch (ChangeManager) lock-status metadata.
--
--  @return lock-data lookup table: keys are photos, values are tables with single boolean member: 'locked' (I must have had lock-date in mind in the beginning..).
--  @return num-locked number of locked photos.
--
function Catalog:batchGetLockMetadata( photos, call )
    app:callingAssert( call, "no call" )
    local lockData = {}
    local nLocked = 0
    local changeManagerId = app:getPref( 'changeManagerId' ) -- allow default in the form of a function? ###3
    if changeManagerId == nil then
        local errm
        changeManagerId, errm = custMeta:getPluginId( "ChangeManager" )
        if errm then
            app:error( errm )
        end
    end
    local cap
    if str:is( changeManagerId ) then
        cap = call:setCaption( "Getting ChangeManager lock status..." )
        local cMeta = cat:getBatchRawMetadata( photos, { 'customMetadata' } ) -- empty table if no custom metadata.
        for i, photo in ipairs( photos ) do -- photos are keys, values are whole shootin' match...
            local cmeta = custMeta:getMetadata( photo, changeManagerId, cMeta )
            -- Debug.lognpp( "cmeta", cmeta )
            if not tab:isEmpty( cmeta ) then
                local locked = cmeta.locked
                if locked == nil then -- not sure this happens when testing for empty table but this is the value for locked status when never been locked.
                    lockData[photo] = { locked = false }
                elseif locked == 'yes' then -- locked
                    lockData[photo] = { locked = true }
                    nLocked = nLocked + 1
                elseif locked == 'no' then -- unlocked
                    lockData[photo] = { locked = false }
                else 
                    lockData[photo] = { locked = false }
                    app:logWarning( "Invalid change manager lock status: '^1' - considering '^2' unlocked", str:to( locked ), photo:getRawMetadata( 'path' ) )
                end
            -- else this happens sometimes even when cm enabled - nil values are not returned.
            end
            if call:isQuit() then
                break
            else
                call:setPortionComplete( i, #photos )
            end
        end
    else
        app:logv( "Change manager pref indicates change manager not in use on this system - do edit if such is false." )
        -- note: calling context should distinguish between not-locked, and lock-state not determined.
    end
    call:setCaption( cap ) -- @20/Mar/2013 6:41, handles nil
    return lockData, nLocked
end



--- Determine if locked, and if so: return lock-date as string, as 2nd item in return list (1st item is boolean locked, or not).
--
--  @param photo lr-photo
--  @param orXmp if photo not locked, also check if xmp is read-only.
--  @param cache metadata-cache, optional (only used when or-xmp is true).
--
--  @return locked true if so
--  @return qualification may accompany *true* status: lock-date or xmp notice.
--
function Catalog:isLocked( photo, orXmp, cache )
    local changeManagerId = app:getPref( 'changeManagerId' ) -- check for change manager Id to be explicitly dictated.
    local locked
    if not str:is( changeManagerId ) then
        local errm
        changeManagerId, errm = custMeta:getPluginId( "ChangeManager" ) -- derive from partially specified name, if possible.
        if errm then
            app:error( errm )
        end
    end
    if str:is( changeManagerId ) then
        local cdata = custMeta:getMetadata( photo, changeManagerId ) -- none to start with.
        --Debug.pause( cdata )
        if cdata then
            if cdata.locked == 'yes' then
                return true, cdata.lockDate
            -- until 22/Dec/2013 16:32, the or-xmp clause used to be here (predicated on change manager and cdata). Seems it should apply whether change-manager or not, so moved to below.
            elseif cdata.locked == 'no' then
                locked = false
            end
        end
    end
    if orXmp then -- moved to here on 22/Dec/2013 16:33.
        local fmt = lrMeta:getRaw( photo, 'fileFormat', cache ) -- accept uncached.
        local path = lrMeta:getRaw( photo, 'path', cache )
        local xmpFile
        if fmt == 'RAW' then
            xmpFile = LrPathUtils.replaceExtension( path, 'xmp' )
        else
            xmpFile = path
        end
        if fso:existsAsFile( xmpFile ) then
            -- return fso:isReadOnly( xmpFile ) - I'm trying to wean myself from this method, yet not trusting Lr's method yet.
            if not LrFileUtils.isWritable( xmpFile ) then
                return true, "Not ChangeManager-locked, but xmp isn't writable."
            end
        -- else return nil/false.
        end
    end
    return locked -- nil => indeterminate (e.g. no change manager) false => definitely not locked.
end



--- Determine if photo is missing - i.e. not physical file and no smart copy stub.
--
--  @return status (boolean, always) true if photo source file does not exist.
--  @return qualifier (string, sometimes) Note: it's not an error message (never set when false is returned), if accomanying 'true' status, it means smart preview exists.
--
function Catalog:isMissing( photo, cache )
    local file = lrMeta:getRaw( photo, 'path', cache ) -- accept uncached.
    if fso:existsAsFile( file ) then
        return false
    else
        if app:lrVersion() >= 5 then
            local spi = lrMeta:getRaw( photo, 'smartPreviewInfo', cache ) -- returns empty table if no smart preview.
            if tab:isEmpty( spi ) then
                return true
            else
                return true, "Original is missing, but smart preview is present" -- returns true for backward compatibility, but qualification in case one is interested.
                -- to be clear: calling context must check qualifier to determine if smart preview is present, which may be sufficient for purpose.
            end
        else
            return true -- if source file not existing, then photo is missing.
        end
    end
end



--- Determine if photo has a smart preview.
--
--  @usage Previews object has a 'getSmartPreview' method, if you actually want to have the preview.
--
--  @return is (boolean) true or false.
--
function Catalog:isSmartPreview( photo, cache )
    if app:lrVersion() < 5 then
        return false
    end
    local spi = lrMeta:getRaw( photo, 'smartPreviewInfo', cache ) -- accept uncached.
    if tab:is( spi ) then
        return true
    else
        return false
    end
end



--- Get collection set popup items.
--
--  @param pub (boolean, default=false) set true for publish services collection sets; false => catalog coll sets.
--
--  @return items for popup: titles are collection set paths.., values are local IDs or "LrCatalog".
--  @return lookup keys are item values, values are item titles.
--
function Catalog:getCollectionSetPopupItems( pub )
    local roots
    local types = {}
    if pub then
        roots = catalog:getPublishServices()
        types['LrPublishedCollectionSet'] = true
        types['LrPublishService'] = true
    else
        roots = catalog:getChildCollectionSets()
        types['LrCollectionSet'] = true
        --types['LrCatalog'] = true
    end
    local items = {}
    local lookup = {}
    local function getSome( from, ppath )
        for i, v in ipairs( from ) do
            local typ = self:getSourceType( v )
            if types[typ] then
                local item = { title=ppath..cat:getSourceName( v ), value=v.localIdentifier or "LrCatalog" }
                items[#items + 1] = item
                lookup[item.value] = item.title
            end
        end
        for i, v in ipairs( from ) do
            local typ = self:getSourceType( v )
            if types[typ] then
                local childSets = v:getChildCollectionSets()
                if #childSets > 0 then
                    --items[#items + 1] = { separator=true }
                    getSome( childSets, ppath..cat:getSourceName( v ).."/" )
                    --items[#items + 1] = { separator=true }
                end
            end
        end
    end
    getSome( roots, "" )
    return items, lookup
end



--- Get publish service popup items.
--
--  @return items for popup: titles are publish service names, values are local IDs.
--  @return lookup keys publish service local IDs, values are tables with: pubSrv, name, pid.
--
function Catalog:getPublishServicePopupItems()
    local it = {}
    self.pubSrvLookup = {}
    local srvs = catalog:getPublishServices() -- all
    for i, ps in ipairs( srvs ) do
        local pid = ps:getPluginId()
        local ext = LrPathUtils.extension( pid )
        if str:is( ext ) then
            if ext == 'file' then
                pid = 'HardDrive'
            else
                pid = ext
            end
        end
        self.pubSrvLookup[ps.localIdentifier] = { pubSrv=ps, name=ps:getName(), pid=pid }
        it[#it + 1] = { title=pid.." - "..ps:getName(), value=ps.localIdentifier }    
    end
    return it, self.pubSrvLookup
end



--- Get publish service, and name, corresponding to specified ID.
--
--  @param id publish service ID.
--
--  @return publish service
--  @return name
--  @return id
--
function Catalog:getPublishService( id )
    if not self.pubSrvLookup then
        self.pubSrvLookup = {}
        local srvs = catalog:getPublishServices() -- all
        for i, ps in ipairs( srvs ) do
            local pid = ps:getPluginId()
            local ext = LrPathUtils.extension( pid )
            if str:is( ext ) then
                if ext == 'file' then
                    pid = 'HardDrive'
                else
                    pid = ext
                end
            end
            self.pubSrvLookup[ps.localIdentifier] = { pubSrv=ps, name=ps:getName(), pid=pid }
        end
    end
    local ent = self.pubSrvLookup[id]
    if ent then 
        return ent.pubSrv, ent.name, ent.pid
    else
        return nil
    end
end



--- Get smart collection popup items (within catalog or publish service).
--
--  @param startHere (collection set or publish service, default = catalog)
--
--  @return popup items: titles are indented collection names, values are collections local-IDs.
--
function Catalog:getSmartCollectionPopupItems( startHere )
    startHere = startHere or catalog -- could be pub-srv
    self.smartCollLookup = {}
    local it = {}
    local indent = 0
    local function getFromSet( set )
        local cnt = 0
        for i, coll in ipairs( set:getChildCollections() ) do
            if coll:isSmartCollection() then
                it[#it + 1] = { title=string.rep( " ", indent )..coll:getName(), value=coll.localIdentifier }
                self.smartCollLookup[coll.localIdentifier] = { coll=coll, name=coll:getName(), path=collections:getCollPath( coll ) } -- reminder: you can't get name from a binding transform function, so has to be prepared in advance.
                cnt = cnt + 1
            end
        end
        for i, set in ipairs( set:getChildCollectionSets() ) do
            local setName = collections:getCollPath( set )
            local index = #it + 1
            it[#it + 1] = { separator=true }
            it[#it + 1] = { title=string.rep( " ", indent ).."Set: "..setName, value=nil }
            it[#it + 1] = { separator=true }
            indent = indent + 4
            local howMany = getFromSet( set )
            if howMany == 0 then
                table.remove( it, index )
                table.remove( it, index )
                table.remove( it, index )
            end
        end
        if indent >= 4 then
            indent = indent - 4
        else
            --Debug.pause( indent )
        end
        return cnt
    end
    getFromSet( startHere )
    return it
end



--- Get smart collection, and name.
--
--  @param id smart collection ID.
--
--  @return collection if found, else nil.
--  @return name if found, else excuse.
--  @return path if found, else nil.
--
function Catalog:getSmartCollection( id )--, startHere )
    if not self.smartCollLookup then
        self.smartCollLookup = {}
        local function getFromSet( set )
            for i, coll in ipairs( set:getChildCollections() ) do
                if coll:isSmartCollection() then
                    self.smartCollLookup[coll.localIdentifier] = { coll=coll, name=coll:getName(), path=collections:getCollPath( coll ) } -- reminder: you can't get name from a binding transform function, so has to be prepared in advance.
                end
            end
            for i, set in ipairs( set:getChildCollectionSets() ) do
                getFromSet( set )
            end
        end
        getFromSet( catalog ) -- ###1 presumptuous.
    end
    local ent = self.smartCollLookup[id]
    if ent then 
        return ent.coll, ent.name, ent.path
    else
        return nil, "Smart collection does not exist having ID: "..( id or "?" )
    end
end



--- Get collection set photos (in regular collections only).
--
--  @usage uses breadth-first algorithm.
--
--  @param collSet collection set object.
--
--  @return photos (array) may be empty, never nil.
--
function Catalog:getCollectionSetPhotos( collSet )
    local photos = {}
    local function getFromColl( coll )
        tab:appendArray( photos, coll:getPhotos() )    
    end
    local function getFromSet( set )
        for i, v in ipairs( set:getChildCollections() ) do -- breadth first
            getFromColl( v )
        end
        for i, v in ipairs( set:getChildCollectionSets() ) do -- depth second
            getFromSet( v )
        end
    end
    getFromSet( collSet )
    return photos
end



--- Get filename preset specified by name.
--
--  @usage case sensitive.
--
--  @return uuidOrPath or nil.
--
function Catalog:getFilenamePreset( presetName )
    for name, uuidOrPath in pairs( LrApplication.filenamePresets() ) do
        if name == presetName then
            return uuidOrPath
        end
    end
end



--- Get original filename corresponding to photo.
--
--  @usage *** requires original filenames initialized via SQLiteroom, or 'Original Filename' filenaming preset (which will be copied during init).
--  @usage - consider checking for corresponding disk file if pertinent (e.g. photo object may be from stale info, and photo and/or file since deleted..).
--  @usage - the reason it defaults to file over preset is because preset requires reset - don't want filenames coming from one place one time, then
--      <br>    without warning, coming from another place the next time.
--
--  @param photo subject photo..
--  @param preferPresetOverFile (boolean, default=false) true to use sqliteroom-compat file data, false to prefer filename preset (when both are available).
--
--  @return filename (string) nil if unavailable.
--  @return excuse (string) nil if available, else reason for no filename.
--
function Catalog:getOriginalFilename( photo, preferPresetOverFile ) -- ###1 added support for preset-based acquistion 17/Sep/2014 0:44 need to release plugins which use it.
    local s, m = self:initForOriginalFilenames()
    if not s then
        return nil, m
    end
    local fn1
    local fn2
    if self.fnPreset then
        s, fn1 = LrTasks.pcall( photo.getNameViaPreset, photo, self.fnPreset )
        if s then
            -- ok
        else
            Debug.pause( "bad name via preset", fn1 )
            fn1 = nil
        end
    end
    if self.altLookup then
        fn2 = self.altLookup[str:to(photo.localIdentifier)]
        if fn2 ~= nil and type( fn2 ) == 'string' then
            if #fn2 > 0 then
                -- ok
            else
                Debug.pause( "empty string in ofn file" )
                fn2 = nil
            end
        else
            Debug.pause( "bad name via ofn file", fn2 )
            fn2 = nil
        end
    end
    -- note: fn2 guarantees correct extension, but fn1 guarantees freshness.
    if fn1 and fn2 then
        fn1 = LrPathUtils.addExtension( fn1, LrPathUtils.extension( fn2 ) )
        Debug.pauseIf( fn1 ~= fn2, "ofn discrepancy, via preset", fn1, "via ofn file", fn2 )
        return preferPresetOverFile and fn1 or fn2
    elseif fn1 then
        fn1 = LrPathUtils.addExtension( fn1, LrPathUtils.extension( photo:getFormattedMetadata( 'fileName' ) ) ) -- ###1 a guess, I guess (could original by NEF and photo be DNG?)
        return fn1
    elseif fn2 then
        return fn2 -- with ext
    else
        return nil, str:fmtx( "Original filename does not exist in '^1' - consider restarting Lightroom using SQLiteroom-saved batch file (with 'Original Filenames' preset enabled). Another possibility is that 'Original Filename' filenaming preset is not being recognized - maybe an Lr restart will remedy (if not, try deleting 'Original Filename.lrtemplate' file and restart Lr again - it will be recreated..).", self.ofile )
    end
end



--- Determine if original filenames are even a possibility, and if so, prepare..
--
--  @return status - true iff successful
--  @return message -- reason if not successful.
--
function Catalog:initForOriginalFilenames()
    if self.altLookup == nil then
        local mb = {} -- message buffer
        self.altLookup = false -- one try only
        -- see about sqliteroom-compat orig filenames:
        local ofile = LrPathUtils.child( cat:getDir(), "Original Filenames.txt" ) -- note: although get-dir returns 2 values, only the first is used in this context.
        if fso:existsAsFile( ofile ) then
            local s, alt = pcall( dofile, ofile )
            if s then
                if tab:is( alt ) then
                    --app:log( "Original filenames are available from here: ^1", ofile )
                    self.ofile = ofile
                    self.altLookup = alt -- overwrite
                else
                    mb[#mb + 1] = str:fmtx( "No original filenames in ^1", ofile )
                end
            else
                mb[#mb + 1] = str:fmtx( "Syntax error in original filenames file: '^1' - ^2", ofile, alt )
            end
        else
            mb[#mb + 1] = str:fmtx( "Original filenames file does not exist here: ^1 (written by SQLiteroom, if 'Original Filenames' preset is enabled upon startup).", ofile )
        end
        -- see about using fn preset:
        local preset = self:getFilenamePreset( "Original Filename" )
        if preset then -- preset exists, but may not be ready for prime time, yet (new presets don't work in plugin until Lr restarted).
            local photo = self:getAnyPhoto()
            if photo then
                local s, fn = LrTasks.pcall( photo.getNameViaPreset, photo, preset )
                if s then -- hopefully, is OK.
                    self.fnPreset = preset
                else
                    mb[#mb + 1] = str:fmtx( "Unable to get original filename using 'Original Filename' preset - if it's recently been created, you'll need to restart Lightroom. Error message: ^1", fn )
                end
            else
                mb[#mb + 1] = str:fmtx( "No photos in catalog, so unable to test original filename preset." )
            end
        else
            local srcFile, isA = app:getFrameworkPath( "Catalog/Support/Original Filename.lrtemplate" ) -- must exist
            if srcFile then
                local destDir, orMsg = lightroom:getPresetDir( "Filename Templates" )
                if destDir then -- exists
                    local destFile = LrPathUtils.child( destDir, "Original Filename.lrtemplate" )
                    if not LrFileUtils.exists( destFile ) then
                        local s, m = fso:copyFile( srcFile, destFile ) -- dir exists, overwrite not required.
                        if s then
                            -- note: normally, user will not have sqliteroom file, since it's no longer required, so a verbose message should suffice.
                            -- if user does not have the sqliteroom file, then this message will be returned and should be issued as a warning.
                            mb[#mb + 1] = str:fmtx( "Copied original filenaming preset to '^1' - you must restart Lightroom so it can be used by this plugin.", destFile )
                        else
                            mb[#mb + 1] = m
                        end
                    else
                        mb[#mb + 1] = str:fmtx( "Original filenaming preset '^1' already exists - you must restart Lightroom so it can be used by this plugin.", destFile )
                    end
                else
                    mb[#mb + 1] = orMsg
                end
            else
                mb[#mb + 1] = str:fmtx( "Unable to locate framework file: ^1", isA ) -- path where it was expected.
            end
        end
        if self.fnPreset then
            if self.altLookup then
                app:log( "'Original Filename' filenaming preset is available to use for obtaining original filenames, and may trump those in '^1' (depends on plugin/options..).", self.ofile )
            else
                app:log( "'Original Filename' filenaming preset will be used to obtain original filenames." )
            end
        else
            if self.altLookup then -- this'll do
                app:log( "'Original Filename' filenaming preset is NOT available to use for obtaining original filenames, so they will come from here: '^1'", self.ofile )
            else
                mb[#mb + 1] = str:fmtx( "You need to have one of two things for original filename support: 'Original Filenames' filenaming preset (restart Lightroom after it's been created), or SQLiteroom-compatible file: ^1", ofile )
            end
        end
        if self.altLookup or self.fnPreset then -- we got one or the other, which is all we need.
            if #mb > 0 then -- stuff happened, but hardly worth mentioning if all's well..
                app:logV( table.concat( mb, "\n \n" ) )
            end
            return true
        else
            assert( #mb > 0, "no mb" )
            return false, table.concat( mb, "\n \n" ) -- hopefully, this will be logged.
        end
    -- else initialized, or a failed attempt was made.
    end
    if self.fnPreset or self.altLookup then
        return true
    else
        return false, "Original filenames not initialized - something should have been logged about it.."    
    end
end
Catalog.initOriginalFilenames = Catalog.initForOriginalFilenames -- function Catalog:initOriginalFilenames( ... ) - probably a better name.



--- Determine if original filename subsystem is properly initialized.
--
--  @return file *iff* init'd sans issue.
--
function Catalog:isOriginalFilenamesInit()
    return self.altLookup and self.ofile
end



--- Add photo's original filename to lookup table.
--
--  @usage for importer support after new file added to catalog - supports dup. checking.
--
--  @param photo (lr-photo, required) photo
--  @param fn (string, required) filename (includes extension, but excludes path).
--
--  @return status (boolean) true iff added.
--  @return message (string) accompanies non-true status to explain.
--
function Catalog:addOriginalFilename( photo, fn )
    local s, m = self:initForOriginalFilenames()
    if not s then
        return nil, m
    end
    local id, err = self:getLocalImageId( photo )
    if id then
        if self.altLookup[id] ~= fn then
            Debug.pauseIf( self.altLookup[id] ~= nil, "original filename changed - hmm..." )
            self.altLookup[id] = fn -- record in ram for access prior to re-load..
            local s, m = self:appendOriginalFilename( id, fn ) -- add new filename to disk, for access after re-load (or log error tryin').
            if not s then
                assert( s ~= nil, "hmm...(s is nil)" ) -- as currently programmed, should be false or true.
                app:logE( m )
            end
        else
            Debug.pause( "original filename already present", id, fn ) -- in ram, presumably on disk too.
        end
        return true
    else
        return false, err
    end
end


-- could have a "remove original filename" method, but plugins not responsible for removal, just yet ###2 - not a bad idea though: if user was diligent to
-- only remove photos via plugin, then original filenames could be perfectly maintained.


--  Update original filenames disk file, in case plugin restarted, they'll remain current (so far: for internal use only).
--
--  @usage this method is synchronous but executes quickly, and logs successful info verbosely - problem log (or preferred handling) must be done externally.
--
--  @param id lr-photo local id.
--  @param fn filename
--
--  @return status (boolean) true iff success
--  @return message (string) iff not success
--
function Catalog:appendOriginalFilename( id, fn )
    if not self.ofile then
        Debug.pause("no orig file")
        return false, "no orig file"
    end
    local s, m, f
    return app:pcall{ name="Catalog_appendOriginalFilename", function( call )

        s, m = fso:getFileSize( self.ofile )
        if s then
            if s > 0 then
                f = io.open( self.ofile, "r+b" )
                -- search back for proper insertion point, i.e. before closing colon, and determine if previously last entry is comma terminated.
                local offset = s
                local p = f:seek( 'set', offset ) -- overwrite ending bracket.
                local c = f:read( 1 )
                while c ~= "}" and offset > 0 do -- normally, this loop is never even entered, since last char *is* '}'.
                    offset = offset - 1
                    p = f:seek( 'set', offset ) -- overwrite ending bracket.
                    c = f:read( 1 )
                end
                if offset == 0 then
                    app:error( "Bad original filenames file - bad table format." )
                end
                while c ~= "'" and c ~= '"' and c ~= "," and offset > 0 do -- this loop normally executes once, since c is '}', and previous character is usually '"'.
                    offset = offset - 1
                    p = f:seek( 'set', offset ) -- overwrite ending bracket.
                    c = f:read( 1 )
                end
                if offset == 0 then
                    app:error( "Bad original filenames file." )
                    return
                end
                if c ~= "," then -- quote (no comma after) - this is the current writing convention.
                    c = "," -- comma required as separator.
                else -- comma follows quote.
                    c = ""
                end
                local ln = c.."\n['"..id.."']=\""..fn.."\"}" -- terminate previously last entry, and add new entry on new line - close table.
                f:seek( "set", p + 1 ) -- assure correct write position.
                f:write( ln ) -- replace end of file..
                app:logV( "Original filename (^1) appended to original filenames file.", fn )
            else
                Debug.pause( "No data in original filenames file - rewriting it." ) -- this "shoudn't" happen.
                app:logW( "No data in original filenames file - rewriting it." )
                local ln = "return {\n['"..id.."']=\""..fn.."\"}"
                local s, m = fso:writeFile( self.ofile, ln )
                if s then
                    app:log( "Re-wrote original filenames file - contains just a single entry." )
                else
                    app:error( m )
                end
            end
        else
            app:error( m or "no file size" ) -- file gone missing..
        end
        
    end, finale=function( call )
        if f then
            f:close()
            --[[ this seems to be reliable, so double-checking no longer necessary - save for stormy day..
            if app:isAdvDbgEna() then
                local _s, _m = fso:getFileSize( self.ofile )
                if _s then
                    assert( _s > s, "hmm fn added but file not bigger?" )
                    _s, _m = pcall( dofile, self.ofile )
                    if not _s then
                        app:error( _m )
                    end
                else
                    app:error( _m )
                end
            -- else nada
            end
            --]]
        -- else error logged, hopefully.
        end
    end }
end



--- Initialize caches/lookups to be used by get-smart-colls.
--
function Catalog:initSmartColls()
    self.smartCollPhotoSet = {}
end



--- Get array of all collections in a set, optionally: smart collections too.
--
function Catalog:getCollsInCollSet( set, smToo )
    local colls = {}
    local function doColls( moreColls )
        if smToo then
            tab:appendArray( colls, moreColls )
        else
            for i, coll in ipairs( moreColls ) do
                if not coll:isSmartCollection() then
                    colls[#colls + 1] = coll
                end
            end
        end
    end
    local function doSet( theSet )
        doColls( theSet:getChildCollections() )
        for i, v in ipairs( theSet:getChildCollectionSets() ) do
            doSet( v )
        end
    end
    doSet( set )
    return colls 
end



--- Get smart collections associated with specified photo ###1 coll-set?
--
--  @usage probably needs to be called from async task, protected..
--
--  @return array of smart collections.
--
function Catalog:getSmartColls( photo, collSet )
    if not self.smartCollPhotoSet then
        Debug.pause( "Getting smart colls without pre-init smart colls - hmm..." ) -- recommend calling init first, as reminder that this function is only as good as how recently it's been initialized.
        self:initSmartColls()
    end
    app:callingAssert( gbl:getValue( 'SmartCollections' ), "'Catalog/SmartCollections' class needs to be required" )
    app:callingAssert( collSet, "need coll-set - can be catalog or publish service" )
    local smartColls = {}
    --local yc = 0
    --local strt = LrDate.currentTime()
    --local accr = 0
    --local cnt = 0
    --local ttl = 0
    local function getSome( from )
        --yc = app:yield( yc ) - this doesn't help
        local typ = cat:getSourceType( from )
        if typ:find( "Set" ) then
            for i, v in ipairs( from:getChildCollections() ) do
                getSome( v )
            end
            for i, v in ipairs( from:getChildCollectionSets() ) do
                getSome( v )
            end
        elseif typ:find( "Collection" ) then
            if from:isSmartCollection() then
                --ttl = ttl + 1
                if self.smartCollPhotoSet[from] == nil then
                    self.sco = self.sco or SmartCollections:new{ noInit=true } -- just need access to get-photos method which requires no special initialization.
                    --local mark = LrDate.currentTime()
                    self.smartCollPhotoSet[from] = tab:createSet( self.sco:getPhotos( from ) ) -- this is very time consuming.
                    --accr = accr + ( LrDate.currentTime() - mark )
                    --cnt = cnt + 1
                end
                if self.smartCollPhotoSet[from][photo] then
                    smartColls[#smartColls + 1] = from
                end
            -- else dont
            end
        elseif from.getChildCollections and from.getChildCollectionSets then -- includes lr-catalog & pub-srv objects.
            for i, v in ipairs( from:getChildCollections() ) do
                getSome( v )
            end
            for i, v in ipairs( from:getChildCollectionSets() ) do
                getSome( v )
            end
        else
            app:error( "Invalid source type: ^1", typ )
        end
    end
    getSome( collSet )
    --Debug.pause( LrDate.currentTime() - strt, accr, ttl, cnt )
    return smartColls
end



--- Get batch of raw metadata without bringing down the system.
--
--  @usage I'm not sure about the value of this function - I think this did not fix a problem caused by something else.
--  @usage Gets in batches of 1000 instead of all at once, presumably to keep Lr from being unresponsive or using too much memory or something - don't remember 'zactly.
--  @usage must be called from async task.
--  @usage this method may take a loooong time to run, so consider displaying progress scope before calling.
--
--  @param photos array of lr-photos
--  @param ... raw IDs
--
--  @return table, indexed by photos, values are metadata tables, whose keys are metadata ids and values are metadata.
--
function Catalog:getBatchRawMetadata( photos, ... )
    local photoBuf
    if #photos <= 1000 then
        return catalog:batchGetRawMetadata( photos, ... )
    else
        photoBuf = tab:arraySlice( photos, 1, 1000 ) -- partial
    end
    local rawMeta = {}
    local index = 1001 -- next array slice starting index
    while #photoBuf > 0 do
        local dataBuf = catalog:batchGetRawMetadata( photoBuf, ... )
        tab:addItems( rawMeta, dataBuf )
        photoBuf = tab:arraySlice( photos, index, index + 999 )
        index = index + 1000
        LrTasks.sleep( .5 ) -- this seems to help even out the load, without impacting performance too much (getting metadata for a thousand photos generally takes a few seconds or more).
        if shutdown then return {} end
    end
    return rawMeta
end



--- Get batch of formatted metadata without bringing down the system.
--
--  @usage I'm not sure about the value of this function - I think this did not fix a problem caused by something else.
--  @usage Gets in batches of 1000 instead of all at once, presumably to keep Lr from being unresponsive or using too much memory or something - don't remember 'zactly.
--  @usage must be called from async task.
--  @usage this method may take a loooong time to run, so consider displaying progress scope before calling.
--
--  @return table, indexed by photos, values are metadata tables, whose keys are metadata ids and values are metadata.
--
function Catalog:getBatchFormattedMetadata( photos, ... )
    local photoBuf
    if #photos <= 1000 then
        return catalog:batchGetFormattedMetadata( photos, ... )
    else
        photoBuf = tab:arraySlice( photos, 1, 1000 ) -- partial
    end
    local fmtMeta = {}
    local index = 1001 -- next array slice starting index
    while #photoBuf > 0 do
        local dataBuf = catalog:batchGetFormattedMetadata( photoBuf, ... )
        tab:addItems( fmtMeta, dataBuf )
        photoBuf = tab:arraySlice( photos, index, index + 999 )
        index = index + 1000
        LrTasks.sleep( .5 ) -- this seems to help even out the load, without impacting performance too much (getting metadata for a thousand photos generally takes a few seconds or more).
        if shutdown then return {} end
    end
    return fmtMeta
end



--- Get folder path, normalized (without the trailing -slash which accompanies top-level folders).
--
function Catalog:getFolderPath( f )
    local fPath = f:getPath()
    if fPath:sub( -1 ):find( "[\\/]" ) then -- trailing slash or backslash (probably would manifest as OS path sep, but cheap insurance to check both..).
        return fPath:sub( 1, #fPath - 1 ) -- assuming only one.
    else
        return fPath
    end
end



--- Determine if two folders are equal.
--  @usage object equality only valid if both folders are top-level, or neither is.
function Catalog:isEqualFolders( f1, f2 )
    if f1 == f2 then -- if equal, then equal.
        return true
    else -- equality based on normalized paths.
        return self:getFolderPath( f1 ) == self:getFolderPath( f2 )
    end
end
Catalog.foldersAreEqual = Catalog.isEqualFolders -- function Catalog:foldersAreEqual( ... ) -- "natural" syntax / synonym.
Catalog.isFolderEqual = Catalog.isEqualFolders -- function Catalog:isFolderEqual( ... ) -- if you prefer..
        
        

return Catalog

