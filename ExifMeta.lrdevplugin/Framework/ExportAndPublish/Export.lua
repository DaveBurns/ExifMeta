--[[
        Export.lua
        
        Dual-purpose object:
        
        1. To support export dialog box (or publish settings).
        2. To support actual export (or publish) service exporting.
--]]

local Export, dbg, dbgf = Object:newClass{ className = 'Export' }



Export.dialog = nil -- pointer to object handling dialog box.
Export.exports = {} -- lookup for all unfinished export objects - key is export context.



--- Constructor for extending class.
--      
function Export:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor to create the export object that represents the export dialog box.
--      
--  <p>One of these objects is created when the export dialog box is presented,
--  if it has not already been.</p>
--
function Export:newDialog( t )
    local o = Object.new( self, t )
    o.propChgGate = Gate:new{ max = 50 } -- it is recommended to use this in property change handling method, so calls don't recurse but no changes get lost (i.e. call is gated).
        -- remember: it's possible for multiple gated calls to be executed back-to-back, so use prompt-once parameter of app-show method to eliminate redundent prompts.
        -- I assume 50 will be enough, if not this gate can be overridden.
    return o
end
Export.new = Export.newDialog -- function Export:new( ... ) -- synonym for (minimal) object which has access to export methods, but not representing an export in progress (with session, context, settings, ... ).



--- Create a new export object.
--      
--  <p>One of these objects is created EACH time a new export is initiated,
--  then killed at export completion - supports multiple concurrent exports,
--  without interference (assuming a different set of photos is selected,
--  otherwise all kinds of interference...)</p>
--                          
--  @param t     Parameter table<ul>
--                  <li>exportContext
--                  <li>functionContext</ul>
--                          
--  @return      Export object
--
function Export:newExport( t )

    local o = Object.new( self, t )
	o.exportParams = o.exportContext.propertyTable
	
    --Debug.lognpp( o.exportParams )
    --Debug.showLogFile()
    --Debug.pause()
	
    o.exportSession = o.exportContext.exportSession
    o.functionContext = o.functionContext
    o.exportProgress = nil -- initialized when service gets under way (after renditions have been checked)
    o.nPhotosToExport = 0
    o.nPhotosToRender = 0 -- initialized in service function.
    o.nPhotosRendered = 0 -- counted during service.
    o.nRendFailures = 0
    o.filenamePreset = nil
    o.filenamePresetCache = nil
    --Debug.lognpp( o.exportParams )
    --Debug.showLogFile()
    o.srvc = nil
    
    --intercom:listen( Export.callback, o, { ["com.robcole.lightroom.ExportManager"]=true } ) - works fine, but bad design.
    
    intercom:broadcast{ exportState='ready' } -- reminder: new-export is called each time an export is initiated.
    
    return o
    
end



--- "Protected" method to get export parameters based on properties.
--
--  This method only makes sense in the context of a publish service that also supports non-publish exporting.
--
function Export:_getExportParams( props )
    local myName = props.LR_publish_connectionName
    if str:is( myName ) then
        local pservices = catalog:getPublishServices( _PLUGIN.id )
        for i, pservice in ipairs( pservices ) do
            local name = pservice:getName()
            --Debug.logn( i, name )
            if name == myName then
                local ps = pservice:getPublishSettings()
                if ps ~= nil then
                    local ep = ps['< contents >']
                    if ep ~= nil then
                        return ep
                    end
                else
                    Debug.pause( "?" )
                end
                break
            end
        end
    else
        return props -- note: this also has a <contents> member, but can be used as-is unless making a table copy..
    end
end



local maxDimConstraints = { min=0, max=65000 } -- technically min=1, but some people are putting 0 in to mean "anything for this dim, let other dim constrain".
--
-- Export settings definition table.
--
Export.settingsDef = {
    ['LR_format'] = { section="File Settings", title="Image Format", required='yes', dataType='string', legalValues={ ['JPEG']=true, ['TIFF']=true, ['ORIGINAL']=true, ['PSD']=true, ['DNG']=true } },
    ['LR_collisionHandling'] = { section="Export Location", title="Existing Files (collision handling)", required='yes', legalValues = { ['overwrite']=true, ['skip']=true, ['ask']=true, ['rename']=true } },
    ['LR_metadata_keywordOptions'] = { section="Metadata", title="Include", required='depends', legalValues={ ['lightroomHierarchical']=true, ['flat']=true } },
    ['LR_embeddedMetadataOption'] = { section="Metadata", title="Include", required='yes', legalValues={ ['copyrightOnly']=true, ['copyrightAndContactOnly']=true, ['allExceptCameraInfo']=true, ['all']=true } },
    ['LR_export_colorSpace'] = { section="File Settings", title="Color Space", required='yes', legalValues={ sRGB='sRGB', AdobeRGB='AdobeRGB', ProPhotoRGB='ProPhotoRGB', _=true } }, -- different format for emphasis: custom colorspaces may also be valid.
    ['LR_size_resizeType'] = { section="Image Sizing", title="Method", required='depends', legalValues={ ['wh']=true, ['longEdge']=true, ['shortEdge']=true, ['megapixels']=true, ['dimensions']=true } },
    ['LR_size_units'] = { section="Image Sizing", title="Units", required='depends', legalValues={ ['pixels']=true,   ['in']=true, ['cm']=true } },
    ['LR_useWatermark'] = { section="Watermarking", title="Use Watermark", required='yes', dataType='boolean', default=false },
    ['LR_watermarking_id'] = { section="Watermarking", title="Watermark ID", required='depends', dataType='string' },
    ['LR_export_bitDepth'] = { section="", title="File Settings", required='depends', dataType='number', constraints={ min=8, max=16 } },
    ['LR_jpeg_quality'] = { section="File Settings", title="Quality", required='depends', dataType='number', constraints={ min=0, max=1 } },
    ['LR_jpeg_useLimitSize'] = { section="File Settings", title="Limit File Size", required='depends', dataType='boolean' },
    ['LR_jpeg_limitSize'] = { section="File Settings", title="File Size Limit", required='depends', dataType='number', constraints={ min=1, max=math.huge } }, -- constraints
    ['LR_size_maxHeight'] = { section="Image Sizing", title="Height/Edge-Dim", required='depends', dataType='number', constraints=maxDimConstraints },
    ['LR_size_megapixels'] = { section="Image Sizing", title="Megapixels", required='depends', dataType='number', constraints={ min=.000001, max=512 } }, -- dunno if it'll export a 1-pixel jpeg, but hey..
    ['LR_extensionCase'] = { section="File Naming", title="Extensions", required='yes', legalValues={ ['lowercase']=true, ['uppercase']=true }, default='lowercase' }, -- sure about no default in table? (reminder: defaults can be implemented as depends). Note: there is a same case option in ottomanic-importer, but not seeing it in Lr proper for export (not sure why - I thought it used to be there ###2).
    ['LR_export_destinationType'] = { section="Export Location", title="Export To (destination type)", required='yes', legalValues={ ['specificFolder']=true, ['chooseLater']=true, ['sourceFolder']=true } },    
    ['LR_minimizeEmbeddedMetadata'] = { section="Metadata", title="Legacy Setting", required='depends', dataType='boolean' },
    ['LR_export_useSubfolder'] = { section="Export Location", title="Put in Subfolder", required='depends', dataType='boolean' },
    ['LR_export_destinationPathPrefix'] = { section="Export Location", title="Folder (destination path prefix)", required='depends', dataType='string' }, -- constraint (str:is)? ###2
    ['LR_export_destinationPathSuffix'] = { section="Export Location", title="Subfolder (destination path suffix)", required='depends', dataType='string' }, -- constraint (str:is)? ###2
    ['LR_removeLocationMetadata'] = { section="Metadata", title="Remove Location Info", required='depends', dataType='boolean' },
    ['LR_size_doConstrain'] = { section="Image Sizing", title="Resize (to fit)", required='yes', dataType='boolean' },
    ['LR_size_doNotEnlarge'] = { section="Image Sizing", title="Dont Enlarge", required='depends', dataType='boolean' },
    ['LR_reimportExportedPhoto'] = { section="Export Location", title="Add to This Catalog", required='yes', dataType='boolean', default=false },
    ['LR_renamingTokensOn'] = { section="File Naming", title="Rename To (via tokens)", required='yes', dataType='boolean' },
    ['LR_tokens'] = { section="File Naming", title="Token Preset", required='depends', dataType='string' },
    ['LR_tokenCustomString'] = { section="File Naming", title="Custom Text (custom token replacement)", required='depends', dataType='string' },
    ['LR_tokensArchivedToString2'] = { section="File Naming", title="behind the scenes...", required='no', dataType='any' }, -- ###2 not sure if data-type should be string or table.
    ['LR_exportServiceProviderTitle'] = { section="General", title="Export To", required='no', dataType='string' },
    ['LR_exportServiceProvider'] = { section="General", title="Export To?", required='no', dataType='string' }, -- ###2
    ['LR_selectedTextFontFamily' ] = { section="General", title="Font Family?", required='no', dataType='string' }, -- ###2
    ['LR_selectedTextFontSize' ] = { section="General", title="Font Size?", required='no', dataType='number', constraints={ min=1, max=math.huge } }, -- ###2 constraints
    ['LR_initialSequenceNumber'] = { section="File Naming", title="Start Number", required='no', dataType='number', constraints={ min=1, max=math.huge } }, -- ###2 may be required to satisfy renaming template - if so, you'd best pass it..
    ['LR_outputSharpeningOn'] = { section="Output Sharpening", title="Sharpen For", required='no', dataType='boolean' },
    ['LR_outputSharpeningLevel'] = { section="Output Sharpening", title="Amount", required='depends', dataType='number', constraints={ min=0, max=3 } },
    ['LR_size_resolution'] = { section="Image Sizing", title="Resolution", required='no', dataType='number', constraints={ min=0, max=math.huge } },
    ['LR_size_resolutionUnits'] = { section="Image Sizing", title="Resolution Units", required='no', dataType='string' },
    ['LR_includeVideoFiles'] = { section="Video", title="Include Video Files", required='no', dataType='boolean' },
    ['LR_export_videoFileHandling'] = { section="Video", title="File Handling", required='depends', dataType='string' },
    ['LR_removeFaceMetadata'] = { section="Metadata", title="Remove Face Metadata", required='no', dataType='boolean' },
    ['LR_includeFaceTagsAsKeywords'] = { section="Metadata", title="Face Tags As Keywords", required='no', dataType='boolean' },
    ['LR_reimport_stackWithOriginal_position'] = { section="Export Location", title="Stack Position", required='depends', dataType='string' },
    ['LR_tiff_preserveTransparency'] = { section="File Settings", title="Preserve Transparency", required='depends', dataType='boolean' },
    ['LR_tiff_compressionMethod' ] = { section="File Settings", title="Compression", required='depends', dataType='string' },
    ['LR_export_postProcessing'] = { section="Post-processing", title="Post-processing", required='no', dataType='string' }, -- depends on export service (I assume only for hard-drive).

    ['LR_outputSharpeningMedia'] = { section="Output Sharpening", title="Sharpen For", required='depends', dataType='string' },
    ['LR_reimport_stackWithOriginal'] = { section="Export Location", title="Stack Position", required='depends', dataType='boolean' },
    ['LR_reimport_stackWithOriginal_position'] = { section="Export Location", title="Stack Position", required='depends', dataType='string' },
    ['LR_reimportExportedPhoto'] = { section="Export Location", title="Add to This Catalog", required='true', dataType='boolean' },
    
    ['LR_export_videoFormat'] = { section="Video", title="Format", required='depends', dataType='string' },
    ['LR_export_videoPreset'] = { section="Video", title="Preset", required='depends', dataType='string' },
    
    ['reserved'] = { section="", title="", required='', dataType='' },
}

local reqFuncs = { -- determine whether conditions are such that setting is required (only called if it's not been supplied, i.e. is nil).
    ['LR_size_resizeType'] = function( settings ) return settings.LR_size_doConstrain end,
    ['LR_size_units'] = function( settings ) return settings.LR_size_doConstrain and settings.LR_size_resizeType ~= 'megapixels' end,
    ['LR_jpeg_quality'] = function( settings ) return settings.LR_format == 'JPEG' end,
    ['LR_tiff_preserveTransparency'] = function( settings ) return settings.LR_format == 'TIFF' end,
    ['LR_tiff_compressionMethod'] = function( settings ) return settings.LR_format == 'TIFF' end,
    ['LR_jpeg_useLimitSize'] = function( settings ) return settings.LR_format == 'JPEG' end,
    ['LR_jpeg_limitSize'] = function( settings ) return settings.LR_format == 'JPEG' end,
    ['LR_export_bitDepth'] = function( settings ) return settings.LR_format == 'TIFF' or settings.LR_format=='PSD' end,
    ['LR_export_destinationPathPrefix'] = function( settings ) return settings.LR_export_destinationType=='specificFolder' end,
    ['LR_export_destinationPathSuffix'] = function( settings ) return settings.LR_export_destinationType=='specificFolder' and settings.LR_export_useSubfolder end,
    ['LR_watermarking_id'] = function( settings ) return settings.LR_useWatermark end,
    ['LR_size_maxHeight'] = function( settings ) return settings.LR_size_doConstrain and settings.LR_size_resizeType ~= 'megapixels' end,
    ['LR_size_maxWidth'] = function( settings ) return settings.LR_size_doConstrain and settings.LR_size_resizeType == 'wh' or settings.LR_size_resizeType ~= 'dimensions' end,
    ['LR_size_megapixels'] = function( settings ) return settings.LR_size_doConstrain and settings.LR_size_resizeType=='megapixels' end,
    ['LR_tokens'] = function( settings ) return settings.LR_renamingTokensOn end,
    ['LR_tokenCustomString'] = function( settings ) return settings.LR_renamingTokensOn and settings.LR_tokens:find("{custom_token}") end,
    ['LR_metadata_keywordOptions'] = function( settings )
        if settings.LR_embeddedMetadataOption=='all' or settings.LR_embeddedMetadataOption=='allExceptCameraInfo' then
            return true
        else
            settings.LR_metadata_keywordOptions = 'flat' -- hopefully this is a no-op
            return false
        end
    end,
    ['LR_minimizeEmbeddedMetadata'] = function( settings )
        if settings.LR_embeddedMetadataOption == 'copyrightOnly' then
    	    settings.LR_minimizeEmbeddedMetadata = true -- Lr3-
    	end
    	return false -- not required, but may be set anyway - kinda weird, but works.
    end,
    ['LR_export_useSubfolder'] = function( settings )
        settings.LR_export_useSubfolder = false -- reminder, this is only called if it's nil.
        return false
    end,
    ['LR_removeLocationMetadata'] = function( settings )
        if settings.LR_embeddedMetadataOption=='all' or settings.LR_embeddedMetadataOption=='allExceptCameraInfo' then
            return true
        else
            settings.LR_removeLocationMetadata = true
            return false
        end
    end,
    ['LR_size_doNotEnlarge'] = function( settings ) return settings.LR_size_doConstrain end,
    ['LR_outputSharpeningLevel'] = function( settings ) return settings.LR_outputSharpeningOn end,
    ['LR_outputSharpeningMedia'] = function( settings ) return settings.LR_outputSharpeningOn end,
    ['LR_reimport_stackWithOriginal_position'] = function( settings ) return settings.LR_reimport_stackWithOriginal end,
    ['LR_export_videoFileHandling'] = function( settings ) return settings.LR_includeVideoFiles end,
    ['LR_export_videoFormat'] = function( settings ) return settings.LR_includeVideoFiles end,
    ['LR_export_videoPreset'] = function( settings ) return settings.LR_includeVideoFiles end,
    ['reserved'] = function( settings ) return end,
}



-- Private/protected method, so far.
function Export:checkDepends( depends, settings )
    for i, k in pairs( depends ) do
        local reqFunc = reqFuncs[k]
        if reqFunc then
            local req = reqFunc( settings ) -- reminder, setting was nil, and reqFunc returns whether settings are such that it is required.
            if req then
                return false, "missing: "..k
            else
                -- so far so good..
            end
        else
            return false, "no req func: "..k
        end
    end
    return true -- all dependencies satisfied
end



--  Private/protected method, so far - get constrained setting value, given prospective (current) value, and default that originates in calling context.
--
--  @return value, status
--
function Export:getConstrainedSetting( id, curVal, default )
    local spec = Export.settingsDef[id]
    if spec == nil then
        return curVal, str:fmtx( "No spec registered for setting w/ID: '^1' - this may indicate a problem, but returning current value anyway: '^2'", id, curVal )
    end
    if curVal == nil then
        if default ~= nil then
            -- log
            return default
        else
            if spec.required == 'yes' then
                app:error( "Value is required (but is not present) for: '^1'", id )
            elseif spec.required == 'depends' then
                return nil, 'depends'
            else -- 'no' (or nil).
                return nil -- optional, and unspecified.
            end
        end
    else -- current value not nil.
        if spec.legalValues then
            if spec.legalValues[curVal] then
                return curVal
            elseif spec.legalValues['_'] then -- others too
                app:logV( "Value for '^1' is not one of the common legal values - it may or may not be OK: ^2", id, curVal ) -- other values *are* legal, whether this particular value is legal - who knows..
                return curVal
            else
                app:error( "Value for '^1' is invalid: ^2", id, curVal )
            end
        elseif spec.dataType == 'boolean' then
            if type( curVal ) == 'boolean' then
                return curVal
            else
                app:error( "Value (^1) for '^2' should be 'boolean', not '^3'", curVal, id, type( curVal ) )
            end
        elseif spec.dataType == 'number' then
            if type( curVal ) == 'number' then
                if tab:is( spec.constraints ) then
                    if curVal >= spec.constraints.min and curVal <= spec.constraints.max then -- have both or else..
                        return curVal
                    else
                        app:error( "Value for '^1' is out of range, must be between ^1 and ^2, inclusively.", id, spec.constraints.min, spec.constraints.max )
                    end
                else
                    app:logW( "Spec has no numeric range constraints for '^1', so dunno if value (^2) is valid.", id, curVal ) -- not severe enough? ###2
                    return curVal -- unconstrained
                end
            else
                app:error( "Value (^1) for '^2' should be 'number', not '^3'", curVal, id, type( curVal ) )
            end
        elseif spec.dataType == 'string' then
            if type( curVal ) == 'string' then
                return curVal
            else
                app:error( "Value (^1) for '^2' should be 'string', not '^3'", curVal, id, type( curVal ) )
            end
        elseif spec.dataType == 'any' then
            return curVal
        else
            app:error( "unexpected data-type: ^1", spec.dataType )
        end
    end
end



-- p/p
function Export:getConstrainedSettings( uSettings, depends ) --, defaults )
    --defaults = defaults or {}
    local settings = {}
    local issues = {}
    for k, v in pairs( uSettings ) do
        local issue
        settings[k], issue = self:getConstrainedSetting( k, uSettings[k], nil ) -- defaults[k] )
        if issue then
            if issue == 'depends' then
                depends[#depends + 1] = k -- value is nil.
            else
                issues[#issues + 1] = issue
            end
        end
    end
    if #issues > 0 then
        return settings, "settings may have issues: "..table.concat( issues, ", " )
    else
        return settings -- no issues.
    end
end



local constrainParamValues = { ['yes']=true, ['no']=true, ['strict']=true }



--- Do export on current task.
--
--  @usage      convenience method for on-the-fly exporting - assuming called from task (is synchronous).
--  @usage      example:
--              <br>    local s, m = export:doExport {
--              <br>        photos = photos,
--              <br>        defaults = export:getSettingsFromPreset{ file=file }, -- get baseline from preset which exports as tiff
--              <br>        constrainDefaults = 'no', -- settings in preset file are pre-constrained (proven to work together and be in bounds..).
--              <br>        settings = { LR_format='JPEG' } -- export as jpeg instead (you may want to set other jpeg options to be sure).
--              <br>        constrainSettings = app:isAdvDbgEna() and 'strict' or 'yes' -- do strict checking in debug mode only, but in any case - assure on-the-fly settings are valid..
--              <br>    }
--
--  @param      params      parameter table, with members:
--              <br>        photos (array) or photo (single lr-photo) - one of these is required.
--              <br>        settings - critical export settings - will supercede defaults - required.
--              <br>        defaults - baseline settings - optional.
--              <br>        constrainSettings (enum, default='no') 'yes', 'no', 'strict'. Determines whether to constrain critical export settings, and if so whether to check strictly.
--              <br>        constrainDefaults (enum, default='no') 'yes', 'no', 'strict'. Determines whether to constrain baseline export settings, and if so whether to check strictly.
--
--  @return s
--  @return m
--
function Export:doExport( params )
    local photos = params.photos or { params.photo }
    app:callingAssert( tab:is( photos ), "photo(s) must be specified" )
    local explicit = app:callingTypeAssert( params.settings, "settings", 'table' )
    app:callingAssert( tab:is( explicit ), "settings table must be passed" )
    local explicitConstrain = app:callingLegalAssert( params.constrainSettings, "constrainSettings", constrainParamValues )
    -- default table is now optional.
    local baseline = params.defaults -- can be nil/empty.
    -- only applies 
    local settings
    local depends = {}
    local issues
    if explicitConstrain ~= "no" then
        settings, issues = self:getConstrainedSettings( explicit, depends ) -- , baseline )
        if issues then
            if explicitConstrain=='strict' then -- don't export if settings issues and strict mode.
                return false, issues
            else
                Debug.pause( issues )
                app:logV( "Explicit settings table - "..issues )
            end
        else
            dbgf( "Settings constrained with no issues." )
        end
    else
        dbgf( "Assigning explicit settings without constraining." )
        if tab:is( baseline ) then -- note: adding *baseline* settings to passed table (explicit) will make it grow - safer to copy settings.
            settings = tab:copy( explicit )
        else
            settings = explicit -- safe to simply assign external table, since won't be altered.
        end
    end

    if tab:is( baseline ) then -- defaults
        local baselineConstrain = app:callingLegalAssert( params.constrainDefaults, "constrainDefaults", constrainParamValues )
        if baselineConstrain ~= 'no' then
            baseline, issues = self:getConstrainedSettings( baseline, depends )
            if issues then
                if baselineConstrain=='strict' then
                    return false, issues
                else
                    Debug.pause( issues )
                    app:logV( "Baseline/default table - "..issues )
                end
            else
                dbgf( "Merging baseline/default settings constrained with no issues." )
            end
        else -- do not constrain
            dbgf( "Merging baseline/default settings without constraining." )
        end
        for k, v in pairs( baseline ) do
            if settings[k] == nil then
                settings[k] = baseline[k]
            end
        end
    else
        app:logV( "No baseline (default) settings." )
    end
    
    -- note: dependencies are encountered whilst evaluating constraints.
    if #depends > 0 then -- some settings had unresolved dependency constraints.
        local s, m = self:checkDepends( depends, settings )
        if s then
            app:logV( "Dependencies satisfied." )
        else
            return false, "Dependencies not satisfied: "..( m or "oops" )
        end
    end
    
    -- check whether all requirements have been satisfied, and assign spec defaults if any required settings are missing.
    -- this is being done whether settings are otherwise being constrained or not - I hope that's OK.
    for k, v in pairs( Export.settingsDef ) do
        if v.required=='yes' then
            if settings[k] == nil then
                if v.default ~= nil then
                    settings[k] = v.default
                else
                    return false, "Missing required setting: "..k
                end
            end
        end
    end
    
    --Debug.lognpp( settings )

    if settings.LR_export_destinationType == 'specificFolder' then
        local dir = settings.LR_export_destinationPathPrefix
        if settings.LR_export_useSubfolder then
            dir = LrPathUtils.child( dir, settings.LR_export_destinationPathSuffix )
        end
        if not fso:existsAsDir( dir ) then
            local s, m = fso:assureDir( dir )
            if s then
                app:logV( "Assured dir: ^1", dir )
            else
                return false, m
            end
        else
            app:logV( "Export destination already exists: ^1", dir )
        end
    end
    
    local session = LrExportSession {
        photosToExport = photos,
        exportSettings = settings,
    }
    
    -- *** uncomment these lines to enable custom export functionality:
    local s, m = LrTasks.pcall( session.doExportOnCurrentTask, session ) -- perform export synchronously (without spawning another asynchronous task).
    return s, m

end



local exportFormats = { ['JPEG']="JPEG", ['TIFF']="TIFF", ['ORIGINAL']="ORIGINAL", ['PSD']="PSD", ['DNG']="DNG" }
local collisionHandling = { ['overwrite']="overwrite", ['skip']="skip", ['ask']="ask", ['rename']="rename" }
local metadataLoopback = { copyrightOnly="copyrightOnly", copyrightAndContactOnly="copyrightAndContactOnly", allExceptCameraInfo="allExceptCameraInfo", all="all" }
local colorSpaces = { sRGB='sRGB', AdobeRGB='AdobeRGB', ProPhotoRGB='ProPhotoRGB', _=true } -- custom colorspaces may also be valid.
local resizeTypes = { 'wh', 'longEdge', 'shortEdge', 'megapixels', 'dimensions' }
local jpegQualityConstraints = { min=0, max=1 }
local maxDimConstraints = { min=0, max=65000 } -- technically min=1, but some people are putting 0 in to mean "anything for this dim, let other dim constrain".
local megapixelsConstraints = { min=.000001, max=512 } -- dunno if it'll export a 1-pixel jpeg, but hey..
local caseLoopback = { lowercase="lowercase", uppercase="uppercase" } -- I could have sworn there used to be a "same case" option, hmm...
local destinationLoopback = { specificFolder='specificFolder', chooseLater='chooseLater', sourceFolder='sourceFolder' }



--- function to export photo(s) with specified settings.
--
--  @param params (table, required) essential export settings, and also:
--      <br>    photo or photos (single LrPhoto, or array of).
--      <br>    explicitSettings (explicit Lr export settings, overrides baseline settings).
--      <br>    baselineSettings (default Lr export settings, will be assigned if no explicit settig override).
--
--  @usage *** deprecated: use do-export method instead.
--  @usage LR export settings must be specified without the LR prefix.
--  @usage only the first char is required of string settings when unambiguous.
--  @usage alternate specifiers:
--      <br>    watermark (boolean) true = simple-copyright; false = none.
--  @usage does NOT assure target dir is created, so calling context must do so, if appropriate.
--
function Export:doExportOnCurrentTask( params )
    local photos = params.photos or { params.photo }
    app:callingAssert( tab:is( photos ), "photo(s) must be specified" )
    local explicit = params.explicitSettings or {}
    local checking = app:callingTypeAssert( params.checkExplicitSettings, "checkExplicitSettings", 'boolean' )
    local checked = {}
    local baseline = params.baselineSettings or {}
    app:callingAssert( tab:is( explicit ) or tab:is( baseline ), "no explicit or baseline settings" )
    local settings = {} -- lotta checking if photo-by-photo exports - consider a re-partitioning ###2
    local function setting( p )
        checked[p.name] = true
        if not checking then
            settings[p.name] = explicit[p.name]
            return
        end        
        local value
        if explicit[p.name] ~= nil then
            value = explicit[p.name]
        else
            value = baseline[p.name]
        end
        if value == nil then
            if p.default ~= nil then -- assume default is acceptable without further ado.
                app:logV( "^1 defaulting to ^2", p.name, p.default )
                settings[p.name] = p.default
                return
            end
        end
        if value == nil then
            if p.required then
                error( p.name.." is required", 4 )
            else
                app:logV( "^1 is unassigned (i.e. remaining nil).", p.name )
                return -- unassigned
            end
        elseif p.loopback then
            local _value = p.loopback[value]
            if _value == nil then
                if p.loopback['_'] then
                    Debug.pause( "Custom value for", p.name, ":", value )
                    app:logV( "Custom value for ^1: ^2", p.name, value )
                    settings[p.name] = value
                    return
                else
                    error( p.name.." - bad value: "..str:to( value ).." - should be one of: "..table.concat( tab:createArray( p.loopback ), ", " ), 4 )
                end
            else
                app:assert( _value == value, "bad loopback table for ^1", p.name )
                settings[p.name] = value
                return
            end
        else
            local typ = p.type or type( p.default ) or app:callingError( "need loopback, default, or type for ^1", p.name )
            if type( value ) == typ then
                if typ == 'string' then -- assumption: if require parameter is string, then empty is not a legal value.
                    if #value == 0 then
                        error( p.name.." - empty string.", 4 )
                    end
                elseif typ == 'number' then
                    if p.constraints then
                        if value < p.constraints.min then
                            error( p.name.." too small", 4 )
                        elseif value > p.constraints.max then
                            error( p.name.." too big", 4 )
                        -- else just right..
                        end
                    -- else no constraints
                    end
                -- else probably boolean (table settings exist?), anyway: definitely no function settings.
                end
                settings[p.name] = value
                return
            else
                error( p.name.." - bad type: "..type( value ), 4 )
            -- else type ok
            end
        end
    end
    
    -- reminders: need name and loopback, default, or type; optional: required. if number, recommend constraints.
    setting{ name='LR_format', required=true, loopback=exportFormats } -- no need for type if loopback is supplied.
    setting{ name='LR_export_bitDepth', required=( settings.LR_format == 'TIFF' or settings.LR_format == 'PSD' ), type='number', constraints={ min=8, max=16 } } -- no default.
    setting{ name='LR_jpeg_quality', required=( settings.LR_format == 'JPEG' ), type='number', constraints=jpegQualityConstraints } -- no default.
    -- fall-through => legal format.
    
    setting{ name='LR_export_colorSpace', required=true, loopback=colorSpaces } -- custom colorspaces allowed, but log message & debug if such is the case.

    setting{ name='LR_collisionHandling', required=true, loopback=collisionHandling } -- no need for type if loopback is supplied.
    setting{ name='LR_embeddedMetadataOption', required=true, loopback=metadataLoopback } -- no need for type if loopback is supplied.
    if settings.LR_embeddedMetadataOption == 'copyrightOnly' then
	    settings.LR_minimizeEmbeddedMetadata = true -- Lr3-
	end
    
    setting{ name='LR_export_useSubfolder', default=false } -- reminder, if nil this will be treated as true (and Lr will scare up a suffix even if not supplied!).
    setting{ name='LR_export_destinationPathSuffix', required=settings.LR_export_useSubfolder, type='string' }
    setting{ name='LR_useWatermark', default = false }
    setting{ name='LR_watermarking_id', required=settings.LR_useWatermark, default=( settings.LR_useWatermark and '<simpleCopyrightWatermark>' ) or nil } -- "<simpleCopyrightWatermark>" or UUID.

    setting{ name='LR_metadata_keywordOptions', default='flat' }
    setting{ name='LR_removeLocationMetadata', default=true }

    setting{ name='LR_size_doConstrain', default=false }
    setting{ name='LR_size_resizeType', required=settings.LR_size_doConstrain, loopback=resizeTypes }
    setting{ name='LR_size_maxHeight', required=settings.LR_size_doConstrain and settings.LR_size_resizeType ~= 'megapixels', type='number', constraints=maxDimConstraints }
    setting{ name='LR_size_maxWidth', required=settings.LR_size_doConstrain and settings.LR_size_resizeType == 'wh' or settings.LR_size_resizeType == 'dimensions', type='number', constraints=maxDimConstraints } -- If long/short-edge, the height field is used and width ignored.
    setting{ name='LR_size_megapixels', required=settings.LR_size_doConstrain and settings.LR_size_resizeType == 'megapixels', type='number', constraints=megapixelsConstraints }
    
    setting{ name='LR_size_doNotEnlarge', default=true } -- default is to shrink, but not enlarge. If not what you want, then remember to pass false.
    setting{ name='LR_extensionCase', default='lowercase', loopback=caseLoopback } -- not required, but if passed, should be a recognized value.
    setting{ name='LR_reimportExportedPhoto', default=false } -- default to non-reimporting, if not set.

    setting{ name='LR_renamingTokensOn', required=true, type='boolean' } -- whether renaming or not, should always be specified
    setting{ name='LR_tokens', required=settings.LR_renamingTokensOn, type='string' } -- note: for explicit filenaming, set lr-tokens to {{custom_token}}
    setting{ name='LR_tokenCustomString', required=settings.LR_renamingTokensOn and settings.LR_tokens:find("{custom_token}"), type='string' } -- Note: may be theoretically possible to have token-custom-string be nil or "", but rarely if ever on purpose. ###3
    setting{ name='LR_tokensArchivedToString2', default=settings.LR_tokens } -- Not sure this does anything, but I don't think it hurts to have it match the "unarchived" tokens. ###2 string?
    
    setting{ name='LR_export_destinationType', required=true, loopback=destinationLoopback }
    setting{ name='LR_export_destinationPathPrefix', required=settings.LR_exportDestinationType=='specificFolder', type='string' } -- prefix is folder.
    setting{ name='LR_export_destinationPathSuffix', required=settings.LR_exportDestinationType=='specificFolder' and settings.LR_export_useSubfolder, type='string' } -- suffix is subfolder.

    -- this checking is done regardless.
    for k, v in pairs( explicit ) do
        if not checked[k] then
            app:callingError( "What's this: ^1", k )
        end
    end    
    
    if params.baselineSettings then
        Object.inherit( settings, baseline ) -- sorta wonkily putting horse behind the cart, but works... (copies members from baseline which aren't already represented in settings).
    end

    -- beware: not assuring-dir (documented in func hdr).
    -- Debug.lognpp( settings )
    -- Debug.showLogFile()

    local session = LrExportSession {
        photosToExport = photos,
        exportSettings = settings,
    }
    
    -- *** uncomment these lines to enable custom export functionality:
    local s, m = LrTasks.pcall( session.doExportOnCurrentTask, session ) -- perform export synchronously (without spawning another asynchronous task).
    return s, m

end



--- get export settings from an export preset file.
--
--  @usage 
--
--  @param params (table) members:
--      <br>    file        as of 2/Jun/2014, file can be relative, just beware: it needs to include subfolder, e.g. "User Presets/My Preset.lrtemplate"
--      <br>                or of course, just specify absolutely like before..
--
--  @return export settings, or throws error trying.
--
function Export:getSettingsFromPreset( params )
    app:callingAssert( type( params ) == 'table', "params must be table" )
    local file = params.file or app:callingError( "no file specified in params" )
    local ext = LrPathUtils.extension( file )
    if not ext == "lrtemplate" then
        app:error( "not an export preset (doesn't end with .lrtemplate): ^1", file )
    end
    if LrPathUtils.isRelative( file ) then
        -- app:error( "file must be absolute path, '^1' isn't.", file ) - until 2/Jun/2014 3:12
        local dir, err = lightroom:getPresetDir( 'Export Presets' )
        if dir then
            file = LrPathUtils.child( dir, file )
        else
            app:error( err )
        end
    end
    if not fso:existsAsFile( file ) then
        app:error( "preset not found: ^1", file )
    end
    pcall( dofile, file )
    app:assert( _G.s ~= nil, "bad preset: ^1", file )
    local exportServiceProvider = _G.s.value["exportServiceProvider"]
    local exportServiceProviderTitle = _G.s.value["exportServiceProviderTitle"]
    local pluginId = _G.s.value["exportServiceProvider"] -- synonym
    local pluginName = _G.s.value["exportServiceProviderTitle"] -- ditto.
    local _exportSettings = {}
    local prefixLen = string.len( exportServiceProvider ) + 2 -- compute amount to skip over in user keys.
    for k, value in pairs(_G.s.value) do
        local is = str:isStartingWith( k, exportServiceProvider ) --       ###1 25/Apr/2014 2:38 - do I really want regex here?
        if is then -- its an service specific setting (e.g. log-file).
            local key = string.sub( k, prefixLen ) -- remove the extraneous user key prefix.
            _exportSettings[key] = value
            -- app:logV( "Saving User setting, name: ^1, value: ^2", key, str:to( value ) )
        elseif k == 'exportFilters' then
            if not tab:isEmpty( value ) then
                app:error( "Export filters (post-process actions) are not supported, as in '^1'", file ) -- I suppose they could simply be ignored, but it seems one should be picking a preset without filters..
            else
                -- ignore (all export filters were removed).
            end
        else
            local key = 'LR_' .. k -- add the required lightroom key prefix.
            -- app:logV( "Saving Lightroom setting, name: ^1, value: ^2", key, str:to( value ) )
            _exportSettings[key] = value
        end
    end
    return _exportSettings
end



--- Get export destination directory
--
--  @usage      consider disallowing "Choose Later" option if you are planning to use this function as is - it will prompt for the folder, but so will Lightroom making for an obnoxious double-prompt: probably not what you want.
--
--  @param      props       export settings
--  @param      photo       photo under consideration.
--  @param      cache       metadata cache, which needs 'path', at least, to be useful.
--
--  @return     string      throws error if problem.
--
function Export:getDestDir( props, photo, cache )
    if props == nil then
        app:callingError( "need export params" )
    end
    local typ = props.LR_export_destinationType
    local mainDir = props.LR_export_destinationPathPrefix -- path
    local subDir = props.LR_export_destinationPathSuffix -- name
    local useSub = props.LR_export_useSubfolder 
    if typ == 'specificFolder' then
        if useSub then
            return LrPathUtils.child( mainDir, subDir )
        else
            return mainDir
        end
    elseif typ == 'sourceFolder' then
        local srcDir = LrPathUtils.parent( lrMeta:getRaw( photo, 'path', cache ) )
        if useSub then
            return LrPathUtils.child( srcDir, subDir )
        else
            return srcDir
        end
    elseif typ == 'chooseFolderLater' then
        if self.destDirChosen then
            return self.destDirChosen
        else
            self.destDirChosen = dia:selectFolder{
                title = "Choose export destination folder",
                canCreateDirectories = true,
            }
            if self.destDirChosen == nil then
                app:error( "Unable to obtain export directory." )
            end
            return self.destDirChosen
        end
    else
        app:error( "Unable to compute destination dir when 'Export To' is set to '^1'", typ )
    end
end



--- Get export destination extension - with correct case.
--
--  @usage consider disallowing "Choose Later" option if you are planning to use this function as is - it will prompt for the folder, but so will Lightroom making for an obnoxious double-prompt: probably not what you want.
--
--  @param      props       export settings
--  @param      photo       photo under consideration.
--  @param      cache       metadata cache, which needs 'path' & 'fileFormat', at least, to be useful.
--
--  @return     string      throws error if problem.
--
function Export:getDestExt( props, photo, cache )
    if props == nil then
        app:callingError( "need export params" )
    end
    local fmt = lrMeta:getRaw( photo, 'fileFormat', cache )
    local ext
    if props.LR_format == 'ORIGINAL' then
        ext = LrPathUtils.extension( lrMeta:getRaw( photo, 'path', cache ) )
    elseif fmt == 'VIDEO' then
        if app:lrVersion() >= 4 then
            --Debug.pause( props.LR_export_videoFormat, props.LR_export_videoPreset )
            if props.LR_export_videoFormat == 'original' or props.LR_export_videoPreset == 'original' then -- I think it's just the format, not the preset, which will be 'original', but hey...
                ext = LrPathUtils.extension( lrMeta:getRaw( photo, 'path', cache ) )
            elseif props.LR_export_videoFormat ==  "3f3f3f3f-4450-5820-fbfb-fbfbfbfbfbfb" then -- ###2 not sure if this will be the same in all Lr copies, so better to check using some other means if possible.
                app:error( "dpx video exports to a directory, not a file, therefore file extension does not make sense." )
            else
                for i, vp in ipairs( LrExportSettings.videoExportPresets() ) do
                    local name = LrStringUtils.lower( vp:name() )
                    if props.LR_export_videoPreset:find( name, 1, true ) then -- e.g. "SIZE_max" 
                        ext = vp:extension()
                        break
                    end
                end
                if not ext then -- not present in standard presets
                    -- try custom presets for this plugin.
                    for i, vp in ipairs( LrExportSettings.videoExportPresetsForPlugin( _PLUGIN ) ) do
                        --local name = LrStringUtils.lower( vp:name() )
                        --if props.LR_export_videoPreset:find( name, 1, true ) then -- e.g. "SIZE_max" 
                            ext = vp:extension()
                            if ext then
                                break
                            end
                        --end
                    end
                end
                if not ext then
                    app:error( "Unable to determine destination video extension from video-preset code: ^1", props.LR_export_videoPreset )
                end
            end
        else
            ext = LrPathUtils.extension( photo:getRawMetadata( 'path' ) )
        end
    elseif str:is( props.LR_format ) then
        ext = LrExportSettings.extensionForFormat( props.LR_format ) -- seems to be lower case regardless of case setting, at least when "rename" is disabled,
        if not ext then
            app:error( "Unable to compute destination extension for format: ^1", props.LR_format )
        end
    else
        app:error( "No lr-format in props" )
    end
    if props.LR_extensionCase == 'lowercase' then
        ext = LrStringUtils.lower( ext )
    else
        ext = LrStringUtils.upper( ext )
    end
    return ext
end



-- private/protected method to determine if sequence number is present in specified tokens (string).
--
function Export:_isSeqNum( tokens )
    if tokens:find( "sequenceNumber" ) then -- example: {{naming_sequenceNumber_1Digit}}.
        return true
    end
end



--- Process change to export-to export param - for cases when export location may have some restrictions.
--
--  @param      props       export settings
--  @param      name        name of property causing change.
--  @param      value       changed property value.
--
--  @usage      nothing is returned - properties may be adjusted..
--
function Export:processExportLocationChange( props, name, value )
    local checkSubfolder
    if name == 'LR_export_useSubfolder' then
        checkSubfolder = value and props.LR_export_destinationPathSuffix
    elseif name == 'LR_export_destinationPathPrefix' then
        Debug.pause( "No handling in base class for path prefix" )
    elseif name == 'LR_export_destinationPathSuffix' then
        checkSubfolder = value
    elseif name == 'LR_destinationType' then
        if value == 'chooseFolderLater' then
            app:show{ 'Export location can not be chosen later - please choose another option.' }
            props.LR_export_destinationType = 'specificFolder'
        else
            Debug.pause( "No handling in base class for normal destination types." )
        end
    else
        Debug.pause( "Unrecognized property name - ignored", name, value )
        return
    end
    if checkSubfolder then
        Debug.pause( "No handling in base class for subfolder" )
    else
        Debug.pause( "Not checking subfolder" )
    end
end



-- private/protected method to get a filenaming preset based on tokens
--
function Export:_getVerifiedPreset( tokens )
    local presets = self.filenamePresetLookup[tokens]
    if presets then
        for i, p in ipairs( presets ) do
            if p.verified then
                return p
            end
        end
    end
end




--- Process change to export-filenaming property - for cases when export filenaming may have some restrictions.
--
function Export:processExportFilenamingChange( props, name, value )
    self.filenamePreset = nil -- assume nothing about chosen preset
    local photo = cat:getAnyPhoto() -- prefers most-sel, but accepts filmstrip[1] or all[1].
    if photo == nil then
        app:show{ warning="You must have at least one photo in catalog to assure filenaming is copacetic", actionPrefKey="Filenaming pre-check" }
        return
    end
    self:_assurePresetCache( props, photo ) --  true ) -- true => freshen for each change, since preset could be added - UPDATE: added presets don't work anyway, so may as well handled as non-existent.
    local checkTokens
    if name == 'LR_renamingTokensOn' then
        checkTokens = value and props.LR_tokens
    elseif name == 'LR_tokens' then
        checkTokens = value
    elseif name == 'LR_extensionCase' then
        --Debug.pause( "No handling in base class for extension case change." )
    elseif name == 'LR_tokenCustomString' then
        --Debug.pause( "No handling in base class for custom text change." )
    elseif name == 'LR_initialSequenceNumber' then
        --Debug.pause( "No handling in base class for start number change." )
    else
        --Debug.pause( "Unrecognized property name - ignored", name, value )
        return
    end
    if checkTokens then
        local filenamePreset = self:_getVerifiedPreset( checkTokens ) -- note: not a true preset object, but a reference to some harvested info...
        if filenamePreset then
            if self:_isSeqNum( filenamePreset.tokenString ) then
                --Debug.pause( "No handling in base classe for filenaming presets with sequence number." )
            end
            assert( checkTokens == filenamePreset.tokenString, "token mismatch" )
            --Debug.pause( checkTokens )
            local s, t = LrTasks.pcall( self.getDestBaseName, self, props, photo, nil ) -- nil => no cache.
            if s then
                --Debug.pause( t )
                app:logv( "Example file base-name: ^1", t )
            else
                app:show{ warning="There are some issues with the chosen filenaming preset - ^1", t }
            end
        else
            --Debug.pause( checkTokens )
            app:show{ warning="You may need to save filenaming preset and/or restart Lightroom to use the chosen filenaming scheme." }
            return
        end
    else
        -- Debug.pause( "not checking tokens" )
    end
end



-- private/protected method to assure preset cache is populated.
--
function Export:_assurePresetCache( props, photo )
    if self.filenamePresetCache == nil then
        local cust
        local seq
        if str:is( props['LR_tokenCustomString'] ) then
            cust = props.LR_tokenCustomString
        else
            cust = "custom-text"
        end
        if props['LR_initialSequenceNumber'] then
            seq = props.LR_initialSequenceNumber
        else
            seq = ""
        end
        self.filenamePresetCache = {}
        self.filenamePresetLookup = {}
        
        -- pre 13/Apr/2014 2:57
        --local dir = LrPathUtils.getStandardFilePath( 'appData' )
        --local fdir = LrPathUtils.child( dir, 'Filename Templates' )
        -- post 13/Apr/2014 2:57 ###1 not fully tested / released.
        local fdir, err = lightroom:getPresetDir( 'Filename Templates' )
        if fdir then
            dbgf( "preset dir: ^1", fdir )
        else
            Debug.pause( "no filename templates dir" )
            app:logErr( "Unable to obtain reference to filename templates folder - ^1", err or "no more info" )
            return
        end
        
        gbl:initVar( "ZSTR", LOC, true )
        for de in LrFileUtils.files( fdir ) do -- I assume lightroom will not find templates in subfolders - certainly you can't put them there using native UI.
            repeat
                if LrPathUtils.extension( de ) ~= 'lrtemplate' then
                    break
                end
                local name = LrPathUtils.removeExtension( LrPathUtils.leafName( de ) )
                local sts, ret = pcall( dofile, de ) -- global 's'.
                if not sts then
                    app:logErr( "Invalid filename template file: ^1 - ret: ^2", de, ret )
                    break
                end
                if not s or not s.deflated then
                    app:logErr( "Invalid filename template file: ^1", de )
                    break
                end
                if not s.deflated[1] then
                    app:logWarning( "No tokens in: ^1", de )
                    break
                end
                if not s.id then
                    --[[ until 4/Jul/2014 16:26:
                    if name ~= 'Filename' then
                        app:logv( "no id for filename preset '^1'", name ) -- not sure why this is happening now, but can't use it without an ID.
                        -- break - 
                        
                    else
                        s.id = '__filename__' -- pseudo ID
                    end
                    --]]
                    app:logv( "no id for filename preset '^1' - using path instead as ID.", name ) -- not sure why this is happening now, but can't use it without an ID.
                    s.id = de -- id can be path if no true ID.
                end
                local tokens = {}
                for i, v in ipairs( s.deflated[1] ) do
                    local token
                    if type( v ) == 'table' then
                        if v.value ~= nil then
                            tokens[#tokens + 1] = "{{" .. v.value .. "}}"
                        else
                            --Debug.pause( v )
                        end
                    else
                        tokens[#tokens + 1] = v
                    end
                end
                if #tokens > 0 then
                    --Debug.pause( name )
                    local tokenString = table.concat( tokens, "" )
                    self.filenamePresetCache[name] = { tokenString = tokenString, path=de, id=s.id, name=name }
                    app:logv( "Adding preset to cache, name=^1, for tokens=^2", name, tokenString )
                    if not self.filenamePresetLookup[tokenString] then
                        self.filenamePresetLookup[tokenString] = { self.filenamePresetCache[name] } -- there can be more than one.
                    else
                        local a = self.filenamePresetLookup[tokenString]
                        a[#a + 1] = self.filenamePresetCache[name]
                    end
                else
                    --Debug.pause( s )
                end
            until true
        end
        
        if not photo then
            photo = cat:getAnyPhoto()
            if not photo then
                app:logWarning( "Unable to validate presets in cache since there are no photos in the catalog to use for trial." )
                -- note: no presets will be verified.
                return
            end
        end
        for name, id in pairs( LrApplication.filenamePresets() ) do
            repeat
                if not id then
                    app:logW( "no id for filename preset '^1' - skipped", name ) -- I don't think this should ever happen(?)
                    break
                end
                if not self.filenamePresetCache[name] then
                    app:logv( "not cached - skipped" )
                    break
                end
                local sts, filename = LrTasks.pcall( photo.getNameViaPreset, photo, id, cust, seq )
                if sts then -- note: filename = "nil" if say 'Headline Only' and headline field is nil.
                    app:logV( "Filename preset verified: ^1, ^2 (sample filename: ^3)", name, id, filename )
                    self.filenamePresetCache[name].verified = true
                    if self.filenamePresetCache[name].id ~= id then
                        app:logV( "Internal uuid or path (^1) being replaced by filename-preset ID: ^2", self.filenamePresetCache[name].id, id )
                        self.filenamePresetCache[name].id = id -- use true ID from filename-preset, rather than internal uuid.
                    end
                else
                    -- this extra try with cached ID added 14/Nov/2014 - fixes problem with erroneous "unable to verify filename preset" errors.
                    local uuid = self.filenamePresetCache[name].id
                    local sts, filename = LrTasks.pcall( photo.getNameViaPreset, photo, uuid, cust, seq )
                    if sts then
                        self.filenamePresetCache[name].verified = true
                        app:logV( "Filename preset verified, not with filename-preset ID (^1), but internal uuid (^2) - good 'nuff.. (sample filename: ^3)", id, uuid, filename )
                    else
                        app:logV( "*** Unable to verify filename preset (^4): ^1, ^2 - tokens: ^3", name, id, self.filenamePresetCache[name].tokenString, filename )
                        self.filenamePresetCache[name].verified = false
                    end
                end
                --if filename == "custom-text" then - custom-name only is actually a perfectly valid naming preset in some cases.
                --    app:logv( '    - "^1" preset may be not worth having, in any case consider entering something more interesting for custom text.', name )
                --end
            until true
        end
        
    else
        --Debug.pause()
    end
end




--- Get export destination filename (without extension).
--
--  @param      props       export settings
--  @param      photo       lr-photo under consideration
--  @param      cache       metadata cache, which must contain 'path' at least, to be useful. 
--
function Export:getDestBaseName( props, photo, cache )
    if props == nil then
        app:callingError( "need export params" )
    end
    local srcBase = LrPathUtils.removeExtension( LrPathUtils.leafName( lrMeta:getRaw( photo, 'path', cache ) ) )
    local basename
    if not props.LR_renamingTokensOn then -- universal:
        basename = srcBase
    else -- rename
        self:_assurePresetCache( props, photo )
        if not self.filenamePreset then
            self.filenamePreset = self:_getVerifiedPreset( props.LR_tokens )
            if not self.filenamePreset then
                --Debug.logn( "tokens", props.LR_tokens )
                --Debug.lognpp( "lookup", self.filenamePresetLookup ) -- ###1
                --Debug.pause( "View debug log file - tokens and lookup" )
                app:error( "You must restart Lightroom in order to use selected filenaming preset - tokens: ^1", props.LR_tokens )
            end
        else
            --Debug.pause( self.filenamePreset.name )
        end
        if self.filenamePreset then
            --Debug.lognpp( props )
            --Debug.showLogFile()
            local s
            if self.seqNum == nil then
                self.seqNum = props.LR_initialSequenceNumber or 1
            else
                self.seqNum = self.seqNum + 1
            end
            if not self.filenamePreset.id then
                app:error( "how's there a preset with no ID? named '^1'", self.filenamePreset.name )
            end
            s, basename = LrTasks.pcall( photo.getNameViaPreset, photo, self.filenamePreset.id, props.LR_tokenCustomString or "", self.seqNum )
            if s then
                if basename then
                    if #basename > 0 then
                        --Debug.pauseIf( basename == "nil" )
                        --Debug.pause( self.filenamePreset['name'], self.filenamePreset.tokenString )
                        app:logv( "File base-name based on preset (^2) : ^1 (tokens in preset=^3)", basename, self.filenamePreset.name, self.filenamePreset.tokenString )
                    else
                        app:error( "Invalid file base-name (^1) from preset - must be at least 1 characters, preset name: ^2, tokens in preset: ^3", basename, self.filenamePreset.name, self.filenamePreset.tokenString )
                    end
                else
                    app:error( "Unable to obtain filename from preset." )
                end
            else
                --Debug.pause( self.filenamePreset.name )
                app:error( "Unable to get filename via preset - id: ^1, error message: ^2", self.filenamePreset.id, basename )
            end
        else
            app:error( "Unable to obtain preset for filenaming - you must use a saved preset for filenaming, custom/unsaved won't cut it - also you may have to restart Lightroom if it's a newly created preset." )
        end
    end
    assert( basename ~= nil, "no file basename" )
    return basename
end



--- Get export destination filename, with extension.
--
--  @param      props       export settings
--  @param      photo       lr-photo under consideration
--  @param      cache       metadata cache, which must contain 'path' at least, to be useful. 
--
function Export:getDestFilename( props, photo, cache )

    if props == nil then
        app:callingError( "need export params" )
    end
    local basename = self:getDestBaseName( props, photo, cache )
    local ext = self:getDestExt( props, photo, cache ) -- requires special handling for original formats.
    assert( ext ~= nil, "no ext" )
    assert( basename ~= nil, "no file basename" )
    return LrPathUtils.addExtension( basename, ext )
end



--- Get export destination path for photo.
--
--  @param      props       export settings
--  @param      photo       lr-photo under consideration
--  @param      cache       metadata cache, which must contain 'path' at least, to be useful. 
--
function Export:getDestPath( props, photo, cache )
    if props == nil then
        app:callingError( "need export params" )
    end
    
    -- local dir = self:getDestDir( photo, cache ) -- this till 28/Aug/2013 0:25 which is wrong ###4 - but, it seems no plugin was calling it, so if no problems come 2015, delete this comment.
    local dir = self:getDestDir( props, photo, cache ) -- this @28/Aug/2013 0:26
    
    local filename = self:getDestFilename( props, photo, cache )
    assert( dir ~= nil, "no dir" )
    assert( filename ~= nil, "no filename" )
    local path = LrPathUtils.child( dir, filename )
    return path
end



--- Method version of like-named static function.
--      
--  @usage      This base class implementation simply calls the export service method wrapped in an app call.
--  @usage      Derived export class can certainly override this method, but consider overriding the service & finale methods instead.
--  @usage      Called immediately after process-rendered-photos static "boot-strap" function.
--
function Export:processRenderedPhotosMethod()

    dbg( "Export class: ", str:to( self ) )

    self.srvc = Service:new{
         name = app:getAppName() .. ' export',
         object = self,
         main = self.service,
         finale = self.finale,
    }
    
    app:call( self.srvc )

end



--- Perform export service wrap-up.
--
--  @usage    Override this method in derived class to log stats...
--  @usage    *** IMPORTANT: This method is critical to export integrity.
--            Derived export class must remember to call it at end of special
--            export finale method.
--
--  @param      service     call object
--  @param      status      same as service.status
--  @param      message     same as service.message
--
function Export:finale( call, status, message )
    -- assert( self == Export.exports[self.exportContext], "whoami?" )
    -- app:logInfo( str:format( "^1 finale, ^2 rendered.", name, str:plural( self.nPhotosRendered, "photo" ) ) )
    if status then
        app:log( "^1 finished.", call.name ) -- log added 9/Dec/2011. ###2 - not sure if this is kosher here.
        intercom:broadcast{ exportState = 'finished', exportMessage = call.name .. " completed successfully."  } -- default lifetime of 10 seconds should be fine.
    else
        --app:logErr( "^1 terminated due to error - ^2", service.name, str:to( message ) ) - results in a duplicate, since service class itself logs a service error.
        intercom:broadcast{ exportState = 'finished', exportMessage = call.name .. " terminated due to error."  } -- default lifetime of 10 seconds should be fine.
    end    
    Export.exports[self.exportContext] = nil -- *** kill self reference, garbage collection runs later... this is not the cause of ftp reliability problems.
end



-- Determine if export is finished.
--
--[[
function Export:isFinished()
    if self.exportContext then
        if Export.exports[self.exportContext] then
            return false
        end
    end
    return true
end
--]]


--- Called when export is initiated.
--
--  @usage This method helps export manager track managed exports (all exports based on this class are managed).
--
function Export:initiate( call )
    -- fprops:setPropertyForPlugin( _PLUGIN, "exportState", 'running' ) -- pre 2012.
    -- fprops:setPropertyForPlugin( _PLUGIN, "exportMessage", service.name .. ' in progress' ) -- ditto.
    fprops:setPropertyForPlugin( _PLUGIN, "exportState", nil ) -- kill this property for future.
    fprops:setPropertyForPlugin( _PLUGIN, "exportMessage", nil ) -- kill this property for future.
    Debug.logn( "export in progress" )
    intercom:broadcast{ exportState = 'running', exportMessage = call.name .. " in progress"  } -- default lifetime of 10 seconds should be fine.
end



--[[ this needs more thought - problems with managed exports could cause unmanaged exports not to run - not cool.
-- note: can be very time consuming if exporting thousands of photos and not much inherent delay,
-- maybe best to tie to yield counter or something in that case.
-- note: checks for user cancelation via progress scope as well as managed cancelation via export-manager.
function Export:isCanceled()
    if self.srvc.scope and self.srvc.scope:isCanceled() then
        return true
    end
    local exportCanceled = fprops:getPropertyForPlugin( 'com.robcole.lightroom.export.ExportManager', 'exportCanceled', true ) -- re-reading nearly always required when reading a propterty to be set by a different plugin.
    if exportCanceled == nil then
        if self.notManaged == nil then
            self.notManaged = true
            app:logInfo( "Export appears not to be executing in managed environment." )
        end
        return false
    end
    if exportCanceled == 'yes' then
        return true
    elseif exportCanceled == 'no' then
        return false
    else
        app:logError( "bad cancel property value: " .. str:to( exportCanceled ) )
        return false
    end
    -- save for pausterity I guess:
    --app:logInfo( "Export paused." )
    --while exportEnabled == 'no' and not shutdown do
    --    LrTasks.sleep( 1 )
    --    exportEnabled = fprops:getPropertyForPlugin( 'com.robcole.lightroom.export.ExportManager', 'exportEnabled', true ) -- re-reading nearly always required when reading a propterty to be set by a different plugin.
    --end
    --app:logInfo( "Export resuming from pause." )
    --return true -- did pause
end
--]]



--- Service function of base export - processes renditions.
--      
--  <p>You can override this method in its entirety, OR just:</p>
--     <ul> 
--       <li>checkBeforeRendering
--       <li>processRenderedPhoto
--       <li>processRenderingFailure
--       <li>(and finale maybe)
--    </ul>
--
--  @usage  Just inits some stuff, logs some stuff, configures progress scope, and loops through renditions, calling rendered processing functions (photo or failure), depending on status.
--      <br>*** also checks that exported photo exists on disk at specified location, if successful. If you do NOT want this behavior, then override this function.

function Export:service( call )

    if app:isAdvDbgEna() then
        app:logV( "Export Params:")
        app:logPropertyTable( self.exportParams ) -- no-op unless advanced debugging is enabled, then logs verbosely.
        app:logV()
    end

    self.nPhotosToExport = self.exportSession:countRenditions()
    self:checkBeforeRendering() -- remove photos not to be rendered.

    app:logInfo( "Exporting " .. str:plural( self.nPhotosToExport, "selected photo" ) )
    app:logInfo( "Rendering " .. str:plural( self.nPhotosToRender, "exported photo" ) )
    app:logInfo( "Export Format: " .. str:to( self.exportParams.LR_format ) )
    app:logInfo()
    
    local title = app:getAppName() .. " rendering " .. str:plural( self.nPhotosToRender, "photo" )
    self.exportProgress = self.exportContext:configureProgress{ title = title }
    
    -- export seems to be canceled just fine, but export filters keep on going.
    -- so an independent progress-scope must be used for cancelable export filters.
    
    for i, rendition in self.exportContext:renditions{ stopIfCanceled = true, progressScope = self.exportProgress } do
    
        -- self:pauseOrNot() -- make sure you call this in the processing loop(s) if you override the service method.
    
        local status, other = rendition:waitForRender()
        if status then
            local exportPath = other
            -- hard to imagine, but status may be OK despite no rendered file, if source photo is corrupt - check added 19/Oct/2012 9:12.
            if fso:existsAsFile( exportPath ) then
                self:processRenderedPhoto( rendition, exportPath )
            else
                local missing, qualified = cat:isMissing( photo ) -- no cache.
                if missing then
                    if not qualified then -- neither source photo file nor smart preview.
                        self:processRenderingFailure( rendition, str:fmtx( "Lightroom supposedly exported photo successfully, however since neither source file (nor smart preview) exists on disk, such is suspicious..: ^1", rendition.photo:getRawMetadata( 'path' ) ) )
                            -- it's possible this is not a failure, so override method if need be..
                    else -- smart preview is present
                        app:log( "*** ^1 - ^2", rendition.photo:getRawMetadata( 'path' ), qualified ) -- pseudo warning of smart preview being exported: if you don't want this, override method..
                    end
                -- else great (source photo file exists).
                end
            end
        else
            local message = other or "Unable to obtain rendition - perhaps it was skipped" -- shouldn't be nil, but is if rendition skipped. ###2 (may not be looking out for this elsewhere).
            self:processRenderingFailure( rendition, message )
        end
        
    end
    
end



--   E X P O R T   D I A L O G   B O X



--- Handle change to properties under authority of base export class.
--      
--  <p>Presently there are none - but that could change</p>
--
--  @usage        Call from derived class to ensure base property changes are handled.
--
function Export:propertyChangeHandlerMethod( props, name, value )
end



--- Do whatever when dialog box opening.
--      
--  <p>Nuthin to do so far - but that could change.</p>
--
--  @usage        Call from derived class to ensure dialog is initialized according to base class.
--
function Export:startDialogMethod( props )
    dia:clearPromptOnce()
end



--- Do whatever when export dialog box closing, OR a different export service selected.
--      
--  <p>Nuthin yet...</p>
--
--  @usage        Call from derived class to ensure dialog is ended properly according to base class.
--
--  @param      props export settings
--  @param      why - (string) The reason this function was called. One of 'ok', 'cancel', or 'changedServiceProvider'. Note: does NOT apply to export filters (or plugin manager).
--
function Export:endDialogMethod( props, why )
end



--- Standard export sections for top of dialog.
--      
--  <p>Presently seems like a good idea to replicate the plugin manager sections.</p>
--
--  @usage      These sections can be combined with derived class's in their entirety, or strategically...
--
function Export:sectionsForTopOfDialogMethod( vf, props )
    return Manager.sectionsForTopOfDialog( vf, props ) -- instantiates the proper manager object via object-factory.
end



--- Standard export sections for bottom of dialog.
--      
--  <p>Reminder: Lightroom supports named export presets.</p>
--
--  @usage      These sections can be combined with derived class's in their entirety, or strategically - presently there are none.
--
function Export:sectionsForBottomOfDialogMethod( vf, props )
end



--   E X P O R T   S U B - T A S K   M E T H O D S


--- Remove photos not to be rendered, or whatever.
--
function Export:checkBeforeRendering()
    self.nPhotosToRender = self.nPhotosToExport
end



--- Process one rendered photo.
--
function Export:processRenderedPhoto( rendition, exportPath )
    self.nPhotosRendered = self.nPhotosRendered + 1
end



--- Process one photo rendering failure.
--
--  @param      message         error message generated by Lightroom.
--
function Export:processRenderingFailure( rendition, message )
    self.nRendFailures = self.nRendFailures + 1
    app:logE( "Photo rendering failed, photo path: ^1, error message: ^2", rendition.photo:getRawMetadata( 'path' ) or 'nil',  message or 'nil' )
end



--- Cancel export, if possible, by attempting to remove all photos from export session.
--
--  @usage      if I remember correctly, if export already under way, this method will fail by throwing an error.
--
function Export:cancelExport()
    if self.exportSession then
        for photo in self.exportSession:photosToExport() do
            self.exportSession:removePhoto( photo )
        end
        app:log( "Export was canceled." )
    else
        app:logW( "Export could not be canceled." )
    end
end



--- Export parameter change handler proper - static function
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export object.
--
function Export.propertyChangeHandler( id, props, name, value )
    if Export.dialog == nil then
        return
    end
    --assert( Export.dialog ~= nil, "No export dialog to handle change." ) - not sure whether the potential for dialog
    -- box to not be created has disappeared or not, hmmm...... ###3 - hasn't been happening though...
    Export.dialog:propertyChangeHandlerMethod( props, name, value )
end



--- Called when dialog box is opening - static function as required by Lightroom.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export object.
--
function Export.startDialog( props )
    if Export.dialog == nil then
        Export.dialog = objectFactory:newObject( 'ExportDialog' )
    end
    assert( Export.dialog ~= nil, "No export dialog to start." )
    Export.dialog:startDialogMethod( props )
end



--- Called when dialog box is closing.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export object.
--
function Export.endDialog( props, why )
    if Export.dialog == nil then
        return
    end
    assert( Export.dialog ~= nil, "No export dialog to end." )
    Export.dialog:endDialogMethod( props, why )
end



--- Presently, it is imagined to just replicate the manager's top section in the export.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export dialog object.
--
function Export.sectionsForTopOfDialog( vf, props )
    if Export.dialog == nil then
        Export.dialog = objectFactory:newObject( 'ExportDialog' )
    end
    assert( Export.dialog ~= nil, "No export dialog for top sections." )
    return Export.dialog:sectionsForTopOfDialogMethod( vf, props )
end



--- Presently, there are no default sections imagined for the export bottom.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export dialog object.
--
function Export.sectionsForBottomOfDialog( vf, props )
    if Export.dialog == nil then
        Export.dialog = objectFactory:newObject( 'ExportDialog' )
    end
    assert( Export.dialog ~= nil, "No export dialog for bottom sections." )
    return Export.dialog:sectionsForBottomOfDialogMethod( vf, props )
end



--- Called to process render(ing) photos.
--      
--  <p>Photos have not started rendering when this is first called.
--  Once started, they will be rendered in an asynchronous task within Lightroom.
--  Rendering may be started implicitly by invoking the renditions iterator of the export context,
--  or explicitly by calling export-context - start-rendering.</p>
--      
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      1st: creates derived export object via object factory,
--              <br>then calls corresponding method of actual (i.e derived class) export object.
--  @usage      Rendering order is not guaranteed, however experience dictates they are in order.
--
function Export.processRenderedPhotos( functionContext, exportContext )

    if Export.exports[exportContext] ~= nil then
        app:logError( "Export not properly terminated." ) -- this should never happen provided derived class remembers to call base class finale method.
        Export.exports[exportContext] = nil -- terminate improperly...
    end
    Export.exports[exportContext] = objectFactory:newObject( 'Export', { functionContext = functionContext, exportContext = exportContext } )
    Export.exports[exportContext]:processRenderedPhotosMethod()
    
end


-- Note: 'Export' class does not need to explicitly inherit anything.


return Export