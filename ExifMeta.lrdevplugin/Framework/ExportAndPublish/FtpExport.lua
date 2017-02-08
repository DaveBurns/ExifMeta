--[[
        Export.lua
--]]

local FtpExport, dbg, dbgf = Export:newClass{ className = 'FtpExport' }



--- Constructor for extending class.
--      
function FtpExport:newClass( t )
    return Export.newClass( self, t )
end



--- Constructor to create the export object that represents the export dialog box.
--      
--  <p>One of these objects is created when the export dialog box is presented,
--  if it has not already been.</p>
--
function FtpExport:newDialog( t )
    local o = Export.new( self, t )
    o:init()
    return o
end
FtpExport.new = FtpExport.newDialog -- function FtpExport:new( ... ) -- synonym for (minimal) object which has access to export methods, but not representing an export in progress (with session, context, settings, ... ).



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
--  @return      FtpExport object
--
function FtpExport:newExport( t )

    local o = Export.newExport( self, t )
    -- default property name map:
    -- (if your derived class uses different name, be sure to provide a proper mapping in constructor).
    o:init()
    return o
end



function FtpExport:init()
    self.ftpPropertyMap = { -- reminder: there is one entry for each property needed for ftp'ing, not all are for ftp-settings proper.
        localRootPath = 'localRootPath',
        server = "server",
        username = "username",
        password = "password",
        port = "port",
        passive = "passive",
        protocol = "protocol",
        path = "path", -- "remote" (ftp) server root path. name is not so descriptive for historical reasons..
        remoteSubpath = "remoteSubpath", -- ftp child path.
        remoteDirPathForFtpUploadTest = "remoteDirPathForFtpUploadTest", -- added 12/Mar/2014 20:22 based on comment that it was probably missing - hope nothing breaks..
    }

end



-- if export via ftp enabled, then initialize the service according to interface, @now only one is supported (ftp-ag-app).
-- return s, m.
function FtpExport:_initFtpService( srvcName )
    
    app:assert( self.ftpPropertyMap, "no ftp property map" )
    app:assert( ftpAgApp, "global ftp-ag-app expected" )
    app:assert( self.exportParams, "no export params" )
    
    local destDir = self:getDestDir( self.exportParams, cat:getAnyPhoto(), nil ) -- nil is cache. ###2 theoretically, should not need to get dest dir based on any-photo.
    local localRootPath = self.exportParams[self.ftpPropertyMap.localRootPath]
    local localPath
    if str:is( localRootPath ) then -- specified explicitly
        app:logV( "Local root path has been specified in export params (determines remote subpath): ^1", localRootPath )
        localPath = localRootPath
    elseif str:is( destDir ) then -- this case occurs when using export-filter mode, in which case it's presumptuous to assume ftp-export properties necessarily
        -- represent the correct export location. If export service is via hard-drive or one of mine, then yes - otherwise: it's a crap shoot.
        app:logV( "*** No (local) root path in export params, or name not matching mapped ftp property - using computed destination dir instead (considered \"root\" of local export destination): ^1", destDir )
        localPath = destDir
    else
        error( "no (local) root path in export params" )
    end
    local remotePath = self.exportParams[self.ftpPropertyMap.path] or error( "no (server root) path in export params" )
    if str:is( self.exportParams[self.ftpPropertyMap.remoteSubpath] ) then
        remotePath = str:parentSepChild( remotePath, "/", self.exportParams[self.ftpPropertyMap.remoteSubpath] )
        app:logV( "Remote root path (as specified in export params): ^1", remotePath )
    else -- again: normal case when uploading via export filter.
        app:logV( "*** Remote (server) path is being used without child-dir, since no remote sub-path property found - root path: ^1", remotePath )
    end
    local srvcSettings = {
        serviceName = srvcName,
        localRootPath = localPath,
    }
    local ftpSettings = {
        server=self.exportParams[self.ftpPropertyMap.server] or error( "no server in export params" ),
        username=self.exportParams[self.ftpPropertyMap.username] or error( "no username in export params" ),
        password=self.exportParams[self.ftpPropertyMap.password], -- --###1? (17/Mar/2014 18:01)   or error( "no password field in export params" ), -- can be blank, but shouldn't be missing, although I suppose it could be..
        port=self.exportParams[self.ftpPropertyMap.port] or error( "no port in export params" ),
        passive=self.exportParams[self.ftpPropertyMap.passive] or error( "no passive in export params" ),
        protocol=self.exportParams[self.ftpPropertyMap.protocol] or error( "no protocol in export params" ),
        path=remotePath, -- reminder: settings are on a per-service basis, so having remote-subpath rolled in is just fine.
    }
    local errm
    self.jobNum, errm = ftpAgApp:initService( srvcSettings, ftpSettings, self.ftpPropertyMap ) -- for now, ftp settings & password are re-initialized each job.
    -- not such a bad way to go - assures freshness even if "non-optimal" (slight overkill).
    if self.jobNum then -- new/fresh job num
        self.taskNum = 1 -- always start a new job with task #1.
        app:log( "FTP Service initialized, job-num: ^1", self.jobNum )        
        return true
    else
        Debug.pauseIf( not str:is( errm ), "no errm" )
        app:logE( "FTP Service NOT initialized - ^1", errm or "no additional info" )        
        self.taskNum = nil -- probably (hopefully) a dont care, but do not attempt to do tasks when job not properly init.
        return false, errm
    end
end



-- Typically wrapped in a service externally, so service finale box tells status.
-- 
function FtpExport:clearFtpJobs( props )
    local srvcName = self:_getServiceName( props )
    local cleared = ftpAgApp:clearJobs( srvcName, props )
    if cleared then
        self.jobNum = 1
        self.taskNum = 1
        --app:show{ info="Jobs are cleared.", actionPrefKey="Jobs are cleared" }
    else
        -- I assume appropriate error/warning logs have already been issued.
    end
end



--- Called when new export is getting under way (i.e. early in process-rendered-photos func/meth).
--
--  It makes sure the appropriate directory infrastructure exists, and ascertains the correct job-num to use.
--
function FtpExport:newFtpJob()
    local srvcName = self:_getServiceName( self.exportParams )
    local s, m = self:_initFtpService( srvcName )
    if s then
        return ftpAgApp:initJob( srvcName, self.jobNum ) -- assure dir.
    else
        return nil, "Unable to initialize ftp job (service) - "..(m or "no additional info" )
    end
end



--- get fully qualified (unique) service name based on properties.
--
--  @usage *** critical side effect: service name will be assigned to properties *if* not publish service properties.
--  @usage *** to be clear: do NOT assign the output of this to service-name property, since it includes app-name prefix.
--
function FtpExport:_getServiceName( props )
    local myName
    if props.LR_publish_connectionName then -- ps
        myName = props.LR_publish_connectionName
    else
        if str:is( props.serviceName ) then
            -- note: service names are unique within a plugin, and since app-name is prepended, uniqueness is "guaranteed".
            myName = props.serviceName
        else
            Debug.pause( "service-name should be pre-defined export setting/param" ) -- this could happen if export attempted without visiting export dialog box / publish settings (e.g. via old preset).
            myName = LrUUID.generateUUID()
            props.serviceName = myName -- for next time.
        end
    end
    -- note: make sure you dont assign the output of this to service-name property or else there will be a double app-name prefix.
    return app:getAppName().." - "..myName
end



--  Confine service name to a unique value - note: app-name will be auto-pre-pended, so assuming multiple plugins won't have same app-name
--  (would be more robust to use toolkit ID), one need only assure names are unique within the plugin.
--
--  @usage Lr assures publish-service instance names are unique, so no special action required in that case.
--
--  @usage call when pub-conn-name or exp-srvc-name changes.
--
function FtpExport:_confineServiceName( props, value ) -- note: @19/Mar/2014 3:48, value is a don't care.
    app:pcall{ name="FtpExport_confineServiceName", async=not LrTasks.canYield(), guard=App.guardSilent, main=function( call )
        if str:is( props.LR_publish_connectionName ) then
            if not str:is( props.serviceName ) then
                props.serviceName = props.LR_publish_connectionName -- init service name to that of publish service as a good guess,
                -- but note: no need to do it if props.service-name already set, since in publish-service context the conn-name will override
                -- whatever is set as service-name, and no reason to overstep boundaries (stomp on user-edited service-name setting).
            -- else - already set: leave it.
            end
        elseif not str:is( props.serviceName ) then
            props.serviceName = "Any Unique Name "..LrUUID.generateUUID()
        -- else good-to-go..
        end
    end }
end



--- Method version of like-named static function.
--      
--  @usage      Same as base-class method, except pre-init ftp job.
--  @usage      Note: ftp-export needs special finale logic too (to close ftp job) - not handled in this method, since it needs to weather thrown errors.
--
function FtpExport:processRenderedPhotosMethod()

    local s, m = self:newFtpJob()
    if s then
        app:log( "FTP service initialized, current job-num: ^1", self.jobNum )
        Export.processRenderedPhotosMethod( self )
    else
        app:logE( m or "no errm" ) 
        self:cancelExport() -- note: this is silent.
        return
    end

end



--- Perform export service wrap-up.
--
--  @usage    Override this method in derived class to log stats...
--  @usage    *** IMPORTANT: This method is critical to export integrity.
--            Derived export class must remember to call it at end of special
--            export finale method.
--
function FtpExport:finale( service )

    local srvcName = self:_getServiceName( self.exportParams )
    ftpAgApp:endOfJob( srvcName, self.jobNum, self.taskNum )
    Export.finale( self, service, service.status, service.message ) -- still old-style calling maybe ###1.
    
end



--- Called when export is initiated.
--
--  @usage This method helps export manager track managed exports (all exports based on this class are managed).
--
function FtpExport:initiate( service )
    Export.initiate( self, service )
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
function FtpExport:service( service )
    Export.service( self, service )
end



--   E X P O R T   D I A L O G   B O X



--- Handle change to properties under authority of base export class.
--      
--  <p>Presently there are none - but that could change</p>
--
--  @usage        Call from derived class to ensure base property changes are handled.
--
function FtpExport:propertyChangeHandlerMethod( props, name, value )
    -- reminder: nil name just won't match test clauses.
    
    self:_confineServiceName( props ) -- assure appropriate service-name initialization.
    --Export.propertyChangeHandlerMethod( self, props, name, value ) -- no-op, but reserved for future.
    
end



--- Do whatever when dialog box opening.
--      
--  <p>Nuthin to do so far - but that could change.</p>
--
--  @usage        Call from derived class to ensure dialog is initialized according to base class.
--
function FtpExport:startDialogMethod( props )
    view:setObserver( props, 'serviceName', FtpExport, FtpExport.propertyChangeHandler )
    view:setObserver( props, 'LR_publish_connectionName', FtpExport, FtpExport.propertyChangeHandler )
    --view:setObserver( props, 'localRootPath', FtpExport, FtpExport.propertyChangeHandler )
end



--- Do whatever when dialog box closing.
--      
--  <p>Nuthin yet...</p>
--
--  @usage        Call from derived class to ensure dialog is ended properly according to base class.
--
function FtpExport:endDialogMethod( props, why )
end



--- Standard export sections for top of dialog.
--      
--  <p>Presently seems like a good idea to replicate the plugin manager sections.</p>
--
--  @usage      These sections can be combined with derived class's in their entirety, or strategically...
--
function FtpExport:sectionsForTopOfDialogMethod( vf, props )
    return Manager.sectionsForTopOfDialog( vf, props ) -- instantiates the proper manager object via object-factory.
end



--- Standard export sections for bottom of dialog.
--      
--  <p>Reminder: Lightroom supports named export presets.</p>
--
--  @usage      These sections can be combined with derived class's in their entirety, or strategically - presently there are none.
--
function FtpExport:sectionsForBottomOfDialogMethod( vf, props )

    local sections = Export.sectionsForBottomOfDialogMethod( self, vf, props ) or {{
        title = app:getAppName() .. " Settings",
    }}

    local s1 = sections[#sections]

    if str:is( props.LR_publish_connectionName ) then -- publish service: ftp serice name is same as publish connection name.
        app:logV( "publish service: ftp service name is same as publish connection name." )
    else
        s1[#s1 + 1] = vf:row {
            vf:static_text {
                title = "Service Name",
                width = share'labelWidth',
            },
            vf:edit_field {
                value = bind'serviceName',
                width = share'dataWidth',
            },
        }
    end
    
    --[[ *** local-root-path is handled in derived class.
    s1[#s1 + 1] = vf:row {
        vf:static_text {
            title = "Local Root Path",
            width = share'labelWidth',
        },
        vf:edit_field {
            value = bind'localRootPath',
            width = share'dataWidth',
        },
    }
    --]]
    
    s1[#s1 + 1] = view:startFtpSettingsView( self, props, nil, nil, { width=share'labelWidth' }, { width=share'dataWidth' }  )
    
    return sections

end



--   E X P O R T   S U B - T A S K   M E T H O D S


--- Remove photos not to be rendered, or whatever.
--
function FtpExport:checkBeforeRendering()
    self.nPhotosToRender = self.nPhotosToExport
end



--- Process one rendered photo.
--
function FtpExport:processRenderedPhoto( rendition, photoPath )
    self.nPhotosRendered = self.nPhotosRendered + 1
    local srvcName = self:_getServiceName( self.exportParams )
    local s, m = ftpAgApp:uploadFile( srvcName, photoPath, self.jobNum, self.taskNum ) -- note: job-num specified job-dir, task-num specified ordering in control-file (disk) "queue".
    self.taskNum = self.taskNum + 1 -- regardless, I guess.
    if s then
        app:logV( "Upload via FTP has been scheduled." )
    else
        app:logE( "Unable to schedule file upload via FTP - ^1", m or "no m" )
    end
end



function FtpExport:getJobDir()
    assert( self.exportParams, "no export params" )
    assert( self.jobNum, "no job num" )
    local srvcName = self:_getServiceName( self.exportParams )
    return ftpAgApp:getJobDir( srvcName, self.jobNum )
end



function FtpExport:uploadFile( photoPath )
    local srvcName = self:_getServiceName( self.exportParams )
    local s, m = ftpAgApp:uploadFile( srvcName, photoPath, self.jobNum, self.taskNum ) -- note: job-num specified job-dir, task-num specified ordering in control-file (disk) "queue".
    self.taskNum = self.taskNum + 1 -- regardless, I guess.
    if s then
        app:logV( "Upload via FTP has been scheduled." ) -- local path determined by ftp-ag-app based on service config. remote path determined by ftp-app itself.
    else
        app:logE( "Unable to schedule file upload via FTP - ^1", m or "no m" )
    end
    return s, m
end



function FtpExport:purgeFile( photoPath )
    local srvcName = self:_getServiceName( self.exportParams )
    local s, m = ftpAgApp:purgeFile( srvcName, photoPath, self.jobNum, self.taskNum ) -- note: job-num specified job-dir, task-num specified ordering in control-file (disk) "queue".
    self.taskNum = self.taskNum + 1 -- regardless, I guess.
    if s then
        app:logV( "Purge file via FTP has been scheduled." )
    else
        app:logE( "Unable to schedule purge file via FTP - ^1", m or "no m" )
    end
    return s, m
end



function FtpExport:purgeFolder( photoPath )
    local srvcName = self:_getServiceName( self.exportParams )
    local s, m = ftpAgApp:purgeFolder( srvcName, photoPath, self.jobNum, self.taskNum ) -- note: job-num specified job-dir, task-num specified ordering in control-file (disk) "queue".
    self.taskNum = self.taskNum + 1 -- regardless, I guess.
    if s then
        app:logV( "Purge folder via FTP has been scheduled." )
    else
        app:logE( "Unable to schedule purge folder via FTP - ^1", m or "no m" )
    end
    return s, m 
end




--- Process one photo rendering failure.
--
--  @param      message         error message generated by Lightroom.
--
function FtpExport:processRenderingFailure( rendition, message )
    Export.processRenderingFailure( self, rendition, message )
end



--- FtpExport parameter change handler proper - static function
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export object.
--
function FtpExport.propertyChangeHandler( id, props, name, value )

    if FtpExport.dialog == nil then
        return
    end
    --assert( FtpExport.dialog ~= nil, "No export dialog to handle change." ) - not sure whether the potential for dialog
    -- box to not be created has disappeared or not, hmmm...... ###3 - hasn't been happening though...
    FtpExport.dialog:propertyChangeHandlerMethod( props, name, value )
end



--- Called when dialog box is opening - static function as required by Lightroom.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export object.
--
function FtpExport.startDialog( props )

    if FtpExport.dialog == nil then
        FtpExport.dialog = objectFactory:newObject( 'ExportDialog' )
    end
    assert( FtpExport.dialog ~= nil, "No export dialog to start." )
    FtpExport.dialog:startDialogMethod( props )
end



--- Called when dialog box is closing.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export object.
--
function FtpExport.endDialog( props, why )
    if FtpExport.dialog == nil then
        return
    end -- ###3 ditto
    assert( FtpExport.dialog ~= nil, "No export dialog to end." )
    FtpExport.dialog:endDialogMethod( props, why )
end



--- Presently, it is imagined to just replicate the manager's top section in the export.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export dialog object.
--
function FtpExport.sectionsForTopOfDialog( vf, props )
    if FtpExport.dialog == nil then
        FtpExport.dialog = objectFactory:newObject( 'ExportDialog' )
    end
    assert( FtpExport.dialog ~= nil, "No export dialog for top sections." )
    return FtpExport.dialog:sectionsForTopOfDialogMethod( vf, props )
end



--- Presently, there are no default sections imagined for the export bottom.
--
--  @usage      Generally no reason to override in derived class - override method instead.
--  @usage      Just calls corresponding method of actual (i.e derived class) export dialog object.
--
function FtpExport.sectionsForBottomOfDialog( vf, props )
    if FtpExport.dialog == nil then
        FtpExport.dialog = objectFactory:newObject( 'ExportDialog' )
    end
    assert( FtpExport.dialog ~= nil, "No export dialog for bottom sections." )
    local sections = FtpExport.dialog:sectionsForBottomOfDialogMethod( vf, props )
    return sections
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
function FtpExport.processRenderedPhotos( functionContext, exportContext )

    if FtpExport.exports[exportContext] ~= nil then
        app:logError( "FtpExport not properly terminated." ) -- this should never happen provided derived class remembers to call base class finale method.
        FtpExport.exports[exportContext] = nil -- terminate improperly...
    end
    FtpExport.exports[exportContext] = objectFactory:newObject( 'Export', { functionContext = functionContext, exportContext = exportContext } )
    FtpExport.exports[exportContext]:processRenderedPhotosMethod()
    
end



local exportParams = {}

-- this param is needed by ftp-ag-app it will be superceded by LR_publish_connectionName if publish-service-only, but export-service-too plugins must populate it.
exportParams[#exportParams + 1] = { key="serviceName", default="" } -- populated by func.

--exportParams[#exportParams + 1] = { key="localRootPath", default="" } -- ###2 - this must come from derived class, or will be filled in via hook or crook.

-- note: these are as supported by view--get-ftp-settings-view:
exportParams[#exportParams + 1] = { key = 'server', default = "ftp.mydomain.com" }
exportParams[#exportParams + 1] = { key = 'username', default = "me" }
exportParams[#exportParams + 1] = { key = 'password', default = "secret" }
exportParams[#exportParams + 1] = { key = 'path', default = "wwwroot" }
exportParams[#exportParams + 1] = { key = 'port', default = 21 }
exportParams[#exportParams + 1] = { key = 'passive', default = "normal" }
exportParams[#exportParams + 1] = { key = 'protocol', default = "ftp" } 
exportParams[#exportParams + 1] = { key = 'remoteDirPathForFtpUploadTest', default = "" }


FtpExport.exportPresetFields = exportParams


-- note: there are no standard (base class) export preset fields, if there were, then consider uncommenting this:
--tab:appendArray( FtpExport.exportPresetFields, Export.exportPresetFields or {} )


FtpExport:inherit( Export )


return FtpExport