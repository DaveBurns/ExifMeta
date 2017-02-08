--[[
        Filename:           Dialog.lua
        
        Synopsis:           Utilities to support building dialog boxes and such.

        Notes:              -
--]]


local Dialog, dbg, dbgf = Object:newClass{ className = 'Dialog' }


local win_env = WIN_ENV
local mac_env = MAC_ENV


-- static constants
Dialog.inputMsg = "$$$/X=^1 is requesting input..."
Dialog.isOkMsg = "$$$/X=^1 is asking if its OK..."
Dialog.confirmMsg = "$$$/X=^1 is asking..."
Dialog.infoMsg = "$$$/X=^1 has something to say..."
Dialog.warningMsg = "$$$/X=^1 is concerned..."
Dialog.errorMsg = "$$$/X=^1 has encountered a problem..."
Dialog.infoType = "info"
Dialog.warningType = "warning"
Dialog.errorType = "critical" -- @2008-02-13: appears same as warning (SDK version 2.0 or 2.2?) - try again after the next version of SDK is released. Maybe only different on Mac.


local buttonShortcuts = {
    ["YesNo"] = { { label="Yes", verb='ok' }, { label="No", verb='cancel' } },
    ["YesNoCancel"] = { { label="Yes", verb='ok' }, { label="No", verb='other' }, { label="Cancel", verb='cancel' } },
    ["OkCancel"] = { { label="OK", verb='ok' }, { label="Cancel", verb='cancel' } },
}



---  Constructor for extending class.
--
function Dialog:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function Dialog:new( t )
    local o = Object.new( self, t )
    o.answers = {}
    return o
end



--- Klugerian function whose impetus was to support log file contents copy-n-paste to email.
--
--  <p>Presents text in a multi-line edit-field with instructions to user to copy to clipboard...</p>
--
function Dialog:putTextOnClipboard( param )

    local button = 'undefined'
    
    local text = param.contents or 'Oops!'
    local dataName = param.dataName or "Log contents"
    
    app:call( Call:new{ name = "text to clipboard", main = function( call )
        local props = LrBinding.makePropertyTable( call.context )
        --props.copied = false
        props.text = text
        local vi = {} -- no bind-to object
        vi[#vi + 1] = vf:edit_field {
            bind_to_object = props,
            value = bind 'text',
            width_in_chars = param.width_in_chars or 80,
            height_in_lines = param.height_in_lines or 27,
            --allow_newlines = true, -- ###1 works!
        }
        local s = {}
        s[#s+1] = "Instructions:"
        s[#s+1] = "1. If ^3 text not already selected (indicated by being all blue), then click anywhere in the text field, then press ^1 to select all text."
        s[#s+1] = "2. Press ^2 to move to clipboard."
        s[#s+1] = "3. Click 'OK'."
        s = table.concat( s, '\n' )
        vi[#vi + 1] = vf:static_text {
            title = param.subtitle or str:fmtx( s, app:getCtrlKeySeq( "A" ), app:getCtrlKeySeq( "X" ), dataName ),
        }
        --[[
        param.accessoryView = vf:checkbox {
            title = 'I have successfully copied the contents to the clipboard, as instructed.',
            bind_to_object = props,
            value = bind( 'copied' ),            
        }
        --]]
        param.title = param.title or "Move (cut) to Clipboard"
        param.contents = vf:column( vi )
        repeat
            button = LrDialogs.presentModalDialog( param )
            if not str:is( props.text ) then
                break -- good to go
            elseif button == 'ok' then
                self:messageWithOptions( "Please revisit the instructions, or click cancel to abort..." )
            else
                break
            end
        until false
    end } )
    
    return button == 'ok'
    -- return button == 'copied'

end



--      Obsolete: just use '< exclude >' to kill the cancel button (this does not work on some (all?) macs anyway.
--
--      Synopsis:           Returns the specified button if found in the dialog box.
--      
--      Notes:              specified by label, e.g. "OK"
--      
--      Returns:            button object or nil
--
--[[ *** save for reference...
function Dialog:_findButton (x, label, visited)
    if visited == nil then visited = {} end

    if type (x) ~= "table" or visited [x] then return nil end
    visited [x] = true
   
    if x._WinClassName == "AgViewWinPushButton" and x.title == label then
        return x
    else
        -- LrDialog s . m essage( x._WinClassName )
    end
           
    for k, v in pairs (x) do
        local result = self:_findButton (v, label, visited)
        if result then return result end
    end
   
    return nil
end
--]]
 
 

--- Presents a modal dialog without an OK button.
--
--  @param          args                same as to lr-dialog -> present-modal-dialog
--  @param          returnAllButtons    true => return first button click, else hold out for 'cancel' button.
--
--  @usage          *** Only suitable if when you don't need form elements to be commited upon dismissal.
--      
--  @return         string: dismissal button - either 'ok' or one of the other buttons passed - never returns 'cancel',
--                  even if cancel button clicked (Mac).
--
function Dialog:presentModalFrame( args, returnAllButtons )
    args.cancelVerb = '< exclude >'
    --[[local snuff = false *** save for future reference
    local okButtonHidden
    if win_env then 
        args.cancelVerb = args.actionVerb or 'OK'
    	LrTasks.startAsyncTask( function()
    	    while not shutdown and not snuff do
    	        okButtonHidden = self:_findButton( args.contents, "OK" ) -- action-verb pre-checked, so the fram dismissal button will be labeled "OK".
    	        if okButtonHidden then
    	            okButtonHidden.enabled = false
    	            okButtonHidden.visible = false
    	            return
    	        else
    	            LrTasks.yield() -- dont sleep or there may be a noticable visual hitch - yielding is a must however.
    	        end
    	    end
    	end )
    end--]]
	local button
    repeat
    	button = LrDialogs.presentModalDialog( args )
        --[[if win_env then *** save for future reference
            snuff = true
    	    if not okButtonHidden then -- ok button was hidden - this is the normal functioning case in Windows.
    	        app:logErr( "Dialog box frame unsettled." )
    	    end
	        if button == 'cancel' then
	            button = 'ok'
	        end
    	end--]]
    	if returnAllButtons then
    	    break
    	elseif button == 'ok' then
    	    break
    	elseif button == 'cancel' then -- Frame-closer 'X' acts like a 'cancel' button.
    	    break
    	else
    	    -- re-present
    	end
    until false
    return button
end



--- Prompt user to enter a string via simple dialog box.
--      
--  @param          params          table with the following elements:<ul>
--                                      <li>title - window frame title
--                                      <li>subtitle - static text banner at top of content.
--                                      <li>init - initial value optional.</ul>
--                                      <li>width_in_chars - edit-field width (in fat characters) - deprecated.
--                                      <li>height_in_lines - edit-field height (in lines) - deprecated. 
--                                      <li>editFieldOptions - specify width & height and whatever - recommended.
--                                  </ul>
--
--  @usage          self-wrapped.
--      
--  @return         string, or nil for cancelled.
--
function Dialog:getSimpleTextInput( params )

    local text, msg

    app:call( Call:new{ name="get simple text input", main=function( call )
    
        local props = LrBinding.makePropertyTable( call.context )
        
        if params.init then
            props['text'] = params.init
        end
        
        -- compute edit field options:
        local mandatory = { bind_to_object=props, value = bind( 'text' ) } -- required in order for it to work.
        local default = { width_in_chars = params.width_in_chars, height_in_lines = params.height_in_lines, fill_horizontal = 1, } -- legacy way of specifying width & height, but no other options..
        local alt = params.editFieldOptions or {} -- new way of specifying whatever options you want - will override old way if attempting both.
        local editFieldOptions = tab:mergeSets( default, alt, mandatory ) -- alt overrides default, but mandatory overrides all.
        
        local args = {}
        args.title = params.title
        local viewItems = {} -- bind-to-object is being explicitly assigned to edit-field, but add here if other items that'll need it.
        viewItems[#viewItems + 1] =
            vf:row {
                vf:static_text {
                    title = params.subtitle,
                },
            }
        viewItems[#viewItems + 1] =
            vf:row {
                vf:edit_field( editFieldOptions ),
            }
        args.contents = vf:view( viewItems )
        local button = LrDialogs.presentModalDialog( args ) -- ###2 prolly should go through standard show method too, like get popup-menu item.
        if button == 'ok' then
            text = props.text
        else
            msg = "Canceled"
        end
            
    end } )
    
    return text, msg
    
end
-- probably would be more consistent if simply named: get-text-input instead, oh well..



--- Prompt user to enter a number via simple dialog box.
--      
--  @param          param           table with the following elements:<ul>
--                                      <li>title - window frame title
--                                      <li>subtitle - static text banner at top of content.</ul>
--
--  @usage          self-wrapped.
--      
--  @return         string, or nil for cancelled.
--
function Dialog:getNumericInput( param )
    local num, msg
    app:call( Call:new{ name="get numeric input", main=function( call )
    
        local props = LrBinding.makePropertyTable( call.context )
    
        local args = {}
        args.title = param.title or "Enter a number..."
        local viewItems = { bind_to_object = props }
        viewItems[#viewItems + 1] =
            vf:row {
                vf:static_text {
                    title = param.subtitle,
                },
            }
        viewItems[#viewItems + 1] =
            vf:spacer {
                height = 10
            }
        viewItems[#viewItems + 1] =
            vf:row {
                vf:edit_field {
                    value = bind( 'text' ),
                    width_in_chars = 10,
                },
            }
        args.contents = vf:view( viewItems )
        
        repeat
            local button = LrDialogs.presentModalDialog( args ) -- ###2
            if button == 'ok' then
                local sts, text = pcall( tonumber, props.text )
                if sts then
                    num = text
                    break
                else
                    self:messageWithOptions( { warning="This is not a number: ^1" }, str:to ( props.text ) )
                end
            else
                num = nil
                msg = "Canceled"
                break
            end
        until false
            
    end } )
    
    return num, msg
    
end



--- Fetch a user selection from a combo-box.
--      
--  @param              param               Table with the following elements:<ul>
--                                              <li>title - goes on window frame
--                                              <li>subtitle - static text banner goes in content at top.
--                                              <li>items - for combo box.</ul> 
--  @usage              self-wrapped.
--  @usage              multiple selection is not supported.
--      
--  @return             string, or nil for cancel.
--
function Dialog:getComboBoxSelection( param )

    local text, msg
    
    app:call( Call:new{ name="get combo-box selection", async = false, main = function( call )
    
        repeat
        
            if tab:isEmpty( param.items ) then
                msg = "No items"
                break
            end
    
            local props = LrBinding.makePropertyTable( call.context )
            
            props.text = param.items[1] -- can be optimized if inadequate.
        
            local args = {}
            args.title = param.title or 'Choose Item'
            local viewItems = { bind_to_object = props }
            viewItems[#viewItems + 1] =
                vf:row {
                    vf:static_text {
                        title = param.subtitle or "Choose an item from the drop-down list",
                        height_in_lines = param.lines or 1
                    },
                }
            viewItems[#viewItems + 1] =
                vf:row {
                    vf:combo_box {
                        value = bind( 'text' ),
                        items = param.items,
                        fill_horizontal = param.fill_horizontal or 1,
                        immediate = true -- added 26/Apr/2014 23:04 - otherwise use popup instead - no point in combo-box unless true text entry also supported, which requires immediate=true.
                    },
                }
            args.contents = vf:view( viewItems )
            local button = LrDialogs.presentModalDialog( args ) -- ###2
            if button == 'ok' then
                text = props.text
            else
                msg = "Canceled"
            end
            
        until true
            
    end } )
    
    return text, msg
    
end



--- Fetch a user selection from a popup-menu.
--      
--  @param              param               Table with the following elements:<ul>
--                                              <li>title - goes on window frame
--                                              <li>subtitle - static text banner goes in content at top.
--                                              <li>items - for popup menu.</ul> 
--  @usage              self-wrapped.
--  @usage              multiple selection is not supported.
--      
--  @return             selected item's value, or nil for cancel.
--  @return             msg - in case of failure.
--
function Dialog:getPopupMenuSelection( param )

    local itemValue, msg, button

    app:call( Call:new{ name="get popup-menu selection", async = false, main = function( call )
    
        repeat
        
            if tab:isEmpty( param.items ) then
                msg = "No items"
                break
            end
    
            local viewOptions = tab:copy( param.viewOptions ) or {}
            local props
            local propName
            if param.props then
                props = param.props
                propName = param.propName or app:callingError( "no prop name" )
                -- init externally if desired.
            else
                props = LrBinding.makePropertyTable( call.context )
                propName = 'itemValue'
                props[propName] = param.items[1].value
            end

            local viewItems = param.viewItems or {}
            local buttons = param.buttons
            viewItems[#viewItems + 1] =
                vf:row {
                    vf:static_text {
                        title = param.subtitle or "Choose an item from the drop-down list",
                        height_in_lines = param.lines or 1
                    },
                }
            viewOptions.bind_to_object = props
            viewOptions.value = bind ( propName )
            viewOptions.items = param.items
            viewOptions.fill_horizontal = param.fill_horizontal or 1
            viewItems[#viewItems + 1] =
                vf:row {
                    vf:popup_menu( viewOptions )
                }
            --[[
            args.contents = vf:view( viewItems )
            local button = LrDialogs.presentModalDialog( args ) -- @3/Jul/2012 1:14, goes through standard show method instead.
            --]]
            button = self:messageWithOptions{ confirm=param.title or "Choose Item", viewItems=viewItems, buttons=buttons, actionPrefKey=param.actionPrefKey }
            if button ~= 'cancel' then
                itemValue = props[propName]
            else
                msg = nil -- no message means cancel, message means error.
            end
            
        until true
            
    end, finale=function( call )
        if not call.status then
            itemValue = nil -- no doubt, already nil, but hey...
            msg = call.message
        end
    end } )

    return itemValue, msg, button
    
end



--- Fetch a user selection from a popup-menu.
--      
--  @param              param               Table with the following elements:<ul>
--                                              <li>title - goes on window frame
--                                              <li>subtitle - static text banner goes in content at top.
--                                              <li>items - for popup menu.</ul> 
--  @usage              self-wrapped.
--  @usage              multiple selection only.
--      
--  @return             selected items as array of item values (empty if no selection but OK button), or nil for cancel.
--  @return             msg - in case of failure.
--
function Dialog:getSimpleListSelections( param )

    local itemValue, msg, button

    app:pcall{ name="get simple-list selections", async = false, main = function( call )
    
        if tab:isEmpty( param.items ) then
            msg = "No items"
            return -- from pcall
        end

        local viewOptions = tab:copy( param.viewOptions ) or {}
        local props
        local propName
        if param.props then
            props = param.props
            propName = param.propName or app:callingError( "no prop name" )
            -- init externally if desired.
        else
            props = LrBinding.makePropertyTable( call.context )
            propName = 'itemValue'
            props[propName] = {} -- equivalent to nil: no selection.
        end

        local viewItems = param.viewItems or {}
        local buttons = param.buttons
        viewItems[#viewItems + 1] =
            vf:row {
                vf:static_text {
                    title = param.subtitle or "Choose an item from the drop-down list",
                    height_in_lines = param.lines or 1
                },
            }
        viewOptions.bind_to_object = props
        viewOptions.value = bind ( propName )
        viewOptions.items = param.items
        viewOptions.allows_multiple_selection = true
        viewOptions.fill_horizontal = param.fill_horizontal or 1
        viewItems[#viewItems + 1] =
            vf:row {
                vf:simple_list( viewOptions )
            }
            
        button = self:messageWithOptions{ confirm=param.title or "Choose Items", viewItems=viewItems, buttons=buttons, actionPrefKey=param.actionPrefKey }
        if button ~= 'cancel' then
            itemValue = props[propName] or {} -- translate nil into empty table if 'OK' button used to dismiss - calling context can loop if not kosher..
        else
            msg = nil -- no message means cancel, message means error.
        end
            
    end, finale=function( call )
        if not call.status then
            itemValue = nil -- no doubt, already nil, but hey...
            msg = call.message
        end
    end }

    return itemValue, msg, button
    
end
-- probably would be more consistent if simply named: get-list-selections instead, oh well..



--- Allows user to select a folder by way of the "open file" dialog box.
--      
--  @param              param       table - same as run-open-panel, except all are optional:<ul>
--                          <li>title
--                          <li>prompt ("OK" button label alternative) - NOT supported.
--                          <li>can-create-directories
--                          <li>file-types (string or array of strings, optional): prefix with '.' for best results.
--                          <li>initial-directory</ul>
--  @param              props       Properties into which folder path will be written.
--  @param              name        Name of property to write.
--      
--  @usage              Folder is written to named property if provided, in which case return value is typically ignored.
--  @usage              Internally wrapped with error handling context for ready use as button action function or the like...
--
--  @return             string: path of folder, else nil if user cancelled.
--
function Dialog:_selectFolder( param, props, name, save )
    local folder
    app:call( Call:new{ name="Select folder", main=function( call )
        local args = {}
        args.title = param.title or "Choose Folder"
        if param.prompt then
            Debug.pause( "prompt parameter not supported by folder chooser" )
        end
        args.canChooseFiles = false
        if param.canCreateDirectories == nil then
            args.canCreateDirectories = false
        else
            args.canCreateDirectories = param.canCreateDirectories
        end
        args.canChooseDirectories = true
        args.allowsMultipleSelection = false
        local dir
        if not param.initialDirectory then
            if props and name and str:is( props[name] ) then
                dir = LrPathUtils.parent( props[name] ) -- if this is wonky, Lightroom handles in a reasonable fashion.
            else
                if win_env then
                    dir = "\\"
                else
                    dir = "/"
                end
            end
        else
            dir = param.initialDirectory
        end
        if str:is( dir ) and fso:existsAsDir( dir ) then
            args.initialDirectory = dir
        else
            args.initialDirectory = nil -- this is an optional parameter, if best hope for initial directory is invalid, let Lightroom deal with it somehow.
        end
        if save then
            if param.requiredFileType == nil then
                args.requiredFileType = "*"
            end
        else
            if param.fileTypes == nil then
                args.fileTypes = "*"
            end
        end
    
        repeat
        
            local folders = nil
            if save then
                Debug.pause( args.initialDirectory )
                local folder = LrDialogs.runSavePanel( args )
                if folder ~= nil then
                    if type( folder ) == 'string' then
                        folders = { folder }
                    elseif type( folder ) == 'table' then
                        app:logWarning( "*** Run save panel should return string." ) -- ###2
                        folders = folder
                    else
                        app:error( "Invalid response from run-save-panel." )
                    end
                --else should mean canceled.
                end
            else
                folders = LrDialogs.runOpenPanel( args )
                if folders ~= nil and type( folders ) == 'string' then -- this shouldn't be happening, but I think there must be a new twist in Lr4, or something. ###2
                    folders = { folders } -- update 6/Jan/2015 - I think it's an array if multiple selections allowed, but a string if only one allowed.
                end
            end
            
            if folders ~= nil and #folders > 0 then
                local _folder = folders[1]
                if _folder == nil then
                    if save then
                        app:error( "Invalid folder argument returned from LrDialogs.runSavePanel" )
                    else
                        app:error( "Invalid folders argument returned from LrDialogs.runOpenPanel" )
                    end
                end
                local isOk = false
                local dotExt = {}
                local fileTypes
                if type( param.fileTypes ) == 'string' then
                    fileTypes = { param.fileTypes }
                else
                    fileTypes = param.fileTypes
                end
                if tab:isArray( fileTypes ) then
                    for i, v in ipairs( fileTypes ) do
                        if not str:isStartingWith( v, ".", 1, true ) then
                            dotExt[#dotExt + 1] = "." .. v
                        else
                            Debug.logn( "*** Warning: may not be OK to pass file-types with dot prefix:", v )
                            dotExt[#dotExt + 1] = v
                        end
                    end
                    local folderDotExt = "." .. LrStringUtils.lower( str:to( LrPathUtils.extension( _folder ) ) )
                    for i, v in ipairs( dotExt ) do
                        local ext = LrStringUtils.lower( v )
                        if ext == folderDotExt then
                            isOk = true
                        end
                    end
                else
                    isOk = true
                end
                if isOk then
                    if props then
                        props[name] = _folder
                    end
                    folder = _folder
                    return
                else
                    app:show{ warning="Folder must end with ^1.", table.concat( dotExt, ", or " ) }
                end
            else
                return
            end
            
        until false
    end } )        
    return folder
end



--- Allows user to select a folder by way of the "open file" dialog box.
--      
--  @param              param       table - same as run-open-panel, except all are optional:<ul>
--                          <li>title
--                          <li>prompt ("OK" button label alternative) - NOT supported.
--                          <li>can-create-directories
--                          <li>file-types (string or array of strings, optional): prefix with '.' for best results.
--                          <li>initial-directory</ul>
--  @param              props       Properties into which folder path will be written.
--  @param              name        Name of property to write.
--      
--  @usage              Folder is written to named property if provided, in which case return value is typically ignored.
--
--  @return             string: path of folder, else nil if user cancelled.
--
function Dialog:selectFolder( param, props, name )
    return self:_selectFolder( param, props, name, false )
end



--- Select package (.lrplugin or .app folder on Mac) - folder on Windows, file on Mac.
--
function Dialog:selectPackage( param, props, name )
    if WIN_ENV then -- in Windows: folders are folders and files are files.
        return self:selectFolder( param, props, name )
    else -- package folders on Mac are files.
        return self:selectFile( param, props, name )
    end
end



--- Allows user to select a folder by way of the "save file" dialog box.
--      
--  @param              param       table - same as run-open-panel, except all are optional:<ul>
--                          <li>title
--                          <li>prompt ("OK" button label alternative) - NOT supported.
--                          <li>can-create-directories
--                          <li>file-types (string or array of strings, optional): prefix with '.' for best results.
--                          <li>initial-directory</ul>
--  @param              props       Properties into which folder path will be written.
--  @param              name        Name of property to write.
--      
--  @usage              Folder is written to named property if provided, in which case return value is typically ignored.
--
--  @return             string: path of folder, else nil if user cancelled.
--
function Dialog:selectSaveFolder( param, props, name )
    return self:_selectFolder( param, props, name, true )
end



--  Allows user to select a file by way of the "open file" dialog box.
--      
--  @param              param       Same as run-open-panel, except all are optional:<ul>
--                          <li>title
--                          <li>prompt ("OK" button label alternative)
--                          <li>fileTypes
--                          <li>initialDirectory</ul>
--  @param              props       Properties into which folder path will be written.
--  @param              name        Name of property to write.
--      
--  @usage              File path is written to named property if provided, in which case return value is typically ignored.
--  @usage              Internally wrapped with error handling context for ready use as button action function or the like...
--
--  @return             string: path of file, else nil if user cancelled.
--
function Dialog:_selectFile( param, props, name, _out )
    local file
    app:call( Call:new{ name="Select file", main=function( call )
        local args = {}
        local dir
        if not param.initialDirectory then
            if props and name and str:is( props[name] ) then
                dir = LrPathUtils.parent( props[name] ) -- if this is wonky, Lightroom handles in a reasonable fashion.
            else
                if win_env then
                    dir = "\\"
                else
                    dir = "/"
                end
            end
        else
            dir = param.initialDirectory
        end
        if str:is( dir ) and fso:existsAsDir( dir ) then
            args.initialDirectory = dir
        else
            args.initialDirectory = nil -- this is an optional parameter, if best hope for initial directory is invalid, let Lightroom deal with it somehow (e.g. use most recent).
        end
        args.title = param.title or "Choose File"
        if win_env then
            args.prompt = param.prompt or "OK" -- ###3 not working on windows @19/Dec/2012 5:58. - maybe only applies to folder selection or someting?
        else
            args.prompt = nil -- ###2 param.prompt or "OK" - dunno if this helps on Mac(/Lion) yet, but its not working as is, so it can't hurt...
        end
        args.canChooseFiles = true
        args.canCreateDirectories = false
        args.canChooseDirectories = false
        args.allowsMultipleSelection = false
        if _out then -- save
            args.requiredFileType = param.requiredFileType or "*"
        else
            args.fileTypes = param.fileTypes or "*"
        end
        
        local files
        if _out then
            files = LrDialogs.runSavePanel( args )
            if files ~= nil then
                if type( files ) == 'string' then
                    files = { files }
                elseif type( files ) == 'table' then
                    app:logWarning( "*** Run save panel should return string." ) -- ###2
                else
                    app:error( "Invalid response from run-save-panel." )
                end
            else
                app:logVerbose( "User canceled run-save-panel." )
            end
        else
            files = LrDialogs.runOpenPanel( args )
            if files ~= nil then
                if type( files ) == 'string' then -- this shouldn't be happening, but I think there must be a new twist in Lr4, at least on Mac. ###2 dunno if this might happen, but the folder case inspired this clause.
                    files = { files }
                elseif type( files ) == 'table' then
                    app:logVerbose( "run-open-panel returned table." )
                else
                    app:logWarning( "Invalid response from run-open-panel." )
                end
            else
                app:logVerbose( "User canceled run-open-panel." )
            end
        end
                
        if files ~= nil and #files > 0 then
            local _file = files[1]
            if _file == nil then
                if save then
                    app:error( "Invalid file argument returned from LrDialogs.runSavePanel" )
                else
                    app:error( "Invalid files argument returned from LrDialogs.runOpenPanel" )
                end
            end
            if props then
                props[name] = _file
            end
            file = _file
            return
        else
            return
        end
    end } )
    return file
end



--- Allows user to select a file by way of the "open file" dialog box.
--      
--  @param              param       Same as run-open-panel, except all are optional:<ul>
--                          <li>title
--                          <li>prompt ("OK" button label alternative)
--                          <li>fileTypes
--                          <li>initialDirectory</ul>
--  @param              props       Properties into which folder path will be written.
--  @param              name        Name of property to write.
--      
--  @usage              File path is written to named property if provided, in which case return value is typically ignored.
--
--  @return             string: path of file, else nil if user cancelled.
--
function Dialog:selectFile( param, props, name )
    return self:_selectFile( param, props, name, false )
end



--- Allows user to select a file by way of the "save file" dialog box.
--      
--  @param              param       Same as run-save-panel, except all are optional:<ul>
--                          <li>title
--                          <li>prompt ("OK" button label alternative)
--                          <li>fileTypes
--                          <li>initialDirectory</ul>
--  @param              props       Properties into which folder path will be written.
--  @param              name        Name of property to write.
--      
--  @usage              File path is written to named property if provided, in which case return value is typically ignored.
--
--  @return             string: path of file, else nil if user cancelled.
--
function Dialog:selectSaveFile( param, props, name )
    return self:_selectFile( param, props, name, true )
end



--- Present quick-tips dialog box.
--      
--  @param              strTbl - table of "paragraph" strings - will be concatenated with double EOL between.
--
--  @usage              Convenience function for presenting a help string with standard title, buttons, and link to web for more info.
--      
function Dialog:quickTips( strTbl, oneEol )
    local helpStr
    if type( strTbl ) == 'table' then
        if oneEol then
            helpStr = table.concat( strTbl, "\n" )
        else
            helpStr = table.concat( strTbl, "\n\n" )
        end
    elseif type( strTbl ) == 'string' then
        helpStr = strTbl
    else
        helpStr = "Sorry - no quick tips."
    end
    local button = self:messageWithOptions( { info=helpStr, buttons={{label="More on the Web",verb='ok'},{label="That's Enough",verb='cancel'}} } )
    if button == 'ok' then
        LrHttp.openUrlInBrowser( app:getPluginUrl() ) -- get-plugin-url returns a proper url for plugin else site home.
    end

end



--- Show information, and remember answer for a while.
--
--  @usage *** deprecated - uses non-standard dialog box. workaround has been simply to store answer in a call var, until end of call..
--
--  @usage          Keyword consolidator uses like function in rc-utils: its the only one using this technique, so this function
--                  is reserved in case kwc is ever ported to elare framework.
--  @usage          How long answer is remembered is governed by the plugin - generally memory lasts for the duration of a service.
--  @usage          Must be used in conjunction with "forget-answer" or there's not much point in it...
--  @usage          Unlike normal Lr memory, remembers "cancel" answer as well.
--
function Dialog:showInfoAndRememberAnswer( msg, memKey, memText, okButton, cancelButton, otherButton )

    local answer

    LrFunctionContext.callWithContext( memKey, function( context )
    
        local props = LrBinding.makePropertyTable( context )
        props.box = false

        local message = LOC( Dialog.confirmMsg, app:getAppName() )
        local info = msg
    
    	if not str:is( memKey ) then
    	    error( "need key to remember answer" )
    	end
    	
        answer = self.answers[memKey]
        if answer then
            return
        end
        
        local viewItems = {} -- no properties on main view.
        viewItems[#viewItems + 1] = vf:static_text{
            title = msg,
        }
        
        local args = {}
        --args.title = "Please answer by clicking button"
        args.title = message
        args.contents = vf:view( viewItems )
        args.accessoryView = vf:row { 
            vf:push_button{
                title = otherButton,
                action = function( button )
                    LrDialogs.stopModalWithResult( button, 'other' )
                end,
            },
            vf:spacer{
                alignment = 'right',
                fill_horizontal = 1,
            },
            vf:checkbox{
                title = memText or "Do same for remainder...",
                bind_to_object = props,
                value = bind( 'box' ),
            },
        }
        args.resizable = true
        args.save_frame = memKey
        args.actionVerb = okButton
        args.cancelVerb = cancelButton
        args.otherVerb = otherButton
    
        answer = LrDialogs.presentModalDialog( args ) -- ###2
        if props.box then
            self.answers[memKey] = answer
        end
        
    end )
    
    return answer
    
end



--[=[ *** these methods are obsolete @13/Jun/2014 21:11 (this version of get-answer has been broken for a long time
          anyway, so they can't possibly have been used by any currently active plugin - probably just left-over from port of rc-common).

-- Forget previously remembered answer.
--
--  usage Call before a loop where you always want user to answer the first time, even if not subsequently.
--
function Dialog:forgetAnswer( memKey )
    self.answers[memKey] = nil
end
-- ********* THIS IS BEING OVERWRITTEN BY FUNCTION BELOW WHICH OPERATES ON APK, WHICH IS NOT THE SAME.
-- I NEED TO MAKE SURE I CHECK PLUGINS USING THIS METHOD BEFORE RE-RELEASING THEM, E.G. KEYWORD CONSOLIDATOR.
--
--  Get answer if rememebered.
--
function Dialog:getAnswer( memKey )
    local answer = self.answers[memKey]
    return answer
end
--  Remember answer.
--
--  usage      Used in case presentation is via custom dialog box.
--
function Dialog:rememberAnswer( memKey, answer )
    self.answers[memKey] = '' .. answer -- remember a copy, since Lr likes to garbage collect properties.
end
--]=]



--- Determine if its OK with the user to do something, or not - aLways prompts.
--
--	<p>For more complex prompts, use confirm box directly.</p>
--
--  @usage buttons are OK/Cancel.
--
--  @param  msg     string message.
--
--  @return boolean true iff is ok.
--
function Dialog:isOk( msg, ... )
    assert( msg ~= nil and type( msg ) == 'string', "dia-is-ok needs msg string" )
    local answer = self:messageWithOptions( { confirm=msg, buttons={{label="OK",verb='ok'}} }, ... )
    return answer == 'ok'
end



--- Determine if its OK with the user to do something, or not - aLways prompts.
--
--	<p>For more complex prompts, use confirm box directly.</p>
--
--  @usage buttons are Yes/No.
--
--  @param  msg     string message.
--
--  @return boolean true iff is ok.
--
function Dialog:isYes( msg, ... )
    assert( msg ~= nil and type( msg ) == 'string', "dia-yes/no needs msg string" )
    local answer = self:messageWithOptions( { confirm=msg, buttons={{label="Yes",verb='ok'},{label="No",verb='cancel'}} }, ... )
    return answer == 'ok'
end



--- Prompt user to continue or not, with option to remember decision.
--
--  @param  msg     string message.
--  @param  id      string key for dismissal option.
--
--  @usage  Same as is-ok plain, except with option to suppress next time.
--
--  @return boolean true iff is user answered ok this time or previously...
--
function Dialog:isOkOrDontAsk( msg, id )
    assert( msg ~= nil and type( msg ) == 'string', "dia-is-ok-or... needs msg string" )
    assert( str:is( id ), "isOkOrDontAsk requires actionPrefKey" ) -- check for common mistake to omit the apk.
    local answer = self:messageWithOptions{  confirm=msg, actionPrefKey=id, buttons={{label="OK",verb='ok'}} }
    return answer == 'ok'
end



--- Auto-wrap text to fit in specified width.
--
--  @param          m text to wrap.
--  @param          maxWidth maximum len in real string-len characters.
--
--  @usage          Assumes single line-feed as term char.
--
--  @return         wrapped text (string)
--  @return         number of lines required to display wrapped text.
--
function Dialog:autoWrap( m, maxWidth )
    -- auto-wrap long lines and compute height-in-lines.
    local lines = 2 -- (height-in-lines)
    local maxLen = 0
    local lineBuf = {}
    local s = m
    local prevLine = false
    for v in m:gmatch( "[^\n]*" ) do
        repeat
            local len = v:len()
            --dbg( "next line: ", v )
            if len == 0 then
                if not prevLine then
                    lineBuf[#lineBuf + 1] = ""
                    s = nil
                else
                    prevLine = false
                end
                break
            else
                prevLine = true -- ignore eol that just caps this line.
            end
            s = v
            local buf = {}
            while len > maxWidth do
                local ln = s:sub( 1, maxWidth ) -- take first maxWidth characters
                local lastSpace = str:lastIndexOf( ln, " " )
                if lastSpace > 0 then
                    --dbg( "Last space ", lastSpace )
                    buf[#buf + 1] = ln:sub( 1, lastSpace - 1 ) -- .. "%"
                    --dbg( "piece before space: ", buf[#buf] )
                    s = s:sub( lastSpace + 1 )
                    --dbg( "s remainder ", s )
                    len = len - lastSpace -- I assume this is correct???
                else
                    buf[#buf + 1] = ln:sub( 1, maxWidth ) -- .. "@"
                    --dbg( "piece since no space: ", buf[#buf] )
                    s = s:sub( maxWidth + 1 )
                    --dbg( "s remainder after no space ", s )
                    len = len - maxWidth
                end
            end
            --dbg( "remainder, taking s ", s )
            local remLen = s:len()
            if remLen > 0 then
                if buf[#buf] ~= nil then
                    local lastLineLen = string.len( buf[#buf] )
                    if (remLen + lastLineLen) <= maxWidth then
                        buf[#buf] = buf[#buf] .. " " .. s -- .. "*"
                    else
                        buf[#buf + 1] = s -- .. "^"
                    end
                else
                    buf[#buf + 1] = s -- .. "$"
                end
            end
            s = nil
            --dbg( "line broken into pieces ", #buf )
            if #buf > 0 then
                lines = lines + #buf - 1
                lineBuf[#lineBuf + 1] = table.concat( buf, "\n" )
            end
            --if len > maxLen then
            --    maxLen = len
            --end
        until true
    end
    if s then
        --dbg( "final piece ", s )
        lineBuf[#lineBuf + 1] = s
        --dbg( "final count ", #lineBuf )
    end
    lines = lines + #lineBuf - 1
    m = table.concat( lineBuf, "\n" )
    --self:rawMessageDisplay( "m", m )
    return m, lines
        
end



--- Determine if action already remembered, and hence there will be no prompt.
--
function Dialog:getAnswer( apkRaw )
    local apk               -- formatted.
    local apkPrefEna        -- global action-pref-key preference name for dont-show-again enable setting.
    local apkPrefFriendly   -- name for global property to set friendly name
    local apkPrefAnswer     -- global action-pref-key preference name for answer lookup when not showing.
    local flavor            -- akin to "style" but delegates responsibility for all garnish to this method.
    local buttons           -- button table as passed by calling context.
    local okButton          -- for special handling of "main action" button.
    local cancelButton      -- for special handling of "cancel" button.
    local args={}           -- arguments to lr-dialogs-present-modal-dialog, OR self-present-modal-frame.
    
    if str:is( apkRaw ) then
        apk = str:makeLuaVariableNameCompliant( apkRaw )
        apkPrefEna = "actionPrefKey_enabled_" .. apk -- must be resettable.
        apkPrefAnswer = "actionPrefKey_answer_" .. apk -- must be resettable.
        apkPrefFriendly = "actionPrefKey_friendly_" .. apk -- must be resettable.
        app:initGlobalPref( apkPrefEna, false ) -- default to do-show if not set already by user.
        if app:getGlobalPref( apkPrefEna ) then
            local answer = app:getGlobalPref( apkPrefAnswer )
            if not str:is( answer ) then
                app:error( "no answer" )
            else
                return answer
            end
        else -- pref not enabled.
            return nil
        end
    else
        app:callingError( "need apk" )
    end
end




--- Clear prompts which only occur once per "session" (session meaning from the time this function is called until..).
--  @param keyOpt (string, optional) if nil, all prompt-once's are cleared; if string, then only specified one is cleared.
function Dialog:clearPromptOnce( keyOpt )
    if not self.promptOnce or not keyOpt then
        self.promptOnce = {}
    else -- tbl exists and reseting just one.
        self.promptOnce[keyOpt] = nil
    end
end




--- Displays a message for the user to see, and provides options for the user to choose.
--  
--  @param      message ( string or table, default="" )<br>
--              If string<br>
--              - message is info-type format string.<br>
--              If table<br>
--              - message table contains the following members:<br>
--              - info (string) info format string, or<br>
--              - warning (string) warning format string, or<br>
--              - error (string) error format string.<br>
--              - actionPrefKey (string, default=nil ) for "do not show" informational messages only (never warning or error messages).<br>
--                - This should be a user friendly string since these prefs are now individual clearable by user via combo_box.
--              - buttons ( table, default = nil ) button entries are tables with members:<br>
--                label (string, required) button display text<br>
--                verb (string, required) button return text<br>
--                forget (string, default=false) whether button must not be remembered (only applies if actionPrefKey is passed),<br>
--                In which case, at least one button must not be forgetable.<br>
--                *** One button must have verb='ok'
--                Note: A cancel button is not optional in the dialog box, but it is optional as a parameter to this function.
--                - if passed, it may be used to change the label and optionally make memorable (the default for cancel button (labeled "Cancel") is not memorable). the verb must be 'cancel' (that's what makes it a "cancel" button definition).
--                - if not passed, then it defaults to "Cancel" label, returns 'cancel', and is not memorable (will not be remembered by checking 'Don't show again').
--              - viewItems (array, default=nil) of items to be added to main UI.
--              Normal use does not include these, but for special occasions: 
--              - width (integer, default=nil) units are pixels, or
--              - width_in_chars (integer, default=nil) units are that of big fat characters, generally 50% to double that of true character width.
--              - height (integer, default=nil) of message text, in pixels, or
--              - height_in_lines (integer, default = nil) in lines - best to include an extra line or two to spare and to keep it above the buttons.
--              - wrap (boolean, default=false) whether text should be wrapped at width. Note: strings without spaces are still truncated to fit. *** Requires width AND height to be specified somehow.
--              - call (Call, default=nil) if passed, auto-caption will be displayed and previous caption restored.
--                
--  @param      ... ( any type, default = nil, nil, nil, ... ) variables to be formatted<br>
--
--  @usage      Like lr-dialogs.message, lr-dialogs.message-with-do-not-show, lr-dialogs.confirm, and lr-dialogs.prompt-for-action-with-do-not-show combined,<br>
--              except won't compress nor truncate the message.
--  @usage      Will automatically wrap if lines are too long, at space if possible, otherwise cuts in the middle.<br>
--              Max width chosen to accomodate most whole file paths.
--  @usage      Supports formatting and named parameter passing.
--  @usage      Examples:<br>
--              app:show( "I'm simple" ) -- informational<br>
--              app:show( "I'm ^1 simple", howSimple ) -- informational/formatted.<br>
--              app:show( { info="I'm simple" } ) -- informational using named parameter passing.<br>
--              app:show( { info="I'm ^1 simple" }, "very" ) -- informational, named, formatted.<br>
--              app:show( { confirm="I'm asking, but I'll remember your answer", actionPrefKey="QuestionablePrompt", buttons={{label="Yes",verb='ok'},{label='No',verb='cancel',memorable=true}} } ) -- confirm prompt, both yes and no answers can be remembered.
--              app:show( { warning="I'm ^1 simple" }, adjective ) -- simple warning, formatted.<br>
--              app:show( { info="I'm ^1 simple", actionPrefKey="My friendly prompt", buttons={ {label='OK',verb='ok'},{label='Not OK',verb='other',memorable=false} }, "not so" ) -- you can remember OK button only,<br>
--              app:show( { error="I'm an error", buttons={{label="I guess its OK...",verb='ok'},{label='Abort',verb='cancel'}} } ) -- error message with custom cancel button.<br>
--
function Dialog:messageWithOptions( message, ... )

    -- step 0: check main message argument
    if message == nil then
        app:logError( "Message for display in dialog box is nil - displaying as blank." )
        message = "" -- might as well give a blank box I guess.
    end
    
    local m                 -- formatted message to present.
    local apk               -- action-pref-key as passed by caller.
    local apkPrefEna        -- global action-pref-key preference name for dont-show-again enable setting.
    local apkPrefFriendly   -- name for global property to set friendly name
    local apkPrefAnswer     -- global action-pref-key preference name for answer lookup when not showing.
    local promptOnce        -- boolean or string-key indicating prompt should not occure multiple times (if true, string-key will be apk).
    local flavor            -- akin to "style" but delegates responsibility for all garnish to this method.
    local buttons           -- button table as passed by calling context.
    local okButton          -- for special handling of "main action" button.
    local cancelButton      -- for special handling of "cancel" button.
    local args={}           -- arguments to lr-dialogs-present-modal-dialog, OR self-present-modal-frame.
    local caption
    
    --   S T E P   1 :   analyze passed parameters, and translate un-named or named parameters to local variables.
    --                   (includes checking for and returning stored answer)
    
    if type( message ) == 'string' then
        m = str:fmtx( message, ... )
        flavor = 'info'
    else
        args.save_frame = message.save_frame
        buttons = message.buttons
        if str:is( message.actionPrefKey ) then
            -- equivalent to self:getAnswer, except the various variables are needed internally too, so...
            apk = str:makeLuaVariableNameCompliant( message.actionPrefKey )
            apkPrefEna = "actionPrefKey_enabled_" .. apk -- must be resettable.
            apkPrefAnswer = "actionPrefKey_answer_" .. apk -- must be resettable.
            apkPrefFriendly = "actionPrefKey_friendly_" .. apk -- must be resettable.
            app:initGlobalPref( apkPrefEna, false ) -- default to do-show if not set already by user.
            if app:getGlobalPref( apkPrefEna ) then
                local answer = app:getGlobalPref( apkPrefAnswer )
                if not str:is( answer ) then
                    app:logError( "no answer" )
                else
                    return answer
                end
            end
        end
        if message.promptOnce then
            if not message.confirm then
                if type( message.promptOnce ) == 'boolean' then
                    if str:is( apk ) then
                        promptOnce = apk
                    else
                        Debug.pause( "prompt once must be string, or if boolean must be accompanied by action pref key string" )
                    end
                else -- string, presumably.
                    if str:is( message.promptOnce ) then -- this throws error if type is not string.
                        promptOnce = message.promptOnce
                    else
                        Debug.pause( "prompt once can not be empty string" )
                    end
                end
                if promptOnce then -- string key
                    if not self.promptOnce then
                        Debug.pause( "consider initializing prompt-once in start dialog method, or plugin-init.." )
                        self.promptOnce = {}
                    end
                    if self.promptOnce[promptOnce] then
                        return nil -- prompt-once is only appropriate for prompts which do not require an answer (i.e. info)
                    else
                        self.promptOnce[promptOnce] = true
                    end
                end
            else -- ignore prompt-once if caller attempting to use with confirm message, which requires an answer each time, and hence a prompt.
                Debug.pause( "prompt-once is not appropropriate with confirm message" )
            end
        -- else no prompt-once
        end
        if message.info then
            m = message.info
            flavor = 'info'
        elseif message.warning then
            m = message.warning
            flavor = 'warning'
        elseif message.error then
            m = message.error
            flavor = 'error'
        elseif message.confirm then
            m = message.confirm
            flavor = 'confirm'
            if tab:isEmpty( buttons ) then
                buttons = { self:btn( "OK", 'ok' ) } -- counter-intuitively, this assures there is a 'Cancel' button to go with the default 'OK' button.
            end
        else
            error( "Message to be shown should be passed as named parameter, either 'info', 'confirm', 'warning', or 'error'." )
        end
        if message.subs == nil then -- no named substitutions.
            if #message > 0 then -- substitution variables included unnamed in message table.
                if #{ ... } > 0 then -- ya can't have unnamed param in calling table and calling list.
                    app:callingError( "Unnamed params in both table and calling list." )
                else
                    m = str:fmtx( m, unpack( message ) )
                end
            else
                m = str:fmtx( m, ... ) -- assume legacy mode: substitutions after message table - optional.
            end
        elseif type( message.subs ) == 'table' then
            if #message > 0 or #{...} > 0 then
                app:callingError( "Pass subs table or unnamed, not both." )
            else
                m = str:fmtx( m, unpack( message.subs ) ) -- next way: named substitution table.
            end
        else -- one sub - any type
            if #message > 0 or #{...} > 0 then
                app:callingError( "Pass subs or unnamed, not both." )
            else
                m = str:fmtx( m, message.subs ) -- other next way: named substitution simple variable.
            end
        end
    end
    
    --   S T E P   2 :   Determine dimensions for static-text, and reformat message by wrapping if necessary.
    --                   (includes determination of wrap specifier)
    
    -- *** There's rarely a need for explicit wrap specification or explicit dimensions
    -- since automatic wrapping and dimensions computation is supported.

    if message.wrap then
        dbg( "Are you sure you need text wrapping?" )
    end
    
    if message.width then
        dbg( "Are you sure you need to specify text width explicitly?" )
    end
    
    if message.width_in_chars then
        dbg( "Are you sure you need to specify text width-in-chars explicitly?" )
    end
    
    if message.height then
        dbg( "Are you sure you need to specify text height explicitly?" )
    end
    
    if message.height_in_lines then
        dbg( "Are you sure you need to specify text height_in_lines explicitly?" )
    end
    
    local chars = nil
    local width = nil
    local height = nil
    local wrap = nil
    local lines = nil

    if message.width_in_chars then
        if message.width then
            error( "specify width or width_in_chars, not both" )
        end
        chars = message.width_in_chars
    elseif message.width then
        width = message.width
    end
    
    if message.height_in_lines then
        if message.height then
            error( "specify height or height_in_lines, not both" )
        end
        lines = message.height_in_lines
    elseif message.height then
        height = message.height
    else
        m, lines = self:autoWrap( m, 100 ) -- 100 seems like a good balance between controlled width and not truncating paths...
    end

    -- wrap spec is supported, but should *never* be warranted(?)
    if message.wrap then
        if (message.height or message.height_in_lines) and (message.width or message.width_in_chars) then
            wrap = message.wrap
        else
            error( '"width" and "height" must be specified somehow along with \'wrap\'' )
        end
    end
    
    --   S T E P   3 :   Initialize args for "present modal" dialog box.
    --                   (includes detection of ok & cancel buttons, and determination of whats memorable and what not)    
    
    local title -- window title
    local icon -- upper left corner
    if flavor == 'info' then
        if not apkPrefEna then -- distinction between this and the normal prompting...
            args.title = "Info"
            title = app:getAppName() .. " has something to say..."
            icon = "info.png"
        else
            args.title = "Lightroom" -- the idea being the less things to have to read the better...
            title = app:getAppName() .. " can remember your answer for next time..."
            icon = "Adobe_Lightroom_Icon_32x32.png"
        end
    elseif flavor == 'warning' then
        args.title = "Warning"
        title = app:getAppName() .. " is concerned..."
        icon = "warning.png"
        if apkPrefEna then
            app:logWarning( "Warnings can not be suppressed, key: " .. apk )
            apkPrefEna = nil
        end
    elseif flavor == 'error' then
        args.title = "Error"
        title = app:getAppName() .. " has encountered a problem..."
        icon = "error.png"
        if apkPrefEna then
            app:logWarning( "Errors can not be suppressed, key: " .. apk )
            apkPrefEna = nil
        end
    elseif flavor == 'confirm' then
        args.title = "Confirm"
        title = app:getAppName() .. " is asking..."
        icon = "Adobe_Lightroom_Icon_32x32.png"
    else
        error( str:fmtx( "Program failure: invalid flavor: ^1", str:to ( flavor ) ) ) -- should've been checked/set above.
    end
    local viewItems = {}
    viewItems[#viewItems + 1] =
        vf:picture {
            value = app:getFrameworkResource( icon ),
            width = share 'wid',
        }
    viewItems[#viewItems + 1] = vf:spacer{ width = 10 }
    local fontName
    -- ref: http://www.ampsoft.net/webdesign-l/WindowsMacFonts.html
    if win_env then
        fontName = 'Lucida Sans Unicode'
    else
        -- fontName = 'Lucida Grande' -- this doesn't work - default font is chosen on Mac. ###2
        fontName = 'Lucida Sans Unicode' -- might as well try this...
    end
    local viewCol = {}
    viewCol[1] = 
        vf:static_text {
            title = title,
            font = { name=fontName, size = 14 },
            text_color = LrColor( .1, .2, .5 ), -- off blue (dark).
            height_in_lines = 2, -- "spacer".
        }
    viewCol[2] =
        vf:static_text {
            title = m,
            height = height,
            height_in_lines = lines,
            width = width,
            width_in_chars = chars,
            wrap = wrap,
        }
    if message.viewItems then
        tab:appendArray( viewCol, message.viewItems )
        viewCol[#viewCol + 1] = vf:spacer{ height = 20 }
    end    
    viewItems[#viewItems + 1] = vf:column( viewCol )
    local accItems = { bind_to_object=prefs }
    if apkPrefEna then
        accItems[#accItems + 1] = vf:spacer{ width = share 'wid' }
        accItems[#accItems + 1] = vf:spacer{ width = 10 }
        accItems[#accItems + 1] =
            vf:checkbox {
                title = "Don't show again",
                tooltip = str:fmtx( "If checked, your answer (button clicked) will be remembered for next time, and this dialog box will not be shown; if unchecked, this dialog box will be shown again next time...\n \nPrompt ID: ^1", message.actionPrefKey ),
                value = app:getGlobalPrefBinding( apkPrefEna ),
                height = share 'ht',
            }
    end
    if message.accItems then
        if #accItems > 0 then
            accItems[#accItems + 1] = vf:spacer{ width = 10 } -- separate from apk prompt.
        else
            accItems[#accItems + 1] = vf:spacer{ width = share 'wid' }
            accItems[#accItems + 1] = vf:spacer{ width = 10 } -- separate from wid space.
        end
        tab:appendArray( accItems, message.accItems )
    end
    accItems[#accItems + 1] = vf:spacer{ width = 1, fill_horizontal = 1 }
    local memorable = {}
    local forgetable = {}
    if buttons then
        local rowItems = {}
        local verbs = {}
        if type( buttons ) == 'table' then
            for i = 1, #buttons do
                repeat
                    local button = buttons[i]
                    if button == nil then break end
                    assert( str:is( button.verb ), "button verb must be non-blank string, this isn't: " .. str:to( button.verb ) )
                    assert( str:is( button.label ), "button label must be non-blank string, this isn't: " .. str:to( button.label ) )
                    if button.verb == 'ok' then
                        if okButton then
                            error( "Only one button can have verb='ok'" )
                        else
                            okButton = button
                            args.actionVerb = okButton.label -- Adobe got confused...
                        end
                    elseif button.verb == 'cancel' then
                        if cancelButton then
                            error( "Only one button can have verb='cancel'" )
                        else
                            cancelButton = button
                            if cancelButton.label == 'Cancel' then
                                if cancelButton.memorable then
                                    error( "Memorable cancel button must not be labeled 'Cancel'." )
                                else
                                    cancelButton.forgetable = true -- assure all cancel buttons labeled 'Cancel' are not memorable (i.e. are forgetable).
                                end
                            -- else as long as label is not 'Cancel', its treated like any other button.
                            end
                            args.cancelVerb = cancelButton.label -- Adobe got verb & label terminology mixed up...
                        end
                    else
                        if verbs[button.verb] then
                            -- app:logVerbose( "Redundent verb: " .. button.verb ) -- not prohibited, although represents an unusual case which is usually a bug.
                            error( str:fmtx( "Verbs must be unique, '^1' is already taken by ^2.", button.verb, str:to( verbs[button.verb].label ) ) ) -- on the other hand, app can always do the same thing for both answers - make it an error.
                        end
                        verbs[button.verb] = button
                        rowItems[#rowItems + 1] =
                            vf:push_button {
                                title = button.label,
                                action = function( view )
                                    LrDialogs.stopModalWithResult( view, button.verb )
                                end,
                                tooltip = button.tooltip,
                            }
                    end
                    if button.forgetable or button.memorable == false then
                        forgetable[button.verb] = button
                    elseif (button.memorable==nil or button.memorable) then -- default is memorable, but can be explicitly asserted.
                        assert( not button.forgetable, "cant be both" )
                        if button.label == 'Cancel' then
                            error( "No buttons labeled 'Cancel' should be memorable." )
                        end
                        memorable[button.verb] = button
                    end
                until true
            end
            -- ok button is not optional
            if not okButton then
                error( "One button must have verb='ok'" )
            end
            -- cancel button is optional, and is used only for altering label and memorable-ness.
            if not cancelButton then -- unlike other buttons, cancel button defaults to not-memorable.
                forgetable['cancel'] = { label='Cancel', verb='cancel' } -- pseudo-button to record default forgetableness of cancel button.
                memorable['cancel'] = nil -- this would have got set above.
            end
            local row = vf:row( rowItems )
            accItems[#accItems + 1] =
                vf:column {
                    vf:spacer{ height=1, fill_vertical = 1 },
                    row,
                    height = share 'ht',
                }
        elseif type( buttons ) == 'string' then
            args.cancelVerb = '< exclude >'
            args.actionVerb = buttons -- 1-button label.
            forgetable = { cancel = { label='Cancel' } } -- this won't do anything if there's no action-pref-key.
            memorable = { ok = { label = "OK" } } -- this won't do anything if there's no action-pref-key.
        else
            error( "Buttons must be table or string, this isn't: " .. str:to( buttons ) )
        end
    else
        args.cancelVerb = 'Cancel' -- will only show on Mac(?)
        args.actionVerb = 'OK'
        forgetable = { cancel = { label='Cancel' } } -- this won't do anything if there's no action-pref-key.
        memorable = { ok = { label = "OK" } } -- this won't do anything if there's no action-pref-key.
    end
    if buttons and apkPrefEna and tab:isEmpty( memorable ) then
        error( "Must have at least one memorable answer" )
    end
    args.accessoryView = vf:row( accItems )
    local rows={}
    rows[1] = vf:row( viewItems )
    rows[2] = vf:row{ vf:spacer{ width=share'wid' }, vf:spacer{ width=8 }, vf:separator{ fill_horizontal = 1 } }
    args.contents = vf:view( rows ) -- view and column are same with default placement being vertical.
    
    -- S T E P   4 :   Present modal dialog box until user chooses an acceptable answer.
    --                 (unacceptable answers are those that try to remember non memorable choices)
    
    if message.call then
        caption = message.call:setCaption( "Dialog box needs your attention..." )
    end
    local answer
    repeat
        if buttons then
            answer = LrDialogs.presentModalDialog( args )
        else
            answer = self:presentModalFrame( args ) -- generally only returns 'ok', but one should be prepared for 'cancel' also (due to the 'X' button).
        end
        assert( type( answer ) == 'string', "answer should be string" ) -- a "safety" convention, not a technical necessity.
        if apkPrefEna then -- don't show again?
            if app:getGlobalPref( apkPrefEna ) then
                if memorable[answer] then
                    app:setGlobalPref( apkPrefAnswer, answer )
                    app:setGlobalPref( apkPrefFriendly, message.actionPrefKey )                    
                    break
                else -- default if not memorable is forgettable. Note: normal buttons will have forgetable set explicitly, but ad-hoc acc-item buttons will not.
                    app:setGlobalPref( apkPrefEna, false )
                    app:setGlobalPref( apkPrefAnswer, "" )
                    app:setGlobalPref( apkPrefFriendly, "" )
                    if forgetable[answer] then                    
                        app:show{ warning="The '^1' answer can not be remembered for next time - try again...", forgetable[answer].label } -- recursive but should be OK.
                    else
                        app:show{ warning="That button can not be remembered for next time - try again..." } -- recursive but should be OK.                        
                    end
                end
            else
                app:setGlobalPref( apkPrefEna, false )
                app:setGlobalPref( apkPrefAnswer, "" )
                app:setGlobalPref( apkPrefFriendly, "" )
                break
            end
        else
            break
        end
    until false
    
    -- step 5: return answer...
    if caption then
        message.call:setCaption( caption )
    end
    return answer     
end             



--- Convenience function to make a button ultimately bound for lr-dialog box.
--
--  @param label (string, required) button text
--  @param verb (string, required) return value
--  @param memorable (boolean, default=true) pass false to make otherwise memorable buttons not memorable.
--
function Dialog:btn( label, verb, memorable )
    return { label=label, verb=verb, memorable=memorable }
end



--- get specified dialog buttons.
--
--  @param shortcut (string, required) specification keys:<br>
--            YesNo - 'ok' => Yes, 'cancel' => No.
--
function Dialog:buttons( shortcut, cancelNotMemorable )
    local buttons = buttonShortcuts[shortcut]
    Debug.pauseIf( buttons==nil, "No buttons having shortcut", shortcut )
    return buttons
end
Dialog.btns = Dialog.buttons -- function Dialog:btns( ... ) - synonym/shortcut.



--- get specified dialog buttons.
--
--  @param shortcut (string, required) specification keys:<br>
--            YesNo - 'ok' => Yes, 'cancel' => No.
--
function Dialog:yesNo( cancelNotMemorable )
    local buttons = buttonShortcuts['YesNo']
    Debug.pauseIf( buttons==nil, "No buttons having shortcut" )
    if cancelNotMemorable then
        buttons[2].memorable = false
    end
    return buttons
end



--- get specified dialog buttons.
--
--  @param shortcut (string, required) specification keys:<br>
--            YesNo - 'ok' => Yes, 'cancel' => No.
--
function Dialog:yesNoCancel()
    local buttons = buttonShortcuts['YesNoCancel']
    Debug.pauseIf( buttons==nil, "No buttons having shortcut" )
    return buttons
end



--- Function to prompt for initiation of operation to be performed on selected photo(s), filmstrip, or whole catalog.
--
--  @param prefix (string, required) operation prefix e.g. "Update metadata of", "Adjust"
--  @param returnComponents (boolean, default=false) true => omit the prompt and return confirm, subs, buttons, and actionPrefKey items. false => prompt user and return photos.
--  @param call (Call, required) call object instance.
--
--  @usage check if call has been canceled upon return. If not canceled, then there will be at least one target photo.<br>
--  @usage Named parameter passing is supported (i.e. parameters can be named members of a single table if you prefer).
--
function Dialog:promptForTargetPhotos( prefix, returnComponents, call, viewItems, accItems, noApk )
    if type( prefix ) == 'table' then
        noApk = bool:booleanValue( prefix.noApk, false ) -- as passed, or false.
        accItems = prefix.accItems
        viewItems = prefix.viewItems
        call = prefix.call
        returnComponents = prefix.returnComponents
        prefix = prefix.prefix
    end
    assert( call ~= nil, "need call" )
    local selectedPhotos = cat:getSelectedPhotos()
    local auxPhotos = #selectedPhotos == 1 and catalog:getMultipleSelectedOrAllPhotos() or catalog:getTargetPhotos()
    local allPhotos = catalog:getAllPhotos()
    if #allPhotos == 0 then
        app:show{ warning = "^1 only makes sense if there is at least one photo in the catalog", call.name }
        call:cancel()
        return
    end
    local okPhotos
    local otherPhotos
    local photos
    local buttons
    local confirm
    local subs
    local apk
    local stackOpt
    if #selectedPhotos == #auxPhotos then
        if #selectedPhotos == 0 then -- no photos in filmstrip - all are filtered out or collection is empty...
            buttons = { dia:btn( "Yes - Whole Catalog", 'ok' ) }
            okPhotos = allPhotos
            confirm = "^1 all ^2 in catalog? (will include photos buried in stacks...)"
            subs = { prefix, str:nItems( #allPhotos, "photos" ) }
            apk = str:fmtx( "^1 - whole catalog", prefix )
        elseif #selectedPhotos == 1 then -- only one photo in the filmstrip, and it is selected.
            local photo = selectedPhotos[1]
            local stacked = photo:getRawMetadata( 'isInStackInFolder' )
            if stacked then -- note: I supposed I could just always ask (unless whole catalog) if underlings should be included - might simplify things.
                stackOpt = photo:getRawMetadata( 'stackInFolderIsCollapsed' )
            end
            buttons = { dia:btn( "Yes - Selected Photo", 'ok' ) }
            okPhotos = selectedPhotos
            confirm = "^1 selected photo?"
            subs = { prefix }
            apk = str:fmtx( "^1 - selected photos", prefix ) -- same pref key as multiple selected.
        else -- multiple photos selected
            stackOpt = true
            buttons = { dia:btn( "Yes - All Selected Photos", 'ok' ), dia:btn( "Yes - Most-selected Only", 'other' ) }
            okPhotos = selectedPhotos
            otherPhotos = { catalog:getTargetPhoto() }
            confirm = "^1 all ^2, or most-selected photo only?"
            subs = { prefix, str:nItems( #selectedPhotos, "selected photos" ) }
            apk = str:fmtx( "^1 - selected photos or most-selected only", prefix )
        end
    elseif #selectedPhotos == 0 then -- 1 or more exist in filmstrip, none are selected.
        stackOpt = true
        buttons = { dia:btn( "Yes - Filmstrip Photos", 'ok' ), dia:btn( "Yes - Whole Catalog", 'other' ) }
        okPhotos = auxPhotos
        otherPhotos = allPhotos
        confirm = "^1 photos in filmstrip (+/- those buried in folder stacks), or whole catalog (including photos buried in stacks...)?\n \n^2 in filmstrip, ^3 in catalog."
        subs = { prefix, str:nItems( #auxPhotos, "photos" ), #allPhotos }
        apk = str:fmtx( "^1 - filmstrip versus whole catalog", prefix )
    elseif #selectedPhotos == 1 then -- multiple photos exist in filmstrip, of which only one is selected.
        if #auxPhotos > 1 then -- the "normal" case
            stackOpt = true
            buttons = { dia:btn( "Yes - Selected Photo Only", 'ok' ), dia:btn( "Yes - Filmstrip Photos", 'other' ) }
            okPhotos = selectedPhotos
            otherPhotos = auxPhotos
            confirm = "^1 selected photo, or all ^2 in filmstrip?"
            subs = { prefix, str:nItems( #auxPhotos, "photos" ) }
            apk = str:fmtx( "^1 - filmstrip versus selected photo", prefix )
        else -- in my experience, this means Lr is reporting a selected photo, but there really isn't one (e.g. all are filtered out.)
            -- treat same  as 0-photos selected and 0 in filmstrip above.
            assert( #auxPhotos == 0, "?" ) -- reminder: not aux not equal to sel.
            buttons = { dia:btn( "Yes - Whole Catalog", 'ok' ) }
            okPhotos = allPhotos
            confirm = "^1 all ^2 in catalog? (will include photos buried in stacks...)"
            subs = { prefix, str:nItems( #allPhotos, "photos" ) }
            apk = str:fmtx( "^1 - whole catalog", prefix )
        end
    else
        app:error( "Unexpected photo selection" )
    end
    if noApk then
        apk = nil
    end
    if returnComponents then
        return { -- if you want photos underneath, call get-photo-set-from-seed-photos upon return
            confirm=confirm,
            subs=subs,
            buttons=buttons,
            actionPrefKey = apk,
            okPhotos = okPhotos,
            otherPhotos = otherPhotos,
        }
    end
    if stackOpt then
        app:initGlobalPref( 'includePhotosInFolderStacks', false )
        local tidbit = "" -- assume no regular collections which may have independent stacks.
        for i, src in ipairs( catalog:getActiveSources() ) do
            local typ = cat:getSourceType( src )
            if typ == 'LrCollection' or typ == 'LrPublishedCollection' or typ == 'special' then
                tidbit = " (in folder of origin, whether collapsed or not)"
                break
            end
        end
        if viewItems then
            viewItems[#viewItems + 1] = vf:spacer{ height=15 }
        else
            viewItems = {}
        end
        viewItems[#viewItems + 1] = vf:row {
            vf:checkbox {
                title = str:fmtx( "Include photos in same folder stack^1, if applicable.", tidbit ),
                bind_to_object = prefs,
                value = app:getGlobalPrefBinding( 'includePhotosInFolderStacks' ),
                tooltip = "Not applicable when choosing \"Whole Catalog\", since *all* photos in the catalog will be included in that case, regardless of folder or collection stacking.\n \n*** Note: there is no way to access photos buried in collapsed collection stacks, only folder stacks, so if you're in a collection and want the underlings too - expand stacks...",
            },
        }
        view:setObserver( prefs, app:getGlobalPrefKey( 'includePhotosInFolderStacks' ), Dialog, function( id, props, key, value )
            app:pcall{ name='includePhotosInFolderStacks', async=true, guard=App.guardSilent, main = function( call )
                if not value then
                    if okPhotos == allPhotos or otherPhotos == allPhotos then
                        app:show{ info="If you choose \"Whole Catalog\", *all* photos in the catalog will be included - even those buried in collapsed stacks etc., regardless of \"Include photos buried in stacks...\" checkbox.", actionPrefKey="Whole catalog means all photos" }
                    end
                end
            end }
        end )
    end
    call:setCaption( "Dialog box needs your attention..." ) -- will create scope if not already existing, so beware...
    local answer = app:show{ confirm=confirm,
        subs = subs,
        buttons = buttons,
        actionPrefKey = apk,
        viewItems = viewItems,
        accItems = accItems,
    }
    call:setCaption( "" ) -- in case calling context fails to put up a better caption.
    if answer == 'ok' then
        photos = okPhotos
    elseif answer == 'other' then
        photos = otherPhotos
    elseif answer == 'cancel' then
        call:cancel()
        return
    else
        error( "bad answer" )
    end
    assert( #photos > 0, "no target photos - please select different complement of photos, and report problem - thanks." )
    if stackOpt and app:getGlobalPref( 'includePhotosInFolderStacks' ) then
        local photoSet
        if photos == allPhotos then -- already includes underlings - confirmed.
            return photos
        else
            call:setCaption( "Rounding up buried photos..." )
            local cache = lrMeta:createCache{ photos, rawIds={ 'isInStackInFolder', 'stackInFolderMembers' } } 
            photoSet = cat:getPhotoSetFromSeedPhotos( photos, cache ) -- note: @2/Feb/2014 5:35 this will include all photos in associated folder stacks (whether collapsed or not, and whether seed photo is at top of stack or not).
            call:setCaption( "" ) -- in case calling context fails to put up a better caption.
            return tab:createArrayFromSet( photoSet ) -- this is pretty-darn fast, even with huge photo-set.
        end
    else
        return photos
    end
end



--- Present non-modal (floating dialog), in "like" fashion in Lr4 (not officially supported) as Lr5 (1st version in which offcially supported).
--
--  @usage Supports Lr4 (by somewhat emulating Lr5) and Lr5 (by somewhat emulating Lr4). - DO NOT PUT A QUIT BUTTON IF LR4 (quitting requires 'X').
--  @usage Call-forwards: to-front and close - not supported in Lr4. So cross-version contexts must not be dependent on them.
--  @usage examples:
--      <br>    dia:presentFloatingDialog { -- param table is args.
--                  <br>    title=str:fmtx( "^1 - My fancy dbox..", app:getAppName() ),
--                  <br>    save_frame=str:fmtx( "^1 - My fancy dbox..", app:getAppName() ), -- can be same as title
--                  <br>    resizable = true, -- generally a good idea for floaters.
--                  <br>    contents = vf:view( vi ), -- excludes quit button if Lr4.
--                  <br>    blockTask = true, -- wrapped externally in async task
--                  <br>    windowWillClose = nil, -- finale handled in calling context.
--                  <br>    onShow = function( callForward ) self.toFront = callForward.toFront; self.close = callForward.close end -- calling context expects these to be defined, even if no-ops in Lr4.
--              <br>    }
--      <br>    dia:presentFloatingDialog { -- param table has name, guard, and args.
--                  <br>    name=str:fmtx( "^1 - My fancy dbox..", app:getAppName() ),
--                  <br>    guard=App.guardVocal,
--                  <br>    args = {
--                              <br>    save_frame=str:fmtx( "^1 - My fancy dbox..", app:getAppName() ), -- can be same as title
--                              <br>    resizable = true, -- generally a good idea for floaters.
--                              <br>    contents = vf:view( vi ), -- excludes quit button if Lr4.
--                              <br>    blockTask = false, -- not internally wrapped in async task.
--                              <br>    windowWillClose = function() exifTool:closeSession( self.ets ) end
--                              <br>    onShow = function( callForward ) self.toFront = callForward.toFront; self.close = callForward.close end
--              <br>    }}
--
--  @param params (table, required) parameter elements:
--      <br>    name (string, default: "generic") unique dialog box name - used for guarding. Note: if there are no other guarded calls active, the default name will suffice.
--      <br>    guard (number, default: no guarding) App.guardXXX - whether call should be guarded internally or not. Usually call should be guarded externally if not internally.
--      <br>    args (table) params may be dialog box args (if all other params to default), or may be member of params, in order to pass the others in enclosing table.
--      <br>        be sure to consider:
--                  <br>    title (string, default: "app-name - floating dialog") recommended to override.
--                  <br>    save_frame (string, default: don't save) hardly any reason not to allow user to define spot - recommend app-name - window-name.
--                  <br>    resizable (boolean, default: false) usually good to set true, since floaters may have too big frame for contents - allows user to control.
--                  <br>    background_color (LrColor, default: white) rarely needs to be otherwise specified.
--                  <br>    contents (view, required) a complete view, not an array of view items...
--                  <br>    blockTask (boolean, default: blocking, if called from async task, else non-blocking) note: this is an emulation via wrappage, actual floater will be blocking regardless.
--                  <br>    windowWillClose (function, default: nil) callback when window is closing (Lr5), or has closed (Lr4). Recommend using for finalization, if not handled externally.
--                  <br>    onShow (function, default: nil) callback when dialog about to be presented, contains to-front and close functions, which work as advertised in Lr5, and do nothing in Lr4.
--
function Dialog:presentFloatingDialog( params )
    local args
    local name = params.name or app:getAppName().." - floating dialog" -- string
    local guard = params.guard or App.guardNot -- numeric
    local async -- boolean
    -- another option: background_color.
    if params.contents then
        args = params
    else
        args = params.args
        assert( args.contents, "no contents" )
    end
    if args.blockTask == nil then
        async = not LrTasks.canYield()
    else
        async = not args.blockTask
    end
    dbgf( "non-modal dialog '^1', async: ^2, guarded: ^3", name, async, guard )
    app:pcall{ name=name, guard=guard, async=async, main=function( call ) -- async value determines blocking/non-blocking.
        if app:lrVersion() <= 3 then
            app:error( "Floaters require Lr4, Lr5, or better..." )
        elseif app:lrVersion() == 4 then
            args.background_color = args.background_color or LrColor( 'white' ) -- In Lr4 it's black by default.
            if args.onShow then
                args.onShow{ toFront = function()
                    --Debug.pause()
                    -- to-front doesn't work in Lr4, but common code may be expecting to see it assigned.                
                end, close = function() -- ditto.
                    Debug.pause( "Quit should be via red 'X' in Lr4, not this function." )
                end }
            end
            LrDialogs.presentFloatingDialog( args ) -- always blocking (does not support block-task arg as Lr5 does).
            -- Lr4 does not close context until dialog closed.
        else -- 5+
            args.blockTask = true -- blocking mandatory since non-blocking implemented by way of wrapper task.
            -- beware, this is setting block-task to true in calling context, so args should be temp construction prior to each call (the usual).
            -- Lr5 will call "window-will-close" if defined.
            LrDialogs.presentFloatingDialog( _PLUGIN, args )
        end
    end, finale=function( call )
        --Debug.pause( "finale status", call.status )
        if app:lrVersion() == 4 and args.windowWillClose then -- manually invoking
            args.windowWillClose() -- actually, window already closed, but this gives Lr4 context a chance to close exiftool sessions etc..
        end
        if call.status then
            app:log( "^1 - closed (done) ...", call.name ) -- if no errors, finale won't be called until floater is closed.
        else
            error( call.message ) -- propagate error.
        end
    end }  

end


return Dialog
