--[[
        User Manager
        
        Supports multi-user plugins.
--]]



local User = Object:newClass{ className = 'User' }



--- Constructor for extending class.
--
function User:newClass( t )
    return Object.newClass( self, t )
end



--- Create user object.
--      
--  <p>User's name is obtained from shared property file.</p>
--      
--  @return            user object instance.
--
function User:new( t )

    local o = Object.new( self, t ) -- create generic new object, or add "object-ness" to user table.
    -- o.name = fprops:getSharedProperty( "user" ) - obsoleted 19/Aug/2011. Uses reglar global pref now instead.
    return o
    
end



--- Determine if there is a non-anonymous user active.
--      
--  @return     boolean: true iff user not anonymous.
--
function User:is()
    return self:getName() ~= '_Anonymous_' -- is non-anonymous user.
end



--- Get's user name for display/logging, or decision making.
--
--  @usage      Use 'is' method first if you want to distinguish between "real user" and "anonynmous".
--
--  @return     string: Real user name if applicable, else something indicating anonymous user, presently '_Anonymous_'.
--
function User:getName()
    local username = prefs['_global_username'] or prefs['username'] -- so this can be used during initialization, before app constructed.
    -- *** Warning: username is sometimes used for FTP so conflict is possible. ###4
    if username ~= nil and username:len() > 0 then -- str may not be created yet.
        return username
    else
        return '_Anonymous_'
    end
end



return User        

