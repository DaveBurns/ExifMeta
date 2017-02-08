--[[
        ImageMagick.lua
        
        Represents ImageMagick's assembly of utilities.
        
        Note: this class is not derived from external app (nor are the mogrify & convert utils it embodies).
        
        *** Instructions:
            - Init global class variable 'ImageMagick'.
            - Init global object instance 'imageMagick'.
            - Assure pref is init in manager.
            - Assure property change detection.
            - Assure configuration UI.
            - If app is required for core functionality, call imageMagick:checkConfig() to get status and error-message. @19/Dec/2013, those can be passed to app-done so warning is displayed after init.
--]]


local ImageMagick, dbg, dbgf = Object:newClass{ className = 'ImageMagick', register = true }



--- Constructor for extending class.
--
function ImageMagick:newClass( t )
    return Object.newClass( self, t )
end



-- Note: although it's called "Utility" at the moment, it really means "Convert" or "Mogrify" utility (i.e. base class for those two).
local Utility = Object:newClass{ className='ImageMagickUtility', register=false }
-- no class extender, since it's an internal (private) class.
function Utility:new( t )
    return Object.new( self, t )
end
local Convert = Utility:newClass{ className='ImageMagickConvert', register=false } -- could use less qualified name, but until competing class is fully deprecated...
function Convert:new( t )
    return Utility.new( self, t )
end
local Mogrify = Utility:newClass{ className='ImageMagickMogrify', register=false } -- ditto
function Mogrify:new( t )
    return Utility.new( self, t )
end



--- Constructor for new instance.
--
--  @usage pref name for app-dir is hard-coded: 'imageMagickDir'.
--
function ImageMagick:new( t )
    local o = Object.new( self, t )
    o:loadExeAppDir()
    o.conv = Convert:new()
    o.mog = Mogrify:new()
    return o
end


-- 
function ImageMagick:loadExeAppDir()
    self.exeAppDir = nil
    local imDir = app:getPref( 'imageMagickDir' ) -- or app:getGlobalPref( 'imageMagickDir' ) - not a good idea to mix these up: otherwise one can hide the other and make for confusing bugnomalies..
    if str:is( imDir ) then -- user has configured something for it.
        self.exeAppDir = imDir -- keep even if wrong.
    else -- free to recompute..
        if WIN_ENV then
            for path in LrFileUtils.directoryEntries( "C:\\Program Files" ) do
                if LrFileUtils.exists( path ) == 'directory' then
                    local leaf = LrPathUtils.leafName( path )
                    if str:isBeginningWith( leaf, "ImageMagick" ) then
                        if self:isUsable() then -- has convert & mogrify in it.
                            self.exeAppDir = path
                            break
                        -- else keep looking
                        end
                    end
                -- else ignore files
                end
            end
            if self.exeAppDir == nil then
                self.exeAppDir = "C:\\Program Files\\ImageMagick-6.7.3-Q16" -- for example.
            end
        else
            if self.exeAppDir == nil then
                self.exeAppDir = "/usr/local/bin" -- verified at IM site 19/Dec/2013.
            end
        end
        app:setPref( 'imageMagickDir', self.exeAppDir ) -- if user blankens it (or was blank as factory default), it'll be populated with something found, or where it might be found..
    end
    assert( self.exeAppDir ~= nil, "oops" )
    assert( self.exeAppDir == app:getPref( 'imageMagickDir' ), "oops2" )
end



--- Determine if image magick is usable.
--
function ImageMagick:isUsable()
    if not str:is( self.exeAppDir ) then
        return false, "ImageMagick application directory is blank/undefined."
    end
    if not fso:existsAsDir( self.exeAppDir ) then
        return false, "ImageMagick application directory does not exist: "..self.exeAppDir
    end
    local convExeApp = LrPathUtils.child( self.exeAppDir, WIN_ENV and "convert.exe" or "convert" )
    if not fso:existsAsFile( convExeApp ) then
        return false, "ImageMagick application directory does not contain convert app: "..convExeApp
    end
    local mogExeApp = LrPathUtils.child( self.exeAppDir, WIN_ENV and "mogrify.exe" or "mogrify" )
    if not fso:existsAsFile( mogExeApp ) then
        return false, "ImageMagick application directory does not contain mogrify app: "..mogExeApp
    end
    return true, self.exeAppDir
end


-- pass nil to double-check current dir, e.g. if required for correct functioning.
function ImageMagick:processDirChange( newDir )
    if newDir ~= nil then -- true change in UI.
        self.exeAppDir = newDir -- even if "" - could be user wants to blanken to indicate "don't use"..
    end
    local is, q = self:isUsable() -- with exe-app-dir member as set.
    if is then
        assert( q == self.exeAppDir, "dir mismatch" )
        app:setPref( 'imageMagickDir', q ) -- q is dir
        app:logV( "Image Magick dir set to ^1", q )
        return true
    else -- q is errm.
        if newDir ~= nil then -- called by change handler
            app:setPref( 'imageMagickDir', newDir ) -- Note: user can set it to whatever he/she wants, whether usable or not.
            app:show{ warning="Image Magick is not usable - ^1", q }
            return nil -- ignofre return value if called from change handler.
        else -- do not change pref if called with no param - just check it as set.
            return false, q
        end
    end
end



function ImageMagick:checkConfig()
    return self:processDirChange()
end



-- convert or mogrify
function Utility:_exec( params, target, ... )
    return app:executeCommand( self.exeAppPath, params, target, ... )
end



function ImageMagick:convert( params, target, ... )
    self.conv.exeAppPath = LrPathUtils.child( self.exeAppDir, WIN_ENV and "convert.exe" or "convert" )
    return self.conv:_exec( params, target, ... )
end



function ImageMagick:mogrify( params, target, ... )
    self.mog.exeAppPath = LrPathUtils.child( self.exeAppDir, WIN_ENV and "mogrify.exe" or "mogrify" )
    return self.mog:_exec( params, target, ... )
end

-- should I have an image-magick view-item in settings? ###1


return ImageMagick
