--[[
        LrMetadata.lua
        
        Interface for Lr-standard raw & formatted metadata "utility" methods - initialized as part of framework.
--]]        



local LrMetadata, dbg, dbgf = Object:newClass{ className='LrMetadata', register=true } -- registration is default, but explicit for clarity..



-- Metadata cache object, methods are exposed externally, but creation is private / internal-only. - use create-cache method externally to "construct" a new (initialized) cache object.

local Cache = Object:newClass{ className='LrMetadataCache', register=false }

--[[
        Example use of cache objects:
        
        local cache = lrMeta:createCache() -- empty cache.
        local photos = catalog:getTargetPhotos()
        cache:loadFormattedMetadata( photos, { 'copyName' } )
        cache:loadRawMetadata( photos, { 'path' } )
        for i, photo in ipairs( photos ) do        
            local cn = cache:getFormattedMetadata( photo, 'copyName' )
            local pth = cache:getRawMetadata( photo, 'path' )
            local fnc = my:getFancy( blah, blah, blah, cache )
            -- ...
        end
        
        also:
        
        local cache - lrMeta:createCache{ photos=photos, rawIds={...}, fmtIds={...} } -- fill in the ID blanks..
        local metadata = lrMeta:getRaw( photo, name, cache ) -- get from cache, if available, else photo directly.
        
        Note: in adv.debug mode, if metadata not in cache, it will be debug-logged (if lr-metadata class is enabled), so you can see which items may be added for improved efficiency.
--]]

--- Constructor for new instance.
--
--  @usage presently no way to extend internal cache class.<br>
--         if that changes, then provide new class constructor and go through object factory to create.
--
function Cache:new( t )
    local o = Object.new( self, t )
    return o
end



--- Assure specified formatted metadata is in cache for short-term future use.
--
--  @usage      clears any previous metadata from cache - use add-fmt-metadata to, well, add formatted metadata to the cache.
--
function Cache:loadFormattedMetadata( photos, names )
    if #photos == 1 then
        local fmtMeta = {}
        local photo = photos[1]
        for i, id in ipairs( names ) do
            fmtMeta[id] = photo:getFormattedMetadata( id ) -- I'm assuming it's faster to get metadata for one photo using this method insead of batch method.
        end
        self.fmtMeta = { [photo]=fmtMeta }
    else -- sometimes #photos is zero, in which case this won't fail, even if non-optimal..
        self.fmtMeta = cat:getBatchFormattedMetadata( photos, names )
    end
    self.fmtLookup = {}
    for i, name in ipairs( names ) do
        self.fmtLookup[name] = true
    end
end    
    


--- Get specified formatted metadata, hopefully from cache.
--
--  @usage Enable advanced debugging for this module to see uncached metadata accesses.
--
function Cache:getFormattedMetadata( photo, name, acceptUncached, rejectNil )
    local value
    if self.fmtMeta ~= nil then
        if self.fmtLookup[name] then
            if self.fmtMeta[photo] ~= nil then
                value = self.fmtMeta[photo][name]
            elseif acceptUncached then
                dbgf( "Uncached formatted metadata id: '^1'", name )
                value = photo:getFormattedMetadata( name )
            else
                app:callingError( "need formatted metadata named '^1' for photo: ^2", name, cat:getPhotoNameDisp( photo, true, nil ) )
            end
        elseif acceptUncached then
            dbgf( "Formatted metadata uncached for name: ^1", name ) -- in the interest of performance, don't use photo name.
            value = photo:getFormattedMetadata( name )
        else
            app:callingError( "Formatted metadata not available in cache for name: ^1", name )
        end
    elseif acceptUncached then
        dbgf( "No formatted metadata in cache, fetching from photo for name: ^1", name ) -- in the interest of performance, don't use photo name.
        value = photo:getFormattedMetadata( name )
    else
        app:callingError( "No formatted metadata in cache, for *any* photos, so can't get '^1' from cache for ^2", name, cat:getPhotoNameDisp( photo, true, nil ) )
    end
    if value == nil and rejectNil then
        app:callingError( "^1 is nil (formatted metadata) for photo: ^2", name, cat:getPhotoNameDisp( photo, true, nil ) )
    end
    return value
end
Cache.getFmt = Cache.getFormattedMetadata -- function Cache:getFmt( ... ) - synonym/shortcut..



--- Cache specified raw metadata for short-term future use.
--
--  @usage      clears any previous metadata from cache - use add-raw-metadata to, well, add raw metadata to the cache.
--
function Cache:loadRawMetadata( photos, names )
    if #photos == 1 then -- new @6/Dec/2014 20:49 - dunno if faster or not ###4
        local rawMeta = {}
        local photo = photos[1]
        for i, id in ipairs( names ) do
            rawMeta[id] = photo:getRawMetadata( id ) -- I'm assuming it's faster to get metadata for one photo using this method insead of batch method.
        end
        self.rawMeta = { [photo]=rawMeta }
    else -- sometimes #photos is zero, in which case this won't fail, even if non-optimal..
        self.rawMeta = cat:getBatchRawMetadata( photos, names )
    end
    self.rawLookup = {} -- name lookup
    for i, name in ipairs( names ) do
        self.rawLookup[name] = true -- ok, really it's a set not a lookup.
    end
end    



-- if metadata for incoming photos already exists, merge incoming metadata.
-- if not, then make sure metadata for new photos is added.
function Cache:_mergeMetadata( meta, photos, newMeta )
    -- add metadata to entries for existing photos
    if newMeta == nil then
        Debug.pause( "no metadata to merge" )
        return
    end
    local merged = {}
    for photo, data in pairs( meta ) do -- peruse photos in existing set.
        if newMeta[photo] then
            tab:addToSet( data, newMeta[photo] )
        else
            -- Debug.pause( "no new meta" )
        end
        merged[photo] = true
    end
    -- consider added photos
    for i, photo in ipairs( photos ) do
        if not merged[photo] then -- new
            meta[photo] = newMeta[photo]
        end
    end
end



--- Add raw metadata to cache - note: photos may be different, caller of get-raw-metadata beware.
--
function Cache:addRawMetadata( photos, names )
    if self.rawMeta == nil or self.rawLookup == nil then
        self:loadRawMetadata( photos, names )
        return self.rawMeta
    end
    local rawMeta = cat:getBatchRawMetadata( photos, names ) -- ###2 could optimize for 1-photo?
    
    -- new @1/Feb/2013 20:11:
    if rawMeta then -- this test added 17/Mar/2013 18:37
        self:_mergeMetadata( self.rawMeta, photos, rawMeta ) -- beware, as coded, not all photos will necessarily have the same complement of metadata items.
    else
        app:callingError( "no raw metadata to add" )
    end
    --tab:addToSet( self.rawMeta, rawMeta ) - until 1/Feb/2013 20:11.
    
    tab:addToSet( self.rawLookup, names )
    return self.rawMeta
end



--- Add formatted metadata to cache - note: photos may be different, caller of get-fmt-metadata beware.
--
function Cache:addFormattedMetadata( photos, names )
    if self.fmtMeta == nil or self.fmtLookup == nil then
        self:loadFormattedMetadata( photos, names )
        return self.fmtMeta
    end
    local fmtMeta = cat:getBatchFormattedMetadata( photos, names ) -- ###2 could optimize for 1-photo?
    if fmtMeta then -- this test added 17/Mar/2013 18:37
        self:_mergeMetadata( self.fmtMeta, photos, fmtMeta )
    else
        app:callingError( "no formatted metadata to add" )
    end
    tab:addToSet( self.fmtLookup, names )
    return self.fmtMeta
end



--- Get specified raw metadata, hopefully from cache.
--
--  @usage Enable advanced debugging for this module to see uncached metadata accesses.
--
function Cache:getRawMetadata( photo, name, acceptUncached, rejectNil )
    local value
    if self.rawMeta ~= nil then
        if self.rawLookup[name] then -- is guaranteed to be in for some, but not all photos (since the introduction of add-metadata functions).
            --Debug.pause( name, self.rawMeta[photo][name] )
            if self.rawMeta[photo] ~= nil then
                value = self.rawMeta[photo][name]
            elseif acceptUncached then
                dbgf( "Uncached raw metadata id: '^1'", name )
                value = photo:getRawMetadata( name )
            else
                app:error( "need raw metadata for photo to get ^1 for ^2", name, photo:getRawMetadata( 'path' ) )
            end
        elseif acceptUncached then
            dbgf( "Raw metadata uncached for name: ^1", name )
            value = photo:getRawMetadata( name )
        else
            app:error( "Raw metadata not available in cache for name: ^1", name )
        end
    elseif acceptUncached then
        dbgf( "No raw metadata in cache, fetching from photo for name: ^1", name )
        value = photo:getRawMetadata( name )
    else
        app:error( "No raw metadata in cache." )
    end
    if value == nil and rejectNil then
        app:error( "^1 is nil (raw metadata).", name )
    end
    return value
end
Cache.getRaw = Cache.getRawMetadata -- function Cache:getRaw( ... )



--- Get raw metadata table - for legacy methods that still require separate, raw-meta and fmt-meta tables.
--
--  @return lookup table, needs to be indexed by photo, value contains raw metadata table (key is id, value is metadata).
--
function Cache:getRawMeta()
    return self.rawMeta
end



--- Get formatted metadata table - for legacy methods that still require separate, raw-meta and fmt-meta tables.
--
--  @return lookup table, needs to be indexed by photo, value contains fmt metadata table (key is id, value is metadata).
--
function Cache:getFmtMeta()
    return self.fmtMeta
end



--  L R - M E T A D A T A   M E T H O D S



--- Create metadata cache for local use.
--
--  @usage      equivalent to Lr catalog's batch get metadata functions, with the following conveniences:
--      <br>You can add metadata to the cache, for same or different photos, after the fact.
--      <br>When getting metadata via lr-meta methods, it will take from cache if available, else photo - thus no "attempt to index nil..." errors.
--      <br>if data not in cache, debug message logged, so you can try passing an empty cache, and then based on what's logged learn how to fill it.
--  @usage      If you you know the cache variable exists, then there is no reason not to access directly, setting accept-cached as desired, 
--      <br>but if cache is being passed in, it's best to call lr-meta--get-raw/fmt instead, since it not only checks for cache, but accepts uncached.
--
--  @param      t       (table, optional) members: photos, rawIds, fmtIds, call. If provided, cache will be pre-loaded (and call used for caption while loading).
--
function LrMetadata:createCache( t )
    local c = Cache:new()
    t = t or {}
    local cap
    if t.call then
        cap = t.call:setCaption( "Gathering requisite metadata..." )
    end
    if t.photos then
        if t.rawIds then
            c:loadRawMetadata( t.photos, t.rawIds )
        end
        if t.fmtIds then
            c:loadFormattedMetadata( t.photos, t.fmtIds )
        end
    end
    if cap then
        t.call:setCaption( cap )
    end
    return c
end



--- Constructor for extending class.
--
function LrMetadata:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function LrMetadata:new( t )
    local o = Object.new( self, t )
    o.simple = tab:createSet{ 'string', 'number', 'boolean' }
    o.other = tab:createSet{ 'array', 'struct', 'proxy' }
    return o
end



--- Determine if key is known in formatted metadata.
--
function LrMetadata:isKnownKey( photo, name )
    photo = photo or cat:getAnyPhoto() or app:error( "no photos" )
    local s, m = LrTasks.pcall( photo.getFormattedMetadata, photo, name )
    if s then
        return true
    else
        return false
    end
end
LrMetadata.isKnownFmtKey = LrMetadata.isKnownKey -- function LrMetadata:isKnownFmtKey(...) - synonym for consistency with raw version.



--- Determine if key is valid for reading raw metadata.
--
--  @param photo (LrPhoto, optional) test photo.
--  @param name (string, required) key.
-- 
function LrMetadata:isKnownRawKey( photo, name )
    photo = photo or cat:getAnyPhoto()
    if photo == nil then
        app:error( "no photo" )
    end
    local s, m = LrTasks.pcall( photo.getRawMetadata, photo, name )
    if s then
        return true
    else
        return false
    end
end



--- Initialize data descriptors for getting/setting raw/formatted Lightroom metadata.
--
--  @usage called automatically if need be, but feel free to call upon plugin init for faster initial on-demand response.
--  @usage info is static, so only needs to be called once.
--
function LrMetadata:init()
    if self.rawGetDescr then return end -- init is static.
    self.rawGetDescr = {
        { id='fileSize', friendly="File Size", dataType='number', viewType='' }, --  (number) The size of the file in bytes
        { id='rating', friendly="Rating", dataType='number', viewType='' }, --  (number) The user rating of the file (number of stars)
        { id='dimensions', friendly="Dimensions", dataType='struct', viewType='' }, --  (table) The original dimensions of file (for example, { width = 2304, height = 3072 } )
        { id='croppedDimensions', friendly="Cropped Dimensions", dataType='struct', viewType='' }, --  (table) The cropped dimensions of file (for example, { width = 2304, height = 3072 } )
        { id='shutterSpeed', friendly="Shutter Speed", dataType='number', viewType='' }, --  (number) The shutter speed, in seconds (for example, 1/60 sec = 0.016666)
        { id='aperture', friendly="Aperture", dataType='number', viewType='' }, --  (number) The denominator of the aperture (for example, 2.8)
        { id='exposureBias', friendly="Exposure Bias", dataType='number', viewType='' }, --  (number) The exposure bias/compensation (for example, -0.666666)
        { id='flash', friendly="Flash", dataType='boolean', viewType='' }, --  (Boolean) Whether flash fired or not (true = flash fired; false = flash did not fire; nil = unknown)
        { id='isoSpeedRating', friendly="ISO", dataType='number', viewType='' }, --  (number) The ISO speed rating (for example, 200)
        { id='focalLength', friendly="Focal Length", dataType='number', viewType='' }, --  (number) The focal length of lens as shot, in millimeters (for example, 132)
        { id='focalLength35mm', friendly="Focal Length 35mm", dataType='number', viewType='' }, --  (number) The focal length as 35mm equivalent, in millimeters (for example, 211.2)
        { id='dateTimeOriginal', friendly="Capture Time", dataType='number', viewType='' }, --  (number) The date and time of capture (seconds since midnight GMT January 1, 2001)
        { id='dateTimeDigitized', friendly="Digitization Time", dataType='number', viewType='' }, --  (number) The date and time of scanning (seconds since midnight GMT January 1, 2001)
        { id='dateTime', friendly="Date/Time", dataType='number', viewType='' }, --  (number) The adjusted date and time (seconds since midnight GMT January 1, 2001)
        { id='gps', friendly="GPS", dataType='struct', viewType='' }, --  (table) The location of this photo (for example, { latitude = 37.9362, longitude = 27.3451 } )
        { id='gpsAltitude', friendly="GPS Altitude", dataType='number', viewType='' }, --  (number) The GPS altitude for this photo, in meters (for example, 82.317)
        { id='countVirtualCopies', friendly="Count Virtual Copies", dataType='number', viewType='' }, --  (number) The number of virtual copies of this photo. Zero if this photo is itself a virtual copy.
        { id='virtualCopies', friendly="Virtual Copies", dataType='array', viewType='' }, --  (array of LrPhoto) All virtual copies of this photo.
        { id='masterPhoto', friendly="Master Photo", dataType='proxy', viewType='' }, --  (LrPhoto) The master photo from which this virtual copy is derived.
        { id='isVirtualCopy', friendly="Is Virtual Copy", dataType='boolean', viewType='' }, --  (Boolean) True if this photo is a virtual copy of another photo.
        { id='countStackInFolderMembers', friendly="Count Stack in Folder Members", dataType='number', viewType='' }, --  (number) The number of the members of the stack that this photo is in.
        { id='stackInFolderMembers', friendly="Stack in Folder Members", dataType='array', viewType='' }, --  (array of LrPhoto) All members of the stack that this photo is in.
        { id='isInStackInFolder', friendly="Is in Stack in Folder", dataType='boolean', viewType='' }, --  (Boolean) True if the photo is in a stack.
        { id='stackInFolderIsCollapsed', friendly="Stack in Folder is Collapsed", dataType='boolean', viewType='' }, --  (Boolean) True if the stack containing this photo is collapsed.
        { id='stackPositionInFolder', friendly="Stack Position in Folder", dataType='string', viewType='' }, --  (string) The position of this photo in the stack. The top of the stack is at position 1; other photos are numbered sequentially starting from 2.
        { id='topOfStackInFolderContainingPhoto', friendly="Top of Stack in Folder Containing Photo", dataType='proxy', viewType='' }, --  (LrPhoto) The parent photo of the stack containing this photo.
        { id='colorNameForLabel', friendly="Color Name for Label", dataType='string', viewType='' }, --  (string) The color name corresponding to the color label associated with this photo. 
        { id='fileFormat', friendly="File Format", dataType='string', viewType='' }, --  (string) The format of the file. One of 'RAW', 'DNG', 'JPG', 'PSD', 'TIFF', or 'VIDEO'.
        { id='width', friendly="Width", dataType='number', viewType='' }, --  (number) The width of the original source photo in pixels.
        { id='height', friendly="Height", dataType='number', viewType='' }, --  (number) The height of the original source photo in pixels.
        { id='aspectRatio', friendly="Aspect Ratio", dataType='number', viewType='' }, --  (number) The aspect ratio of the photo (defined as width / height). (For example, a standard 35mm photo in landscape mode returns 1.5.).
        { id='isCropped', friendly="Is Cropped", dataType='boolean', viewType='' }, --  (Boolean) True if the photo has been cropped in Lightroom from its original dimensions.
        { id='dateTimeOriginalISO8601', friendly="Capture Time (ISO8601)", dataType='string', viewType='' }, --  (string) The date and time of capture (ISO 8601 string format).
        { id='dateTimeDigitizedISO8601', friendly="Digitization Time (ISO8601)", dataType='string', viewType='' }, --  (string) The date and time of scanning (ISO 8601 string format).
        { id='dateTimeISO8601', friendly="Date/Time (ISO8601)", dataType='string', viewType='' }, --  (string) The adjusted date and time (ISO 8601 string format).
        { id='lastEditTime', friendly="Last Edit Time", dataType='number', viewType='' }, --  (number) The date and time of the last edit to this photo (seconds since midnight GMT January 1, 2001).
        { id='editCount', friendly="Edit Count", dataType='number', viewType='' }, --  (number) Counter for edits on this photo. (Warning - This is not an absolute counter. Consecutive changes within a few seconds are counted as a single edit.)
        { id='uuid', friendly="UUID", dataType='string', viewType='' }, --  (string) Persistent ID for this photo
        { id='path', friendly="Path", dataType='string', viewType='' }, --  (string) The current path to the photo file if available; otherwise, the last known path to the file.
        { id='isVideo', friendly="Is Video", dataType='boolean', viewType='' }, --  (boolean) True if this file is a video.
        { id='durationInSeconds', friendly="Duration in Seconds", dataType='number', viewType='' }, --  (number) The duration in seconds if the file is a video.
        { id='keywords', friendly="Keywords", dataType='array', viewType='' }, --  (array of LrKeyword) The list of keyword objects for the photo.
        { id='customMetadata', friendly="Custom Metadata", dataType='struct', viewType='' }, --  (table) Custom metadata for this photo as shown in the Metadata panel. Each element in the return table is a table that describes one metadata field associated with a photo, with these entries:
--          id (string): A unique identifier for this field.
--          value (any): The value for this field, if any.
--          sourcePlugin (string): The unique identifier of the plug-in that defines the custom metadata.
    }
--    The following items are first supported in version 4.0 of the Lightroom SDK.
    if app:lrVersion() >= 4 then
        self.rawGetDescr[#self.rawGetDescr + 1] = { id='pickStatus', friendly="Pick Status", dataType='number', viewType='' } --  (number) 1 if the photo's flag status is 'picked', 0 if the photo's flag is not set, -1 if the photo's flag status is 'rejected'.
--    The following items are first supported in version 4.1 of the Lightroom SDK.
        self.rawGetDescr[#self.rawGetDescr + 1] = { id='trimmedDurationInSeconds', friendly="Trimmed Duration in Seconds", dataType='number', viewType='' } --  (number) If the file is a video, the trimmed duration of the video in seconds, otherwise nil.
        self.rawGetDescr[#self.rawGetDescr + 1] = { id='durationRatio', friendly="Duration Ratio", dataType='struct', viewType='' } --  (table) If the file is a video, a table, otherwise nil. The table has keys 'numerator' and 'denominator', which combine to the untrimmed duration of the video in seconds.
        self.rawGetDescr[#self.rawGetDescr + 1] = { id='trimmedDurationRatio', friendly="Trimmed Duration Ratio", dataType='struct', viewType='' } --  (table) If the file is a video, a table, otherwise nil. The table has keys 'numerator' and 'denominator', which combine to the trimmed duration of the video in seconds.
        self.rawGetDescr[#self.rawGetDescr + 1] = { id='locationIsPrivate', friendly="Location is Private", dataType='boolean', viewType='' } --  (Boolean) True if the photo's location has been marked as private in Lightroom.      
    end
    -- Lr5
    if app:lrVersion() >= 5 then
        self.rawGetDescr[#self.rawGetDescr + 1] = { id='smartPreviewInfo', friendly="Smart Preview Info", dataType='struct', viewType='' } --  smartPreviewPath, smartPreviewSize.
    end
    self.rawSetDescr = {
        { id='rating', friendly="Rating", dataType='number', viewType='' },
        { id='label', friendly="Label", dataType='string', viewType='' },
        { id='title', friendly="Title", dataType='string', viewType='' },
        { id='caption', friendly="Caption", dataType='string', viewType='' },
        { id='copyName', friendly="Virtual Copy Name", dataType='string', viewType='' },
        { id='creator', friendly="Creator", dataType='string', viewType='' },
        { id='creatorJobTitle', friendly="Creator Job Title", dataType='string', viewType='' },
        { id='creatorAddress', friendly="Creator Address", dataType='string', viewType='' },
        { id='creatorCity', friendly="Creator City", dataType='string', viewType='' },
        { id='creatorStateProvince', friendly="Creator State/Province", dataType='string', viewType='' },
        { id='creatorPostalCode', friendly="Creator Postal Code", dataType='string', viewType='' },
        { id='creatorCountry', friendly="Creator Country", dataType='string', viewType='' },
        { id='creatorPhone', friendly="Creator Phone", dataType='string', viewType='' },
        { id='creatorEmail', friendly="Creator Email", dataType='string', viewType='' },
        { id='creatorUrl', friendly="Creator URL", dataType='string', viewType='' },
        { id='headline', friendly="Headline", dataType='string', viewType='' },
        { id='iptcSubjectCode', friendly="IPTC Subject Code", dataType='string', viewType='' },
        { id='descriptionWriter', friendly="Description Writer", dataType='string', viewType='' },
        { id='iptcCategory', friendly="IPTC Category", dataType='string', viewType='' },
        { id='iptcOtherCategories', friendly="IPTC Other Categories", dataType='string', viewType='' },
        { id='dateCreated', friendly="Date Created", dataType='string', viewType='' },
        { id='intellectualGenre', friendly="Intellectual Genre", dataType='string', viewType='' },
        { id='scene', friendly="Scene", dataType='string', viewType='' },
        { id='location', friendly="Location", dataType='string', viewType='' },
        { id='city', friendly="City", dataType='string', viewType='' },
        { id='stateProvince', friendly="State/Province", dataType='string', viewType='' },
        { id='country', friendly="Country", dataType='string', viewType='' },
        { id='isoCountryCode', friendly="(ISO) Country Code", dataType='string', viewType='' },
        { id='jobIdentifier', friendly="Job Identifier", dataType='string', viewType='' },
        { id='instructions', friendly="Instructions", dataType='string', viewType='' },
        { id='provider', friendly="Provider", dataType='string', viewType='' },
        { id='source', friendly="Source", dataType='string', viewType='' },
        { id='copyright', friendly="Copyright", dataType='string', viewType='' },
        { id='copyrightState', friendly="Copyright State", dataType='string', viewType='' },
        { id='rightsUsageTerms', friendly="Rights Usage Terms", dataType='string', viewType='' },
        { id='copyrightInfoUrl', friendly="Copyright Info URL", dataType='string', viewType='' },
        { id='copyrightInfo', friendly="Copyright Info", dataType='string', viewType='' },
        { id='colorNameForLabel', friendly="Color Name for Label", dataType='string', viewType='' },
        { id='personShown', friendly="Person Shown", dataType='string', viewType='' },
        { id='locationCreated', friendly="Location Created", dataType='struct', viewType='' }, -- array-of-struct ###1
        { id='locationShown', friendly="Location Shown", dataType='struct', viewType='' }, -- array-of-struct ###1
        { id='nameOfOrgShown', friendly="Name of Organization Shown", dataType='string', viewType='' },
        { id='codeOfOrgShown', friendly="Code of Organization Shown", dataType='string', viewType='' },
        { id='event', friendly="Event", dataType='string', viewType='' },
        { id='artworksShown', friendly="Artworks Shown", dataType='struct', viewType='' }, -- array-of-struct ###1
--[[
    artworksShown = {
        [1] = {
            AOSource = "dunno", 
            AOSourceInvNo = "2", 
            AOCreator = "me", 
            AOCopyrightNotice = "cpyrt...", 
            AOTitle = "ttl", 
            AODateCreated = "2014-01-01"}, 
        -- [2]...
}, 
--]]        
        { id='additionalModelInfo', friendly="Additional Model Info", dataType='string', viewType='' },
        { id='modelAge', friendly="Model Age", dataType='string', viewType='' },
        { id='minorModelAge', friendly="Minor Model Age", dataType='string', viewType='' },
        { id='modelReleaseStatus', friendly="Model Release Status", dataType='string', viewType='' },
        { id='modelReleaseID', friendly="Model Release ID", dataType='string', viewType='' },
        { id='imageSupplier', friendly="Image Supplier", dataType='struct', viewType='' },
        { id='com.adobe.imageSupplierImageId', friendly="Image Supplier Image ID", dataType='string', viewType='' }, -- guessed at data-type.
        { id='registryId', friendly="Registry ID", dataType='struct', viewType='' }, -- array-of-struct ###1
--[[
        [1] = {
            RegOrgId = "asdf", 
            RegItemId = "asfddsfadsf"}, 
        [2] = {}}, 
--]]        
        { id='maxAvailWidth', friendly="Max Available Width", dataType='number', viewType='' },
        { id='maxAvailHeight', friendly="Max Available Height", dataType='number', viewType='' },
        { id='sourceType', friendly="Source Type", dataType='string', viewType='' },
        { id='imageCreator', friendly="Image Creator", dataType='struct', viewType='' }, -- array-of-struct ###1
        { id='copyrightOwner', friendly="Copyright Owner", dataType='struct', viewType='' }, -- array-of-struct ###1
        { id='licensor', friendly="Licensor", dataType='struct', viewType='' }, -- array-of-struct ###1
        { id='propertyReleaseID', friendly="Property Release ID", dataType='struct', viewType='' }, -- "
        { id='propertyReleaseStatus', friendly="Property Release Status", dataType='struct', viewType='' }, -- "
    }
    if app:lrVersion() >= 4 then
        self.rawSetDescr[#self.rawSetDescr + 1] = { id='gps', friendly="GPS", dataType='struct', viewType='' } -- ?
        self.rawSetDescr[#self.rawSetDescr + 1] = { id='gpsAltitude', friendly="GPS Altitude", dataType='number', viewType='' }
        self.rawSetDescr[#self.rawSetDescr + 1] = { id='pickStatus', friendly="Pick Status", dataType='number', viewType='' }
    end
    self.fmtGetDescr = {
        { id='keywordTags', friendly="Keywords", dataType='string', viewType='' }, -- (string) The list of keywords as shown in the Keyword Tags panel (with Enter Keywords selected). This is the exact set of tags that were directly applied to the photo without any filtering for "Show on Export" flags, etc.
        { id='keywordTagsForExport', friendly="Exportable Keywords", dataType='string', viewType='' }, --  (string) The list of keywords as shown in the Keyword Tags panel (with Will Export selected). First supported as of Lightroom 2.0. This removes tags that were meant to be hidden via "Show on Export" and inserts all of the parents and ancestor tags (except when silenced via "Export Containing Keywords").
        { id='fileName', friendly="File Name", dataType='string', viewType='' }, --  (string) The leaf name of the file (for example, "myFile.jpg")
        { id='copyName', friendly="Virtual Copy Name", dataType='string', viewType='' }, --  (string) The name associated with this copy
        { id='folderName', friendly="Folder Name", dataType='string', viewType='' }, --  (string) The name of the folder the file is in
        { id='fileSize', friendly="File Size", dataType='string', viewType='' }, --  (string) The formatted size of the file (for example, "6.01 MB")
        { id='fileType', friendly="File Type", dataType='string', viewType='' }, --  (string) The user-visible file type (DNG, RAW, etc.)
        { id='rating', friendly="Rating", dataType='number', viewType='' }, --  (number) The user rating of the file (number of stars)
        { id='label', friendly="Label", dataType='string', viewType='' }, --  (string) The name of assigned color label
        { id='title', friendly="Title", dataType='string', viewType='' }, --  (string) The title of photo
        { id='caption', friendly="Caption", dataType='string', viewType='' }, --  (string) The caption for photo
        { id='dimensions', friendly="Dimensions", dataType='string', viewType='' }, --  (string) The original dimensions of file (for example', "3072 x 2304")
        { id='croppedDimensions', friendly="Cropped Dimensions", dataType='string', viewType='' }, --  (string) The cropped dimensions of file (for example', "3072 x 2304")
        { id='exposure', friendly="Exposure", dataType='string', viewType='' }, --  (string) The exposure summary (for example', "1/60 sec at f/2.8")
        { id='shutterSpeed', friendly="Shutter Speed", dataType='string', viewType='' }, --  (string) The shutter speed (for example', "1/60 sec")
        { id='aperture', friendly="Aperture", dataType='string', viewType='' }, --  (string) The aperture (for example', "f/2.8")
        { id='brightnessValue', friendly="Brightness Value", dataType='string', viewType='' }, --  (string) The brightness value (HELP: need an example)
        { id='exposureBias', friendly="Exposure Bias", dataType='string', viewType='' }, --  (string) The exposure bias/compensation (for example', "-2/3 EV")
        { id='flash', friendly="Flash", dataType='string', viewType='' }, --  (string) Whether the flash fired or not (for example', "Did fire")
        { id='exposureProgram', friendly="Exposure Program", dataType='string', viewType='' }, --  (string) The exposure program (for example', "Aperture priority")
        { id='meteringMode', friendly="Metering Mode", dataType='string', viewType='' }, --  (string) The metering mode (for example', "Pattern")
        { id='isoSpeedRating', friendly="ISO", dataType='string', viewType='' }, --  (string) The ISO speed rating (for example', "ISO 200")
        { id='focalLength', friendly="Focal Length", dataType='string', viewType='' }, --  (string) The focal length of lens as shot (for example', "132 mm")
        { id='focalLength35mm', friendly="Focal Length 35mm", dataType='string', viewType='' }, --  (string) The focal length as 35mm equivalent (for example', "211 mm")
        { id='lens', friendly="Lens", dataType='string', viewType='' }, --  (string) The lens (for example', "28.0-135.0 mm")
        { id='subjectDistance', friendly="Focus Distance", dataType='string', viewType='' }, --  (string) The subject distance (for example', "3.98 m")
        { id='dateTimeOriginal', friendly="Capture Time", dataType='string', viewType='' }, --  (string) The date and time of capture (for example', "09/15/2005 17:32:50") Formatting can vary based on the user's localization settings
        { id='dateTimeDigitized', friendly="Digitization Time", dataType='string', viewType='' }, --  (string) The date and time of scanning (for example', "09/15/2005 17:32:50") Formatting can vary based on the user's localization settings
        { id='dateTime', friendly="Date/Time", dataType='string', viewType='' }, --  (string) Adjusted date and time (for example', "09/15/2005 17:32:50") Formatting can vary based on the user's localization settings
        { id='cameraMake', friendly="Camera Make", dataType='string', viewType='' }, --  (string) The camera manufacturer
        { id='cameraModel', friendly="Camera Model", dataType='string', viewType='' }, --  (string) The camera model
        { id='cameraSerialNumber', friendly="Camera Serial Number", dataType='string', viewType='' }, --  (string) The camera serial number
        { id='artist', friendly="Artist", dataType='string', viewType='' }, --  (string) The artist's name
        { id='software', friendly="Software", dataType='string', viewType='' }, --  (string) The software used to process/create photo
        { id='gps', friendly="GPS", dataType='string', viewType='' }, --  (string) The location of this photo (for example', "37°56'10" N 27°20'42" E")
        { id='gpsAltitude', friendly="GPS Altitude", dataType='string', viewType='' }, --  (string) The GPS altitude for this photo (for example', "82.3 m")
        { id='creator', friendly="Creator", dataType='string', viewType='' }, --  (string) The name of the person that created this image
        { id='creatorJobTitle', friendly="Creator Job Title", dataType='string', viewType='' }, --  (string) The job title of the person that created this image
        { id='creatorAddress', friendly="Creator Address", dataType='string', viewType='' }, --  (string) The address for the person that created this image
        { id='creatorCity', friendly="Creator City", dataType='string', viewType='' }, --  (string) The city for the person that created this image
        { id='creatorStateProvince', friendly="Creator State/Province", dataType='string', viewType='' }, --  (string) The state or province for the person that created this image
        { id='creatorPostalCode', friendly="Creator Postal Code", dataType='string', viewType='' }, --  (string) The postal code for the person that created this image
        { id='creatorCountry', friendly="Creator Country", dataType='string', viewType='' }, --  (string) The country for the person that created this image
        { id='creatorPhone', friendly="Creator Phone", dataType='string', viewType='' }, --  (string) The phone number for the person that created this image
        { id='creatorEmail', friendly="Creator Email", dataType='string', viewType='' }, --  (string) The email address for the person that created this image
        { id='creatorUrl', friendly="Creator URL", dataType='string', viewType='' }, --  (string) The web URL for the person that created this image
        { id='headline', friendly="Headline", dataType='string', viewType='' }, --  (string) A brief', publishable synopsis or summary of the contents of this image
        { id='iptcSubjectCode', friendly="IPTC Subject Code", dataType='string', viewType='' }, --  (string) Values from the IPTC Subject NewsCode Controlled Vocabulary (see: http://www.newscodes.org/)
        { id='descriptionWriter', friendly="Description Writer", dataType='string', viewType='' }, --  (string) The name of the person who wrote', edited or corrected the description of the image
        { id='iptcCategory', friendly="IPTC Category", dataType='string', viewType='' }, --  (string) Deprecated field; included for transferring legacy metadata
        { id='iptcOtherCategories', friendly="IPTC Other Categories", dataType='string', viewType='' }, --  (string) Deprecated field; included for transferring legacy metadata
        { id='dateCreated', friendly="Date Created", dataType='string', viewType='' }, --  (string) The IPTC-formatted creation date (for example', "2005-09-20T15:10:55Z")
        { id='intellectualGenre', friendly="Intellectual Genre", dataType='string', viewType='' }, --  (string) A term to describe the nature of the image in terms of its intellectual or journalistic characteristics', such as daybook', or feature (examples at: http://www.newscodes.org/)
        { id='scene', friendly="Scene", dataType='string', viewType='' }, --  (string) Values from the IPTC Scene NewsCodes Controlled Vocabulary (see: http://www.newscodes.org/)
        { id='location', friendly="Location", dataType='string', viewType='' }, --  (string) Details about a location shown in this image
        { id='city', friendly="City", dataType='string', viewType='' }, --  (string) The name of the city shown in this image
        { id='stateProvince', friendly="State/Province", dataType='string', viewType='' }, --  (string) The name of the state shown in this image
        { id='country', friendly="Country", dataType='string', viewType='' }, --  (string) The name of the country shown in this image
        { id='isoCountryCode', friendly="(ISO) Country Code", dataType='string', viewType='' }, --  (string) The 2 or 3 letter ISO 3166 Country Code of the country shown in this image
        { id='jobIdentifier', friendly="Job Identifier", dataType='string', viewType='' }, --  (string) A number or identifier needed for workflow control or tracking
        { id='instructions', friendly="Instructions", dataType='string', viewType='' }, --  (string) Information about embargoes', or other restrictions not covered by the Rights Usage field
        { id='provider', friendly="Provider", dataType='string', viewType='' }, --  (string) Name of person who should be credited when this image is published
        { id='source', friendly="Source", dataType='string', viewType='' }, --  (string) The original owner of the copyright of this image
        { id='copyright', friendly="Copyright", dataType='string', viewType='' }, --  (string) The copyright text for this image
        { id='rightsUsageTerms', friendly="Rights Usage Terms", dataType='string', viewType='' }, --  (string) Instructions on how this image can legally be used
        { id='copyrightInfoUrl', friendly="Copyright Info URL", dataType='string', viewType='' }, -- string? - a guess...
        { id='personShown', friendly="Person Shown", dataType='string', viewType='' }, --  (string) Name of a person shown in this image
        { id='locationCreated', friendly="Location Created", dataType='struct', viewType='' }, --  (table) The location where the photo was taken. Each element in the return table is a table which is a structure named LocationDetails as defined in the IPTC Extension spec. Definition details can be found at http://www.iptc.org/std/photometadata/2008/specification/.
        { id='locationShown', friendly="Location Shown", dataType='struct', viewType='' }, --  (table) The location shown in this image. Each element in the return table is a table which is a structure named LocationDetails as defined in the IPTC Extension spec. Definition details can be found at http://www.iptc.org/std/photometadata/2008/specification/.
        { id='nameOfOrgShown', friendly="Name of Organization Shown", dataType='string', viewType='' }, --  (string) Name of the organization or company featured in this image
        { id='codeOfOrgShown', friendly="Code of Organization Shown", dataType='string', viewType='' }, --  (string) Code from a controlled vocabulary for identifying the organization or company featured in this image
        { id='event', friendly="Event", dataType='string', viewType='' }, --  (string) Names or describes the specific event at which the photo was taken
        { id='artworksShown', friendly="Artuworks Shown", dataType='struct', viewType='' }, --  (table) A set of metadata about artwork or an object in the image. Each element in the return table is a table which is a structure named ArtworkOrObjectDetails as defined in the IPTC Extension spec. Definition details can be found at http://www.iptc.org/std/photometadata/2008/specification/.
        { id='additionalModelInfo', friendly="Additional Model Info", dataType='string', viewType='' }, --  (string) Information about the ethnicity and other facets of model(s) in a model-released image
        { id='modelAge', friendly="Model Age", dataType='string', viewType='' }, --  (string) Age of human model(s) at the time this image was taken in a model released image
        { id='minorModelAge', friendly="Minor Model Age", dataType='string', viewType='' }, --  (string) Age of the youngest model pictured in the image', at the time that the image was made
        { id='modelReleaseStatus', friendly="Model Release Status", dataType='string', viewType='' }, --  (string) Summarizes the availability and scope of model releases authorizing usage of the likenesses of persons appearing in the photo
        { id='modelReleaseID', friendly="Model Release ID", dataType='string', viewType='' }, --  (string) A PLUS-ID identifying each Model Release
        { id='imageSupplier', friendly="Image Supplier", dataType='struct', viewType='' }, --  (table) Identifies the most recent supplier of this image', who is not necessarily its owner or creator. Each element in the return table is a table which is a structure named ImageSupplierDetail defined in PLUS. Definition details can be found at http://ns.useplus.org/LDF/ldf-XMPReference.
        { id='registryId', friendly="Registry ID", dataType='struct', viewType='' }, --  (table) Both a Registry Item Id and a Registry Organization Id to record any registration of this photo with a registry. Each element in the return table is a table which is a structure named RegistryEntryDetail as defined in the IPTC Extension spec. Definition details can be found at http://www.iptc.org/std/photometadata/2008/specification/.
        { id='maxAvailWidth', friendly="Max Available Width", dataType='number', viewType='' }, --  (number) The maximum available width in pixels of the original photo from which this photo has been derived by downsizing
        { id='maxAvailHeight', friendly="Max Available Height", dataType='number', viewType='' }, --  (number) The maximum available height in pixels of the original photo from which this photo has been derived by downsizing
        { id='sourceType', friendly="Source Type", dataType='string', viewType='' }, --  (string) The type of the source of this digital image', selected from a controlled vocabulary
        { id='imageCreator', friendly="Image Creator", dataType='struct', viewType='' }, --  (table) Creator or creators of the image. Each element in the return table is a table which is a structure named ImageCreatorDetail defined in PLUS. Definition details can be found at http://ns.useplus.org/LDF/ldf-XMPReference.
        { id='copyrightOwner', friendly="Copyright Owner", dataType='struct', viewType='' }, --  (table) Owner or owners of the copyright in the licensed image. Each element in the return table is a table which is a structure named CopyrightOwnerDetail defined in PLUS. Definition details can be found at http://ns.useplus.org/LDF/ldf-XMPReference.
        { id='licensor', friendly="Licensor", dataType='struct', viewType='' }, --  (table) A person or company that should be contacted to obtain a license for using the photo', or who has licensed the photo. Each element in the return table is a table which is a structure named LicensorDetail defined in PLUS. Definition details can be found at http://ns.useplus.org/LDF/ldf-XMPReference.
        { id='propertyReleaseID', friendly="Property Release ID", dataType='string', viewType='' }, --  (string) A PLUS-ID identifying each Property Release
        { id='propertyReleaseStatus', friendly="Property Release Status", dataType='string', viewType='' }, --  (string) Summarizes the availability and scope of property releases authorizing usage of the likenesses of persons appearing in the image.
        { id='digImageGUID', friendly="Digital Image GUID", dataType='string', viewType='' }, --  (string) Globally unique identifier for the item', created and applied by the creator of the item at the time of its creation
        { id='plusVersion', friendly="Plus Version", dataType='string', viewType='' }, --  (string) The version number of the PLUS standards in place at the time of the transaction
    }
    -- Note: there is no fmt-set.
end



--- Get list of metadata items for printing or clipboard..
--
--  @usage excludes custom (plugin) metadata
--
--  @param      params      parameter table, with optional members: 'format' (idOnly, idPlusFriendly, friendlyOnly, friendlyPlusId)
--
--  @return contents (string)
--  @return content buffer (array)
--
function LrMetadata:getHelpText( params )
    self:init()
    local b = { "Lightroom Formatted Metadata:" }
    b[#b + 1] = "-----------------------------"
    if params.format == 'friendlyPlusId' then
        for i, v in ipairs( self.fmtGetDescr ) do
            b[#b + 1] = v.friendly .. ":  " ..v.id
        end
    elseif params.format == 'idPlusFriendly' then
        for i, v in ipairs( self.fmtGetDescr ) do
            b[#b + 1] = v.id .. ":  " ..v.friendly
        end
    elseif params.format == 'idOnly' then
        for i, v in ipairs( self.fmtGetDescr ) do
            b[#b + 1] = v.id
        end
    elseif params.format == 'friendlyOnly' then
        for i, v in ipairs( self.fmtGetDescr ) do
            b[#b + 1] = v.friendly
        end
    else
        app:callingError( "bad what-how" )
    end    
    b[#b + 1] = ""
    b[#b + 1] = "Lightroom Raw Metadata:"
    b[#b + 1] = "-----------------------"
    if params.format == 'friendlyPlusId' then
        for i, v in ipairs( self.rawGetDescr ) do
            b[#b + 1] = v.friendly .. ":  " ..v.id
        end
    elseif params.format == 'idPlusFriendly' then
        for i, v in ipairs( self.rawGetDescr ) do
            b[#b + 1] = v.id .. ":  " ..v.friendly
        end
    elseif params.format == 'idOnly' then
        for i, v in ipairs( self.rawGetDescr ) do
            b[#b + 1] = v.id
        end
    elseif params.format == 'friendlyOnly' then
        for i, v in ipairs( self.rawGetDescr ) do
            b[#b + 1] = v.friendly
        end
    else
        app:callingError( "bad what-how" )
    end    
    local contents = table.concat( b, "\n" )
    return contents, b
end



--- Get gettable raw items suitable for popup menu.
--
function LrMetadata:getRawGetPopupItems( params )
    self:init()
    local lookup = {}
    local rawGetPopupItems = {}
    for i, v in ipairs( self.rawGetDescr ) do
        repeat
            if params.simpleOnly then
                if v.dataType == nil then
                    app:error( "missing data type: ^1", v.id )
                elseif self.simple[v.dataType] then
                    -- get it
                elseif self.other[v.dataType] then
                    break
                else
                    app:error( "^1 has bad type: ^2", v.id, v.dataType )
                end
            end
            rawGetPopupItems[#rawGetPopupItems + 1] = { title=v.friendly, value=( params.idOnly and v.id ) or v }
            lookup[v.id] = v
        until true
    end
    return rawGetPopupItems, lookup
end



--- Get settable raw items suitable for popup menu.
--
--  @param      params      optional parameter table, with members: simpleOnly (exclude table metadata), idOnly (item values to be id, not spec).
--
--  @return popup items - menu-compatible: titles are friendly, and values may be ids or raw-metadata specs (as seen in this module) depending on param.
--  @return lookup - keys are ids, values are specs.
--
function LrMetadata:getRawSetPopupItems( params )
    self:init()
    local lookup = {}
    local rawSetPopupItems = {}
    for i, v in ipairs( self.rawSetDescr ) do
        repeat
            if params.simpleOnly then
                if v.dataType == nil then
                    app:error( "missing data type: ^1", v.id )
                elseif self.simple[v.dataType] then
                    -- get it
                elseif self.other[v.dataType] then
                    break
                else
                    app:error( "^1 has bad type: ^2", v.id, v.dataType )
                end
            end
            rawSetPopupItems[#rawSetPopupItems + 1] = { title=v.friendly, value=( params.idOnly and v.id ) or v }
            lookup[v.id] = v
        until true
    end
    return rawSetPopupItems, lookup
end



--- Get gettable formatted items suitable for popup menu.
--
--  @param      params      optional parameter table, with members: simpleOnly (exclude table metadata), idOnly (item values to be id, not spec).
--
--  @return popup items - menu-compatible: titles are friendly, and values may be ids or raw-metadata specs (as seen in this module) depending on param.
--  @return lookup - keys are ids, values are specs.
--
function LrMetadata:getFmtGetPopupItems( params )
    self:init()
    local lookup = {}
    local fmtGetPopupItems = {}
    for i, v in ipairs( self.fmtGetDescr ) do
        repeat
            if params.simpleOnly then
                if v.dataType == nil then
                    app:error( "missing data type: ^1", v.id )
                elseif self.simple[v.dataType] then
                    -- get it
                elseif self.other[v.dataType] then
                    break
                else
                    app:error( "^1 has bad type: ^2", v.id, v.dataType )
                end
            end
            fmtGetPopupItems[#fmtGetPopupItems + 1] = { title=v.friendly, value=( params.idOnly and v.id ) or v }
            lookup[v.id] = v
        until true
    end
    return fmtGetPopupItems, lookup
end



--- Get gettable raw items suitable for popup menu.
--
--[[ *** on hold - needs more thought..
function LrMetadata:getPopupItems()
    self:init()
    local items = {}
    for i, v in ipairs( self.fmtGetDescr ) do
        local value = tab:copy( v )
        value.metaType = 'fmt'
        items[#items + 1] = { title=v.friendly, value=value }
    end
    for i, v in ipairs( self.rawGetDescr ) do
        local value = tab:copy( v )
        value.metaType = 'raw'
        items[#items + 1] = { title=v.friendly, value=value }
    end
    return items
end
--]]



--- Determine if key is valid for setting raw metadata.
--
function LrMetadata:isSettableRawKey( name )
    self:init()
    if self.rawSetLookup == nil then
        self.rawSetLookup = {}
        for i, v in ipairs( self.rawSetDescr ) do
            self.rawSetLookup[v.id] = v
        end
    end
    -- ###4 @22/Jan/2013 22:02 not yet tested. I think this is in use and therefore working, but @12/Aug/2013 21:58 - not sure. Delete this comment in 2015 if no incidents by then.
    return self.rawSetLookup[name]
end



--- Get lookup table (can be used as a "set" in most contexts) of all raw-settable items, indexed by id.
function LrMetadata:getRawSetLookup()
    self:init()
    if self.rawSetLookup == nil then
        self.rawSetLookup = {}
        for i, v in ipairs( self.rawSetDescr ) do
            self.rawSetLookup[v.id] = v
        end
    end
    return self.rawSetLookup
end



--- Get specified formatted metadata, from cache if available.
--
--  @usage good for functions that can take advantage of a cache created externally, or not.
--
function LrMetadata:getFormattedMetadata( photo, name, cache )
    if cache then
        return cache:getFormattedMetadata( photo, name, true ) -- accept uncached.
    else
        return photo:getFormattedMetadata( name )
    end
end
LrMetadata.getFmt = LrMetadata.getFormattedMetadata -- function LrMetadata:getFmt(...) -- synonym/shortcut.



--- Get specified raw metadata, from cache if available.
--
--  @usage good for functions that can take advantage of a cache created externally, or not.
--
function LrMetadata:getRawMetadata( photo, name, cache )
    if cache then
        return cache:getRawMetadata( photo, name, true ) -- accept uncached is implied when using this method.
    elseif photo then
        return photo:getRawMetadata( name )
    else
        app:callingError( "no photo" )
    end
end
LrMetadata.getRaw = LrMetadata.getRawMetadata -- function LrMetadata:getRaw(...) -- synonym/shortcut.



--- Transfer metadata from photo (possibly missing) to photo (presumably file must exist, unless inclusions/exclusions carefully chosen).
--
--  @usage *** deprecated in favor of dividing transfers between those using sdk and updating catalog, vs. those that go through exiftool and rely on pre-saved and post-read metadata.
--  @usage Uses a combination of exiftool and sdk for both reading and writing.
--  @usage *** If changes are made to catalog and xmp in same with-do wrapper, then some changes may be lost (when reading metadata), thus this method takes some care to use for both, and @11/Dec/2014 I recommend using it for ets-based adjustments only, and using it's sister method xfr-raw-settables in separate phase - see relative-antics for example.
--  @usage Derived originally from NxToo's transferLrMetadata function.
--  @usage Probably doesn't (wont/cant) transfer icc profile(?)
--  @usage comment added 5/May/2014 18:01 - if metadata set via exiftool, I think a read-meta is required afterward so Lr gets the memo(?)
--  @usage Initially used for transferring metadata from missing photo to recovered preview, also used in relative antics (selective mode).
--  @usage This method may be preferred if target is photo in catalog, see also: Image:transferMetadata and Xmp:transferMetadata (in case target is file on disk).
--  @usage incl/excl as passed - does not depend on prefs.
--
--  @param params (table) required. elements:<br>
--             catUpdTitle (string, default="Transfer Lr Metadata") 
--             fromPhoto (LrPhoto, required) source of metadata (from catalog only).
--             toPhoto (LrPhoto, required) target of metadata (catalog and maybe file too).
--             inclusions (table, optional, but recommended) set (or array) of metadata names to include.
--             exclusions (table, optional, usually omitted) set (or array) of metadata names to exclude.
--             toIsVirginal (boolean, default = false) if true, blank from items will be ignored.
--             exifToolSession (object, usually required) - in case included items will require exiftool to transfer.
--             exifTool (object, fallback) - will be used if ets not provided, and et needed - @5/May/2014 18:00, I think it's safest to pass ets.
--             writeBlanks (boolean, default=false) pass true to zero-out target fields if source field is blank.
--
function LrMetadata:transfer( params )
    local sts, msg
    local nExifMeta, nLrMeta = 0, 0
    app:call( Call:new{ name="Transfer Lr Metadata", async=false, main=function( call )
        local catUpdTitle = params.catUpdTitle or call.name
        local tries = params.tries or 60
        local fromPhoto = params.fromPhoto or app:callingError( "need from photo" )
        local toPhoto = params.toPhoto or app:callingError ( "need to photo" )
        app:callingAssert( fromPhoto ~= toPhoto, "can't xfr lr metadata to self" )
        local exclusions = params.exclusions or {}
        local et = params.exifTool or gbl:getValue( 'exifTool' )
        local ets = params.exifToolSession
        local writeBlanks = params.writeBlanks
        if ets then
            --Debug.pause( "got ets" )
        else
            ets = et
            --Debug.pause( "xfr not tested w/et proper. ###2" )
        end
        local todo = {}
        -- determine if table is a set.
        local function isSet( sclusion )
            for _, __ in pairs( sclusion ) do
                return true
            end
        end
        if #exclusions > 0 then
            if not isSet( exclusions ) then
                exclusions = tab:createSet( exclusions )
            else
                app:error( "wonky exclusions table" )
            end
        end
        local inclusions = params.inclusions or {
            keywords = true,
            rating = true,
            title = true,
            caption = true,
            dateTimeOriginal = true, -- requires exif-tool.
        }
        if #inclusions > 0 then
            if not isSet( inclusions )  then
                inclusions = tab:createSet( inclusions )
            else
                app:error( "wonky inclusions table" )
            end
        end
        local fmtFlag
        local function write( name, value )
            if lrMeta:isSettableRawKey( name ) then
                local status
                local origRawValue
                status, origRawValue = LrTasks.pcall( toPhoto.getRawMetadata, toPhoto, name )
                if not status then -- value not readable in raw form.
                    origRawValue = nil
                    local s, o = LrTasks.pcall( toPhoto.getFormattedMetadata, toPhoto, name )
                    if s then -- value readable as formatted.
                        origRawValue = o
                    end
                end
                if value ~= nil then
                    if type( value ) == 'string' and value == "" then
                        if not writeBlanks then -- and virginal
                            return
                        else -- writing blanks ok
                            if origRawValue == nil then -- already "blank".
                                return
                            -- else proceed.
                            end
                        end
                    -- else proceed.
                    end
                elseif not writeBlanks then
                    return
                end
                -- this clause added 8/Apr/2013 17:50 (no reason to write value if it's already same as raw value, is there?).
                if value == origRawValue then
                    -- Debug.pause( name, value )
                    return
                end                
                todo[#todo + 1] = function()
                    local s, m = LrTasks.pcall( toPhoto.setRawMetadata, toPhoto, name, value ) -- here we go again: not trapping bad key error (thus the reason for is-settable..).
                    if s then
                        app:logv( "Set '^1' to '^2'", name, value or 'nil' )
                    else
                        app:logWarning( "Unable to set '^1' to '^2'", name, value )
                    end
                end
            else
                app:logWarning( "Not supported: ^1", name )
            end
        end
        local function xfrKeywords()
            -- dbgf( "Considering keyword transfer" ) -- too much when being done in background.
            local toKeywords = toPhoto:getRawMetadata( 'keywords' )
            local fromKeywords = fromPhoto:getRawMetadata( 'keywords' )
            if #toKeywords == #fromKeywords then
                local toSet = tab:createSet( toKeywords )
                local doXfr
                for i, k in ipairs( fromKeywords ) do
                    if not toSet[k] then
                        Debug.pause( "not", k, k:getName() )
                        doXfr = true
                        break
                    end
                end
                if not doXfr then
                    return -- keywords are already same.
                end
            end
            -- keywords are not same.
            app:logv( "Transferring keywords" )
            todo[#todo + 1] = function()
                if writeBlanks then
                    local c = 0
                    for i, keyword in ipairs( toKeywords ) do
                        toPhoto:removeKeyword( keyword )
                        c = c + 1
                    end
                    if c > 0 then
                        app:logv( "^1 removed", str:nItems( c, "keywords" ) )
                    end
                end
                local c = 0
                for i, keyword in ipairs( fromKeywords ) do
                    toPhoto:addKeyword( keyword )
                    c = c + 1
                end
                if c > 0 then
                    app:logv( "^1 added", str:nItems( c, "keywords" ) )
                end
            end
        end
        local function xfrDate( name, value, typ)
            if typ == 'string' then
                -- parse
                if name == 'dateCreated' then
                    Debug.pause( "string date created - not parsed", name, value )
                else
                    app:logWarning( "Date type not supported: ^1", name )
                    return
                end
                    
            elseif typ == 'number' then
                 assert( fmtFlag == false, "how number date if formatted?" )
                 Debug.pause( "Number date", name, value, typ, fmtFlag )
            else
                app:error( "Bad date type" )
            end
            
            write( name, value )
            
        end
        local function xfrMisc( name, value, typ )
            if typ == 'string' or typ == 'boolean' or typ == 'number' or typ == 'nil' then
                if not fmtFlag then
                    -- gotta be fine (was raw data, or raw same as formatted)
                    -- Debug.pause( "Misc-supported for setting raw", name, value, typ ) -- all good.
                else -- formatted value available, but no raw equivalent.
                    if typ == 'string' then
                        -- Debug.pause( "Misc-supported formatted string - needs parsing?", name, value, typ ) -- so far, so good...
                    else
                        --Debug.pause( str:fmtx( "Misc-supported formatted ^1 - assuming can be set as is", typ ), name, value ) -- ok too, e.g. rating
                    end
                end
            elseif typ == 'table' then
                --Debug.pause( "table - setting verbatim", name ) - this seems to be working just fine @10/Dec/2014 4:17.
            else
                --Debug.pause( "not supported", name, value, typ )
                app:logWarning( "^1 not supported as ^2, value: ^3", name, typ, value or 'nil' )
                return
            end
            
            write( name, value )
            
        end
        local function miscTag( name, value, typ, tagName, tagValue )
            if toPhoto:getRawMetadata( 'isVirtualCopy' ) then
                app:logv( "Exif file tags are not transferred to virtual copies." )
                return
            end
            if typ == 'string' and tagValue == "" and not writeBlanks then
                return
            end
            ets:addArg( "-overwrite_original" )
            ets:addArg( str:fmtx( '-^1=^2', tagName, tagValue ) )
            ets:addTarget( toPhoto:getRawMetadata( 'path' ) )
            local rslt, errm = ets:execute() -- 1st is et rslt - which needs to be parsed to see if OK, 2nd is errm.
            if not str:is( errm ) then
                if str:is( rslt ) then
                    local s, m = et:getUpdateStatus( rslt )
                    if s then
                        app:logv( "Updated '^1' to '^2' via exiftool", tagName, tagValue )
                        nExifMeta = nExifMeta + 1
                    else
                        app:logWarning( "Unable to tag ^1 w/value ^2 - ^3", tagName, tagValue, m )
                    end
                else
                    app:logWarning( "Unable to update capture time - exiftool returned no result." )
                end
            else
                app:logWarning( "Unable to update capture time - ^1", errm )
            end
        end
        local function dateTag( name, value, typ, tagName )
            if toPhoto:getRawMetadata( 'isVirtualCopy' ) then
                app:logv( "Date tags are not transferred to virtual copies." )
                return
            end
            if ets then
                local dt
                if typ == 'number' then
                    --- 2005:10:23 20:06:34.33-05:00
                    dt = LrDate.timeToUserFormat( value, "%Y:%m:%d %H:%M:%S", false ) -- not gmt.
                elseif typ == 'string' then
                    app:logWarning( "^1 is string, expected number", tagName )
                    return
                else
                    app:logWarning( "^1 has wonky type, expected number", tagName )
                    return
                end
                miscTag( name, value, typ, tagName, dt )
            else
                app:logWarning( "Unable to transfer ^1", name )
            end
        end
        local function xfr( name )
            if name == 'keywords' then
                xfrKeywords()
                return
            end
            local status
            local rawValue
            local fmtValue
            status, fmtValue = LrTasks.pcall( fromPhoto.getFormattedMetadata, fromPhoto, name ) -- no-throw
            if not status then
                fmtValue = nil
            end
            status, rawValue = LrTasks.pcall( fromPhoto.getRawMetadata, fromPhoto, name ) -- no throw
            if not status then
                rawValue = nil
            end
            local value
            if fmtValue ~= nil then
                local fmtType = type( fmtValue )
                if rawValue ~= nil then
                    local rawType = type( rawValue )
                    if fmtType == rawType then
                        if rawValue ~= fmtValue then
                            -- Debug.pause( name, "formatted difference - taking raw", fmtValue, "raw", rawValue ) -- taking raw is the right thing to do.
                            value = rawValue
                            fmtFlag = false
                        else
                            value = rawValue -- they're same.
                            -- fmt-flag not set.
                        end
                    else -- avoid erroneous comparison - take raw
                        value = rawValue
                        fmtFlag = false
                    end
                else
                    value = fmtValue
                    --Debug.pause( "format is compatible?", name, fmtValue, fmtType ) -- so far, so good...
                    fmtFlag = true
                end
            elseif rawValue ~= nil then -- aok.
                value = rawValue
                fmtFlag = false
            else
                -- no need to set nil values. - this 'til 8/Apr/2013 19:22 - need to set nil values though sometimes, right?
                if not writeBlanks then
                    return
                end
            end
            local valType = type( value ) -- it's ok to get type of nil.
            --Debug.pause( name, value, valType, fmtFlag )
            if name == 'dateCreated' then
                xfrDate( name, value, valType ) -- could be handled by xfr-misc too.
            elseif name == 'dateTimeOriginal' then
                dateTag( name, value, valType, "DateTimeOriginal" )
            elseif name == 'dateTimeDigitized' then
                dateTag( name, value, valType, "DateTimeDigitized" )
            elseif name == 'dateTime' then
                dateTag( name, value, valType, "DateTime" )
            elseif name == 'lens' then
                miscTag( name, value, valType, "Lens", value )
            elseif name == 'aperture' then
                miscTag( name, value, valType, "ApertureValue", value )
            elseif name == 'flash' then
                miscTag( name, value, valType, "FlashFired", value )
            elseif name == 'exposureProgram' then
                --miscTag( name, value, valType, "ExposureProgram", value ) -- ###2 @12/Aug/2013 22:00 - I don't recall what the trouble was, but obviously there was some.
                app:logWarning( "Exposure program not universally transferrable." )
            elseif name == 'exposureBias' then
                miscTag( name, value, valType, "ExposureCompensation", value )
            elseif name == 'meteringMode' then
                miscTag( name, value, valType, "MeteringMode", value )
            elseif name == 'isoSpeedRating' then
                miscTag( name, value, valType, "ISO", value )
            elseif name == 'focalLength' then
                miscTag( name, value, valType, "FocalLength", value )
            elseif name == 'focalLength35mm' then
                miscTag( name, value, valType, "FocalLength35mm", value )
            elseif name == 'subjectDistance' then
                miscTag( name, value, valType, "FocusDistance", value )
            elseif name == 'shutterSpeed' then
                miscTag( name, value, valType, "ExposureTime", value )
            elseif name == 'cameraMake' then
                miscTag( name, value, valType, "Make", value )
            elseif name == 'cameraModel' then
                miscTag( name, value, valType, "Model", value )
            else
                xfrMisc( name, value, valType )
            end
        end
        for k, v in pairs( inclusions ) do
            if v then
                if not exclusions[k] then
                    --app:logv( "Including ^1", k )
                    xfr( k )
                else
                    app:logv( "Excluding ^1", k )
                end
            end
        end
        local function doIt( context, phase )
            for i, v in ipairs( todo ) do
                v()
            end
        end
        if #todo > 0 then
            if not catalog.hasWriteAccess then
                local sts, msg = cat:update( tries, catUpdTitle, doIt )
                if not sts then
                    error( msg )
                end
            else
                doIt()
            end
            nLrMeta = #todo -- to-done...
        else
            nLrMeta = 0
        end
    end, finale=function( call )
        sts, msg = call.status, call.message
    end } )
    if sts then
        return nExifMeta, nLrMeta
    else
        return false, msg
    end
end



-- options for ets-metadata-id inclusion:
local _inclEtsMeta = {
    shutterSpeed = true,
    aperture = true,
    brightnessValue = nil, -- dunno what this is.
    exposureBias = true,
    flash = true,
    exposureProgram = false, -- not working universally.
    meteringMode = true,
    isoSpeedRating = true,
    focalLength = true,
    focalLength35mm = false, -- computed?
    lens = true,
    subjectDistance = true,
    -- from get-raw-metadata:
    dateTimeOriginal = true,
    dateTimeDigitized = true,
    dateTime = true,
}



--- Transfer metadata from photo (possibly missing) to photo (file which must exist) using exiftool - preferrably in session mode.
--
--  @usage Uses sdk to read and exiftool to write.
--  @usage Note: will NOT update your catalog, and if catalog is accessible when calling, an error will be thrown.
--  @usage History: Derived initially from NxToo's transferLrMetadata function, then transcoded here as 'transfer' method, subsequently split between catalog-writing function (see below) and this non-catalog-writing function.
--  @usage Probably doesn't (wont/cant) transfer icc profile(?)
--  @usage I recommend saving metadata before calling, and reading metadata upon return. Unlike some similar methods, auto-saving/reading within is not (yet) supported.
--  @usage Initially used for transferring metadata from missing photo to recovered preview, also used in relative antics (selective mode).
--
--  @param params (table) required. elements:<br>
--             catUpdTitle (string, default="Transfer Lr Metadata") 
--             fromPhoto (LrPhoto, required) source of metadata (from catalog only).
--             toPhoto (LrPhoto, required) target of metadata (catalog and maybe file too).
--             metadataIdSet (table, required) *set* of metadata "names" (IDs) to include (exclusion is no longer supported).
--             toIsVirginal (boolean, default = false) if true, blank from items will be ignored.
--             exifToolSession (object, usually required) - in case included items will require exiftool to transfer.
--             exifTool (object, fallback) - will be used if ets not provided, and et needed - @5/May/2014 18:00, I think it's safest to pass ets.
--             writeBlanks (boolean, default=false) pass true to zero-out target fields if source field is blank.
--
function LrMetadata:transferExifToolSettableMetadata( params )
    app:callingAssert( not catalog.hasWriteAccess, "this method must not update the catalog, so make sure you've exited all with-do wrappers before calling" ) -- this check is not really necessary,
        -- and it's conceivable that one may want to use within a method which updates the catalog (changes won't interfere..), but it makes me nervous (due to potential to lose changes if not handled with sufficient care), thus this check.
    local sts, msg
    local nExifMeta, nLrMeta = 0, 0
    app:call( Call:new{ name="Transfer Exiftool-settable Metadata", async=false, main=function( call )
        local catUpdTitle = params.catUpdTitle or call.name
        local tries = params.tries or 60
        local fromPhoto = params.fromPhoto or app:callingError( "need from photo" )
        local toPhoto = params.toPhoto or app:callingError ( "need to photo" )
        app:callingAssert( fromPhoto ~= toPhoto, "can't xfr lr metadata to self" )
        local idSet = params.metadataIdSet or app:callingError( "metadata-id-set is required" ) -- seems too "dangerous" to default - calling context must specify explicitly from options e.g. above.
        local et = params.exifTool or gbl:getValue( 'exifTool' )
        local ets = params.exifToolSession
        local writeBlanks = params.writeBlanks
        if tab:hasItems( idSet ) then -- false items are still considered items, even though not processed..
            -- good enough for now..
        else
            app:callingError( "metadata-id-set is empty" )
        end
        if ets then
            --Debug.pause( "got ets" )
        else
            ets = et
            --Debug.pause( "xfr not tested w/et proper. ###2" )
        end
        local todo = {}
        local fmtFlag
        local function write( name, value )
            if lrMeta:isSettableRawKey( name ) then
                app:logWarning( "Not handled by this function: '^1' - consider using transfer-raw-settable-metadata instead.", name )
            else
                app:logWarning( "Not supported: ^1", name )
            end
        end
        local function xfrKeywords()
            app:logWarning( "Keywords are not handled by this function - consider using transfer-raw-settable-metadata instead.", name )
        end
        local function xfrDate( name, value, typ)
            write( name, value ) -- warn..
        end
        local function xfrMisc( name, value, typ )
            write( name, value ) -- warn..
        end
        local function miscTag( name, value, typ, tagName, tagValue )
            if toPhoto:getRawMetadata( 'isVirtualCopy' ) then
                app:logv( "Exif file tags are not transferred to virtual copies." )
                return
            end
            if typ == 'string' and tagValue == "" and not writeBlanks then
                return
            end
            ets:addArg( "-overwrite_original" )
            ets:addArg( str:fmtx( '-^1=^2', tagName, tagValue ) )
            ets:addTarget( toPhoto:getRawMetadata( 'path' ) )
            local rslt, errm = ets:execute() -- 1st is et rslt - which needs to be parsed to see if OK, 2nd is errm.
            if not str:is( errm ) then
                if str:is( rslt ) then
                    local s, m = et:getUpdateStatus( rslt )
                    if s then
                        app:logv( "Updated '^1' to '^2' via exiftool", tagName, tagValue )
                        nExifMeta = nExifMeta + 1
                    else
                        app:logWarning( "Unable to tag ^1 w/value ^2 - ^3", tagName, tagValue, m )
                    end
                else
                    app:logWarning( "Unable to update capture time - exiftool returned no result." )
                end
            else
                app:logWarning( "Unable to update capture time - ^1", errm )
            end
        end
        local function dateTag( name, value, typ, tagName )
            if toPhoto:getRawMetadata( 'isVirtualCopy' ) then
                app:logv( "Date tags are not transferred to virtual copies." )
                return
            end
            if ets then
                local dt
                if typ == 'number' then
                    --- 2005:10:23 20:06:34.33-05:00
                    dt = LrDate.timeToUserFormat( value, "%Y:%m:%d %H:%M:%S", false ) -- not gmt.
                elseif typ == 'string' then
                    app:logWarning( "^1 is string, expected number", tagName )
                    return
                else
                    app:logWarning( "^1 has wonky type, expected number", tagName )
                    return
                end
                miscTag( name, value, typ, tagName, dt )
            else
                app:logWarning( "Unable to transfer ^1", name )
            end
        end
        local function xfr( name )
            if name == 'keywords' then
                xfrKeywords()
                return
            end
            local status
            local rawValue
            local fmtValue
            status, fmtValue = LrTasks.pcall( fromPhoto.getFormattedMetadata, fromPhoto, name ) -- no-throw
            if not status then
                fmtValue = nil
            end
            status, rawValue = LrTasks.pcall( fromPhoto.getRawMetadata, fromPhoto, name ) -- no throw
            if not status then
                rawValue = nil
            end
            local value
            if fmtValue ~= nil then
                local fmtType = type( fmtValue )
                if rawValue ~= nil then
                    local rawType = type( rawValue )
                    if fmtType == rawType then
                        if rawValue ~= fmtValue then
                            -- Debug.pause( name, "formatted difference - taking raw", fmtValue, "raw", rawValue ) -- taking raw is the right thing to do.
                            value = rawValue
                            fmtFlag = false
                        else
                            value = rawValue -- they're same.
                            -- fmt-flag not set.
                        end
                    else -- avoid erroneous comparison - take raw
                        value = rawValue
                        fmtFlag = false
                    end
                else
                    value = fmtValue
                    --Debug.pause( "format is compatible?", name, fmtValue, fmtType ) -- so far, so good...
                    fmtFlag = true
                end
            elseif rawValue ~= nil then -- aok.
                value = rawValue
                fmtFlag = false
            else
                -- no need to set nil values. - this 'til 8/Apr/2013 19:22 - need to set nil values though sometimes, right?
                if not writeBlanks then
                    return
                end
            end
            local valType = type( value ) -- it's ok to get type of nil.
            --Debug.pause( name, value, valType, fmtFlag )
            if name == 'dateCreated' then
                xfrDate( name, value, valType ) -- could be handled by xfr-misc too.
            elseif name == 'dateTimeOriginal' then
                dateTag( name, value, valType, "DateTimeOriginal" )
            elseif name == 'dateTimeDigitized' then
                dateTag( name, value, valType, "DateTimeDigitized" )
            elseif name == 'dateTime' then
                dateTag( name, value, valType, "DateTime" )
            elseif name == 'lens' then
                miscTag( name, value, valType, "Lens", value )
            elseif name == 'aperture' then
                miscTag( name, value, valType, "ApertureValue", value )
            elseif name == 'flash' then
                miscTag( name, value, valType, "FlashFired", value )
            elseif name == 'exposureProgram' then
                --miscTag( name, value, valType, "ExposureProgram", value ) -- ###2 @12/Aug/2013 22:00 - I don't recall what the trouble was, but obviously there was some.
                app:logWarning( "Exposure program not universally transferrable." )
            elseif name == 'exposureBias' then
                miscTag( name, value, valType, "ExposureCompensation", value )
            elseif name == 'meteringMode' then
                miscTag( name, value, valType, "MeteringMode", value )
            elseif name == 'isoSpeedRating' then
                miscTag( name, value, valType, "ISO", value )
            elseif name == 'focalLength' then
                miscTag( name, value, valType, "FocalLength", value )
            elseif name == 'focalLength35mm' then
                miscTag( name, value, valType, "FocalLength35mm", value )
            elseif name == 'subjectDistance' then
                miscTag( name, value, valType, "FocusDistance", value )
            elseif name == 'shutterSpeed' then
                miscTag( name, value, valType, "ExposureTime", value )
            elseif name == 'cameraMake' then
                miscTag( name, value, valType, "Make", value )
            elseif name == 'cameraModel' then
                miscTag( name, value, valType, "Model", value )
            else
                xfrMisc( name, value, valType )
            end
        end
        for k, v in pairs( idSet ) do
            if v then -- no exclusions
                xfr( k )
            -- else false, meaning don't transfer.
            end
        end
        local function doIt( context, phase )
            for i, v in ipairs( todo ) do
                v()
            end
        end
        if #todo > 0 then
            doIt()
            nLrMeta = #todo -- to-done...
        else
            nLrMeta = 0
        end
    end, finale=function( call )
        sts, msg = call.status, call.message
    end } )
    if sts then
        return nExifMeta, nLrMeta
    else
        return false, msg
    end
end



--- Transfer catalog metadata via SDK from one photo to another - photos need not be present, and can be virtual - exiftool not required.. changes take place AFTER return from cat-upd-wrapper, if wrapped externally. Will be wrapped internally, if need be, in which cases changes are committed upon return.
--
--  @usage will auto-wrap internally with cat-accessor if need be (detects need to update before requesting catalog access) - appropriate for background calling.
--  @usage should NOT be done in same cat-upd with other ops that depend on metadata xfr'd (e.g. those doing exiftool/xmp manipulation..), since changes aren't settled until exit/commission, and if read-metadata prematurely, catalog changes will be lost.
--  @usage auto-detects background call and adjusts logging to be appropriate to background task..
--         
--  @param params table of named function arguments:
--      <br>    call (Call, required)
--      <br>    catUpdTitle (string, default = "Transfer SDK-supported metadata") consider using call.name..
--      <br>    catUpdTmo (number, default = 30) ignored if wrapped externally.
--      <br>    fromPhoto (lr-photo, required)
--      <br>    fromPhotoName (string, optional)
--      <br>    fromPhotoPath (string, optional)
--      <br>    toPhoto (lr-photo, required)
--      <br>    toPhotoName (string, optional)
--      <br>    toPhotoPath (string, optional)
--      <br>    metadataIdSet (table/set, optional - if not passed nor raw-id-set nor fmt-id-set, default is "all items supported by SDK", i.e. all raw-settable items") -- set of all raw-settable IDs - this method figures out whether to read raw or formatted.
--      <br>    rawIdSet (table/set, optional, alternative to metadata-id-set) -- set of raw-readable and raw-settable IDs.
--      <br>    fmtIdSet (table/set, optional, alternative to metadata-id-set) -- set of fmt-readable and raw-settable IDs.
--      <br>    metadataCache (LrMetadata::Cache, optional)
--      <br>    writeBlanks (boolean, default=false) pass true to zero-out target fields if source field is blank.
--
--  @return numberOfChanges, or nil if error.
--  @return qualificationMessage, always present if error, sometimes present if no error.
--
function LrMetadata:transferRawSettableMetadata( params )
    local call = params.call or app:callingError( "no call" )    
    local bgProcess = gbl:getValue( 'background' ) and call==background.call
    local fromPhoto = params.fromPhoto or app:callingError( "no from-photo" )    
    local toPhoto = params.toPhoto or app:callingError( "no to-photo" )
    local idSet = params.metadataIdSet
    local cache = params.metadataCache or self:createCache{ photos={fromPhoto,toPhoto}, rawIds={'path', 'isVirtualCopy'}, fmtIds={'copyName' } } -- not passing call, since this will be fast.
    local fromPhotoName = params.fromPhotoName or cat:getPhotoNameDisp( fromPhoto, true, cache )
    local fromPhotoPath = params.fromPhotoPath or lrMeta:getRaw( fromPhoto, 'path', cache )
    local toPhotoName = params.fromPhotoName or cat:getPhotoNameDisp( fromPhoto, true, cache )
    local fromPhotoPath = params.fromPhotoPath or lrMeta:getRaw( fromPhoto, 'path', cache )
    local writeBlanks = params.writeBlanks -- or dont.
    if not idSet then
        if params.rawIdSet or params.fmtIdSet then -- specified in form of raw/fmt instead
            idSet = tab:mergeTables( {}, rawIdSet, fmtIdSet )
        else -- not specified at all..
            idSet = lrMeta:getRawSetLookup()
        end
    end
    if tab:isEmpty( idSet ) then
        Debug.pause( "?" )
        return 0, "no metdata items specified for transfer" -- no errors, but no metadata items transferred either
    end
    local fmtFlag
    -- write to catalog via SDK
    local nLrMeta = 0
    local todo = {}
    local function write( name, value )
        if lrMeta:isSettableRawKey( name ) then
            local status
            local origRawValue
            status, origRawValue = LrTasks.pcall( toPhoto.getRawMetadata, toPhoto, name )
            if not status then -- value not readable in raw form.
                origRawValue = nil
                local s, o = LrTasks.pcall( toPhoto.getFormattedMetadata, toPhoto, name )
                if s then -- value readable as formatted.
                    origRawValue = o
                end
            end
            if value ~= nil then
                if type( value ) == 'string' and value == "" then
                    if not writeBlanks then -- and virginal
                        return
                    else -- writing blanks ok
                        if origRawValue == nil then -- already "blank".
                            return
                        -- else proceed.
                        end
                    end
                -- else proceed.
                end
            elseif not writeBlanks then
                return
            end
            -- this clause added 8/Apr/2013 17:50 (no reason to write value if it's already same as raw value, is there?).
            if value == origRawValue then
                -- Debug.pause( name, value )
                return
            end                
            todo[#todo + 1] = function()
                local s, m = LrTasks.pcall( toPhoto.setRawMetadata, toPhoto, name, value ) -- here we go again: not trapping bad key error (thus the reason for is-settable..).
                if s then
                    call:logV( "Set '^1' to '^2'", name, value or 'nil' )
                else
                    call:logW( "Unable to set '^1' to '^2'", name, value )
                end
            end
        else
            call:logW( "Not supported: ^1", name )
        end
    end
    local function xfrKeywords()
        -- dbgf( "Considering keyword transfer" ) -- too much when being done in background.
        local toKeywords = toPhoto:getRawMetadata( 'keywords' )
        local fromKeywords = fromPhoto:getRawMetadata( 'keywords' )
        if #toKeywords == #fromKeywords then
            local toSet = tab:createSet( toKeywords )
            local doXfr
            for i, k in ipairs( fromKeywords ) do
                if not toSet[k] then
                    Debug.pause( "not", k, k:getName() )
                    doXfr = true
                    break
                end
            end
            if not doXfr then
                return -- keywords are already same.
            end
        end
        -- keywords are not same.
        call:logV( "Transferring keywords" )
        todo[#todo + 1] = function()
            if writeBlanks then
                local c = 0
                for i, keyword in ipairs( toKeywords ) do
                    toPhoto:removeKeyword( keyword )
                    c = c + 1
                end
                if c > 0 then
                    call:logV( "^1 removed", str:nItems( c, "keywords" ) )
                end
            end
            local c = 0
            for i, keyword in ipairs( fromKeywords ) do
                toPhoto:addKeyword( keyword )
                c = c + 1
            end
            if c > 0 then
                call:logV( "^1 added", str:nItems( c, "keywords" ) )
            end
        end
    end
    local function xfrDate( name, value, typ)
        if typ == 'string' then
            -- parse
            if name == 'dateCreated' then
                Debug.pause( "string date created - not parsed", name, value )
            else
                call:logW( "Date type not supported: ^1", name )
                return
            end
                
        elseif typ == 'number' then
             assert( fmtFlag == false, "how number date if formatted?" )
             Debug.pause( "Number date", name, value, typ, fmtFlag )
        else
            app:error( "Bad date type" )
        end
        
        write( name, value )
        
    end
    local function xfrMisc( name, value, typ )
        if typ == 'string' or typ == 'boolean' or typ == 'number' or typ == 'nil' then
            if not fmtFlag then
                -- gotta be fine (was raw data, or raw same as formatted)
                -- Debug.pause( "Misc-supported for setting raw", name, value, typ ) -- all good.
            else -- formatted value available, but no raw equivalent.
                if typ == 'string' then
                    -- Debug.pause( "Misc-supported formatted string - needs parsing?", name, value, typ ) -- so far, so good...
                else
                    --Debug.pause( str:fmtx( "Misc-supported formatted ^1 - assuming can be set as is", typ ), name, value ) -- ok too, e.g. rating
                end
            end
        elseif typ == 'table' then
            -- Debug.pause( "table - setting verbatim", name ) - @11/Dec/2014 5:12, table settings seem to be working.
        else
            --Debug.pause( "not supported", name, value, typ )
            call:logW( "^1 not supported as ^2, value: ^3", name, typ, value or 'nil' )
            return
        end
        
        write( name, value )
        
    end
    local function miscTagErr( name, value, typ, tagName, tagValue )
        call:logW( "Unable to update tag - ^1 (not settable via SDK)", name )
    end
    local function dateTagErr( name, value, typ, tagName )
        call:logW( "Unable to transfer ^1 (not settable via SDK)", name )
    end
    local function xfr( name )
        if name == 'keywords' then
            xfrKeywords()
            return
        end
        local status
        local rawValue
        local fmtValue
        status, fmtValue = LrTasks.pcall( fromPhoto.getFormattedMetadata, fromPhoto, name ) -- no-throw
        if not status then
            fmtValue = nil
        end
        status, rawValue = LrTasks.pcall( fromPhoto.getRawMetadata, fromPhoto, name ) -- no throw
        if not status then
            rawValue = nil
        end
        local value
        if fmtValue ~= nil then
            local fmtType = type( fmtValue )
            if rawValue ~= nil then
                local rawType = type( rawValue )
                if fmtType == rawType then
                    if rawValue ~= fmtValue then
                        -- Debug.pause( name, "formatted difference - taking raw", fmtValue, "raw", rawValue ) -- taking raw is the right thing to do.
                        value = rawValue
                        fmtFlag = false
                    else
                        value = rawValue -- they're same.
                        -- fmt-flag not set.
                    end
                else -- avoid erroneous comparison - take raw
                    value = rawValue
                    fmtFlag = false
                end
            else
                value = fmtValue
                --Debug.pause( "format is compatible?", name, fmtValue, fmtType ) -- so far, so good...
                fmtFlag = true
            end
        elseif rawValue ~= nil then -- aok.
            value = rawValue
            fmtFlag = false
        else
            -- no need to set nil values. - this 'til 8/Apr/2013 19:22 - need to set nil values though sometimes, right?
            if not writeBlanks then
                return
            end
        end
        local valType = type( value ) -- it's ok to get type of nil.
        --Debug.pause( name, value, valType, fmtFlag )
        if name == 'dateCreated' then
            xfrDate( name, value, valType ) -- could be handled by xfr-misc too.
        elseif name == 'dateTimeOriginal' then
            dateTagErr( name, value, valType, "DateTimeOriginal" )
        elseif name == 'dateTimeDigitized' then
            dateTagErr( name, value, valType, "DateTimeDigitized" )
        elseif name == 'dateTime' then
            dateTagErr( name, value, valType, "DateTime" )
        elseif name == 'lens' then
            miscTagErr( name, value, valType, "Lens", value )
        elseif name == 'aperture' then
            miscTagErr( name, value, valType, "ApertureValue", value )
        elseif name == 'flash' then
            miscTagErr( name, value, valType, "FlashFired", value )
        elseif name == 'exposureProgram' then
            --miscTagErr( name, value, valType, "ExposureProgram", value ) -- ###2 @12/Aug/2013 22:00 - I don't recall what the trouble was, but obviously there was some.
            call:logW( "Exposure program not universally transferrable." )
        elseif name == 'exposureBias' then
            miscTagErr( name, value, valType, "ExposureCompensation", value )
        elseif name == 'meteringMode' then
            miscTagErr( name, value, valType, "MeteringMode", value )
        elseif name == 'isoSpeedRating' then
            miscTagErr( name, value, valType, "ISO", value )
        elseif name == 'focalLength' then
            miscTagErr( name, value, valType, "FocalLength", value )
        elseif name == 'focalLength35mm' then
            miscTagErr( name, value, valType, "FocalLength35mm", value )
        elseif name == 'subjectDistance' then
            miscTagErr( name, value, valType, "FocusDistance", value )
        elseif name == 'shutterSpeed' then
            miscTagErr( name, value, valType, "ExposureTime", value )
        elseif name == 'cameraMake' then
            miscTagErr( name, value, valType, "Make", value )
        elseif name == 'cameraModel' then
            miscTagErr( name, value, valType, "Model", value )
        else
            xfrMisc( name, value, valType )
        end
    end
    for id, inclFlag in pairs( idSet ) do
        if inclFlag then
            xfr( id ) -- add to-do function to array, or not.
        else
            Debug.pause( "no incl" )
        end
    end
    local function catUpdFunc( context, phase )
        for i, v in ipairs( todo ) do
            v()
        end
    end
    local sts, msg
    if #todo > 0 then
        if not catalog.hasWriteAccess then
            local catUpdTitle = params.catUpdTitle or "Transfer SDK-supported metadata"
            local catUpdTmo = params.catUpdTmo or 30
            sts, msg = cat:update( catUpdTmo, catUpdTitle, catUpdFunc )
        else -- could be wrapped/phased but doesn't need to be, yet.
            sts, msg = LrTasks.pcall( catUpdFunc )
        end
        if sts then
            nLrMeta = #todo -- to-done...
        -- else return msg (error message).
        end
    else
        sts = true
        nLrMeta = 0
        msg = "no update / no change.."
    end
    if sts then
        return nLrMeta, msg -- msg may or may not qualify true sts.
    else -- error updating catalog
        return nil, msg
    end
end



--- Display dialog box for defining tokens.
--
--  @usage asynchronous (optional callbacks).
--  @usage params may include callbacks as defined in show-floating-dialog method.
--  @usage if more than one simultaneous, pass unique titles, since they're used for guarding.
--
function LrMetadata:defineTokens( params )

    local title = params.title or "Define tokens"
    
    app:pcall{ name=title, async=true, guard=App.guardVocal, main=function( call )

        local getCustomMetadataItems = params.getCustomMetadataItems
        local targetProps = params.targetProps or error( "no target props" )
        local targetKey = params.targetKey or error( "no target key" )
        local targetName = params.targetName or targetKey
        local headerText = params.headerText or str:fmtx( "Select elements for '^1'. Rearrange after selection,\nor delete - if desired.", targetName )
        local footerText = params.footerText or str:fmtx( "Edit \"advanced settings\" (plugin manager, preset manager\nsection) to tweak formatting or define custom metadata items.\n \nYou can fiddle with '^1' field while this box is up\n- close when finished.", targetName )
        local fmtTablesToo = params.fmtTablesToo or false
        local rawTablesToo = params.rawTablesToo or true

        local toFront
        local toClose
        
        local props = LrBinding.makePropertyTable( call.context )
        local fmtPopupItems, fmtLookup = lrMeta:getFmtGetPopupItems{ simpleOnly=(not fmtTablesToo), idOnly=true }
        fmtPopupItems[#fmtPopupItems + 1] = { separator=true }
        fmtPopupItems[#fmtPopupItems + 1] = { title="None", value="" } -- "nothing" selected.
        props.fmtId = nil -- fmtPopupItems[2].value
        local rawPopupItems, rawLookup = lrMeta:getRawGetPopupItems{ simpleOnly=(not rawTablesToo), idOnly=true }
        rawPopupItems[#rawPopupItems + 1] = { separator=true }
        rawPopupItems[#rawPopupItems + 1] = { title="None", value="" } -- ditto.
        props.rawId = nil -- rawPopupItems[1].value
        local custPopupItems, custLookup
        if getCustomMetadataItems then
            custPopupItems, custLookup = getCustomMetadataItems()
            if custPopupItems then
                props.custId = nil -- custPopupItems[1].value
            end
        else
            --
        end
                
        local function chgHdlr( id, propTbl, key, value )
            app:call( Call:new{ name="Defineramous", async=true, guard=App.guardSilent, main=function( call )
                local v
                if str:is( value ) then
                    if key == 'fmtId' then
                        v = str:fmtx( "$F{^1}", value )
                    elseif key == 'rawId' then
                        v = str:fmtx( "$R{^1}", value )
                    elseif key == 'custId' then
                        v = str:fmtx( "$C{^1}", value )
                    end
                    targetProps[targetKey] = str:fmtx( "^1^2 ", targetProps[targetKey], v ) -- consider trimming final string before use.
                -- else don't change target-prop
                end
            end } )
        end
        
        view:setObserver( props, 'fmtId', LrMetadata, chgHdlr )
        view:setObserver( props, 'rawId', LrMetadata, chgHdlr )
        view:setObserver( props, 'custId', LrMetadata, chgHdlr )
        view:setObserver( targetProps, targetKey, LrMetadata, function( id, propTbl, key, value )
            app:pcall{ name=str:fmtx( "^1 - to-front listener", title ), async=true, guard=App.guardSilent, main=function( call )
                if toFront then
                    toFront()
                end
            end }
        end )
    
        local vi={ spacing=5 }
        local function space( spaces )
            vi[#vi + 1] = vf:spacer{ height=( spaces or 5 ) }
        end
        space()
        vi[#vi + 1] = vf:row {
            vf:spacer{ width=5 },
            vf:static_text {
                title = headerText,
            }
        }
        space()
        vi[#vi + 1] = vf:row {
            vf:spacer{ width=5 },
            vf:static_text {
                title = "Lightroom Metadata (pre-formatted)",
            }
        }
        vi[#vi + 1] = vf:row {
            vf:spacer{ width=5 },
            vf:popup_menu {
                bind_to_object = props,
                value = bind 'fmtId',
                items = fmtPopupItems,
                width = 350,
            }
        }
        space( 10 )
        vi[#vi + 1] = vf:row {
            vf:spacer{ width=5 },
            vf:static_text {
                title = "Lightroom Raw Metadata (custom format)",
            }
        }
        vi[#vi + 1] = vf:row {
            vf:spacer{ width=5 },
            vf:popup_menu {
                bind_to_object = props,
                value = bind 'rawId',
                items = rawPopupItems,
                width = 350,
            }
        }
        if custPopupItems then
            space( 10 )
            vi[#vi + 1] = vf:row {
                vf:spacer{ width=5 },
                vf:static_text {
                    title = "Custom Metadata (anything goes...)",
                }
            }
            vi[#vi + 1] = vf:row {
                vf:spacer{ width=5 },
                vf:popup_menu {
                    bind_to_object = props,
                    value = bind 'custId',
                    items = custPopupItems,
                    width = 350,
                }
            }
        -- else none
        end
        space( 10 )
        vi[#vi + 1] = vf:row {
            vf:spacer{ width=5 },
            vf:static_text {
                title = footerText,
            }
        }
        -- ###3 consider exif-metadata. Also, a button that gives an example of *all* metadata items at once.
        local args = {
            title = title or "no title", -- there's a title.
            contents = vf:column( vi ),
            blockTask = true, -- : (Boolean, optional) True to make the call blocking. If true, the call must be enclosed in an asynchronous task. This can be useful when using observers to maintain the state of UI elements in your dialog. If false, the related function context used to create a property table may not be maintained properly and any related observers could be removed while the dialog is still active. Default is false.
                -- I'm not sure how it works, but somehow upon shutdown, the dialog box is being tried correctly, whatever that means.
            resizable = true, -- not documented (for floater), but works.
            save_frame = call.name,
            onShow = function( p ) -- : (Function, optional) If supplied, a function which will be called when the dialog first shows up on the screen. It will be passed a single argument; a table containing two entries, which are both functions that can be invoked to manipulate the dialog. The 'toFront' entry is the function to call to ensure that the dialog is the frontmost window immediately after the call. The 'close' entry is the function to call to programmatically close the dialog window.
                toFront = p.toFront
                toClose = p.close
                if params.onShow then
                    params.onShow( p )
                end                
            end,
            windowWillClose = function() -- : (Function, optional) If supplied, a function which will be called (with no arguments) when the floating dialog is about to close.
                if params.windowWillClose then
                    params.windowWillClose()
                end
            end,
            selectionChangeObserver = function()  -- : (Function, optional) If supplied, a function which will be called (with no arguments) when the selected photos/videos changed. The plug-in can then use catalog:getTargetPhotos to act according to the new selection.
                if params.selectionChangeObserver then
                    params.selectionChangeObserver()
                end            
            end,
            sourceChangeObserver = function()  -- : (Function, optional) If supplied, a function which will be called (with no arguments) when the active source(s) changed. The plug-in can then use catalog:getActiveSources to act according to the new source(s).
                if params.sourceChangeObserver then
                    params.sourceChangeObserver()
                end            
            end,
        }
        
        -- Note: this call is asynchronous
        LrDialogs.presentFloatingDialog( _PLUGIN, args ) -- but this call is blocking.
    
    end, finale=function( call )
        if call.status then
            --
        else
            app:show{ warning=call.message }
        end
    end }
end


return LrMetadata
