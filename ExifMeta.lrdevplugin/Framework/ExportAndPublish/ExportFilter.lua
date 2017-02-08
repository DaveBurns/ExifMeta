--[[
        ExportFilter.lua
--]]


local ExportFilter, dbg, dbgf = Object:newClass{ className="ExportFilter", register=true }



--- Constructor for extending class.
--
function ExportFilter:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance (may serve dialog box only, or actual export filtering - which one depends on whether filter-context is passed in starter table.
--
--  @usage @19/Nov/2013 16:48, "extension" of ID must match class name. - this is not strictly necessary, but more of a sanity check - if too inflexible, delete the assertion (not tested).
--      <br> in any case, class-name will need to be found as part of the ID, and had better be unique.
--  @usage exportSettings or filterContext must be passed.
--  @usage class name must be unique - NOT checked.
--
function ExportFilter:new( t )
    app:callingAssert( t ~= nil, "export filter constructor requires \"starter table\" parameter" )
    app:callingAssert( type( t ) == 'table', "export filter constructor parameter must be 'table'" )
    local o = Object.new( self, t )
    if o.filterContext then -- object for post-processing
        app:callingAssert( o.functionContext, "need function context" )
        o.exportSettings = o.filterContext.propertyTable or error( "no export settings" )
    else -- object for dialog box handling.
        app:callingAssert( o.exportSettings, "no export settings nor filter context" )
    end
    local className = o:getClassName()
    assert( className == self:getClassName(), "insane" )
    o.filterInfo = app:getInfo( 'LrExportFilterProvider' ) -- beware: in other contexts, one may want LR-export-filters-from-this-plugin property instead, for those actually inserted.
    app:assert( o.filterInfo ~= nil, "no filter info" )    
    if #o.filterInfo == 0 then -- alternate (simplified/single-filter) syntax.
        o.filterInfo = { o.filterInfo } -- convert to universal syntax.
    end
    local b = {}
    for i, info in pairs( o.filterInfo ) do -- could have used ipairs, but doesn't matter.
        if info.id:find( className ) then
            local filterName = ExportFilter._getFilterName( info.id )
            app:callingAssert( filterName == className, "filter name (^1) must match class name (^2)", filterName, className ) -- this seems like a good idea, maybe too strict ###4.
            o.id = info.id -- filter ID
            o.filterName = className -- unique name, short (lua property-key compatible format).
            o.title = info.title -- filter title: anything goes - friendly.
            o.info = info
            break -- first come, first served - had better be unique.
        else
            -- Debug.pause( info, info.id, className ) - useful for debuggin, otherwise not.
            b[#b + 1] = info.id
        end
    end
    app:assert( o.id, "filter class (^1) not found amongst these: ^2", className, table.concat( b, ", " ) ) -- , app:func( 3 ) ) -- blame it on caller.
    o.enablePropName = o:getPropName( 'enable' ) -- note: for use in export-preset-fields, do: ExportFilter._getPropName( '"class-name"', 'enable' ) or hard-code, or override/ignore..
    o.synopsisPropName = o:getPropName( 'synopsis' )
    o.stsMsgPropName = o:getPropName( 'stsMsg' )
    o.statusPropName = o:getPropName( 'status' ) -- assure how this filter sets status is how the master export condition clearer will compute it too.
    return o
end



--- Get filter-specific property name, without having filter object.
--
--  @usage this function is implemented as a local function instead of an overridable class function because it's important that all filters
--      <br>    in a plugin are having status property name computed the same way, regardless of their class heritage.
--
function ExportFilter._getPropName( filterName, pqName )
    app:callingAssert( str:is( filterName ), "no filter-name" )
    app:callingAssert( str:is( pqName ), "no pq name" )
    return str:fmtx( "^1_^2", filterName, pqName ) -- partial class name must be unique.
end



--- Compute filter name based on ID - MUST be same as extended filter class name.
--
--  @usage this function assumes id format "{whatev}.{class-name}"
--      <br>    in other words, id will end with the name of the implementing class.
--      <br>    if you prefer another naming convention, override this method, but realize the class name must be *somewhere* (verbatim) in the ID, or else you'll have to override constructor too (and maybe some other methods).
--
function ExportFilter._getFilterName( id )
    local ext = LrPathUtils.extension( id )
    if str:is( ext ) then
        return ext
    else
        return id
    end
end



-- filter log functions - wrappers for app:log functions which insert filter-name, in case multiple filters are inserted.
function ExportFilter:log( x, ... )
    x = "("..self.filterName..") "..(x or "")
    app:log( x, ... )
end
function ExportFilter:logV( x, ... )
    x = "("..self.filterName..") "..(x or "")
    app:logV( x, ... )
end
function ExportFilter:logW( x, ... )
    x = "("..self.filterName..") "..(x or "")
    app:logW( x, ... )
end
function ExportFilter:logE( x, ... )
    x = "("..self.filterName..") "..(x or "")
    app:logE( x, ... )
end



--- Get property name as combination of partially qualified name, and filter name. Thus, each like property will be unique and determinate when multiple filters.
--
function ExportFilter:getPropName( namePart )
    return ExportFilter._getPropName( self.filterName, namePart )
end



--- Export setting property change handler - note: usually should be programmed to handle case when no name/value has been passed too, to check initial values even if nothing's changed yet.
--      <br>    Reminder: initial values may have come from an old (or hand-edited) preset, so all bets are off.
--
function ExportFilter:updateFilterStatusMethod( name, value )
    self:logV( "*** update filter status method has not been overridden." ) -- and probably should be.
end



--- Create export filter for either dialog or filter-context, and store in property table.
--
--  @param id (class, required) class of export filter object to be created, if creation is warranted (i.e. not already created with specified export settings & filter-context...).
--  @param props (export setttings in the form of an observable property table) required if no filter-context in starter table.
--  @param starter (table) optional: typically includes function-context & filter-context in case object is for export-run time (as opposed to dialog-box/set-up time).
--
--  @usage in export class, registry is static array in base class, and object is cleaned up upon completion.
--  @usage export filter registry is export properties themselves, and new objects replace old objects - note: there is no explicit cleanup, cleanup relies on "fact" that Lr will create new properties object at export time, and thus all previously registered filter objects will be wiped.
--  @usage props are used as "registry" for constructed export filter object. Maybe not by the book, but no problems, yet.. - the advantage is that they are recreated by Lightroom each dialog-box/export, thus no explicit cleanup need be implemented.
--
function ExportFilter.assureFilter( id, props, starter )
    if not id then
        error( "no id...", 3 )
    end
    app:callingAssert( id, "no id for assuring filter" )
    starter = starter or {}
    if starter.filterContext then
        props = props or starter.filterContext.propertyTable -- props are optional if starter includes filter context.
    end
    app:callingAssert( props, "no props for assuring filter" )
    local filterName = id.className or error( "bad id - should be extended export filter class" ) -- partially qualified.
    local propName = filterName..'_exportFilter' -- each export filter gets a tailored home property.
    --if props[propName] == nil or ( starter.filterContext and not props[propName].filterContext ) or ( starter.filterContext ~= nil and props[propName].filterContext ~= starter.filterContext ) then
    if props[propName] == nil or starter.filterContext ~= props[propName].filterContext then -- simplified logic (either may be nil, or not) - any descrepancy => recreate object.
        -- i.e. no filter, or filter was for dialog (no filter context), or filter context has changed since last created.
        -- ###3 this seems awefully iffy to me (e.g. dialog instance will be overwritten by exporting instance, but with potentially different property table object.
        -- nevertheless it seems to be working reliably (knock on wood).
        starter.exportSettings = props -- this will be (had better be) same as filter-context.property-table, if there is a filter-context.
        --Debug.pause( "Creating new", filterName, app:func( 3 ) )
        -- props[propName] = id:new( starter ) -- this works
        props[propName] = objectFactory:newObject( id, starter ) -- this does the same thing, except adheres to object factory middleman convention, in case 2ndary plugin author extends extended filters (yeah, like that's ever gonna happen ;-}).
    else -- appropriate export filter object already created.
        --Debug.pause( "Reusing", filterName, app:func( 3 ) )
        if props[propName].exportSettings ~= props then
            --Debug.pause( "prop change", starter.filterContext, props[propName].filterContext ) -- I'm not sure why this happens, but clearly Lr feels free to recreate property tables if the mood strikes (I remember this problem from previous experience assuming I could depend on property table object consistency - I can't).
            props[propName].exportSettings = props -- assures even if filter object already created, it's properties are freshest.
        end
    end
    return props[propName] -- return export filter instance.
end



--- Called from update-filter-status method, to ensure main filter.
--
--  @usage preferrably called in edb when LR-export-filters.. changes, since that catches it at earliest point,
--      <br>    on the down side, if multiple filters are present, you have to set through the prompt multiple times. - oh well, user shouldn't make that mistake more than once or twice..
--
function ExportFilter:requireFilterInDialog( id, nameOrTitle )
    local props = self.exportSettings or error( "no es" )
    local s, m = self:requireFilter( id )
    if s then
        return true
    else
        self:denyExport( "You need to add '^1' export filter - it is required.", nameOrTitle or LrPathUtils.extension( id ) or "Unknown filter" )
        return false
    end
end



--- Assure pre-requisite filter is (still) there.
--
--  @usage call in post-process photos method.
--
--  @param id (string, required) ID of required filter.
--  @param id (string, optional) If not passed, name/title will be the extension of the ID.
--
function ExportFilter:requireFilterInPost( id, nameOrTitle )
    local s, m = self:requireFilter( id )
    if s then
        self:logV( "^1 filter (required) is present.", nameOrTitle or LrPathUtils.extension( id ) or "Unknown filter"  )
        return true
    else
        self:logW( m ) -- fully descriptive error message.
        local s, m = self:cancelExport()
        if s then
            self:log( "Export canceled." )
        else
            self:logW( m )
        end
        return false
    end
end



--- Get section-in-dialog title, prefixed by app-name if >1 filter in plugin.
--
--  @usage one can always override this..
--
function ExportFilter:getSectionTitle()
    local filters = self.exportSettings.LR_exportFiltersFromThisPlugin
    if tab:is( filters ) and #filters > 1 then
        return str:fmtx( "^1 - ^2", app:getAppName(), self.title ) -- if > 1, prefix with app-name as qualifier.
    else -- 0 or 1 means 1.
        return self.title -- presumably author has named filter as desired for section title.
    end
end



--- Update synopsis
--
--  @usage Default implementation here assumes enable/disable & status - override to customize..
--
function ExportFilter:updateSynopsis()
    local props = self.exportSettings
    local syn
    if props[self.enablePropName] then
        if props[self.statusPropName] then
            syn = "ENABLED (No problems detected)"
        else
            syn = "ENABLED *** STATUS IS PROBLEM"
        end
    else
        syn = "DISABLED"
    end
    props[self.synopsisPropName] = syn
end



--- Process rendered photos method.
--
--  @usage ordinarily, derived type would override this method, but maybe not..
--
function ExportFilter:processRenderedPhotosMethod()

    self:logV( "*** Proccess rendered photos method has not been overridden." ) -- not strictly required, but probably..

end



--- This function will check the status of the Export Dialog to determine 
--  if all required fields have been populated.
--
--  @usage this function need not be overridden by base classes, as long as the ID in the observer is the extended class.
--
--  @param extendedExportFilterClass (ExportFilter derivative, required) must be the class of extended export filter.
--  @param props (prop-table) are common to all filters.
--  @param name (string, optional) property table *key* (include 'LR_' prefix, or not, as appropriate). pass name if called due to property change, otherwise may be nil for generic update.
--  @param value (any, optional) value correpsonding to name - makes no sense to pass if no name.
--
function ExportFilter.updateFilterStatus( extendedExportFilterClass, props, name, value )
    local filter = ExportFilter.assureFilter( extendedExportFilterClass, props )
    filter:updateFilterStatusMethod( name, value )
end



--- Clears export condition, *if* no other filters in this plugin have denied it.
--
--  @usage Lr itself keeps track of which plugins have set it, but NOT individual filters within a plugin - yeah: oops (Adobe).
--      <br> it is for this reason the common status property was set up - universal for all plugin filters.
--
function ExportFilter:clearExportCondition()
    -- Note: export-filters-from-this-plugin returns export filters from this plugin, but NOT an array of them,
    -- i.e. there are holes in "pos" where filters from other plugins would be.
    local filters = self.exportSettings.LR_exportFiltersFromThisPlugin
    if filters == nil then
        return -- this happens sometimes when dialog box transitions to another preset/service sans filters - just don't die is the goal then me-thinks.
    end
    for id, pos in pairs( filters ) do -- traverse unordered.
        local propName = ExportFilter._getPropName( ExportFilter._getFilterName( id ), 'status' ) -- ###2
        local status = self.exportSettings[propName]
        if type( status ) == 'boolean' then -- filter has had a shot at it.
            if status == false then -- one filter from this plugin is not a happy camper - don't clear export condition.
                return -- not clear
            end
        else -- 
            assert( status == nil, "bad status type" )
        end
    end
    self.exportSettings.LR_cantExportBecause = nil -- clear.
end
    


--- Sets boolean status property to false (denied), and (always) sets status message to 'reason', thus disabling export.
--
function ExportFilter:denyExport( reason, ... )
    app:callingAssert( str:is( reason, "reason for export denial" ), "there must be a reason for denying export" )
    self.exportSettings[self.stsMsgPropName] = str:fmtx( reason, ... )
    self.exportSettings[self.statusPropName] = false -- denied
    self.exportSettings.LR_cantExportBecause = str:fmtx( "See status in '^1' section.", self.title ) -- last call overwrites previous, but that's OK.
end



--- Sets boolean status property to true (no problem detected), and status message as passed or generic "ok", - export may be enabled if no other filters from this plugin have denied.
--
function ExportFilter:allowExport( message, ... )
    if str:is( message ) then
        message = str:fmtx( message, ... )
    end
    self.exportSettings[self.stsMsgPropName] = message or str:fmtx( "No problems detected in '^1' section.", self.title )
    self.exportSettings[self.statusPropName] = true -- ok in this corner.
    self:clearExportCondition() -- or dont.
end



--- This optional function adds the observers for our required fields metachoice and metavalue so we can change
--  the dialog depending if they have been populated.
--
--  @usage generally should be overridden.
--
function ExportFilter.startDialog( propertyTable )
    app:logV( "Start dialog function has not been overridden." )
    --local filter = ExportFilter.assureFilter( ExportFilter, propertyTable ) -- this creates an export-filter object of specified class.
    --filter:startDialogMethod() - note: base class has no such method, so this would result in error
end



--- This function will create the section displayed on the export dialog 
--  when this filter is added to the export session.
--
--  @usage generally should be overridden, unless you just want the generic "nuthin' to see here" text where settings would otherwise be.
--
function ExportFilter.sectionForFilterInDialog( vf, propertyTable )
    app:logV( "Section for filter in dialog has not been overridden, returning generic \"nuthin' to see here\" section." )
    local filter = ExportFilter.assureFilter( ExportFilter, propertyTable ) -- careful about that ID/class.
    return filter:sectionForFilterInDialogMethod()
end



--- return section for filter setup
--
--  @usage typically overridden.
--
function ExportFilter:sectionForFilterInDialogMethod()
	
	app:logV( "*** Export filter's section-for-filter-in-dialog method has not been overriden." ) -- Not strictly required, but *strongly* recommended.
	
	return {
		title = app:getAppName(),
		vf:row {
			vf:static_text {
				title = str:fmtx( "^1 requires no configuration, or else there's a bug in this plugin.", self.title ),
			},
		},
    }
	
end



--- This function obtains access to the photos and removes entries that don't match the metadata filter.
--
--  @usage Worth noting: there is *no* filter-context at this stage, nor export session, nor export context...
--
function ExportFilter.shouldRenderPhoto( exportSettings, photo )
    app:logV( "Should render photo function has not been overridden." )
    local filter = ExportFilter.assureFilter( ExportFilter, exportSettings ) -- be sure to use proper class here when overriding.
    return filter:shouldRenderPhotoMethod( photo ) -- just returns 'true'.
end



--- Determine if photo should pass go or not.
--
--  @usage if no-go, then it will be *silently* omitted, so if you want to make a fuss, it costs extra..
--  @usage extras you may want to consider: file-format (consider video), virtual-copy, filename extension, smart preview, original source online/offline..
--
function ExportFilter:shouldRenderPhotoMethod( photo )
    return true
end



--- Post process rendered photos.
--
--  @usage override this function, or set it to nil.
--
function ExportFilter.postProcessRenderedPhotos( functionContext, filterContext )

    app:error( "*** post process rendered photos function has not been overridden." )

    -- this is what overridden method should look like:
    --[[
    local filter = ExportFilter.assureFilter( MyExtendedExportFilter, filterContext.propertyTable, { functionContext=functionContext, filterContext=filterContext } )
    filter:postProcessRenderedPhotosMethod()
    --]]
    
end



--- No-op (call from post-process-rendered-photos method if, for example, filter doesn't meet criteria for doing it's thing...).
--
--  @usage - my experience: if post-process-rendered-photos function is defined, it will be called, and expected to operate. This method is therefore necessary to keep the ball rolling.
--
function ExportFilter:passRenditionsThrough( errm )
    assert( self.filterContext, "no filter context" )
    for r1, r2 in self.filterContext:renditions() do
        local s, m = r1:waitForRender()
        if errm then
            r2:renditionIsDone( false, errm )
        else
            r2:renditionIsDone( s, m )
        end
    end
end



--- Get "pseudo-array" of filters, plus indexes of first and last, plus total from this plugin (and names).
--
--  @usage Do NOT traverse filters using ipairs, since first entries may be nil (ipairs quits on a nil).
--  @usage You *can* traverse names array using ipairs, and index filters in loop body..
--  @usage *** last may be greater than total (but will never be less).
--  @usage There are no settings from other plugins in here, nor are they in list of export filters...
--      <br>    such settings influence exporting, but are managed by Lightroom. No doubt the reason we can't initiate exports on the fly which include filters from other plugins.
--
--  @return filters (pseudo-array) aka "sparse" array, of filter IDs.
--  @return first (numeric) index - can be used to index filters or names.
--  @return last (numeric) index - can be used to index filters or names.
--  @return total (numeric) number of export filters from this plugin.
--  @return names (array) array of partially-qualified export filter names (not sparse), values include "other/unknown" entry if not from this plugin.
--
function ExportFilter:getFilters()
    local first = math.huge
    local last = -math.huge
    local total = 0
    local filters = {}
    for id, pos in pairs( self.exportSettings.LR_exportFiltersFromThisPlugin ) do
        if pos < first then
            first = pos
        end
        if pos > last then
            last = pos
        end
        filters[pos] = id
        total = total + 1
    end
    local names = {}
    for i = 1, last do
        local id = filters[i]
        if id then
            names[#names + 1] = LrPathUtils.extension( id )
        else
            names[#names + 1] = "Filter from some other plugin"
        end
    end
    return filters, first, last, total, names
end



--- Assures export filter position within this plugin.
--
--  @usage can not assure position w.r.t. export filters of other plugins.
--
--  @return status (boolean) true iff top/bottom filter, as desired.
--  @return lastId (string) ID of top/bottom filter, if not as desired.
--
function ExportFilter:requireFilter( requiredFilterId, dependentFilterId )
    assert( requiredFilterId, "no required filter ID" ) -- e.g. from Info.lua.
    dependentFilterId = dependentFilterId or self.id
    assert( dependentFilterId, "no dependent filter ID" ) -- e.g. from Info.lua.
    local filters = self.exportSettings.LR_exportFiltersFromThisPlugin
    if not tab:is( filters ) then
        return false, "no viable export filters from this plugin.."
    end
    local b = {}
    for id, pos in pairs( filters ) do
        if id == requiredFilterId then
            return true
        else
            b[#b + 1] = id
        end
    end
    return false, str:fmtx( "'^1' is required by '^2', but is not present. FWIW - these filters are present: ^3", requiredFilterId, dependentFilterId, table.concat( b, ", " ) )
end



--- Generic finale method if section method is wrapped - override, ignore, or use as is..
--
function ExportFilter:sectionForFilterInDialogFinale( call )
    if not call.status then
        self:logE( call.message )
        local button = app:show{ confirm="Uh-oh, trouble in paradise - ^1.\n \nPlease visit the plugin manager, plugin-author tools section for additional diagnostic information, and/or to reload/re-enable plugin. If you continue to have problems, please report them to plugin author.\n \nCare to take a gander at the plugin log file?",
            subs = { call.message },
            buttons = dia:buttons( "YesNo" ),
        }
        if button == 'ok' then
            app:showLogFile()
        end
        error( call.message ) -- propagate error to Lr for displaying generic problem info in dialog box.
    end
end



--- Get view object which presents labeled status, typically at bottom of section.
--
function ExportFilter:sectionForFilterInDialogGetStatusView( lines )
    return vf:row {
		spacing = vf:control_spacing(),
		vf:static_text {
			title = "Status:",
			--width = share 'labels',
		},
		vf:static_text {
			title = bind( self.stsMsgPropName ),
			height_in_lines = lines or 2,
			fill_horizontal = 1,
			font = "<system/bold>",
		},
	}
end



--- Generic finale method for photo processing method - assures exiftool session is closed (if assigned to standard member), and shows dialog box if problem,
--      <br>    since there will be no error box shown if foreign export service.
--  
function ExportFilter:postProcessRenderedPhotosFinale( call )
    self:log()
    if gbl:getValue( 'exifTool' ) then
        exifTool:closeSession( call.ets )
    end
    if call.status then
        self:logV( "No error thrown." )
    else -- call ended prematurely due to error.
        -- ###2 ideally, it would be great to determine if export service is from this plugin, and omit show in that case, lest the various filter boxes stack up.
        -- oh well, they'd still stack up if export service a different plugin, or hard-drive service, so not much point I guess. It might make sense however
        -- if it was possible to have a shared service(call), but I don't see how just now.
        app:show{ error=call.message } -- no finale dialog box?
    end
    self:log()
end
        


--- Peruse renditions and return photo/video tables, candidate renditions, metadata cache.
--
--  @param params (table) named parameters.
--      <br>    rawIds (array, optional) raw ids for metadata cache, if desired.
--      <br>    fmtIds (array, optional) fmt ids for metadata cache, if desired.
--      <br>    call (object, required) calling context call object.
--
--  @return photos (array) of photos - may be empty, but never nil.
--  @return videos (array) of videos - may be empty, but never nil.
--  @return union (array) of photos & videos - may be empty, but never nil.
--  @return unionCache (Cache) containing specified metadata for photos & videos - may be empty, but never nil.
--  @return candidates (array) candidate renditions. It's possible to pare down candidates depending on filter - thus the name.
--
function ExportFilter:peruseRenditions( params )

    local photos = {}
    local videos = {}
    local union = {}
    local unionCache        
    local candidates = {}
    
    -- peruse renditions to get union
    for i, rendition in ipairs( self.filterContext.renditionsToSatisfy ) do
        union[#union + 1] = rendition.photo
        candidates[#candidates + 1] = rendition -- includes video for pass-through (Lr4+) and photos.
    end
    -- acquire metadata for union
    unionCache = lrMeta:createCache{ photos=union, rawIds=params.rawIds, fmtIds=params.fmtIds, call=params.call }
    -- peruse union to divide photos and video.
    for i, u in ipairs( union ) do
        if unionCache:getRawMetadata( u, 'fileFormat' ) == 'VIDEO' then
            videos[#videos + 1] = u
        else
            photos[#photos + 1] = u -- make virtual copies of these.
        end
    end
    
    if #photos > 0 then
        self:log( "^1 may be processed by this filter", str:nItems( #photos, "photos" ) )
    end
    if #videos > 0 then
        self:log( "^1 may be processed by this filter", str:nItems( #videos, "videos" ) )
    end
    if #union > 0 then
        -- got something to work with..
    else -- ###3 should I be using bezel/scope too? (ditto for like others).
        self:logW( "No photos (nor video) are ripe for exporting - perhaps they've not met appropriate pre-requisites, e.g. finished editing, locked, ..." )
        local s, m = self:cancelExport()
        if s then
            self:log( "Export canceled." )
        else
            self:logW( m )
        end
        return nil -- everybody should check for this.
    end
    
    return { photos=photos, videos=videos, union=union, unionCache=unionCache, candidates=candidates }

end



--- Abort/cancel the export.
--
--  @usage Must be called before rendering has started.
--  @usage Best practice: log warning or error before calling this, but note - *** Log file may be suppressed if 'Reload After Export' is enabled in plugin manager.
--
--  @return status (boolean) true iff all renditions skipped.
--  @return message (string) explains false status.
--
function ExportFilter:cancelExport( autoLog )
    assert( self.filterContext, "no filter context" )
    local sts = true
    local msg
    -- abort as many as possible, hopefully all:
    for r1, r2 in self.filterContext:renditions() do
        local s, m = LrTasks.pcall( r1.skipRender, r1 )
        if s then
            -- skipped (successfully), which means no error.
            -- Note: it does not seem to help setting rendition-is-done to true, I think if it's successfully skipped, Lr won't be considering whether it's "done".
        else
            sts = false
            msg = m
            Debug.pause( s, m )
            local s, m = LrTasks.pcall( r2.renditionIsDone, r2, false, str:fmtx( "Unable to skip rendering - ^1", m ) )
            Debug.pause( s, m )
            if s then
                -- and there's an end on it (maintain sts/msg set due to error skipping render.
            else
                -- override skip-render error with error from rendition-is-done method, I guess..
                msg = m
            end
        end
    end
    if autoLog then
        if sts then
            self:log( "Export canceled." )
        else
            self:logW( msg )
        end
        return -- nil.
    else 
        return sts, msg
    end
end



-- "export filter / export preset fields" are relegated to extending class.
-- no need to explicitly inherit from base Object class, since it includes no Lr export-filter functions.
-- extended classes must however inherit explicitly from this base class.



return ExportFilter
