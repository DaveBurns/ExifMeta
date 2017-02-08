--[[
        Filename:           Ftp.lua
        
        Synopsis:           Utilities that supplement Lightroom FTP functionality.
        
        Public Methods:     - Ftp:queryForPasswordIfNeeded
                            - Ftp:existsAsDir
                            - Ftp:existsAsFile
                            - Ftp:removeFile
                            - Ftp:removeEmptyDir
                            - Ftp:removeDirTree
                            - Ftp:assureAllRemoteDirectories
                            - Ftp:assureDir
                            - Ftp:makeDir
                            - Ftp:putFile
                            - Ftp:getDirContents
                            - Ftp:calibrateClock
                            - Ftp:init
                            - Ftp:connect
                            - Ftp:disconnect
                            
        Notes:              - This module born from the original rc-common-modules version, converted to object-orientation, and:
                                - Changed path handling: presently all external paths are considered relative to whatever has been set,
                                  in the ftp-settings. The directory set in the ftp settings is expected to exist, all others may be created
                                  as needed. All functions that use the path set the path before using.
                            - No assumptions are made about whether root path has leading slash. So far, it has worked without a leading slash.
                              leading and trailing slashes in remote-sub-paths are optional and shouldn't make a difference (sub-path is interpreted
                              as being relative to root-path regardless. I recommend omitting both, for simplicity and clarity.
                              
        ###1 warning: *some* (incomplete) strides have been made so ftp settings can be mapped - long story short: if settings are not using standard mapping, take caution.
--]]


local Ftp, dbg, dbgf = Object:newClass{ className='Ftp' }



local _thisYear = LrDate.timestampToComponents( LrDate.currentTime() ) -- year is first return value. Used when year not present in dir-entry timestamp.
local monthTable = nil -- initialization deferred until first use.


Ftp.remoteClockOffset = {} -- set this value externally for each server if desired (which will circumvent clock calibration), this will be subtracted from time parsed from remote file directory entries.



--- Constructor for extending class.
--
function Ftp:newClass( t )
    return Object.newClass( self, t )
end    



--- Constructor for new instance.
-- 
--  @param t (initialization table, optional) ftp-settings and auto-negotiate may come now or in init method.
--
function Ftp:new( t )
    local o = Object.new( self, t )
    if o.autoNegotiate == nil then
        o.autoNegotiate = true
    end
    if o.ftpSettings and o.ftpSettings.path then -- ###1 no mapping
        o.ftpSettings.path = Ftp.formatPath( o.ftpSettings.path )
    end
    return o
end



--- Initialize ftp settings and other particulars.
--
--  @usage      optional method, in case the particulars were not available at the time of new instance creation.
--
function Ftp:init( ftpSettings, autoNegotiate )
    self.ftpSettings = ftpSettings
    if self.ftpSettings and self.ftpSettings.path then
        self.ftpSettings.path = Ftp.formatPath( self.ftpSettings.path ) -- ###1 unmapped.
    end
    if autoNegotiate ~= nil then
        self.autoNegotiate = autoNegotiate
    end
end



--- Connect to the remote server.
--
--  @usage      side-effect: validates root-server-dir exists - this forces a true connection, and is a pre-requisite to everything else.
--
function Ftp:connect()
    assert( self.ftpSettings ~= nil, "ftp settings are needed in constructor, or init method" )
    assert( self.autoNegotiate ~= nil, "auto-negotiate is needed in constructor, or init method." )
    if self.ftpSettings and self.ftpSettings.path then -- unmapped ###1
        self.ftpSettings.path = Ftp.formatPath( self.ftpSettings.path )
    end
    --Debug.lognpp( self.ftpSettings, self.autoNetotiate )
    self.ftpSettings.port = tonumber( self.ftpSettings.port ) or error( "bad port number" ) -- probably should assure numeric before calling, but in case..
    self.ftpConn = LrFtp.create( self.ftpSettings, self.autoNegotiate ) -- auto-negotiate may be nil.
    app:logV( "Created FTP connection to ^1 (but not really connected yet)", self.ftpSettings.server )
    self.rootPath = self.ftpSettings.path -- already formatted.  str:replaceBackSlashesWithForwardSlashes( self.ftpSettings.path ) -- never changes
    local s, m = self:_existsAsDir( "" ) -- make sure root-dir exists as a directory (and anyway, this forces a "real" connection).
    if s then
        if self.ftpConn.connected then
            app:logV( "Connected and logged in as ^1", self.ftpSettings.username )
            return true
        else
            return false, "unexpectedly not connected..."
        end
    else
        return false, m or ( "root dir does not exist: " .. self.ftpSettings.path )
    end
end    



--- Disconnect (gracefully) from the remote server.
--
--  @usage      Optional method - makes for a clean break, but connection cleanup via Lightroom or OS so far has made this unnecessary.
--
function Ftp:disconnect()
    if self.ftpConn then
        local sts, msg = LrTasks.pcall( self.ftpConn.disconnect, self.ftpConn )
        self.ftpConn = nil -- once upon a time, I thought this might be affecting FTP reliability, but it's not - cause is inherent in Lr's ftp lib (happens even using Adobe's FTP upload plugin).
        return sts, msg
    end
    return true -- don't rock the boat.
end



---------------------
-- Private functions:
---------------------



--  Sets the path in the connection, to "{rootPath}/{remoteDirSubPath}/"
--
--  @param      remoteDirSubPath (string, required) sub path from root to dir, not to file.
--
function Ftp:_setPath( remoteDirSubPath )
    assert( remoteDirSubPath ~= nil, "need path" )
    local path = self:_makeDirPath( remoteDirSubPath )
    if path == self.ftpConn.path then
       -- ok 
    else
        self.ftpConn.path = path
        local cnt = 0
        repeat
            LrTasks.sleep( .01 )
            cnt = cnt + 1
        until self.ftpConn.path == path or cnt==100
        Debug.pauseIf( cnt > 1 )
        if self.ftpConn.path ~= path then
            app:error( "Unable to set remote path to (absolute) '^1'", path )
        end
    end
    return path
end



--------------------------------------------------------------------------------
--      The following functions were invented to aid debugging.
--      Although they are theoretically no longer necessary,
--      they provide a debugging focal point and protect against
--      adobe oopsing on the path like they did in ftp-conn-exists.
--
--      PS - My experience has been that some of the FTP functions can take
--      many minutes to return if there is trouble with the connection and/or server.
--      This led me to believe they were hung, but it now appears they will eventually return.
--
--      local _{name} functions that only take a name and not a path must have the path set
--      before calling, and path is "guaranteed" to be same upon return.
--------------------------------------------------------------------------------



--  Get NOT slash appended parent dir name and leaf-name.
--  Note: dir returned is a sub-path, not an absolute ftp path.
--  note2 - rsp is offset to root path, and so having no parent is common-place.
function Ftp:_getDirAndName( rsp )
    assert( rsp:find( "\\", 1, true ) == nil, "pre-normalize remote path: " .. rsp )
    local dir = str:replaceBackSlashesWithForwardSlashes( LrPathUtils.parent( rsp ) ) -- nil passed through
    if dir == nil then
        if str:is( rsp ) then
            return "", rsp -- this must be handled properly by -set-path
        else
            return nil, nil -- this must be handled properly in calling context.
        end
    end
    local name = LrPathUtils.leafName( rsp )
    return dir, name
end



--      Synopsis:       Determines if an entity of any type exists at the set path with the specified name.
--
--      Motivation:     - ftp-conn-exists started changing the path and goofing things up - this routine detects
--                        the condition, responds appropriately, and restores the original path to the ftp connection.
--                      - operates in protected mode, although I'm not sure its necessary, since ftp-conn-exists
--                        returns nil, err-msg - it may be operating in protected mode without being documented as such.
--                        Still, the other functions explicitly state protect mode and ftp-conn-exists does not.
--                        This function provides cheap protected-mode insurance.
--
--      Returns:        - 'file', nil:          exists as file, no comment.
--                      - 'directory', nil:     exists as directory, no comment.
--                      - false, nil:           does not exist, no comment.
--                      - nil, comment:         who knows?
--
function Ftp:_exists( rsp )
    local ftpConn = self.ftpConn
    local existsAs, qualification
    local dir, name = self:_getDirAndName( rsp ) -- not dir is sub-path, not actual path.
    local path = self:_setPath( dir ) -- combines root path with dir
    local s, r1, r2 = LrTasks.pcall( ftpConn.exists, ftpConn, name )
    if s then -- pcall completed without fatal exception.
        -- r1 (required) & r2 (optional) are values returned by ftp-conn-exists method.
        if r1 ~= nil then -- ftp existence function completed without ftp error.
            if type( r1 ) == 'string' then -- 'file' or 'directory' exists.
                assert( r1 == 'file' or r1 == 'directory', LOC( "$$$/X=Illegal string returned by ftp-conn-exists method: ^1", r1 ) )
                existsAs = r1
            elseif type( r1 ) == 'boolean' then
                assert( r1 == false, LOC( "$$$/X=1st value returned by ftp-conn-exists is true - not expected." ) )
                existsAs = false
            else
                error( LOC( "$$$/X=1st value returned by ftp-conn-exists has unexpected type: ^1", type( r1 ) ) )
            end
        else -- ftp error
            assert( r2 ~= nil and type( r2 ) == 'string', LOC( "$$$/X=2nd value returned by ftp-conn-exists is supposed to be an error message, its: ^1", r2 ) )
            existsAs = nil
            qualification = LOC( "$$$/X=FTP error checking for existence of file named (^1) in directory (^2), message: ^3", name, path, r2 )
        end
    else
        assert( r1 ~= nil and type( r1 ) == 'string', LOC( "$$$/X=2nd value returned by pcall is supposed to be an error message, its: ^1", r1 ) )
        existsAs = nil
        qualification = LOC( "$$$/X=Unable to determine if remote file exists, more: ^1", r1 ) -- r1 is pcall error message.
    end
    return existsAs, qualification
end



--      Synopsis:           Remove a file.
--
--      Returns:            - true, nil:        worked, no-comment.
--                          - false, comment:   failed, and here's why...
--
--      Notes:              *** WARNING: Based on some of my previous comments about ftp-conn-p-remove-file, the second
--                          return value seems unreliable.
--
--                          I dont think this function is called unless the file is known to exist.
--                          Not sure what happens if it does not.
--
--                          This function checks ftp-conn-p-remove-file return values very thoroughly but does not
--                          confirm removal. Do this confirmation in calling context if confirmation desired.
--
function Ftp:_pRemoveFile( rsp )
    local ftpConn = self.ftpConn
    local status, qualification
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local r, dummy = ftpConn:pRemoveFile( name ) -- the guts.
    if r ~= nil then
        if type( r ) == 'boolean' then
            if r == true then -- call completed without exception.

                status = true -- for the purposes of this program, assume if call completed, the file was removed,
                    -- even if confirmation was not attained. If there's a problem putting a file in its place
                    -- let the error be handled there. Also, calling context can look at qualifier to see if 
                    -- file removal truly happened and confirmed.

                -- theoretically its possible that the call completed without exception, but the file was not actually removed.
                -- in which case the second return value is suppossedly false.
                if dummy ~= nil then
                    if type( dummy ) == 'boolean' then
                        if dummy == true then
                            -- file removal confirmed.
                        else
                            -- file removal not-confirmed.
                            qualification = LOC( "$$$/X=FTP error confirming removal of file named ^1 from dir: ^2", name, path )
                        end
                    else
                        assert( type( dummy ) == 'string', LOC( "$$$/X=2nd value returned by ftp-conn-p-remove-file has bad type: ^1", type( dummy ) ) )
                    end
                else
                    -- error( "2nd value returned by ftp-conn-p-remove-file is nil" ) - lr-api doc says this is boolean or string: doc is wrong - its nil.
                end
            else
                status = false
                qualification = LOC( "$$$/X=FTP error trying to remove file named ^1 from dir: ^2, more info: ^3", name, path, str:to( dummy ) )
            end
        else
            assert( type( r ) == 'string', LOC( "$$$/X=1st value returned by ftp-conn-p-remove-file has bad type: ^1", type( r ) ) )
            status = false
            qualification = LOC( "$$$/X=FTP error trying to remove file named ^1 from dir: ^2, error message: ^3", name, path, r )
        end
    else
        error( "1st value returned by ftp-conn-p-remove-file is nil" )
    end
    return status, qualification
end



--      Synopsis:           Remove a directory known to exist and be empty.
--
--      Returns:            - true, nil:        worked, no-comment.
--                          - false, comment:   failed, and here's why...
--
--      Notes:              *** WARNING: Based on some of my previous comments about ftp-conn-p-remove-file, the second
--                          return value seems unreliable.
--
--                          I dont think this function is called unless the directory is known to exist.
--                          Not sure what happens if it does not.
--
--                          This function checks ftp-conn-p-remove-directory return values very thoroughly but does not
--                          confirm removal. Do this confirmation in calling context if confirmation desired.
--
function Ftp:_pRemoveEmptyDirectory( rsp )
    local ftpConn = self.ftpConn
    local status, qualification
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local r, dummy = ftpConn:pRemoveDirectory( name ) -- the guts - dir must exist, and be empty.
    if r ~= nil then
        if type( r ) == 'boolean' then
            if r == true then -- call completed without exception.

                status = true -- for the purposes of this program, assume if call completed, the directory was removed,
                    -- even if confirmation was not attained. If there's a problem putting a directory in its place
                    -- let the error be handled there. Also, calling context can look at qualifier to see if 
                    -- directory removal truly happened and confirmed.

                -- theoretically its possible that the call completed without exception, but the directory was not actually removed.
                -- in which case the second return value is suppossedly false.
                if dummy ~= nil then
                    if type( dummy ) == 'boolean' then
                        if dummy == true then
                            -- directory removal confirmed.
                        else
                            -- directory removal not-confirmed.
                            qualification = LOC( "$$$/X=FTP error confirming removal of directory named ^1 from dir: ^2", name, path )
                        end
                    else
                        assert( type( dummy ) == 'string', LOC( "$$$/X=2nd value returned by ftp-conn-p-remove-directory has bad type: ^1", type( dummy ) ) )
                    end
                else
                    -- error( "2nd value returned by ftp-conn-p-remove-directory is nil" ) - lr-api doc says this is boolean or string: doc is wrong - its nil,
                        -- or at least p-remove-file returns nil - I assume p-remove-directory does same thing.
                end
            else
                status = false
                qualification = LOC( "$$$/X=FTP error trying to remove directory named ^1 from dir: ^2, more info: ^3", name, path, str:to( dummy ) )
            end
        else
            assert( type( r ) == 'string', LOC( "$$$/X=1st value returned by ftp-conn-p-remove-directory has bad type: ^1", type( r ) ) )
            status = false
            qualification = LOC( "$$$/X=FTP error trying to remove directory named ^1 from dir: ^2, error message: ^3", name, path, r )
        end
    else
        error( "1st value returned by ftp-conn-p-remove-directory is nil" )
    end
    return status, qualification
end



--      Synopsis:       Get the text contents of a directory.
--
--      Notes:          Calling context must set path in ftp-conn before calling.
--
function Ftp:_getDirContents( rsp )
    local ftpConn = self.ftpConn
    local contents, qualification
    local dir = str:replaceBackSlashesWithForwardSlashes( rsp )
    local path = self:_setPath( dir )
    local s, r = LrTasks.pcall( ftpConn.getContents, ftpConn, "" ) -- getting file contents of empty name means get directory contents.
    if s then
        if r then
            contents = r
        else
            -- contents stays nil
            qualification = str:fmtx( "Unable to obtain contents from remote directory: '^1' - reason unknown (no specific error/message)", path )
        end
    else
        contents = nil
        qualification = LOC( "$$$/X=FTP error getting contents from remote directory: '^1'", path )
    end
    return contents, qualification
end



--      Synopsis:       Write local file to remote host.
--
--      Returns:        - true, nil:        File put, no comment.
--                      - false, comment:   failed.
--
function Ftp:_putFile( localPath, rsp )
    local ftpConn = self.ftpConn
    local status, qualification
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local s, r = LrTasks.pcall( ftpConn.putFile, ftpConn, localPath, name ) -- put-file throws error upon failure.
        -- no return value specified, although my experience has been that it sometimes returns "OK".
    if s then
        status = true
    else
        status = false
        qualification = LOC( "$$$/X=FTP error putting local file (^1) to remote dir (^2), more: ^3", localPath, path, str:to( r ) )
    end
    return status, qualification
end



--      Synopsis:       Read local file to remote host.
--
--      Returns:        - true, nil:        File put, no comment.
--                      - false, comment:   failed.
--
function Ftp:_getFile( localPath, rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local s, c = LrTasks.pcall( ftpConn.getContents, ftpConn, name )
        -- no return value specified, although my experience has been that it sometimes returns "OK".
    if s then
        if str:is( c ) then
            return fso:writeFile( localPath, c )
        else -- technically not an error, but in practice, it almost always will mean a problem! ###2
            return false, str:fmtx( "Remote file is empty: ^1, so not writing local file: ^2", rsp, localPath )
        end
    else
        return false, LOC( "$$$/X=FTP error getting contents of local file (^1) to remote dir (^2), more: ^3", localPath, path, str:to( c ) )
    end
    error( "how here?" )
end



--- Get remote file contents.
--
--  @return contents or nil.
--  @return errm or nil.
--
function Ftp:getFileContents( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local s, c = LrTasks.pcall( ftpConn.getContents, ftpConn, name )
        -- no return value specified, although my experience has been that it sometimes returns "OK".
    if s then
        if c ~= nil then
            return c
        else
            return nil, str:fmtx( "Remote file (^1) in remote dir (^2) does not exist or is empty.", name, dir )
        end
    else
        return nil, LOC( "$$$/X=FTP error getting contents of local file (^1) to remote dir (^2), more: ^3", localPath, path, str:to( c ) )
    end
    error( "how here?" )
end



--      Synopsis:       Create remote directory.
--
--      Returns:        - true, nil:        Directory created, no comment.
--                      - false, comment:   failed.
--
--      * Test mode not yet implemented.
--
function Ftp:_makeDirectory( rsp )
    local ftpConn = self.ftpConn
    local status, qualification
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local s, r = LrTasks.pcall( ftpConn.makeDirectory, ftpConn, name )
    if s then
        if r then
            status = true
        else
            status = true -- ###4 in order to keep the wheel turning, calling context may assume
                -- that the directory was created, even though not confirmed. When it subsequently tries to put files into the directory,
                -- it may have problems and log errors. It can always look at qualification to see if it was confirmed.
            qualification = LOC( "$$$/X=FTP unable to confirm creation of remote directory named ^1, in parent dir: ^2", name, path )
        end
    else
        status = false
        qualification = LOC( "$$$/X=FTP error creating remote directory named ^1, in parent dir: ^2", name, path )
    end
    return status, qualification
end



--      Synopsis:       Determines if directory SEEMS to exist.
--
--      Notes:          My experience has been that answer is not always correct, thus its worth
--                      double checking and waiting if it is expected, in calling context.
--
--      Returns:        true, nil:      directory exists, no comment.
--                      false, nil:     directory does not exist, no comment.
--                      nil, comment:   who knows.
--
function Ftp:_existsAsDir( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local existsAs, message = ftpConn:exists( name )
    if path ~= ftpConn.path then
        ftpConn.path = path
        return false
    end
    if existsAs then
        assert( type( existsAs ) == 'string', LOC( "$$$/X=1st value returned by -exists function has unexpected type: ^1", type( existsAs ) ) )
        if existsAs == 'directory' then
            return true
        elseif existsAs == 'file' then
            -- return false, "directory is a file"
            error( LOC( "$$$/X=Directory entry named (^1) in (^2) should either not exist, or be a directory, but its a file.", name, path ) )
        else
            error( LOC( "$$$/X=1st value (string) returned by -existsAs function not expected: ^1", existsAs ) )
        end
    else -- may be false or nil, message.
        if existsAs == nil then
            assert( str:is( message ), "Expected error message to be returned by -exists function." )
            return nil, LOC( "$$$/X=Unable to ascertain if directory ^1 exists in ^2, error message: ^3", name, path, message )
        else
            assert( (type( existsAs ) == 'boolean') and (existsAs == false), LOC( "$$$/X=1st value returned by -existsAs function unexpected: ^1", str:to( existsAs ) ) )
            return false
        end
    end
end



--      Synopsis:       Determine if specified file SEEMS to exist.
--
--      History:        In the beginning, I assumed lr-ftp-exists function returned 'file', 'directory', or false/nil if neither.
--                      Code like "if exists and is 'file'" ... was normally enough, but I've had such strange errors, with this
--                      function returning inconsistent results that it seemed to warrant a wrapper. It really just makes sure
--                      assumptions about return values are correct, and reinforces the distinction between existence check failure
--                      and item determined not to exist. It also reinforces the fact that more needs to be done to reliably detect
--                      remote file/dir.
--
--      Notes:          My experience has been that ftp-conn-exists method answer is not always correct, thus its worth
--                      double checking and waiting if it if expected, in calling context.
--
function Ftp:_existsAsFile( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local existsAs, message = ftpConn:exists( name )
    if path ~= ftpConn.path then
        ftpConn.path = path
        return false
    end
    if existsAs then
        assert( type( existsAs ) == 'string', LOC( "$$$/X=1st value returned by -exists function has unexpected type: ^1", type( existsAs ) ) )
        if existsAs == 'file' then
            --Debug.pause( "file", self.ftpConn.path, path, dir, name )
            return true
        elseif existsAs == 'directory' then
            -- return false, "file is a directory"
            error( LOC( "$$$/X=Directory entry named (^1) in (^2) should either not exist, or be a file, but its a directory.", name, path ) )
        else
            error( LOC( "$$$/X=1st value (string) returned by -existsAs function not expected: ^1", existsAs ) )
        end
    else -- may be false or nil, message.
        if existsAs == nil then
            assert( str:is( message ), "Expected error message to be returned by -exists function." )
            return nil, LOC( "$$$/X=Unable to ascertain if directory existsAs, error message: ^1", message )
        else
            assert( ( type( existsAs ) == 'boolean') and (existsAs == false), LOC( "$$$/X=1st value returned by -existsAs function unexpected: ^1", str:to( existsAs ) ) )
            return false
        end
    end
end



--      Synopsis:       Waits for a directory to positively exist.
--
--      Notes:          - Called when a directory is expected to exist, but confirmation suggests it does not.
--                      - Trys each second for 10 seconds, then gives up.
--
--      Returns:        true, nil:      directory exists, no comment.
--                      false, nil:     directory does not exist, no comment.
--                      nil, comment:   who knows.
--
function Ftp:_waitForDirectory( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local retryCount = 10
    local retryDelay = 1
    local sts, msg = self:_existsAsDir( rsp ) -- true => exists-as-dir, false means doesn't, but nil means dunno, and is accompanied by msg.
    while( bool:isFalse( sts ) and ( retryCount > 0 ) ) do
        app:logWarning( "Waiting for directory, name: " .. name .. ", location: " .. path )
        app:sleepUnlessShutdown( retryDelay )
        sts, msg = self:_existsAsDir( rsp )
        retryCount = retryCount - 1
    end
    return sts, msg
end



--      Synopsis:       Waits for a file to positively exist.
--
--      Notes:          - Called when a file is expected to exist, but confirmation suggests it does not.
--                      - Trys each second for 10 seconds, then gives up.
--
--      Returns:        true, nil:      file exists, no comment.
--                      false, nil:     file does not exist, no comment.
--                      nil, comment:   who knows.
--
function Ftp:_waitForFile( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local retryCount = 10
    local retryDelay = 1
    local sts, msg = self:_existsAsFile( rsp ) -- true => is file, false => is not, nil => dunno, and is accompanied by msg.
    while( bool:isFalse( sts ) and ( retryCount > 0 ) ) do
        app:logWarning( "Waiting for file, name: " .. name .. ", location: " .. path )
        app:sleepUnlessShutdown( retryDelay )
        sts, msg = self:_existsAsFile( rsp )
        retryCount = retryCount - 1
    end
    return sts, msg
end



--      Synopsis:       Waits for a directory to positively not exist.
--
--      Motivation:     There is room for some error in directory-deletion/existence checking.
--                      This function waits for the dust to settle so calling context doesn't
--                      make any rash decisions.
--
--      Notes:          - Typically called when a directory has been deleted, supposedly successfully - this confirms its deletion.
--                      - Its possible(?) that if I just called lr-ftp functions more blindly they would take care of themselves,
--                        however now that I've got into the game of pre-checking/post-checking, there's no turning back...
--
--      Returns:        - true, nil:                directory certainly gone, no comment.
--                      - false, error message:     can't be certain.
--
function Ftp:_waitForDirToDisappear( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local retryCount = 10
    local retryDelay = 1
    local ret1 = nil
    local ret2 = nil
    repeat
        ret1, ret2 = self:_existsAsDir( rsp )
        if ret1 ~= nil and type( ret1 ) == 'boolean' and ret1 == false then -- existence determined, existence negative.
            return true -- item disappeared.
        end
        app:sleepUnlessShutdown( retryDelay )
        retryCount = retryCount - 1
    until retryCount == 0
    return false, "item wont go away, trouble: " .. str:to( ret2 )
end



--      Synopsis:       Waits for a file to positively not exist.
--
--      Motivation:     There is room for some error in file-deletion/existence checking.
--                      This function waits for the dust to settle so calling context doesn't
--                      make any rash decisions.
--
--      Notes:          - Typically called when a file has been deleted, supposedly successfully - this confirms its deletion.
--                      - Its possible(?) that if I just called lr-ftp functions more blindly they would take care of themselves,
--                        however now that I've got into the game of pre-checking/post-checking, there's no turning back...
--
--      Returns:        - true, nil:                file certainly gone, no comment.
--                      - false, error message:     can't be certain.
--
function Ftp:_waitForFileToDisappear( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local retryCount = 10
    local retryDelay = 1
    local ret1 = nil
    local ret2 = nil
    repeat
        ret1, ret2 = self:_existsAsFile( rsp )
        if ret1 ~= nil and type( ret1 ) == 'boolean' and ret1 == false then -- existence determined, existence negative.
            return true -- item disappeared.
        end
        app:sleepUnlessShutdown( retryDelay )
        retryCount = retryCount - 1
    until retryCount == 0
    return false, "item wont go away, trouble: " .. str:to( ret2 )
end



--      Synopsis:       Remove a directory - whether empty or not. - If directory has subdirectories or files, they will be removed also.
--                      Called recursively to do so.
--
--      Notes:          - You can not remove the root dir.
--                      - This function WILL change the path in ftp-conn (like all functions that are passed a path).
--                      - This function logs deleted directories in verbose mode. - This is a departure from the
--                        "leave logging to calling context" convention. ###4 - Could create a table of removed sub-directories
--                        and files instead.
--
--      Returns:        - true, nil:                directory removed or didn't exist in the first place.
--                      - false, error-message:     failed.
--
function Ftp:_removeDirTree( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local file = self:_setPath( dir )
    app:logVerbose( "Removing remote directory: " .. rsp )
    local sts1, sts2
    local folderTable, fileTable = self:getDirContents( rsp ) -- changes path setting.
    if folderTable == nil then
        return false, fileTable -- ft is qual/err-msg.
    end
    local fname
    for i,v in ipairs( fileTable ) do
        fname = v.leafName
        sts1, sts2 = self:removeFile( rsp .. "/" .. fname )
        if sts1 == true then -- file removed
            app:logVerbose( "Remote file deleted: " .. fname )
        else
            return false, sts2
        end
    end
    for i,v in ipairs( folderTable ) do
        fname = v.leafName
        sts1, sts2 = self:_removeDirTree( rsp .. "/" .. fname )
        if sts1 == true then
            app:logVerbose( "Remote directory deleted: " .. fname )
        else
            return false, sts2
        end
    end
    return self:removeEmptyDir( rsp )
end



--      Synopsis:       Get time as number from *odd components.
--
--      Notes:          - *month component is a string, the rest are numbers.
--                      - Note: could translate month in calling context and call
--                        lr-date function from there as well.
--
function Ftp:_getTime( year, _month, day, hour, minute, second )
    if monthTable == nil then
        monthTable = {}
        monthTable["Jan"] = 1
        monthTable["Feb"] = 2
        monthTable["Mar"] = 3
        monthTable["Apr"] = 4
        monthTable["May"] = 5
        monthTable["Jun"] = 6
        monthTable["Jul"] = 7
        monthTable["Aug"] = 8
        monthTable["Sep"] = 9
        monthTable["Oct"] = 10
        monthTable["Nov"] = 11
        monthTable["Dec"] = 12
    end
    local month = monthTable[_month]
    -- return DateTimeUtils.getTime( year, month, day, hour, minute, second ) - works
    return LrDate.timeFromComponents( year, month, day, hour, minute, second, 0 ) -- does exactly same thing.
end



--		Synopsis:			Parse a directory entry that is assumed to be in windows format, for example:
--
--									02-12-10  04:13AM       <DIR>          1980s (4 tokens)
--
--		Notes: 				See calling context header for more info.
--
--      Returns:            type-val (never nil), date-time, leaf-name, size
--                  OR      nil, error message.
--
function Ftp:_parseWindowsDirEntry( dirEntry )
    --Debug.pause( "What is the date format?", dirEntry ) -- 
    local tokens = str:tokenize( dirEntry, 4 ) -- returns tokens 1-4, where 4th token is the remainder.
	local dateStr = tokens[1]
    local timeStr = tokens[2]
	local typeStr = tokens[3]
	local nameStr = tokens[4]
	local sizeStr
	local typeVal
	if typeStr == "<DIR>" then
		typeVal = 'D'
		sizeStr = nil
	else
		-- app:logInfo( "assuming file: " .. typeStr ) -- will be a number.
		typeVal = 'f'
		sizeStr = typeStr
	end

	local year, month, day = date:parseMmDdYyDate( dateStr )
	if type( year ) == 'string' then
		return nil, str:fmtx( "Unable to parse date returned by server as part of dir listing entry - ^1", year )
	end

	local hour, minute = date:parseHhMmAmPmTime( timeStr )
	if type( hour ) == 'string' then
		return nil, str:fmtx( "Unable to parse time returned by server as part of dir listing entry - ^1", hour )
	end

	local leafName = nameStr

	-- app:logInfo( LOC( "$$$/X=parsed windows date-time: ^1-^2-^3  ^4:^5", year, month, day, hour, minute ) )

	local datetime = LrDate.timeFromComponents( year, month, day, hour, minute, 0, 0 ) -- first zero => second, second zero => UTC offset in seconds for time-zone.
		-- note: it does not matter what UTC offset is, since we don't care whether the time is right - whatever might get added when we calibrate will get subtracted
		-- when we compute difference in local versus remote timestamp.

    local size = num:numberFromString( sizeStr ) -- robustly handles nil, null, and non-numbers...
        
	return typeVal, datetime, leafName, size

end



--      Synopsis:       Parse a directory entry as returned by get-file-contents - may be unix or windows format.
--
--      Example dirEntries:
--
--                      Unix:       drwxrwxr-x   3 rcole    rcole        4096 Aug 25 21:46 LrFlashGalleries (9 tokens)
--
--                      Windows:    Once upon a time, it appeared to return same format as unix, much to my surprise!
--									Now, it seems to be in this format:
--
--									02-12-10  04:13AM       <DIR>          1980s (4 tokens)
--
--      Returns values: 1 - type:       'D' - directory, 'f' - file, nil - COULD HAPPEN?
--                      2 - date-time:  number
--                      3 - leaf-name:  directory or file name, excluding path, including extension.
--                      4 - size (may be nil?)
--
--          OR
--                      1 - nil
--                      2 - error message.
--
--      Notes:          *** If dir entry format changes, so must this function.
--
function Ftp:_parseDirEntry( dirEntry )

	-- app:logInfo ("dir entry: " .. dirEntry )

    local tokens = str:tokenize( dirEntry, 2 )
    local typeString = tokens[1]
    local typeVal
    if str:is( typeString ) then
        local firstChar = str:getChar( typeString, 1 )
        if firstChar == 'd' then
            typeVal = 'D'
        elseif firstChar == '-' then
            typeVal = 'f'
        else -- assume windows format
            return self:_parseWindowsDirEntry( dirEntry ) -- warning, last tokens need to be reconstituted into a string.
        end
    else
        typeVal = nil -- *** COULD RETURN NIL, & ... (NO ERRM).
    end
	-- I think the reason I didn't move this code to date-time utils is that it is only likely to be seen in this format in a remote directory entry.
    tokens = str:tokenize( dirEntry, 9 ) -- returns tokens 1-9, where 9th token is the remainder.
    local dateString = tokens[8]
    local year, month, day, hour, minute, second
    second = 0
    local colonStarts = 0
    local colonEnds = 0
    if str:is( dateString ) then
        colonStarts, colonEnds = string.find( dateString, ':', 1, true )
        if colonStarts then
            year = _thisYear -- not exactly correct: means it was in the last 180 days, so to detect if that means this-year or last-year, we try this year, and if its in the future, it musta shoulda been last year!
            local hourString = string.sub( dateString, colonStarts - 2, colonStarts - 1 )
            if str:is( hourString ) then
                hour = tonumber( hourString )
                if hour == nil then
                    hour = 0
                end
            else
                hour = 0
            end
            local minuteString = string.sub( dateString, colonEnds + 1, colonEnds + 2 )
            if str:is( minuteString ) then
                minute = tonumber( minuteString )
                if minute == nil then
                    minute = 0
                end
            else
                minute = 0
            end
        else
            if str:is( dateString ) then
                year = tonumber( dateString )
                if year == nil then
                    year = 0
                end
            else
                year = 0
            end
            hour = 0
            minute = 0
        end
    else
        app:logWarning( "Unable to parse date string from dir contents." )
        year = 0
        -- month = "Jan"
        -- day = 1
        hour = 0
        minute = 0
    end
    month = tokens[6] -- uses string
    day = tonumber( tokens[7] )

    local timeVal = self:_getTime( year, month, day, hour, minute, second )
    if colonStarts then
        local rightNow = LrDate.currentTime()
        if (timeVal - 720) > rightNow then -- if file timestamp is in the future, it musta shoulda been last year - so make correction - 2 minute fudge factor just for grins :-)
            timeVal = self:_getTime( year - 1, month, day, hour, minute, second )
        end
    end

    local size = num:numberFromString( tokens[5] ) -- *** this so far untested, need unix server to test.

    local leafName = tokens[9]
    return typeVal, timeVal, leafName, size
end





--------------------
-- Public functions:
--------------------



--- Static equivalent of query-for-password-if-needed method.
--
function Ftp.assurePassword( ftpSettings, ftpPropertyMap )
    return Ftp.queryForPasswordIfNeeded( {}, ftpSettings, ftpPropertyMap ) -- method could have been static originally, but wasn't.
end



--- Serves same purpose as Lr-FTP version - prompt user for password if not provided in the settings.
--  <p>
--      Motivation:     Lightroom's version just says "gimme a password" without stating what the password is for.
--                      This is one of my all time pet peeves in modern software - I suppose if you are the kind
--                      of person that uses the same password for everything and dont care what its for when you
--                      are asked for one, it doesn't much matter - I am not that kind of person.
--
--                      Its completely unacceptable for Photooey since passwords may be needed for two different servers.
--  </p>
--
--  @param      ftpSettings (table, required) can be user-created lua table (as long as required members are present),<br>
--                          or that created by binding to make-ftp-preset-popup.
--
--  @usage This function indicates the password request is for ftp user on specified server.
--  @usage Use in conjunction with view--observe-Ftp-Property-Changes, since it will set up the encrypted password store.
--  @usage This function can be called as object method or dot-function (static).
--
--  @return     ok (boolean) true iff valid password entered.
--
function Ftp:queryForPasswordIfNeeded( ftpSettings, ftpPropertyMap )

    --[[ Note: this rather unconventional function allows this method to be called as method with ftp-settings, or static function.
    *** this became broken with 2nd parameter added - now obsolete, saved as reminder..
    local s, m = pcall( function()
        if ftpSettings == nil then
            assert( self ~= nil, "no ftp settings" )
            if self.server ~= nil then -- called as static function
                return self -- return ftp-settings as passed into static function.
            else -- had better by called as method relying on member ftp-settings.
                assert( self.ftpSettings ~= nil, "no ftp settings" )
                return self.ftpSettings
            end
        else -- called as method with specified ftp-settings.
            return ftpSettings
        end
    end )
    if s then
        ftpSettings = m
    else
        app:error( "unable to obtain ftp settings" )
    end
    --]]
    
    -- the new way (@17/Mar/2014 18:22):
    ftpSettings = ftpSettings or self.ftpSettings or app:callingError( "no ftp settings" )

    ftpPropertyMap = ftpPropertyMap or {
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
    assert( str:is( ftpSettings[ftpPropertyMap.server] ), "Bad ftp settings - no server." )

    local password
    local name = str:fmt( "^1_^2_ftp", ftpSettings[ftpPropertyMap.server], ftpSettings[ftpPropertyMap.username] ) -- server, user, protocol-type.
    local unencrypted = LrPasswords.retrieve( name )
    local plain = ftpSettings[ftpPropertyMap.password]
    --Debug.pause( ftpPropertyMap.password, plain, ftpSettings )
    
    if str:is( plain ) and not str:is( unencrypted ) then
        password = plain
        app:logWarning( "Accepting plain password, since encrypted store has no entry for server-username combo. Recommend encrypting password." )
    elseif str:is( unencrypted ) and not str:is( plain ) then
        password = unencrypted
        app:logVerbose( "Accepting encrypted password for server-username combo." )
    elseif str:is( plain ) and str:is( unencrypted ) then -- both
        if plain == unencrypted then
            app:logWarning( "Encrypted password same as password stored in plain text - recommend clearing the plain text one." )
            password = unencrypted
        else
            -- app:logWarning( "Ambiguous password entries: encrypted password and another from preset stored in plain text - warrants a prompt... - to remedy, I suggest blankening the plain text password, once the encrypted password is correct." )
            app:logWarning( "Ambiguous password entries: encrypted password and another from preset stored in plain text - plain text password supercedes. Consider encrypting plain text password." )
            password = plain -- ### this may be problematic for plugins still using method pre 15/May/2012 4:51. Do I have any such unconverted plugins?
        end
    else -- neither
        app:logVerbose( "No password stored for server-username combo - prompting..." )
    end
    
    if str:is( password ) then
        ftpSettings[ftpPropertyMap.password] = password
        return true
    end

    local ok
    LrFunctionContext.callWithContext( "Query for Password If Needed", function( context )

        local props = LrBinding.makePropertyTable( context )
        props.password = ''
        props.encrypt = true

        local c = { vf:column {
			spacing = vf:dialog_spacing(),
            vf:row {
                vf:static_text {
        			title = str:fmt( "Server: ^1", ftpSettings[ftpPropertyMap.server] ),
                },
            },
            vf:row {
                vf:static_text {
        			alignment = "left",
        			title = "FTP Password: ",
                },
                vf:password_field {
                    bind_to_object = props,
                    immediate = true, -- ###3 - probably required for password to take without tabbing out on Mac(?)
                    value = bind 'password',
                    width_in_chars = 15,
                },
            },
            vf:spacer{ height = 1 },
            vf:column {
                spacing = vf:label_spacing(),
                vf:checkbox {
                    bind_to_object = props,
                    title = 'Store encrypted for future - you will have to',
                    tooltip = 'Encryption mechanism depends on operating system, and is recommended...',
                    value = bind 'encrypt',
                },
                vf:static_text {
                    title = "use the Publishing Manager to change."
                },
            },
        }}
        
        repeat
            local answer = app:show{ confirm="Enter password for user ^1",
                subs = ftpSettings[ftpPropertyMap.username],
                viewItems = c,
                -- additional acc-items not supported.
                buttons = { dia:btn( "OK", 'ok' ) },
            }
            if answer == 'ok' then
                if str:is( props.password ) then
                    if props.encrypt then
                        LrPasswords.store( name, props.password )
                    else
                        LrPasswords.store( name, "" ) -- maybe should store 'nil'? ###3
                    end
                    ftpSettings[ftpPropertyMap.password] = props.password
                    ok = true
                    break
                else
                    app:show{ warning="Password can not be blank." }
                end
            else
                ok =  false
                break
            end
        until false
            
    end )
    
    return ok
    
end



---     Synopsis:       Determines if file exists, and will double-check if no expectation,
--                      waits for it to disappear if its supposed to be gone (like when it
--                      was just deleted), or waits for it to be present if expected to be
--                      there (like if it was just put out there, or detected via get-dir-contents...).
--      
--
--      Returns:        - true, nil: file exists, for sure.
--                      - false, nil: file does not exist, for sure.
--                      - nil, error-message: uncertain, see error message.
--
function Ftp:existsAsFile( rsp, expected )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    if expected ~= nil then
        assert( type( expected ) == 'boolean', "expected not boolean" )
    end
    local existsAsFile, orNot = self:_existsAsFile( rsp )
    if existsAsFile ~= nil then -- answer definitive
        if existsAsFile == true then
            if expected ~= nil then
                if expected then
                    return true
                else
                    local sts1, sts2 = self:_waitForFileToDisappear( rsp )
                    if sts1 then -- item gone
                        return false
                    else
                        return true
                    end
                end
            else -- no expectations
                existsAsFile, orNot = self:_existsAsFile( rsp ) -- return second stab, since it may be more accurate than first stab.
                return existsAsFile, orNot
            end
        else -- file does not seem to exist.
            if expected ~= nil then
                if expected then
                    local sts1, sts2 = self:_waitForFile( rsp )
                    return sts1, sts2 -- wait
                else
                    local sts1, sts2 = self:_waitForFileToDisappear( rsp )
                    if sts1 then -- item gone
                        return false
                    else
                        return true
                    end
                end
            else -- no expectations.
                existsAsFile, orNot = self:_existsAsFile( rsp ) -- return second stab, since it may be more accurate than first stab.
                return existsAsFile, orNot
            end
        end
    else -- unable to ascertain files existence.
        if expected ~= nil then
            if expected then
                local sts1, sts2 = self_waitForFile( rsp )
                return sts1, sts2
            else
                local sts1, sts2 = self:_waitForFileToDisappear( rsp )
                if sts1 then -- item gone
                    return false
                else
                    return true
                end
            end
        else -- no expectations.
            existsAsFile, orNot = self:_existsAsFile( rsp ) -- return second stab, since it may be more accurate than first stab.
            return existsAsFile, orNot
        end
    end
end



---     Synopsis:       Determines if dir exists, and will double-check if no expectation,
--                      waits for it to disappear if its supposed to be gone (like when it
--                      was just deleted), or waits for it to be present if expected to be
--                      there (like if it was just put out there, or detected via get-dir-contents...).
--
--      Returns:        - true, nil: dir exists, for sure.
--                      - false, nil: dir does not exist, for sure.
--                      - nil, error-message: uncertain, see error message.
--
function Ftp:existsAsDir( rsp, expected )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local dirExists, orNot = self:_existsAsDir( rsp )
    if dirExists ~= nil then -- answer definitive
        if dirExists == true then -- directory seems to exist
            if expected ~= nil then
                assert( type( expected ) == 'boolean', "expected parameter should be boolean" )
                if expected then
                    return true
                else
                    local sts1, sts2 = self:_waitForDirToDisappear( rsp )
                    if sts1 then -- item gone
                        return false
                    else
                        return true
                    end
                end
            else -- no expectations
                dirExists, orNot = self:_existsAsDir( rsp ) -- return second stab, since it may be more accurate than first stab.
                return dirExists, orNot
            end
        else -- dir does not seem to exist.
            if expected ~= nil then
                assert( type( expected ) == 'boolean', "expected parameter should be boolean 2" )
                if expected then
                    local sts1, sts2 = self:_waitForDirectory( rsp )
                    return sts1, sts2
                else
                    local sts1, sts2 = self:_waitForDirToDisappear( rsp )
                    if sts1 then -- item gone
                        return false
                    else
                        return true
                    end
                end
            else -- no expectations.
                dirExists, orNot = self:_existsAsDir( rsp ) -- return second stab, since it may be more accurate than first stab.
                return dirExists, orNot
            end
        end
    else -- unable to ascertain dir existence.
        if expected ~= nil then
            assert( type( expected ) == 'boolean', "expected parameter should be boolean 3" )
            if expected then
                local sts1, sts2 = self:_waitForDirectory( rsp )
                return sts1, sts2
            else
                local sts1, sts2 = self:_waitForDirToDisappear( rsp )
                if sts1 then -- item gone
                    return false
                else
                    return true
                end
            end
        else -- no expectations.
            dirExists, orNot = self:_existsAsDir( rsp ) -- return second stab, since it may be more accurate than first stab.
            return dirExists, orNot
        end
    end
end



---     Synopsis:       Create a full path to a remote directory from parent and child sub-paths.
--
--      Notes:          This function takes a root-dir-path and sub-dir-path and returns
--                      a full-path to a dir for ftp purposes.
--      
--                      Preferred over lightroom's version when you dont want to run the risk of a slash prefixed child-path
--                      being interpreted as an absolute path, instead of a relative path. Also, makes sure input paths are
--                      interpreted correctly regardless of source path origins (e.g. local windows dir that contains backslashes),
--                      and makes sure result path is properly formatted for FTP, meaning only forward slashes, no backslashes.
--                  
--                      Reminder: the Lr-Ftp function only checks if child-path begins with a forward slash,
--                      and if so root-path is ignored. It interprets backslash prepended child-paths as true children.
--                      Also, although Lr-Ftp is
--                      surprisingly tolerant of appending windows backslashed paths to traditionaly ftp forward
--                      slashed paths, I prefer the asthetic of properly formatted ftp paths, and in so doing, this function may
--                      even prevent a bug in the future.
--
--      Returns:        Full path, no excuses, trailing slash. - No guarantee its to a real directory: garbage in = garbage out.
--
function Ftp:_makeDirPath( rsp )
    assert( rsp ~= nil, "no sub-path to make-dir-path" )
    local childPath = str:replaceBackSlashesWithForwardSlashes( rsp )
    local firstChar = str:getFirstChar( childPath )
    if firstChar == '/' then
        childPath = childPath:sub( 2 ) -- bypass the starting slash, since we want this interpreted as a sub-path, not a root-path.
    -- else good
    end
    return LrFtp.appendFtpPaths( self.rootPath, childPath ) -- this makes sure there's a trailing slash at the end, and one separator between.
        -- Best not to muck with the front of root-path, since it may have a drive spec.
end



---     Synopsis:       Creates a full path to a remote file from parent and child components.
--
--      Notes:          Uses dir-path function to assure leading slash, one sep, and trailing slash,
--                      then removes the trailing slash to turn it into a file reference.
--
--      Returns:        Full path, no excuses, no trailing slash.  - No guarantee its to a real file: garbage in = garbage out.
--
function Ftp:_makeFilePath( rsp )
    local dirPath = self:_makeDirPath( rsp ) -- guaranteed to end with a slash.
    return string.sub( dirPath, 1, string.len(dirPath) - 1 ) -- remove trailing slash to convert to file reference.
end    



---     Synopsis:       Removes a file which is presumably (although not necessarily) existing before calling.
--
--      Notes:          file-path - presumably already in the proper format (hint: use make-file-path).
--
--      Returns:        - true: file removed, or was never there.
--                      - false, error message: file not removed, reason.
--
function Ftp:removeFile( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local sts, qual = self:_pRemoveFile( rsp )
    if sts then -- call completed
        local v1, v2 = self:existsAsFile( rsp, false ) -- false => expect file not to exist.
        if v1 ~= nil then -- answer definitive
            -- v2 suppossedly nil when answer definitive.
            if v1 then -- answer afirmative
                return false, LOC( "$$$/X=Unable to confirm remote file (^1) removal from (^2).", name, path ) -- unconditional failure
            else -- answer negative
                return true -- unconditional success
            end
        else
            return false, LOC( "$$$/X=Some problem removing remote file (^1) from (^2), error message: ^3", name, path, str:to( v2 ) )
        end
    else
        return false, LOC( "$$$/X=Unable to complete remote file (^1) removal from (^2), more: ^3", name, path, qual )
    end
end



---     Synopsis:       Removes a directory known to exist and be empty.
--
--      Notes:          - dir-path - presumably already in the proper format (hint: use make-dir-path).
--                      - first return value will never be nil.
--                      - Tries 3 times with 1 second between. My experience is that if you've just deleted the last file, then the first attempt at removing the directory may fail.
--      
--      Returns:        - true, nil -- worked, no issues.
--                      - false, msg -- maybe didnt work, warning or error message.
--
function Ftp:removeEmptyDir( rsp )

    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local sts, msg
    for try = 1, 3 do
        local path = self:_setPath( dir )
        local status, qualification = self:_pRemoveEmptyDirectory( rsp )
        if status then -- protected function completed without an error being thrown.
            local s1, s2 = self:existsAsDir( rsp, false ) -- false => expect directory to not exist.
            if s1 ~= nil then -- determination definitive
                if s1 then -- affirmative
                    sts, msg = false, str:fmt( "Unable to remove remote dir (^1) from (^2), which is supposedly empty.", name, path )
                else
                    if try ~= 1 then
                        return true, str:fmt( "Removed empty directory (^1) from (^2) on try #^3", name, path, try ) -- worked after at least one retry.
                    else
                        return true
                    end
                end
            else
                sts, msg = false, LOC( "$$$/X=Unable to asertain if remote dir (^1) was removed from (^2), more: ^3", name, path, str:to( s2 ) )
            end
        else
            sts, msg = false, LOC( "$$$/X=Unable to complete remote dir removal of (^1) from (^2), which is supposedly empty, more: ^3", name, path, qualification )
        end
        app:sleep( 1 ) -- give server a second
        if shutdown then break end
    end
    return sts, msg
end



---     Synopsis:       Remove a directory tree, which typically (although not necessarily) pre-exists, including sub-dir & files.
--
--      Note:           - You can not remove the root dir.
--                      - first return value is never nil.
--
--      Returns:        - true, nil:                removed, or wasnt there to begin with, no comment, no distinction.
--                      - false, error-message:     cant, and here's why...
--
function Ftp:removeDirTree( rsp )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local v1, v2 = self:existsAsDir( rsp ) -- unfortunately, as presently coded, dunno whether to expect it or not.
    if v1 ~= nil then -- determination definitive
        if v1 then -- affirmative
            -- keep going
        else
            return true -- nothing to remove
        end
    else -- cant determine if there's a directory to remove or not.
        -- at this point, wont hurt to give it a whack anyway.
        app:logWarning( "Unable to ascertain if directory (^1) exists to be removed from (^2), gonna try anyway..., more: ^3", name, path, str:to( v2 ) )
    end
    local sts1, sts2
    if str:is( rsp ) and ( rsp ~= '/') and ( rsp ~= '\\') then -- now that this is a subpath
        -- to the root, its conceivably OK to delete the whole thing, still it makes me very nervous, so this
        -- stands unless it causes a problem.
        return self:_removeDirTree( rsp ) -- logs files and dirs removed in verbose mode.
    else
        return false, str:fmt( "Cant remove root dir (^1) from (^2): ", name, path )
    end
end



---     Synopsis:       Create directories if not already, up to and including the leaf of specified path.
--
--      Notes:          - path must be to folder, not file.
--                      - departs from the "leave logging to calling context" convention by logging
--                        all dirs created or pre-existing if verbose mode. Idea: could make a table
--                        and return to caller.
--
--      Returns:        - true, nil:              worked, no comment.
--                      - true, comment:          pretend it worked, see comment.
--                      - false, error-message:   failed.
--
function Ftp:assureAllRemoteDirectories( rsp )
    local ftpConn = self.ftpConn
    -- local dir, name = self:_getDirAndName( rsp )
    local dir = rsp
    local name = "not assigned"
    local children = {}
    repeat
        if str:is( dir ) then -- if we havent spun above the root yet.
        
            if dir == "/" then
                app:logVerbose( "Assuming root dir exists." )
                break
            end
        
            local v1, v2 = self:_existsAsDir( dir )
            if v1 ~= nil then -- results are definitive
                -- v2 is nil.
                if v1 == true then -- dir exists.
                    app:logVerbose( "Remote directory already exists: " .. dir )
                    break
                elseif v1 == false then -- dir does not exist.
                    app:logVerbose( "Remote directory does not already exist: " .. dir )
                    children[#children + 1] = dir
                else
                    error( "non-nil value not true nor false returned from dir-exists function." )
                end
            else
                -- v2 has more.
                return false, LOC( "$$$/X=Unable to create remote directory: ^1, more: ^2", rsp, str:to( v2 ) )
            end
        else
            -- return false, LOC( "$$$/X=Unable to create remote directory: ^1", rsp ) - commented out 15/May/2012, since it was preventing files from being uploaded to root dir.
            -- remove warning comments if still OK come 2014.
            app:logVerbose( "Assuming default dir exists." ) -- First test @15/May/2012 - seems to be OK.
            break
        end            
        
        dir, name = self:_getDirAndName( dir )
        
    until false -- until break or error/return.
    local index = #children
    for index = #children, 1, -1 do
        local dir = children[index]
        local sts, qual = self:_makeDirectory( dir )
        if sts then -- call completed - either worked or I should pretend like it did.
            app:logVerbose( "Created remote dir: " .. dir )
        else
            return false, LOC( "$$$/X=Unable to create remote directory, parent: ^1, more: ^2", dir, qual )
        end
    end
    -- check:
    local result, errorMessage = self:existsAsDir( rsp, true ) -- true => directory expected to exist.
    if result ~= nil then -- result definitive
        -- error-message nil.
        if result == true then -- result affirmative
            return true -- no comment.
        else
            return false, LOC( "$$$/X=Unable to assure remote directories, path: ^1", rsp )
        end
    else
        -- error message explains
        return false, LOC( "$$$/X=Unable to assure remote directories, path: ^1, more: ^2", rsp, str:to( errorMessage ) )
    end
end
Ftp.assureDir = Ftp.assureAllRemoteDirectories -- function Ftp:assureDir( ... ) -- same as make-dir, just having a name with a different spin..



---     Synopsis:       Create a remote directory, if not already existing.
--
--      Notes:          Creates parent directories as necessary.
--
--      Returns:        - true, nil:            worked, no comment, no distinction.
--                      - true, comment:        pretend like it worked, see comment.
--                      - false, comment:       failed.
--
function Ftp:makeDir( rsp )
    return self:assureAllRemoteDirectories( rsp )
end



--  ###1 @12/Mar/2014 21:13 ftp-settings expects server unmapped.

--- Determine if local file is same as remote file.
--
--  @usage Uses auto-caching of dir contents, which means it's only good for one "run", and @24/Jan/2014 5:09, no way to clear caches, so a new ftp object must be created for each run.
--  @usage @8/May/2012, size is only criteria, by default.
--
--  @param      localFile (string, required) absolute path
--  @param      rsp (string, required) relative subpath
--  @param      options (struct, optional) named options, including:
--                  <br>    dateTol - to set a date tolerance.
--
--  @return     status (boolean) true if same, false if different, nil if undiscernable or error.
--  @return     errm (string) nil if status is true or false or undiscernable, else error message. 
--
function Ftp:isFileSame( localFile, rsp, options )
    options = options or {}
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local dirTable, fileTable
    if not self.dirCache then
        self.dirCache = {}
        self.fileCache = {}
    end
    if not self.dirCache[dir] then
        local errm
        local ofs
        if options.dateTol then
            ofs = Ftp.remoteClockOffset[self.ftpSettings.server] or error( "Remote clock must be calibrated before calling this method." ) -- get-dir-contents returns errm if clock not cal's.
        else
            ofs = Ftp.remoteClockOffset[self.ftpSettings.server] or 0 -- if not interested in date, clock can be un-calibrated, *** BUT: cached dir will not have ANY dates, so one can not mix calls with different options unless clock is pre-calibrated.
        end
        dirTable, fileTable = self:getDirContents( dir, ofs ) -- pass offset explicitly, to assure we get a dir listing even if clock not calibrated, as long as date-tol is a don't care.
        if dirTable then
            self.dirCache[dir] = dirTable
            self.fileCache[dir] = fileTable
        else
            -- Debug.pause()
            return nil, fileTable -- errm
        end
    else
        dirTable = self.dirCache[dir]
        fileTable = self.fileCache[dir]
    end
    if fileTable then
        local fileEntry
        for i, v in ipairs( fileTable ) do
            if name == v.leafName then
                fileEntry = v
                break
            end
        end
        if fileEntry then
            if fileEntry.size then
                local attrs = LrFileUtils.fileAttributes( localFile )
                if attrs then
                    local size = attrs.fileSize
                    if size then
                        if size == fileEntry.size then
                            if options.dateTol then -- assure date within tolerance to be considered "same".
                                if ( attrs.fileModificationDate - fileEntry.date ) > options.dateTol then
                                    if app:isAdvDbgEna() then
                                        local server = ( self.ftpSettings or {} )['server'] or 0 -- ###1 unmapped
                                        local offset = num:fmtPrec( Ftp.remoteClockOffset[server] or 0, 3 )
                                        Debug.pause( "date of", fileEntry.leafName, "not within tolerance, local date:", attrs.fileModificationDate, "remote date:", fileEntry.date, "diff:", date:formatTimeDiffMsec( attrs.fileModificationDate - fileEntry.date ), "server:", server, "offset:", offset )
                                    end
                                    return false -- to avoid needless re-uploading, make sure date-tol is set high enough - say 2 or 3 minutes. If you can't afford this much, maybe best to force uploading.
                                else
                                    return true
                                end
                            else
                                return true -- size only
                            end
                        else
                            return false
                        end
                    else
                        return nil, "local file has no size"
                    end
                else
                    return nil, "local file not found: " .. localFile
                end
            else
                -- Debug.lognpp( fileEntry )
                return nil, "remote file has no discernable size"
            end
        else
            return nil, "remote file not found: " .. rsp
        end
    else
        return nil, "dir not found: " .. dir
    end
    error( "not supposed to be here" )
end



---     Synopsis:       Put (upload) a file from local disk to remote.
--
--      Notes:          - If file pre-exists and overwrite OK, existing target will be removed first.
--                      - Directory tree created if necessary to support file.
--                      - This function takes the liberty to do a little verbose logging, plus warnings...
--
--      Returns:        - true, nil:        worked, no comment.
--                      - false, comment:   failed.
--
function Ftp:putFile( localPath, rsp, overwriteOK )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local sts, msg = false, "unknown error"
    for try = 1, 3 do
        repeat
            local path = self:_setPath( dir )
            local r1, r2 = self:existsAsFile( rsp )
            if r1 ~= nil then -- file existence determination definitive
                if r1 then -- affirmative
                    if overwriteOK then
                        app:logVerbose( "Putting local to remote file (^1) and it already exists at (^2), removing for overwrite.", name, path )
                        --Debug.pause( rsp )
                        local x1, x2 = self:removeFile( rsp )
                        if x1 ~= nil then -- definitive
                            if x1 then -- affirmative
                                -- good - fall through.
                            else
                                sts, msg = false, "Unable to remove pre-existing file, error message: " .. str:to( x2 )
                            end
                        else -- trouble
                            sts, msg = false, "Unable to determine if pre-existing file was removed, error message" .. str:to( x2 )
                            break
                        end
                    else
                        sts, msg = false, LOC( "$$$/X=Remote file (^1) already exists at (^2), and overwrite not OK.", name, path )
                        break
                    end
                else -- negative
                    app:logVerbose( "File (^1) being put not already existing in ^2", name, path )
                    local sts, qual = self:assureAllRemoteDirectories( dir )
                    if sts then -- call completed
                        -- could check qual here.
                    else
                        sts, msg = false, LOC( "$$$/X=Unable to assure remote directories (^1) to put file (^2) into: ^3", path, name, qual )
                        break
                    end
                end
            else
                sts, msg = false, str:fmt( "unable to ascertain whether file (^1) already exists or not at (^2): ", name, path )
                break
            end
            local d1, d2 = self:existsAsDir( dir, true ) -- even if return codes are being ignored this may still be doing something worthwhile.
            if app:isDebugEnabled() then
                if d1 ~= nil then -- answer definitive
                    if d1 == true then -- answer affirmative
                        -- good
                    else
                        app:logWarning( LOC("$$$/X=Target dir (^1) should exist before putting file (^2): ^3", path, name, str:to( d2 ) ) )
                    end
                else
                    app:logWarning( LOC("$$$/X=Unable to ascertain if target dir (^1) exists before putting file (^2), more: ^3", path, name, str:to( d2 ) ) )
                end
            end
            local f1, f2 = self:existsAsFile( rsp, false ) -- even if return codes are being ignored this may still be doing something worthwhile.
            if app:isDebugEnabled() then
                if f1 ~= nil then -- answer definitive
                    if f1 == true then -- answer affirmative
                        app:logWarning( LOC("$$$/X=Remote file (^1) at (^2) should have been pre-removed before putting local file (^3), more: ^4", name, path, localPath, str:to( f2 ) ) )
                    else
                        -- good
                    end
                else
                    app:logWarning( "Unable to ascertaining if remote file (^1) exists at (^2) before putting local file (^2), more: ^3", name, path, localPath, str:to( f2 ) )
                end
            end
            sts, msg = self:_putFile( localPath, rsp ) -- do it anyway - better to try and fail than not try - often it succeeds even if pre-checks dont - go figure.
            if sts then
                return true
            end
        until true
        -- fall-through => not successfully put.
        app:logVerbose( "Unable to put file after ^1, qualification: ^2", str:plural( try, "try", true ), msg )
        app:sleep( 1 ) -- give server/connection a second to adjust it's attitude...
        if shutdown then break end
    end -- for try loop
    return sts, msg
end


--- Upload file (re-writing remote file if necessary), and optionally: validate.
--
--  @param      localPath       local path
--  @param      rsp             remote path
--  @param      validate        nil or 'no', 'size', or 'full'.
--
function Ftp:uploadFile( localPath, rsp, validate )
    local s, m = self:putFile( localPath, rsp, true ) -- overwrite implied - retries are built in.
    if s then
        if validate == nil or validate == 'no' then
            return true
        elseif validate == 'size' then
            local same, hope = self:isFileSame( localPath, rsp, {} ) -- without date-tol option, validation is via size only.
            if same then
                dbgf( "Remote file same size as local uploaded file - validated." )
                return true
            else
                return false, hope
            end
        elseif validate == 'full' then
            -- ###2 this should probably be moved to is-file-same as an option (with retries?).
            local lc, er = fso:readFile( localPath )
            if lc and not er then
                local c, m = self:getFileContents( rsp )
                if c == nil then
                    assert( str:is( m ), "no m" )
                    return false, m
                else
                    if lc == c then
                        dbgf( "Contents match: ^1 bytes - files are same, exactly.", #c )
                        return true
                    elseif str:is( er ) then
                        return false, er
                    else
                        return false, "Uploaded file has different contents than remote file."
                    end
                end
            else
                return false, er or "unable to read local file"
            end
        else
            app:error( "invalid value for validate: ^1", validate )
        end
    else
        return false, m
    end
end



---     Synopsis:       Get lists of directories and files in the specified remote directory.
--
--      Returns:        two arrays of directory elements (one for directories, one for files) whose entries are structs containing:
--
--                          - leafName: string
--                          - date: last-mod date-time, expressed as a number of seconds since midnight GMT, January 1, 2001 (same as local files ala lr-file-utils).
--                          - size (applies to both dirs & files).
--      
--                      Returns empty tables if directory empty.
--
--                      Returns nil & error message if probs.
--
--      Side Effects:   - Will change path in ftp-conn.
--
--      Notes:          Usually only called when directory known to exist - not sure what happens if it doesn't.
--
--      *** IMPORTANT NOTE: Relies on parsing text content of remote directory - may not be compatible with all servers.
--      *** IMPORTANT NOTE: Must NOT be called from calibrate-clock method or there will be an infinite loop. (_get-dir-contents can be called from calib-clock - with underscore).
--
function Ftp:getDirContents( rsp, remoteClockOffset )
    local ftpConn = self.ftpConn
    local dir, name = self:_getDirAndName( rsp )
    local path = self:_setPath( dir )
    local clockOffset
    if remoteClockOffset == nil then
        if Ftp.remoteClockOffset[ftpConn.server] ~= nil then
            -- good to go
            clockOffset = Ftp.remoteClockOffset[ftpConn.server]
        else
            return nil, LOC( "$$$/X=Unable to get directory contents - remote clock not calibrated." )
        end
    else -- pass an explicit value (e.g. 0) if you want to get dir contents without calibrated timestamps.
        clockOffset = remoteClockOffset
    end

    local dirTable = {}
    local fileTable = {}

    local dirEnt = nil
    local s, qual = self:_getDirContents( rsp )
    if s ~= nil and not qual then
    	for line in str:lines( s ) do
            if string.len(line) > 0 then
                dirEnt = {}
                local dirType, dirDateTime, dirLeafName, dirSize = self:_parseDirEntry( line )
                -- _debugTrace( "ftpugdc", "dir leaf name: " .. dirLeafName )
                if dirLeafName then -- parsed
                    assert( type( dirLeafName ) == 'string', "oh boy.." )
                    local startPos, endPos = dirLeafName:find( ".", 1, true )
                    if startPos and endPos == 1 then -- this logic changed RDC 2010-11: used to use starts-with-end-pos string func used to test end-pos > 0 too, but that seems wrong..(?) - dir could have an extension and still be viable, no?
                        -- hidden dir or file - ignore
                    else
                        dirEnt.leafName = dirLeafName
                        dirEnt.date = dirDateTime - clockOffset
                        dirEnt.size = dirSize
                        if dirType == 'D' then
                            dirTable[#dirTable + 1] = dirEnt
                        elseif dirType == 'f' then
                            fileTable[#fileTable + 1] = dirEnt
                        else
                            return nil, str:fmtx( "Unable to parse directory entries of ^1 in ^2", name, path )  -- calling context MUST check for this, to handle unexpected directory response formats.
                        end
                    end
                elseif dirDateTime then
                    Debug.pauseIf( dirType ~= nil or type( dirDateTime ) ~= 'string', "pgm fail.." )
                    return nil, str:fmtx( "Unable to parse directory entries of ^1 in ^2 - ^3", name, path, dirDateTime )  -- calling context MUST check for this, to handle unexpected directory response formats.
                else
                    return nil, str:fmtx( "Unable to parse directory entries of ^1 in ^2 - not sure why..", name, path )  -- calling context MUST check for this, to handle unexpected directory response formats.
                end
            else
                -- ignore blank lines
            end
    	end
    else
        -- I (no longer) assume directory is empty in this case.
        return nil, qual
    end
    return dirTable, fileTable
end



--- Determine if specified directory (remote sub-path) is empty.
--
--  @return status (boolean) nil => error; true => empty; false => not empty
--  @return message (string) if status == nil, explanation.
--
function Ftp:isEmpty( dir )
    local dirTable, fileTable = self:getDirContents( dir )
    if dirTable ~= nil then
        if #dirTable == 0 then
            if #fileTable == 0 then
                return true
            else
                return false
            end
        else
            return false
        end
    else
        return nil, fileTable -- qual
    end
end



--- Allows get-dir-contents to be had, with the caveat that file-time will be uncalibrated.
--
--  @usage Warning: this will affect all instances.
--
function Ftp.uncalibrateClock( server )
    Ftp.remoteClockOffset[server] = 0 -- don't need calibrated clock offset just for deleting and checking if empty, but
end



---     Synopsis:       Computes offset of remote clock from 2001-01-01, GMT.
--
--      Motivation:     FTP, much to my dissatisfaction, uses the remote clock to set the timestamp of uploaded files.
--                      I wish it would set it to the exact value of the local source file. This would solve a lot of
--                      problems, and cause none. But, for some reason, the FTP protocol is like never improved (go figure),
--                      thus we have to keep chugging along with same 'ol same 'ol for better and for worse...
--
--                      The problem is:
--
--                          If the clock at the remote end is slow, and you upload a file immediately after changing it,
--                          it will appear to be out of date already after being uploaded. Throw in differences in time zone,
--                          and daylight savings and the problem worsens - the file may appear out of date all day long, even
--                          after continually uploading, then appear up-to-date the next day without having done anything except wait.
--                          Likewise, and usually a worse problem - if the clock at the remote end is ahead, a recently changed
--                          local file may appear up-to-date forever and never be uploaded.
--
--                      The solution is:
--
--                          Before beginning an ftp session, create a tiny local file and upload it. Read the remote timestamp back
--                          and save the difference between it and local time. This offset can then be applied in the future to 
--                          compute a normalized remote timestamp that is accurate to within a few seconds, instead of 25 hours.
--                          
--      Note:           This function may be called explicitly from outside, which allows logging of results before ftp session begins,
--                      and allows specification of writeable directory to be used for temp filem
--                      but if not - will be called automatically from within - temp file dir will be whatever.
--
--                      My experience has been that true ftp connections are not really made until they needs to be. 
--                      And since this may be the first need, it will fail if remote server is down.
--
--                      If local-dir-for-temp-file is passed in, make sure it's been standardized, since this function won't do it.
--
--      Returns:        - true, nil:            calibrated, no comment.
--                      - false, error-message: failed.
--
function Ftp:calibrateClock( localDirForTempFile, rsp, leaveRemFile )
    local ftpConn = self.ftpConn

    if not str:is( localDirForTempFile ) then
        localDirForTempFile = LrPathUtils.getStandardFilePath( 'temp' )
    else
        -- assume already in standardized format.
    end
    if not str:is( rsp ) then
        rsp = ""
    else
        rsp = Ftp.formatSubPath( rsp ) -- I think the get-dir-contents needs this to *not* be in standard dir-path format (with trailing slash)! ###2
    end
    -- assert( rsp ~= nil, "Remote clock calibration requires dir for remote temp file." ) - cal using root is OK @15/May/2012.

    local prevOffset = Ftp.remoteClockOffset[ftpConn.server]
    Ftp.remoteClockOffset[ftpConn.server] = nil -- as long as the offset is only a minute or less, there's not going to be any problems. The problems
        -- come when the time is off by several minutes, or hours (or more).

    local filename = "___tempFileForRemoteClockOffsetCalibration.txt"
    local localFilePath
    if str:is( localDirForTempFile ) then
        localFilePath = LrPathUtils.child( localDirForTempFile, filename )
    else
        localFilePath = LrFileUtils.resolveAllAliases( filename )
    end
    local remoteFilePath
    if str:is( rsp ) then
        remoteFilePath = rsp .. "/" .. filename
    else
        remoteFilePath = filename -- uploading to root allowed @15/May/2012.
    end
    local s = "This file should be deleted."
    local status, qualification, message
    status, qualification = fso:writeFile( localFilePath, s )
    if status then -- file actually written.

        app:logInfo( LOC( "$$$/X=Putting local temp file (^1) to remote file (^2) for remote clock calibration.", localFilePath, remoteFilePath ) )
        status, message = self:putFile(localFilePath, remoteFilePath, true ) -- true => overwrite-ok.

        if status and not message then -- file put correctly, which means remote server is alive...
            local fileAttrs = LrFileUtils.fileAttributes( localFilePath )
            local localTime = fileAttrs.fileModificationDate -- seems it would be better to use present/now time, no??? (I believe I already considered this - but correctly?)

            local contents, qual = self:_getDirContents( rsp ) -- same path as file put.

            if contents ~= nil and not qual then

            	for line in str:lines( contents ) do
                    if string.len(line) > 0 then
                        local dirType, dirDateTime, dirLeafName = self:_parseDirEntry( line ) -- 4th return value (size) ignored.
                        if dirLeafName then
                            assert( type( dirLeafName ) == 'string', "crud.." )
                            if dirLeafName == filename then
                                local newOffset = dirDateTime - localTime
                                if prevOffset ~= nil and prevOffset ~= 0 then
                                    Debug.pauseIf( not num:isWithin( newOffset, prevOffset, 60 ), "previous offset:", prevOffset, "new offset:", newOffset, "diff:", newOffset-prevOffset )
                                end
                                if newOffset > ( 3600 * 25 ) then -- more than 24 hours difference in local time vs. remote time - hmm...
                                    Ftp.remoteClockOffset[ftpConn.server] = 0
                                    status = false
                                    qualification = str:fmtx( "Remote clock uncalibrated - remote timestamp (^1) parsed from server dir listing is too different (^2 hours) than local timestamp (^3).", dirDateTime, newOffset / 3600, localTime )
                                else
                                    Ftp.remoteClockOffset[ftpConn.server] = newOffset
                                    app:logInfo("\nRemote Clock calibrated, server: " .. str:to( ftpConn.server ) .. ", offset: " .. str:to( Ftp.remoteClockOffset[ftpConn.server] ) )
                                end
                                break
                            -- else keep going..
                            end
                        elseif dirDateTime then
                            Debug.pauseIf( dirType ~= nil or type( dirDateTime ) ~= 'string', "afu.." )
                            app:logW( "Unable to parse dir entry - ^1", dirDateTime )
                        else
                            app:logW( "Unable to parse dir entry - not sure why.." )
                        end
                    else
                        -- ignore blank lines
                    end
                end
                if Ftp.remoteClockOffset[ftpConn.server] == nil then -- all errors are caught in the same net here.
                    -- this is the one error that is considered fatal, since it means we can't properly parse directory
                    -- contents of the server.
                    error( "****** Remote clock uncalibrated - remote dir content maybe not parsed correctly." )
                        -- most of the apps that use this module will not work correctly if remote clock not calibrated correctly,
                        -- and or remote dir contents can not be parsed correctly, so might as well die here.
            	end
            else
                status = false
                qualification = "Remote clock uncalibrated - bad response from server for directory request: " .. str:to( qual )
                Ftp.remoteClockOffset[ftpConn.server] = 0
            end

            if not leaveRemFile then
                local s, m = self:_pRemoveFile( remoteFilePath ) -- remove remote cal file.
                if not s then
                    app:logWarning( "Unable to remove remote calibration file: ^1, error message: ^2", remoteFilePath, str:to( m ) )
                end
            else
                app:logV( "Leaving remote file for calling context cleanup: ^1", remoteFilePath )
            end

        else -- error writing remote file.
            Debug.pause( message )
            status = false
            qualification = LOC( "$$$/X=Remote clock uncalibrated - ^1", str:to( message ) )
            Ftp.remoteClockOffset[ftpConn.server] = 0
        end

        local s, m = fso:deleteFile( localFilePath ) -- local file was actually written - discard. Reminder: lr-file-utils delete function may not return an error message.
        if not s then
            app:logWarning( "Unable to remove local calibration file: ^1, error message: ^2", localFilePath, m ) -- fso will always return a message.
        end

    else -- failed.
        Ftp.remoteClockOffset[ftpConn.server] = 0 -- calling context can try to proceed,
        status = false -- or not.
        qualification = LOC( "$$$/X=Remote clock uncalibrated - local dir probably not set correctly - ^2 must be writeable. More: ", localFilePath, qualification )
    end
    return status, qualification, remoteFilePath
end



--- Static function to format a sub-path - assures ftp slash convention (forward) and removes leading and trailing slashes.
--
function Ftp.formatSubPath( p, trailingSlashOk )
    if not str:is( p ) then return "" end
    local t = str:replaceBackSlashesWithForwardSlashes( p )
    local c1 = t:find( '/' )
    if c1 == 1 then
        c1 = 2 -- remove leading slash.
    else
        c1 = 1
    end
    local c2 = str:getLastIndexOf( t, '/' )
    if c2 == t:len() then
        if trailingSlashOk then
            c2 = t:len()
        else
            c2 = t:len() - 1 -- remove trailing slash.
        end
    else
        c2 = t:len()
    end
    return t:sub( c1, c2 )
end



--- Static function to format a server path.assures ftp slash convention (forward). optional leading slash will determine whether remote path is absolute or relative to server default.
--
--  @usage Assures ftp slash convention (forward). optional leading slash will determine whether remote path is absolute or relative to server default.<br>
--         Trailing slash is preserved, but should not have any effect.
--
function Ftp.formatPath( p )
    if not str:is( p ) then return "" end
    return str:replaceBackSlashesWithForwardSlashes( p )
end


return Ftp
