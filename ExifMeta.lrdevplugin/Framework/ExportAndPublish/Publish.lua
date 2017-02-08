--[[
        Publish.lua
--]]

local Publish, dbg, dbgf = Export:newClass{ className = 'Publish' }



--Publish.dialog = nil
--Publish.exports = {}



--- Constructor for extending class.
--      
function Publish:newClass( t )
    return Export.newClass( self, t )
end



--- Constructor to create the export object that represents the export dialog box.
--      
--  <p>One of these objects is created when the export dialog box is presented,
--  if it has not already been.</p>
--
function Publish:newDialog( t )
    local o = Export.newDialog( self, t )
    return o
end



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
--  @return      Publish object
--
function Publish:newExport( t )

    local o = Export.newExport( self, t )
    return o
    
end



--- Method version of like-named static function.
--      
--  @usage      Base class implementation simply calls the export service method wrapped in an app call.
--  @usage      Derived export class can certainly override this method, but consider overriding the service & finale methods instead.
--  @usage      Called immediately after process-rendered-photos static "boot-strap" function.
--
function Publish:processRenderedPhotosMethod()
    Export.processRenderedPhotosMethod( self )
end


--- Perform export service wrap-up.
--
--  @usage    Override this method in derived class to log stats...
--  @usage    *** IMPORTANT: This method is critical to export integrity.
--            Derived export class must remember to call it at end of special
--            export finale method.
--
function Publish:finale( service, status, message )
    -- Publish.exports[self.exportContext] = nil -- seems strange killing self reference in mid-method.
    Export.finale( self, service, status, message )
end



--- Service function of base export - processes renditions.
--      
--  <p>You can override this method in its entirety, OR just:</p><ul>
--      
--      <li>checkBeforeRendering
--      <li>processRenderedPhoto
--      <li>processRenderingFailure
--      <li>(and finale maybe)</ul>
--
function Publish:service( service )
    Export.service( self, service )
end



--   E X P O R T   D I A L O G   B O X



--- Handle change to properties under authority of base export class.
--      
--  <p>Presently there are none - but that could change</p>
--
--  @usage        Call from derived class to ensure base property changes are handled.
--
function Publish:propertyChangeHandlerMethod( props, name, value )
    Export.propertyChangeHandlerMethod( self, props, name, value ) -- this was commented out until 1/Mar/2014 12:29, it's a no-op, but for the sake of consistency, I see no need for special handling.
end



--- Do whatever when dialog box opening.
--      
--  <p>Nuthin to do so far - but that could change.</p>
--
--  @usage        Call from derived class to ensure dialog is initialized according to base class.
--
function Publish:startDialogMethod( props )
    Export.startDialogMethod( self, props ) -- instantiates the proper manager object via object-factory.
end



--- Do whatever when dialog box closing.
--      
--  <p>Nuthin yet...</p>
--
--  @usage        Call from derived class to ensure dialog is ended properly according to base class.
--
function Publish:endDialogMethod( props )
    Export.endDialogMethod( self, props )
end



--- Standard export sections for top of dialog.
--      
--  <p>Presently seems like a good idea to replicate the plugin manager sections.</p>
--
--  @usage      These sections can be combined with derived class's in their entirety, or strategically...
--
function Publish:sectionsForTopOfDialogMethod( vf, props )
    -- return Manager.sectionsForTopOfDialog( vf, props ) -- instantiates the proper manager object via object-factory.
    return Export.sectionsForTopOfDialogMethod( self, vf, props ) -- instantiates the proper manager object via object-factory.
end



--- Standard export sections for bottom of dialog.
--      
--  <p>Reminder: Lightroom supports named export presets.</p>
--
--  @usage      These sections can be combined with derived class's in their entirety, or strategically - presently there are none.
--
function Publish:sectionsForBottomOfDialogMethod( vf, props )
    return Export.sectionsForBottomOfDialogMethod( self, vf, props )
end



--   E X P O R T   S U B - T A S K   M E T H O D S


--- Remove photos not to be rendered, or whatever.
--
function Publish:checkBeforeRendering()
    --self.nPhotosToRender = self.nPhotosToPublish
    Export.checkBeforeRendering( self )
end



--- Process one rendered photo.
--
function Publish:processRenderedPhoto( rendition, photoPath )
    --self.nPhotosRendered = self.nPhotosRendered + 1
    Export.processRenderedPhoto( self, rendition, photoPath )
end



--- Process one photo rendering failure.
--
--  @param      message         error message generated by Lightroom.
--
function Publish:processRenderingFailure( rendition, message )
    --self.nRendFailures = self.nRendFailures + 1
    --app:logError( str:fmt( "Photo rendering failed, photo path: ^1, error message: ^2", rendition.photo:getRawMetadata( 'path' ) or 'nil',  message or 'nil' ) )
    Export.processRenderingFailure( self, rendition, message )
end



----------------------------------------------------
--   P U B L I S H   S P E C I F I C   S U P P O R T
----------------------------------------------------



--------------------------------------------------------------------------------
--- Plug-in defined value declares whether this plug-in supports the Lightroom
 -- publish feature. If not present, this plug-in is available in Export only.
 -- When true, this plug-in can be used for both Export and Publish. When 
 -- set to the string "only", the plug-in is visible only in Publish.
	-- @name exportServiceProvider.supportsIncrementalPublish
	-- @class property
Publish.supportsIncrementalPublish = 'only'

--------------------------------------------------------------------------------
--- (string) Plug-in defined value is the filename of the icon to be displayed
 -- for this publish service provider, in the Publish Services panel, the Publish 
 -- Manager dialog, and in the header shown when a published collection is selected.
 -- The icon must be in PNG format and no more than 26 pixels wide or 19 pixels tall.
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name ExtendedPublish.small_icon
	-- @class property
-- Publish.small_icon = 'publish_icon.png' -- uncomment if you want a publish service icon.

--------------------------------------------------------------------------------
--- When set to the string "disable", the "Go to Published Collection" context-menu item
 -- is disabled (dimmed) for this publish service.
 -- <p>First supported in version 3.0 of the Lightroom SDK.</p>
	-- @name ExtendedPublish.titleForGoToPublishedCollection
	-- @class property
Publish.titleForGoToPublishedCollection = "disable"


-- @present the rest is handled in extension class.

Publish:inherit( Export ) -- explicit inheritance required for return tables - Lightroom doesn't go through metatable...



return Publish