--[[
        PublishServices.lua

        Represents publish services (not one publish service) from the point of view of catalog/database functionality,
        as opposed to export functionality, which is handled by the publish module proper.
--]]


local PublishServices, dbg, dbgf = Object:newClass{ className="PublishServices", register=true }



--- Constructor for extending class.
--
function PublishServices:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
--  @usage      Represents the collection of all publish services defined under for a plugin.
--
function PublishServices:new( t )
    local o = Object.new( self, t )
    --o:init() - must be deferred if pso created during synch init, since requires async task.
    return o
end



--- Get publish service given name.
--  @usage see catalog method for getting publish service based on ID.
--  @param name (string, required) name of publish service to get. 
--  @param pluginId (string, optional) ID of plugin - nil means all.
--  @return publish service or nil.
function PublishServices:getPublishService( name, pluginId )
    local array = catalog:getPublishServices( pluginId ) -- nil => all plugins.
    for i, v in ipairs( array ) do
        if v:getName() == name then
            return v
        end
    end
    -- return nil
end



--- Initialize publish service information.
--
--  @usage the initial motivation for this function is to consolidate the variety "get...info" functions which are very similar but slightly different...
--      <br>    this function may take a tad longer than *some* (not all) of them, but the hope is to recode such that it's done once upon startup, and again upon demand if necessary.
--  @usage returns nothing - use get... methods to access info.
--
--  @param call required.
--  @param targetId optional - toolkit ID to confine initialized info - faster in case you only are interested in specific plugin (like current one..).
--
function PublishServices:init( call, targetId )
    app:callingAssert( call, "no call" )
    --Debug.pauseIf( targetId == nil, "are you sure you need pub-srvs init for *all* plugins?" ) - may have to kill Lightroom, since debug screen covered by non-cancelable modal dialog.
    local cap = call:setCaption( "Initializing publish service info (takes time..)." )
    -- format of srvInfo:
    -- { srv=srv, pluginId=pluginId, pubColls={}, pubPhotos={} }
    self.pubPhotoLookup = {} -- for each pubPhoto index, a table with srvInfo and pubColl.
    self.photoLookup = {} -- for each photo (not pub-photo), a table containing array of published photos (pubPhotos), a set of publish services info (pubSrvInfo), and a set of published collections (pubCollSet).
    self.pubCollLookup = {} -- for each published collection index, associated publish service info (un-named, but in srvInfo format).
    self.pubSrvLookup = {} -- for each publish service index, a table of service info (un-named, but in srvInfo format).
    self.pluginLookup = {} -- for each plugin id implementing publish services, a table containing pluginId, and an array of service info (in srvInfo format).
    self.pubPhotoCount = 0
    local initPubCollSets
    local yc = 0
    local function initPubColl( pubColl, srvInfo )
        yc = app:yield( yc )
        srvInfo.pubColls[#srvInfo.pubColls + 1] = pubColl -- service info includes array of published collections.
        local addPubPhotos = pubColl:getPublishedPhotos()
        for i, pubPhoto in ipairs( addPubPhotos ) do
            srvInfo.pubPhotos[#srvInfo.pubPhotos + 1] = pubPhoto -- service info includes array of published photos.
            local photo = pubPhoto:getPhoto()
            -- this defines a published photo record:
            self.pubPhotoLookup[pubPhoto] = { srvInfo=srvInfo, pubColl=pubColl } -- each published photo can access info about corresponding service.
            self.pubPhotoCount = self.pubPhotoCount + 1
            local photoEntry -- structure accessible given photo.
            if self.photoLookup[photo] == nil then
                -- Note: this defines a photo entry:
                self.photoLookup[photo] = { pubPhotos={}, pubSrvSet={}, pubCollSet={} } -- note: array of associated pub'd photos, and srvs and colls - no correlations but could be drawn via pub-photo lookup..(?)
            end
            photoEntry = self.photoLookup[photo]
            photoEntry.pubPhotos[#photoEntry.pubPhotos + 1] = pubPhoto
            photoEntry.pubSrvSet[srvInfo.srv] = srvInfo
            photoEntry.pubCollSet[pubColl] = srvInfo
        end
        -- this defines a publish collection record:
        self.pubCollLookup[pubColl] = srvInfo
    end
    local function initPubColls( pubColls, srvInfo )
        for i, coll in ipairs( pubColls ) do
            initPubColl( coll, srvInfo )
        end
    end
    local function initPubCollSet( set, srvInfo )
        local collSets = set:getChildCollectionSets()
        local colls = set:getChildCollections()
        initPubColls( colls, srvInfo )
        initPubCollSets( collSets, srvInfo )
    end
    function initPubCollSets( sets, srvInfo )
        for i, v in ipairs( sets ) do
            if v:type() == 'LrPublishedCollection' then
                initPubColl( v, srvInfo )
            elseif v:type() == 'LrPublishedCollectionSet' then
                initPubCollSet( v, srvInfo )
            else
                app:error( "what?" )
            end
        end
    end
    local srvs = catalog:getPublishServices( targetId ) -- nil => all plugins.
    -- initialize plugin lookup and publish service lookup
    for i, srv in ipairs( srvs ) do
        -- init service of plugin
        local pluginId = srv:getPluginId()
        local pluginEntry
        if self.pluginLookup[pluginId] == nil then -- first service for this plugin
            self.pluginLookup[pluginId] = { pluginId=pluginId, srvs={} }
        else  -- this plugin Id has already been encountered.
            --Debug.pause()
        end
        pluginEntry = self.pluginLookup[pluginId]
        pluginEntry.srvs[#pluginEntry.srvs + 1] = srv -- add service to array of services corresponding to this plugin.
        -- note: this defines service info:
        self.pubSrvLookup[srv] = { srv=srv, pluginId=pluginId, pubColls={}, pubPhotos={} } -- create new info table corresponding to service
        local srvInfo = self.pubSrvLookup[srv] -- 
        initPubCollSet( srv, srvInfo ) -- treat pub-srv as coll-set (cheating a little...).
    end
    call:setCaption( cap ) -- restore original caption.
end



--- Get array of publish service info (one table for each publish-service setup) corresponding to specified plugin ID.
--
--  @usage table with members: pluginId, array of srvs.
--
function PublishServices:getInfoForPlugin( targetId )
    local info = {}
    if self.pluginLookup then
        local srvs = catalog:getPublishServices( targetId )
        for i, srv in ipairs( srvs ) do
            if self.pubSrvLookup[srv] then
                info[#info + 1] = self.pubSrvLookup[srv] -- srv, pubColls, pubPhotos
            else
                Debug.pause( "?" )
            end
        end
        return info
    else
        app:callingError( "init before calling.." )
    end
end



--- Get info for published collection, in format that hopefully won't change too much over time, despite changes in internal implementation..
--
--  @return srvInfo (table/structure) srv, pluginId, pubColls, pubPhotos.
--
function PublishServices:getInfoForPubColl( pubColl )
    return self.pubCollLookup[pubColl]
end



--- Get info for photo (not published photo), in format that hopefully won't change too much over time, despite changes in internal implementation..
--
--  @return table with pubPhotos, pubSrvSet, pubCollSet, or nil if photo not published.
--
function PublishServices:getInfoForPhoto( photo )
    return self.photoLookup[photo]
end



--- Get info for published photo, in format that hopefully won't change too much over time, despite changes in internal implementation..
--
--  @return table with srvInfo & pubColl.
--
--  @usage srvInfo format: srv, pluginId, pubColls, pubPhotos.
--  @usage pubColl is just LrPublishedCollection.
--
function PublishServices:getInfoForPubPhoto( pubPhoto )
    return self.pubPhotoLookup[pubPhoto]
end



--- Get all published photo info.
--  @usage typicall within a plugin, but that depends on init.
--  @param a trick parameter: must be nil.
--  @return pubPhotoLookup - keys are published photos, and values are srv-info.
--  @return pubPhotoCount - total number of items in pub-photo lookup table.
function PublishServices:getPubPhotoInfo( a )
    app:callingAssert( a == nil, "this method returns all published photo info - no parameters.." )
    return self.pubPhotoLookup, self.pubPhotoCount
end



--- Get plugin name from plugin-id.
--
--  @usage returns typical name - may not be true across the board, but is an almost universal convention - typically used for friendly display / logging..
--
--  @return "extension" or echos ID if no extension.
--
function PublishServices:getPluginName( pluginId )
    local pluginName = LrPathUtils.extension( pluginId )
    if not str:is( pluginName ) then
        pluginName = pluginId
    end
    return pluginName
end



-- private method to accumulate info af photos from specified collection.
function PublishServices:_addFromCollection( pubPhotos, pubColl, pubServices )
    local addPubPhotos = pubColl:getPublishedPhotos()
    local ps = pubColl:getService()
    for i = 1, #addPubPhotos do
        pubServices[#pubServices + 1] = ps
    end
    tab:appendArray( pubPhotos, addPubPhotos )
end



-- private method to accumulate info of photos from specified collections.
function PublishServices:_addFromColls( pubPhotos, colls, pubServices )
    for i, coll in ipairs( colls ) do
        self:_addFromCollection( pubPhotos, coll, pubServices )
    end
end



-- private method to accumulate info of photos from specified collection set.
function PublishServices:_addFromCollSet( pubPhotos, set, pubServices )
    local collSets = set:getChildCollectionSets()
    local colls = set:getChildCollections()
    self:_addFromColls( pubPhotos, colls, pubServices )
    self:_addFromCollSets( pubPhotos, collSets, pubServices )
end



-- private method to accumulate photos from specified collection sets.
function PublishServices:_addFromCollSets( pubPhotos, collSets, pubServices )
    for i, v in ipairs( collSets ) do
        if v:type() == 'LrPublishedCollection' then
            self:_addFromColl( pubPhotos, v, pubServices )
        elseif v:type() == 'LrPublishedCollectionSet' then
            self:_addFromCollSet( pubPhotos, v, pubServices )
        else
            app:error( "what?" )
        end
    end
end



--- Get all published photos, across all collections, all services defined for this plugin.
--
--  @usage *** deprecated in favor of using initialized publish-service info instead. ###2: In my plugins, this is only being used by change-manager auto-publish,
--      <br>    which doesn't use init method of publish services object.
--
function PublishServices:getPublishedPhotos( pluginId )
    if pluginId == nil then
        pluginId = _PLUGIN.id -- for backward compatibility.
    elseif pluginId == 0 then
        pluginId = nil -- for new capability to get published photos for all services.
    end
    local pubPhotos = {}
    local pubServices = {} -- parallel array of services that each published photo is published on.
    local srvs = catalog:getPublishServices( pluginId )
    for i, v in ipairs( srvs ) do
        self:_addFromCollSet( pubPhotos, v, pubServices ) -- treat pub-srv as coll-set (cheating a little...).
    end
    return pubPhotos, pubServices
end



--- Get table of published info (published-photo, published-collection, published-service, indexed by photo.
--
--  @usage *** deprecated ###2 I don't *think* this is being used anymore (was used in psa I think).
--
function PublishServices:getPublishedInfo( targetPhotos, pluginId )
    targetPhotos = targetPhotos or app:callingError( "Specify target photos." ) -- catalog:getTargetPhotos() - don't like the get-target-photos default.
    if pluginId == nil then
        pluginId = _PLUGIN.id -- for backward compatibility.
    elseif pluginId == 0 then
        pluginId = nil -- for new capability to get published photos for all services.
    end
    local photoSet = tab:createSet( targetPhotos )
    local info = {}
    local function fromColl( coll )
        local addPubPhotos = coll:getPublishedPhotos()
        local ps = coll:getService()
        for i, pp in ipairs( addPubPhotos ) do
            local p = pp:getPhoto()
            if photoSet[p] then -- include
                if info[p] == nil then
                    info[p] = { { pubPhoto = pp, pubColl = coll, pubSrv = ps } }
                else
                    local a = info[p]
                    a[#a + 1] = { pubPhoto = pp, pubColl = coll, pubSrv = ps }
                end
            -- else not to be included.
            end
        end
    end
    local function fromColls( colls )
        for i, v in ipairs( colls ) do
            fromColl( v )
        end
    end
    local fromCollSet -- forward reference
    local function fromCollSets( collSets )
        for i, v in ipairs( collSets ) do
            if v:type() == 'LrPublishedCollection' then
                fromColl( v )
            elseif v:type() == 'LrPublishedCollectionSet' then
                fromCollSet( v )
            else
                app:error( "what?" )
            end
        end
    end
    function fromCollSet( set ) -- local
        local collSets = set:getChildCollectionSets()
        local colls = set:getChildCollections()
        fromColls( colls )
        fromCollSets( collSets )
    end
    local srvs = catalog:getPublishServices( pluginId )
    for i, v in ipairs( srvs ) do
        fromCollSet( v ) -- treat pub-srv as coll-set (cheating a little...).
    end
    return info
end



--- Get table of published collections as keys, publish service as value.
--
--  @usage *** deprecated ###2 @30/Nov/2013 2:05, I can't see this used anywhere anymore.
--
function PublishServices:getPublishCollectionInfo( pluginId )
    if pluginId == nil then
        pluginId = _PLUGIN.id
    elseif pluginId == 0 then
        pluginId = nil
    end
    local info = {}
    local function fromColls( _colls )
        for i, v in ipairs( _colls ) do
            info[v] = v:getService()
        end
    end
    local fromCollSet -- forward reference.
    local function fromCollSets( collSets )
        for i, v in ipairs( collSets ) do
            if v:type() == 'LrPublishedCollection' then
                --fromColl( v ) - ###3 presumably a bug, noticed 1/Sep/2013 7:24, not sure scope of applicability.
                fromColls{ v } -- bug presumably fixed 1/Sep/2013 7:25
            elseif v:type() == 'LrPublishedCollectionSet' then
                fromCollSet( v )
            else
                app:error( "what?" )
            end
        end
    end
    function fromCollSet( set )
        local collSets = set:getChildCollectionSets()
        local colls = set:getChildCollections()
        fromColls( colls )
        fromCollSets( collSets )
    end
    local srvs = catalog:getPublishServices( pluginId )
    for i, v in ipairs( srvs ) do
        fromCollSet( v ) -- treat pub-srv as coll-set (cheating a little...).
    end
    return info
end



--- Get published photos corresponding to all selected photos.
--
--  @usage ###2 this is used for Photooey & TreePub's config-run and maint-run.
--
--  @return array of published photos from one collection in one service - may be empty, but never nil.
--  @return Publish service - may be nil.
--  @return Publish collection - may be nil.
--
function PublishServices:getSelectedPublishedPhotos()
    local targetPhotos = catalog:getTargetPhotos()
    if tab:isEmpty( targetPhotos ) then
        return {}
    end
    local photoSet = {}
    for i, photo in ipairs( targetPhotos ) do
        photoSet[photo] = true
    end
    local sources = catalog:getActiveSources()
    local pubPhotos = {}
    local pubSrv -- not array, key'd by PS name.
    local pubColl
    for i, v in ipairs( sources ) do
        if v:type() == 'LrPublishedCollection' then
            if pubColl then
                app:error( "Photos must be from same published collection" )
            else
                pubColl = v
            end
            pubSrv = v:getService()
            local _pubPhotos = v:getPublishedPhotos()
            if #_pubPhotos > 0 then
                for j, pp in ipairs( _pubPhotos ) do
                    if photoSet[pp:getPhoto()] then -- published photo is selected
                        pubPhotos[#pubPhotos + 1] = pp
                    else
                    end
                end
            else
                Debug.logn( "No published photos in " .. pubColl:getName() )
            end
        end
    end
    return pubPhotos, pubSrv, pubColl
end



--- Call to assure fresh data before looking up collections based on id.
--
--  @usage Called automatically if need be, but can be called externally as part of init.
--
function PublishServices:computeCollLookup()
    self.collLookup = {}
    self.collSetLookup = {}
    local fromColl, fromColls, fromSets, fromSet
    function fromColl( coll )
        --Debug.logn( str:fmt( "lookup for coll '^1', ID: ^2", coll:getName(), coll.localIdentifier ) )
        self.collLookup[coll.localIdentifier] = coll
    end
    function fromColls( colls )
        for i, v in ipairs( colls ) do
            fromColl( v )
        end
    end
    function fromSets( sets )
        --Debug.logn( str:fmt( "lookup for ^1 sets", #sets ) )
        for i, v in ipairs( sets ) do
            if v:type() == 'LrPublishedCollection' then
                fromColl( v )
            elseif v:type() == 'LrPublishedCollectionSet' then
                fromSet( v )
            else
                app:error( "what?" )
            end
        end
    end
    function fromSet( set )
        --Debug.logn( str:fmt( "lookup for set", set:getName() ) )
        self.collSetLookup[set.localIdentifier] = set
        local collSets = set:getChildCollectionSets()
        local colls = set:getChildCollections()
        fromColls( colls )
        fromSets( collSets )
    end
    local srvs = catalog:getPublishServices() -- get publish services for all plugins.
    --Debug.logn( str:fmt( "lookup for ^1 services", #srvs ) )
    for i, v in ipairs( srvs ) do
        fromSet( v ) -- treat pub-srv as coll-set (cheating a little...).
    end
end



--- Get published collection or set by local identifier.
--
--  @usage will auto-init if need be, but consider calling computeCollLookup before each "run".
--  @usage ###2 used by sqliteroom's export-collections.
--
--  @param id local identifier as obtained via sdk, or sql.
--
function PublishServices:getCollectionByLocalIdentifier( id )
    if self.collLookup == nil then
        self:computeCollLookup()
    end
    return self.collLookup[id] or self.collSetLookup[id]
end



--- Get published collection set by local identifier.
--
--  @usage will auto-init if need be, but consider calling computeCollLookup before each "run".
--  @usage ###2 used by sqliteroom's export-collections.
--
--  @param id local identifier as obtained via sdk, or sql.
--
function PublishServices:getCollectionSetByLocalIdentifier( id )
    if self.collSetLookup == nil then
        self:computeCollLookup()
    end
    return self.collSetLookup[id]
end



return PublishServices
