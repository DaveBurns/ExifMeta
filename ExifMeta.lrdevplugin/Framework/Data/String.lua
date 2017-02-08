--[[
        String.lua
        
        String handling methods, including path manipulation..
        
        Can be used with LrPathUtils.getStandardFilePath:
        -------------------------------------------------     
            adobeAppData 
            home 
            lightroomCommonFiles 
            desktop 
            documents 
            pictures 
            music 
            -video?
            public_desktop 
            public_documents 
            public_music 
            public_pictures 
            public_videos 
            appData 
            cache 
            appPrefs 
            temp 
            allUserAppData 
            allUserAppDataACR 
            applications 
            applicationsX86 
            users         
--]]

local String, dbg, dbgf = Object:newClass{ className = 'String', register = false }

local pluralLookup     -- initialized upon first need.
local singularLookup   -- ditto.
local pw -- general-purpose/frequently-used scratch var which probably should be more local, but isn't hurting at module level.



--- Constructor for extending class.
--
function String:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function String:new( t )
    return Object.new( self, t )
end



--- Get standard file path items as table of id=name entries.
--
function String:getStandardFilePathItems()
    if not self.stdFilePathItems then
        self.stdFilePathItems =  {
            adobeAppData = "Adobe Application Data",
            home = "User's Home",
            lightroomCommonFiles = "Lightroom Common Files",
            desktop = "Desktop",
            documents = "Documents",
            pictures = "Pictures",
            music = "Music",
            videos = "Videos", -- videos? ###1
            public_desktop = "Public Desktop",
            public_documents = "Public Documents",
            public_music = "Public Music",
            public_pictures = "Public Pictures",
            public_videos = "Public Videos",
            appData = "Application Data",
            cache = "ACR Cache",
            appPrefs = "Lightroom Preferences",
            temp = "Temporary",
            allUserAppData = "Public Lightroom Data",
            allUserAppDataACR = "Public ACR Data",
            applications = "Applications", 
            applicationsX86 = "Applications (x86)",
            users = "Users",
        }
    end
    return self.stdFilePathItems
end



--- Escape characters that are "magic" in lua pattern strings.
--  @usage essentially allows gsub to function as gsub-plain.
--  @usage example: string.gsub( "my hyphenated-expression", str:luaPatternEscape( "hyphenated-expression" ), "nonhyphenatedexpression" ) -- without escaping, this would not work, since '-' is a magic character in lua patterns.
function String:luaPatternEscape( s )
    return (s:gsub('[%-%.%+%[%]%(%)%$%^%%%?%*]','%%%1'):gsub('%z','%%z'))
end



--- Determine if string is all lower case.
--
function String:isLower( s )
    if LrStringUtils.lower( s ) == s then return true end
end



--- Determine if character is lower case (ascii).
--
function String:isCharLower( c )
    if string.byte( c ) >= 97 and string.byte( c ) <= 122 then return true end
end



--- Trim whitespace from front (left) of string.
--
--  @usage Reminder: Lr's trimmer does not handle binary strings (those containing zero bytes) properly, this method does.
--
function String:trimLeft( s )
    local non, stop = s:find( "[^%s]" )
    if non then
        return s:sub( stop )
    else
        return ""
    end
end



--- Trim whitespace from tail (right) of string.
--
--  @usage Reminder: Lr's trimmer does not handle binary strings (those containing zero bytes) properly, this method does.
--
function String:trimRight( s )
    local found
    for i = #s, 1, -1 do
        if not s:sub( i, i ):find( "[%s]" ) then -- right-most char is not any kind of space
            return s:sub( 1, i ) -- get beginning through last non-space char.
        end
    end
    return "" -- no non-space characters were found, so trimmed-right means empty string.
end



--- Trim whitespace from front & tail (left & right) of string.
--
--  @usage Reminder: Lr's trimmer does not handle binary strings (those containing zero bytes) properly, this method does.
--
function String:trim( s )
    return self:trimRight( self:trimLeft( s ) )
end




--- Break down a path into an array of components.
--
--  @usage              *** deprecated - use split-path method instead: it's more robust and *almost* completely backward compatible, differences:
--      <br>    this method always returns two components if unmapped network drive, e.g. "\\asdf\qwerty"\file" path would be '\\asdf\qwerty' & 'file' components (split-path handles more reasonably).
--      <br>    this method always returns forward slash as first component of windows path in format "\asdf\qwerty", whereas split-path will return backslash.
--      <br>I almost replaced this method instead of adding a new one, but I was afraid it might induce some subtle/pesky bugs here or there..
--  @usage              Does not distinguish absolute from relative paths.
--
--  @return             array (1st component is root), usually not empty, never nil.
--
function String:breakdownPath( path )
    local a = {}
    local p = LrPathUtils.parent( path )
    local x = LrPathUtils.leafName( path )
    
    local slashes = path:find( "[\\/]" ) -- default find'r matches lua pattern.
    if not slashes then -- already root drive/device name.
        return { path }        
    end
    
    while x do
        a[#a + 1] = x
        if p then
            x = LrPathUtils.leafName( p )
        else
            break
        end
        p = LrPathUtils.parent( p )
    end

    local b = {}
    local i = #a
    while i > 0 do
        b[#b + 1] = a[i]
        i = i - 1
    end
    return b
end




--- Split a path into an array of components.
--
--  @usage      Can be used on absolute or relative paths (or even non-disk paths, as long as they're using slash or backslash as separator).
--  @usage      format of unmapped network drive on Windows is: \\drv\fldr\file...
--              <br>format of windows path: C:\root\fldr\file
--              <br>format of mac path: /drvOrFlder/fldr/file
--
--  @param      path (string, required) disk folder/file or collection or keyword path..
--
--  @return     array (1st component is root drive on windows - e.g. 'C:', or '/' on Mac, or '\\' (true double) if unmapped windows network drive),
---             <br>and '\' if leading backslash (presumably Windows).
--              <br>last component is filename (or leaf folder name).
--              <br>usually not empty, never nil.
--              <br>
--              <br>examples - path string      component list:
--              <br>\\one\two\file.x        \\, one, two, file.x  -- drive name is 2nd component - better handling than breakdown-path.
--              <br>C:\one\two\file.x       C:, one, two, file.x  -- root drive is first component
--              <br>/one/two/file.x         /, one, two, file.x   -- hard to tell if 'one' is a drive or path was subpath and 'one' is a folder - should be clear from context (maybe if subpath, do not include leading slash).
--              <br>\one\two\file.x         \, one, two, file.x   -- departure from breakdown-path.
--              <br>one\two\file.x          one, two, file.x
--              <br>one/two/file.x          one, two, file.x
--
function String:splitPath( path )
    -- path is not checked, for efficiency, in case this is called repeatedly - check in calling context if uncertain.
    local nd -- windows "network drive" flag: could be true network drive or Lr mobile path..   
    local a = {}
    local slashes = path:find( "[\\/]" ) -- default find'r matches lua pattern.
    if not slashes then -- already root drive/device name.
        return { path }
    elseif path:sub( 1, 2 ) == "\\\\" then -- unmapped windows network drive
        nd = true
        path = path:sub( 3 ) -- make "relative"
    elseif path:sub( 1, 1 ) == "\\" then -- windows leading backslash
        path = path:sub( 2 )
        nd = false
    -- else no compensation required
    end
    local p = LrPathUtils.parent( path )
    local x = LrPathUtils.leafName( path )
    
    while x do
        a[#a + 1] = x
        if p then
            x = LrPathUtils.leafName( p )
        else
            break
        end
        p = LrPathUtils.parent( p )
    end
    if nd then
        a[#a + 1] = "\\\\"
    elseif nd == false then
        a[#a + 1] = "\\"
    -- else still nil - no action required here.
    end
    
    return tab:reverseArray( a ) -- could use reverse-in-place, but no good reason to ('a' will be garbage-collected..).
end



--- Split a string based on delimiter.
--
--  @param      s       (string, required) The string to be split.
--  @param      delim   (string, required) The delimiter string (plain text). Often something like ','.
--  @param      maxItems (number, optional) if passed, final element will contain entire remainder of string. Often is 2, to get first element then remainder.
--
--  @usage              Seems like there should be a lua or lr function to do this, but I haven't seen it.
--  @usage              Components may be empty strings - if repeating delimiters exist.
--      
--  @return             Array of trimmed components - never nil nor empty table unless input is nil or empty string, respectively.
--
function String:split( s, delim, maxItems, regex )
    if s == nil then return nil end
    if s == '' then return {} end
    local t = {}
    local p = 1
    repeat
        local start, stop = s:find( delim, p, not regex )
        if start then
            t[#t + 1] = LrStringUtils.trimWhitespace( s:sub( p, start - 1 ) )
            p = stop + 1
            if maxItems ~= nil then
                if #t >= maxItems - 1 then
                    t[#t + 1] = LrStringUtils.trimWhitespace( s:sub( p ) )
                    break
                end
            end
        else
            t[#t + 1] = LrStringUtils.trimWhitespace( s:sub( p ) )
            break
        end
    until false
    return t
end



--- Split at delimiter, but interpret consecutive delimiters as escaped data, and unescape it.
--
--  @usage does not support max components, but does allow custom preparation function - defaulting to whitespace trimmer.
--
function String:splitEscape( s, delim, prepFunc )
    if s == nil then return nil end
    if s == '' then return {} end
    local t = {}
    local findIndex = 1
    local getIndex_1
    local getIndex_2
    if prepFunc == nil then
        prepFunc = LrStringUtils.trimWhitespace
    end
    repeat
        local start, stop = s:find( delim, findIndex, true )
        --Debug.pause( findIndex, start, stop )
        local n= 1
        if start then
            while s:sub( stop + n, stop + n + #delim - 1 ) == delim do
                n = n + #delim
            end
            if n > 1 then
                local _start, _stop = s:find( delim, stop + n, true )
                if _start then
                    getIndex_1 = findIndex
                    getIndex_2 = _start - 1
                    findIndex = _stop + 1
                else
                    getIndex_1 = findIndex
                    getIndex_2 = nil
                end
            else
                getIndex_1 = findIndex
                getIndex_2 = start - 1
                findIndex = stop + 1
            end
        else
            getIndex_1 = findIndex
            getIndex_2 = nil
        end
        local insert = s:sub( getIndex_1, getIndex_2 )
        if n > 1 then
            insert = insert:gsub( delim..delim, delim )
        end
        t[#t + 1] = prepFunc( insert )
        if getIndex_2 == nil then
            break
        end
    until false
    return t
end



---     Make path from component array, usually identical to that broken down using breakdown-path.
--
--      @usage  uses lrpathutils-child function to assemble components into a path, so most appropriate when paths are for disk files and are absolute.
--          <br>If you need to assure path created by split-path would make an identical path when re-assembled, choose components-to-path instead, and pass a separator if necessary.
-- 
--      @param comps        The array of path components: 1st element is root, last element is child.
--
function String:makePathFromComponents( comps )

    local path = comps[1]

    for i = 2, #comps do
        path = LrPathUtils.child( path, comps[i] )
    end

    return path

end



--- Make path from component array - can be made identical to that parsed using split-path, in all cases.
--
--  @param  comps   array of path component strings - typically obtained using split-path but could also come from breakdown-path, or be wholly computed however..
--  @param  sep     string separator, optional - only required if path parsed was relative and/or different separator from OS is desired.
--
--  @return path string
--
function String:componentsToPath( comps, sep )
    if not tab:isArray( comps ) then return "" end
    if comps[1]:sub(1,1) == "/" then
        if sep ~= "/" then
            Debug.pauseIf( sep~=nil, "sep=", sep, "being overridden to '/' based on first char" )
            sep = "/"
        end
    elseif comps[1]:sub(1,1) == "\\" then
        if sep ~= "\\" then
            Debug.pauseIf( sep~=nil, "sep=", sep, "being overridden to '\\' based on first char" )
            sep = "\\"
        end
    elseif sep == nil then -- caller is leaving it up to this function (and not determinable based on leading char).
        sep = app:pathSep() -- assume OS disk path separator if no hint via first component.
    -- else sep = sep
    end
    local path = comps[1]
    for i = 2, #comps do
        if comps[i] ~= nil then
            path = str:child( path, sep, comps[i] )
        else
            break
        end
    end
    return path
end



---	Determine if two strings are equal other than case differences.
--
function String:isEqualIgnoringCase( s1, s2 )
	local s1l = string.lower( s1 )
	local s2l = string.lower( s2 )
	return s1l == s2l
end



---	Determine if two strings are equal - case-sensitive by default.
--
function String:isEqual( s1, s2, ignoreCase )
    if ignoreCase then
        return self:isEqualIgnoringCase( s1, s2 )
    else
        return s1 == s2
    end
end



---	Makes a string of spaces - used for indentation and output formatting...
--
--  @usage      *** deprecated - use Lua's string-rep function instead.
--
function String:makeSpace( howMany )
    return string.rep( " ", howMany ) -- there used to be a lot more in this function ;-}
end



--- Remove spaces from middle of a string (as well as ends).
--      
--  @usage          Convenience function to make more readable than testing for nil followed by gsub.
--      
--  @return         Squeezed string, nil -> empty.
--
function String:squeeze( s )
    if s == nil then
        return ''
    else
        return s:gsub( " ", '' )
    end
end



--- Remove redundent adjacent characters.
--      
--  @usage          Initial motivation was to format value returned by table.concat( items, " " ) when some items may be empty strings.
--  @usage          Example: newstr = str:consolidate( oldstr, "\n", 2 ) -- consolidate double new-lines into single.
--
--  @param          s (string or nil) returned empty or with gsubs.
--  @param          char (string, default=" ") character(s) to be consolidated.
--  @param          charCount (number, default=1) number of chars in sequence warranting consolidation.
--  @return         Consolidated string.
--
function String:consolidate( s, char, charCount )
    if s == nil then
        return ''
    end
    charCount = charCount or 1
    if charCount == 0 then
        char = ""
    else
        char = ( char or " " ):rep( charCount )
    end
    local chars = char:rep( charCount + 1 )
    local rslt, matchCount = s:gsub( chars, char )
    while matchCount > 0 do
        rslt, matchCount = rslt:gsub( chars, char )
    end
    return rslt
end



--- Squeezes a path to fit into fixed width display field (sacrifices middle chars for sake of first & last chars).
--
--  <p>One could argue for another parameter that selects a balance between first part of path, and second part of path<br>
--     i.e. balance = 0 => select first part only, balance = 1 => prefer trailing path, .5 => split equally between first and last part of path.</p>
--  <p>Although its conceivable that some pathing may be preferred over long filename, that solution is waiting for a problem...</p>
--
--  @usage          Guaranteed to get entire filename, and as much of first part of path as possible.
--  @usage          Lightroom does something similar for progress caption, but algorithm is different.
--
--  @return         first-part-of-path.../filename.
--
function String:squeezePath( _path, _width )
    local len = string.len( _path )
    if len <= _width then
        return _path
    end
    -- fall-through => path reduction necessary.
    local dir = LrPathUtils.parent( _path )
    local filename = LrPathUtils.leafName( _path )
    local fnLen = string.len( filename )
    local dirLen = _width - fnLen - 4 -- dir len to be total len less filename & .../
    if dirLen > 0 then
        dir = string.sub( dir, 1, dirLen ) .. ".../"
        return dir .. filename
    else
        return filename -- may still be greater than width. If this becomes a problem, return substring of filename,
            -- or even first...last.
    end
end



--- Return length-limited version of s, with trailing '...' to indicate.
--
function String:limit( s, n )
    if s == nil or s:len() <= n or n < 4 then
        return s
    else
        return s:sub( 1, n - 3 ) .. "..."
    end
end

       

--- Squeezes a string to fit into fixed width display field.
--
--  @return          first half ... last half
--
function String:squeezeToFit( _str, _width )

    if self:is( _str ) then
        if _str:len() > _width then -- reduction required.
            if _width >= 5 then
                local firstHalf = math.ceil( _width / 2 ) - 2
                -- 5 => 1, 1
                -- 6 => 1, 2
                -- 7 => 2, 2
                -- 8 => 2, 3
                -- 9 => 3, 3
                local secondHalf = math.floor( _width / 2 ) - 1
                return _str:sub( 1, firstHalf ) .. "..." .. _str:sub( - secondHalf )
            else
                return "..." -- just punt if the field is that freakun small.
            end
        else
            return _str
        end
    else
        return ""
    end

end
        


---     Synopsis:       Pads a string on the left with specified character up to width.
--
--      Motivation:     Typically used with spaces for tabular display, or 0s when string represents a number.
--
function String:padLeft( s, chr, wid )
    local n = wid - string.len( s )
    --[[ this until 7/Feb/2013 18:13 -
    while( n > 0 ) do
        s = chr .. s
        n = n - 1
    end
    return s
    --]]
    -- this since 7/Feb/2013 18:13 - (more efficient)
    if n > 0 then
        local pad = string.rep( chr, n )
        return pad .. s
    else
        return s
    end
end



--- Pads a string on the left with specified character up to width.
--
--  @usage Typically used with spaces for tabular display, or 0s when string represents a number.
--  @usage only works right if fixed-width font.
--
function String:padRight( s, chr, wid )
    local n = wid - string.len( s )
    if n > 0 then
        local pad = string.rep( chr, n )
        return s .. pad
    else
        return s
    end
end



--- Convenience function for getting the n-th character of a string.
--
--  @param      s       The string.
--  @param      index   First char is index 1.
--
--  @usage      @2010-11-23: *** Will throw error if index is out of bounds, so check before calling if unsure.
--
--  @return     character in string.
--
function String:getChar( s, index )
    return string.sub( s, index, index )
end



--- Convenience function for getting the first character of a string.
--
--  @usage a slightly more redable equivalent to s:sub( 1, 1 ) - also: won't die if 's' is nil..
--
function String:getFirstChar( s )
    if self:is( s ) then
        return string.sub( s, 1, 1 )
    else
        return ''
    end
end
String.firstChar = String.getFirstChar -- synonym for same method.



--- Convenience function for getting the last character of a string.
--
--  @usage a slightly more redable equivalent to s:sub( -1 ) - also: won't die if 's' is nil..
--      <br>in my defense: I didn't know about negative indexes when I wrote this ;-}, which was a loooong time ago..
--
function String:getLastChar( s )
    if str:is( s ) then
        local len = string.len( s )
        return string.sub( s, len, len )
    else
        return ''
    end
end
String.lastChar = String.getLastChar --- synonym for same method.



--- Compare two strings.
--
--  @usage          Returns immediately upon first difference.
--
--  @return         0 if same, else position of first different character.
--
function String:compare( s1, s2 )
    local len1 = string.len( s1 )
    local len2 = string.len( s2 )
    if len1 > len2 then
        return len2
    elseif len2 > len1 then
        return len1
    end
    local c1, c2
    for i=1, len1, 1 do
        c1 = self:getChar( s1, i )
        c2 = self:getChar( s2, i )
        if c1 ~= c2 then
            return i
        end
    end
    return 0
end



--- Get the difference between two strings.
--      
--  @usage      Use to see the difference between two strings.
--      
--  @return     diff-len
--  @return     s1-remainder
--  @return     s2-remainder
--
function String:getDiff( s1, s2 )
    local len1 = string.len( s1 )
    local len2 = string.len( s2 )
    local compLen
    local diffLen = len1 - len2
    if diffLen > 0 then
        compLen = len2
    else
        compLen = len1
    end
    local c1, c2, i
    i = 1
    while i <= compLen do
        c1 = self:getChar( s1, i )
        c2 = self:getChar( s2, i )
        if c1 ~= c2 then
            return i, string.sub( s1, i ), string.sub( s2, i )
        end
        i = i + 1
    end
    if diffLen > 0 then
        return diffLen, string.sub( s1, i ), nil
    elseif diffLen < 0 then
        return diffLen, nil, string.sub( s2, i )
    else
        return 0, nil, nil
    end
        
end
        


--- Compare two strings in their entirety (or until one string runs out of characters).
--
--  @usage      Use when it is desired to know the character positions of all the differences.
--  @usage      Most appropriate when the files are same length, or at least start off the same, since there is no attempt to resynchronize...
--
--  @return     nil if same, else array of difference indexes.
--
function String:compareAll( s1, s2, count )
    local len1 = string.len( s1 )
    local len2 = string.len( s2 )
    if len1 > len2 then
        return { len2 }
    elseif len2 > len1 then
        return { len1 }
    end
    local c1, c2
    local diffs = {}
    for i=1, len1, 1 do
        c1 = self:getChar( s1, i )
        c2 = self:getChar( s2, i )
        if c1 ~= c2 then
            diffs[#diffs + 1] = i
        end
    end
    if #diffs > 0 then
        return diffs
    else
        return nil
    end
end



--- Extract a number from the front of a string.
--
--  <p>Initial application for ordering strings that start with a number.</p>
--
--  @return          Next parse position.
--
--  @usage           *** Warning: Does NOT check incoming string or parse position.
--
function String:getNonNegativeNumber( s )
    local pos1, pos2 = string.find( s, "%d+", 1 )
    if pos1 ~= nil and pos1 == 1 then
        return tonumber( string.sub( s, pos1, pos2 ) ), pos2 + 1
    else
        return nil, -1
    end
end



--- Format a string using LOC formatter but without localization.
-- 
--  @usage          *** deprecated in favor of fmtx method, which is more robust.
--  @usage          An alternative to lua string.format function (which uses ansi 'C' printf syntax).
--
function String:format( s, ... )
    if s ~= nil then
        return LOC( "$$$/X=" .. s, ... )
    else
        return ""
    end
end
String.fmt = String.format -- synonym: String:fmt( s, ... )



--- Format a string, ampersands are expected to be in && win-compatible format (if plugin runs on Windows too), but will be converted to mac compatible format on mac.
--
--  @param      s       format string in LOC format.
--  @param      ...     substution variables - any format: nil OK.
--
--  @usage      x in the name stands for cross-platform.
--  @usage      Will never throw an error, unless format string is not string type - don't use for critical program strings, just logging and UI display, when it's better to have a small aesthetic bug than a catastrophic error.
--  @usage      LOC will throw error when passed a boolean, string.format will throw an error when insufficient substitutions or incompatible data type.
--  
function String:fmtx( s, ... )
    if not str:is( s ) then
        return ""
    end
    local subs = {}
    local param = { ... } -- include nils
    -- 1st: assure all parameters are substutued.
    for i = #param + 1, math.huge do
        local token = "^" .. i
        local p1, p2 = s:find( token, 1, true )
        if p1 then
            local _, m = pcall( error, "Insufficient substitutions for str:fmtx - missing "..token, 3 ) -- fake an error in caller of this function and get module name + line-no.
            Debug.pause( m )
            s = s:gsub( "%"..token, "???" ) -- no plain text substutution, so escape the '^'.
        else
            break
        end
    end
    for i = 1, #param do -- ipairs quits on first nil, but this "iterator" won't.
        subs[i] = str:to( param[i] )
    end
    local t = LOC( "$$$/X=" .. s, unpack( subs ) )
    return WIN_ENV and t or t:gsub( "&&", "&" )
end



---     Same as format plain except converts ampersands for windows compatibility.
--
--  @usage *** deprecated in favor of fmtx.
--
--      Assumes they are formatted for Mac compatibility upon entry (single '&' ).
--      
--      Pros: More readable on all platforms.
--      Cons: Less efficient on Windows.
--
function String:formatAmps( s, ... )
    local t = LOC( "$$$/X=" .. s, ... )
    return ( WIN_ENV and t:gsub( "&", "&&" ) ) or t
end
String.fmtAmps = String.formatAmps -- Synonym



--- Same as format plain except converts ampersands for mac compatibility.
--      
--  @usage *** deprecated in favor of fmtx.
--      <br>Assumes they are formatted for Windows compatibility upon entry (double '&&' ).
--      <br>
--      <br>Pros: More efficient on windows.
--      <br>Cons: Less efficient on Mac, & less readable.
--
function String:formatAmp( s, ... )
    local t = LOC( "$$$/X=" .. s, ... )
    return ( MAC_ENV and t:gsub( "&&", "&" ) ) or t
end
String.fmtAmp = String.formatAmp -- Synonym




---     Example: str:loc( "My/Thing", "In English, we say...^1", myvar )
--      
--      In my opinion, this is just more readable than the LOC syntax.
--
function String:loc( i18nKey, s, ... )
    return LOC( "$$$/" .. i18nKey .. "=" .. s, ... )
end

function String:locAmps( i18nKey, s, ... )
    local t = LOC( "$$$/" .. i18nKey .. "=" .. s, ... )
    return ( WIN_ENV and t:gsub( "&", "&&" ) ) or t
end

function String:locAmp( i18nKey, s, ... )
    local t = LOC( "$$$/" .. i18nKey .. "=" .. s, ... )
    return ( MAC_ENV and t:gsub( "&&", "&" ) ) or t
end



--- Determine if one string starts with another - BEWARE: regex by default.
--      
--  <p>Avoids the problem of using the nil returned by string.find in a context that does not like it.</p>
--      
--  @usage      Does not check incoming strings.
--  @usage      Does not ignore whitespace.
--  @usage      If string is not expected to be there at the start, and the source string is very long, it will be more efficient to pass a substring instead, for example:<br>
--                  local isThere = str:isStartingWith( longstr:sub( 1, t:len() ), t )
--  @usage      you must also pass parameters "1, true" for plain text (index must be one, followed by boolean true).
--
--  @return     true iff s begins with t in character position 1.
--
function String:isStartingWith( s, t, ... )
    local start = s:find( t, ... )
    return start ~= nil and start == 1
end



--- Determine if one string begins with another - NOTE: plain text (always).
--      
--  <p>Does not use 'find'.</p>
--      
--  @usage      Does not check incoming strings.
--  @usage      Does not ignore whitespace.
--
--  @return     true iff s begins with t.
--
function String:isBeginningWith( s, t )
    return s:sub( 1, t:len() ) == t
end



--- Determine if one string ends with another - plain text.
--      
--  <p>Avoids the problem of using the nil returned by string.find in a context that does not like it.</p>
--      
--  @usage      Does not check incoming strings.
--  @usage      Does not ignore whitespace.
--
--  @return     true iff s begins with t in character position 1.
--
function String:isEndingWith( s, t )
    return ( s:sub( 0 - t:len() ) == t )
end



--- Return last index in source string, of target string.
--
--  @return startIndex or 0 if not found - never returns nil.
--  @return stopIndex or 0 if not found - never returns nil.
--
function String:getLastIndexOf( s, t, regexFlag )
    local index = 0
    local index2 = 0
    local startAt = 1
    while( true ) do
        local start, stop = s:find( t, startAt, regexFlag )
        if start then
            index = start
            index2 = stop
            startAt = stop + 1
        else
            break
        end
    end
    return index, index2
end
String.lastIndexOf = String.getLastIndexOf -- function String:lastIndexOf( ... )



--- Return string that complies with Lr preference key requirements.
--
--  @usage initial motivation is for lr pref key.
--  @usage reminder: photo metadata properties can not begin with an underscore, dunno 'bout catalog properties for plugin. prefs are OK with leading underscore.
--  @usage Also, caller needs to make sure first char isn't a number - ###3.
--
function String:makeLuaVariableNameCompliant( s )
    if s == nil then
        error( "unable to make nil lua variable name compliant", 2 ) -- throw error in calling context.
    end
    return s:gsub( "[^%w_]", '' ) -- strip everything except alpha-numeric and '_'
end



--- Return string that complies with filename requirements.
--
--  @param s string
--  @param replacementCharacter optional - defaults to '-'. empty string is legal..
--
function String:makeFilenameCompliant( s, replacementCharacter )
    app:callingAssert( s ~= nil, "need s to make compliant" )
    return s:gsub( '[\\/:*?"<>|]', replacementCharacter or '-' )
end



function String:makeSubpathCompliant( s, replacementCharacter )
    app:callingAssert( s ~= nil, "need s to make compliant" )
    return s:gsub( '[:*?"<>|]', replacementCharacter or '-' ) -- same as filename compliance, except excludes path sep (note: handle slashes externally depending on context..).
end



--- Convert path to key that can be used for "property for plugin" key: photo or catalog.
--
function String:pathToPropForPluginKey( path )
    local fileKey = path:gsub( "%.", "__D__" )
    fileKey = fileKey:gsub( "\\", "__N__" )
    fileKey = fileKey:gsub( "/", "__Z__" )
    fileKey = fileKey:gsub( ":", "__C__" )
    fileKey = fileKey:gsub( " ", "_" )
    fileKey = fileKey:gsub( "-", "_" )
    -- assure does not begin with underscore: dunno if required for catalog properties for plugin,
    -- but *is* required for photo properties for plugin.
    local pos = 1
    while pos < fileKey:len() do
        local c = str:getChar( fileKey, pos )
        if c ~= '_' then
            break
        else
            pos = pos + 1
        end
    end
    if pos > 1 then
        return fileKey:sub( pos )
    else
        return fileKey
    end
end



--- Generates a unique character sequence (ID) governed by specified options (or default options).
--  @usage defaults to 12 non-space printable chars - be sure to pass fnCompat if filename compatibility is required (or noGuk for a prettier sequence).
--  @usage length should depend on desired probability for uniqueness: 1 would be fine if you only have a few and pass prevIdSet as well, but for UUID-level uniqueness consider 32+.
--  @usage side effect: will add id to prevIdSet if passed.
--  @usage this function is slower than the native version of LrUUID.generateUUID, but can generate shorter (or longer) IDs.
--  @param options table (optional), possible members:
--    <br>  fnCompat -- convenience param to filter non-filename-compatible chars (default=false).
--    <br>  noGuk -- convenience param to use only chars that aren't funny looking (no gobble-de-guk) - implies fn-compat..
--    <br>  lowVal -- decimal value for lowest character (default=33, noGuk => 48).
--    <br>  highVal -- decimal value for highest character (default=126, noGuk => 122).
--    <br>  filterChars -- array of chars requiring special filter (default=none).
--    <br>  charSub -- character to replace filtered characters (default = random letter A-Z, not checked against lo-val/hi-val, so pass explicit if need be).
--    <br>  filterObject -- gsub-compatible table or function specifying replacement for filtered char (default=nil), else char-sub or default.
--    <br>  prevIdSet -- set of unique IDs previously seen, to assure no duplicate generation (recommended if small length passed).
function String:genUniqueId( options )
    options = options or {}
    local prevIdSet = options.prevIdSet -- or nil
    local lowVal = options.lowVal or options.noGuk and 48 or 33
    local highVal = options.highVal or options.noGuk and 122 or 126
    local noGuk = options.noGuk
    local fnCompat = options.fnCompat
    local filterChars = options.filterChars -- or nil
    local filterFunc = options.filterObject -- or nil
    local nChars = options.length or 12
    local function sub()
        return options.charSub or string.char( math.random( 65, 90 ) ) -- random letter: A-Z.
    end
    local function _uniqueId()
        local chars = {}
        if noGuk then
            for i=1, nChars do
                local byte = math.random( lowVal, highVal )
                if byte <= 47 or ( byte >= 58 and byte <= 64 ) or ( byte >= 91 and byte <= 96 ) or byte >= 123 then -- guk
                    chars[#chars + 1] = sub()
                else
                    chars[#chars + 1] = string.char( byte )
                end
            end
        else
            for i=1, nChars do
                chars[i] = string.char( math.random( lowVal, highVal ) )
            end
        end
        local uid
        if fnCompat then -- if noGuk, it's already filename compliant, so this would hopefully be redundent, albeit relatively cheap insurance.
            uid = str:makeFilenameCompliant( table.concat( chars ), sub() ) -- drop second return value.
        else
            uid = table.concat( chars )
        end
        if filterChars then -- likewise: unlikely to need this if using noGuk param.
            for i, c in ipairs( filterChars ) do
                uid = uid:gsub( c, filterFunc or sub() )
            end
        end
        return uid
    end
    if prevIdSet then
        local id
        local c = 0
        repeat
            id = _uniqueId()
            if prevIdSet[id] then
                c = c + 1
                if c == 1 then
                    if Debug.pause then Debug.pause( "id collision" )
                    elseif debugPause then debugPause( "id collision" ) end
                elseif c > 10000 then
                    error( "Unable to generate a unique ID which adheres to specified criteria." )
                end
            else
                break
            end
        until false
        prevIdSet[id] = true
        return id
    else
        return _uniqueId()
    end
end



--- Makes a word presumed to be singular into its plural form.
--      
--  @usage      Call is-plural and trim beforehand if necessary.
--
function String:makePlural(word)

    self:initPlurals() -- if not already.

	local lowerword = string.lower(word)
	local wordlen = string.len(word)

	-- test to see if already plural, if so, return word as is
	-- if TestIsPlural(word) == true then return word end - more efficient to not test unless
	-- unless there is a question about it. if it already is plural, then it will get double pluralized

	-- test to see too short
	if wordlen <=2 then return word end  -- not a word that can be pluralized

	-- test to see if it is in special dictionary
	--check special dictionary, return word if found but keep first letter from original
	local dicvalue  = pluralLookup [lowerword]
	if dicvalue ~= nil then
		local dicvaluelen = #dicvalue
		return string.sub(word,1,1) .. string.sub(dicvalue,2,dicvaluelen)
	end

	-- if the word ends in a consonant plus -y, change the -y into, ies or es
	pw = string.sub(lowerword, wordlen-1,wordlen)
	if	pw=="by" or pw=="cy" or pw=="dy" or pw=="fy" or pw=="gy" or pw=="hy" or
		pw=="jy" or pw=="ky" or pw=="ly" or pw=="my" or pw=="ny" or pw=="py" or
		pw=="qy" or pw=="ry" or pw=="sy" or pw=="ty" or
		pw=="vy" or pw=="wy" or pw=="xy" or pw=="zy" then

		return string.sub(word,1,wordlen -1) .. "ies"
	
	-- for words that end in -is, change the -is to -es to make the plural form.
	elseif pw=="is" then return string.sub(word,1,wordlen -2) .. "es"

		-- for words that end in a "hissing" sound (s,z,x,ch,sh), add an -es to form the plural.
	elseif pw=="ch" or pw=="sh" then return word .. "es"

	else
		pw=string.sub(pw,2,1)
		if pw=="s" or pw=="z" or pw=="x" then
			return word .. "es"
		else
			return word .. "s"
		end
	end
	
end -- function to return plural form of singular



--- Make a plural form singular.
--      
--  @usage          If unsure whether already singular, call is-plural before-hand, and trim if necessary.
--
function String:makeSingular( word, exception )

    self:initPlurals() -- if not already.
    
	local wordlen = string.len(word)

	--not a word that can be made singular if only two letters!
	if wordlen <= 2 then return word end
	
	--check special dictionary, return word if found but keep first letter from original
	local lowerword = string.lower(word)
	local dicvalue  = singularLookup [lowerword]
	if dicvalue ~= nil then
		local dicvaluelen = #dicvalue
		return string.sub(word,1,1) .. string.sub(dicvalue,2,dicvaluelen)
	end

	-- if it is singular form in the special dictionary, then you can't remove plural
	if pluralLookup [lowerword] ~= nil then return word end
	
	-- if at this point it doesn't end in and "s", it is probably not plural
	if string.sub(lowerword,wordlen,wordlen) ~= "s" then return word end

	--If the word ends in a consonant plus -y, change the -y into -ie and add an -s to form the plural – so reverse engineer it to get the singular
	if wordlen >=4 then
		pw = string.sub(lowerword, wordlen-3,wordlen)
		if	pw=="bies" or pw=="cies" or pw=="dies" or pw=="fies" or pw=="gies" or pw=="hies" or
			pw=="jies" or pw=="kies" or pw=="lies" or pw=="mies" or pw=="nies" or
			pw=="pies" or pw=="qies" or pw=="ries" or pw=="sies" or pw=="ties" or
			pw=="vies" or pw=="wies" or pw=="xies" or pw=="zies" then
			return string.sub(word,1,wordlen -3) .. "y"
		--for words that end in a "hissing" sound (s,z,x,ch,sh), add an -es to form the plural.
		elseif pw=="ches" or pw=="shes" then
			return string.sub(word,1,wordlen -2)
		end
	end

	if wordlen >=3 then
		pw = string.sub(lowerword, wordlen-2,wordlen)
		if	pw=="ses" or pw=="zes" or pw=="xes" then
			-- some false positive here, need to add those to dictionary as found
			if not exception then
			    return string.sub(word,1,wordlen -2) -- common
			else
			    return string.sub(word,1,wordlen -1) -- but this comes up regularly for me.
			end
		elseif string.sub(pw,2,3)=="es" then
		    if not exception then
			    return string.sub(word,1,wordlen -2) .. "is" -- not sure which words this applies to.
			else
			    return string.sub(word,1,wordlen -1) -- but this comes up regularly for me.
			end
		end
	end

	-- at this point, just remove the "s"
	return string.sub(word,1,wordlen-1)

end -- function to return a singular form of plural word



--- Determine if a word is singular or plural.
--
--  <p>Note: It is possible for some plurals to escape detection. Not to be used when ascertainment is critical - intention is more for aesthetics...</p>
--      
--  @usage          trim beforehand if necessary.
--      
--  @return         true iff word is plural.
--
function String:isPlural(word)

    self:initPlurals() -- if not already.
    
	local lowerword = string.lower(word)
	local wordlen = #word

	--not a word that can be made singular if only two letters!
	if wordlen <= 2 then return false

	--check special dictionary to see if plural form exists
	elseif singularLookup [lowerword] ~= nil then
		return true  -- it's definitely already a plural


	elseif wordlen >= 3 then
		-- 1. If the word ends in a consonant plus -y, change the -y into -ie and add 			an -s to form the plural 
		pw = string.sub(lowerword, wordlen-3,wordlen)
		if	pw=="bies" or pw=="dies" or pw=="fies" or pw=="gies" or pw=="hies" or
			pw=="jies" or pw=="kies" or pw=="lies" or pw=="mies" or pw=="nies" or
			pw=="pies" or pw=="qies" or pw=="ries" or pw=="sies" or pw=="ties" or
			pw=="vies" or pw=="wies" or pw=="xies" or pw=="zies" or pw=="ches" or
			pw=="shes" then
			
			return true -- it's already a plural (reasonably accurate)
		end
		pw = string.sub(lowerword, wordlen-2,wordlen)
		if	pw=="ses" or pw=="zes" or pw=="xes" then
			
			return true -- it's already a plural (reasonably accurate)
		end

		pw = string.sub(lowerword, wordlen-1,wordlen)
		if	pw=="es" then
			
			return true -- it's already a plural (reasonably accurate)
		end
	end

	--not a plural word (after looking into special dictionary if it doesn't end in s
	if string.sub(lowerword, wordlen,wordlen) ~= "s" then
		return false

	else
		return true

	end -- group of elseifs
		
end -- function to test to see if word is plural



--- Initializes dictionaries for singular/plural support.
--
--  <p>May never be called if plugin does not call at least one plural function.</p>
--
--  @usage          Could be called in plugin-init, or in string constructor - but isn't. - will be called on first demand.
--
function String:initPlurals()

    if singularLookup ~= nil then return end -- test if already init.

--	Here are known words that have funky plural/singular conversions, they should
-- 	be checked first in all cases before the other rules are checked.  Probably wise to
--	set these as a global variable in the "init" code of the plug-in to keep from 
--	initializing everytime.

	pluralLookup = {
		afterlife	= "afterlives",
		alga		= "algae",
		alumna		= "alumnae",
		alumnus		= "alumni",
		analysis	= "analyses",
		antenna		= "antennae",
		appendix	= "appendices",
		axis		= "axes",
		bacillus	= "bacilli",
		basis		= "bases",
		bedouin		= "bedouin",
		cactus		= "cacti",
		calf		= "calves",
		cherub		= "cherubim",
		child		= "children",
		christmas	= "christmases",
		cod			= "cod",
		cookie		= "cookies",
		criterion	= "criteria",
		curriculum	= "curricula",
		dance		= "dances",
		datum		= "data",
		deer		= "deer",
		diagnosis	= "diagnoses",
		die			= "dice",
		dormouse	= "dormice",
		elf			= "elves",
		elk			= "elk",
		erratum		= "errata",
		esophagus	= "esophagi",
		fauna		= "faunae",
		fish		= "fish",
		flora		= "florae",
		focus		= "foci",
		foot		= "feet",
		formula		= "formulae",
		fundus		= "fundi",
		fungus		= "fungi",
		genie		= "genii",
		genus		= "genera",
		goose		= "geese",
		grouse		= "grouse",
		hake		= "hake",
		half		= "halves",
		headquarters= "headquarters",
		hippo		= "hippos",
		hippopotamus= "hippopotami",
		hoof		= "hooves",
		horse		= "horses",
		housewife	= "housewives",
		hypothesis	= "hypotheses",
		index		= "indices",
		jackknife	= "jackknives",
		knife		= "knives",
		labium		= "labia",
		larva		= "larvae",
		leaf		= "leaves",
		life		= "lives",
		loaf		= "loaves",
		louse		= "lice",
		magus		= "magi",
		man			= "men",
		memorandum	= "memoranda",
		midwife		= "midwives",
		millennium	= "millennia",
		miscellaneous= "miscellaneous",
		moose		= "moose",
		mouse		= "mice",
		nebula		= "nebulae",
		neurosis	= "neuroses",
		nova		= "novas",
		nucleus		= "nuclei",
		oesophagus	= "oesophagi",
		offspring	= "offspring",
		ovum		= "ova",
		ox			= "oxen",
		papyrus		= "papyri",
		passerby	= "passersby",
		penknife	= "penknives",
		person		= "people",
		phenomenon	= "phenomena",
		placenta	= "placentae",
		pocketknife	= "pocketknives",
		pupa		= "pupae",
		radius		= "radii",
		reindeer	= "reindeer",
		retina		= "retinae",
		rhinoceros	= "rhinoceros",
		roe			= "roe",
		salmon		= "salmon",
		scarf		= "scarves",
		self		= "selves",
		seraph		= "seraphim",
		series		= "series",
		sheaf		= "sheaves",
		sheep		= "sheep",
		shelf		= "shelves",
		species		= "species",
		spectrum	= "spectra",
		stimulus	= "stimuli",
		stratum		= "strata",
		supernova	= "supernovas",
		swine		= "swine",
		synopsis	= "synopses",
		terminus	= "termini",
		thesaurus	= "thesauri",
		thesis		= "theses",
		thief		= "thieves",
		trout		= "trout",
		vulva		= "vulvae",
		wife		= "wives",
		wildebeest	= "wildebeest",
		wolf		= "wolves",
		woman		= "women",
		yen			= "yen",
		-- RDC 12/Jun/2012 14:24
		-- Note: if you are passing complex terms, like "my filenames" to make singular, you must use the exception parameter.
		file        = "files",
		-- base        = "bases", - this must be handled by passing exception parameter to make-singular, since the singular is ambiguous in this case (see basis above).
		name        = "names",
		filename    = "filenames",
	}

	-- this creates a reverse lookup table of the special dictionary by reversing the variables
	-- names with the string result

	singularLookup = {}
	for k, v in pairs (pluralLookup) do
		singularLookup [v] = k
	end
	
end -- of dictionary initialization function



--- Return singular or plural count of something *** deprecated in favor of str-phrase method.
--
--  <p>Could be enhanced to force case of singular explicitly, instead of just adaptive.</p>
--
--  @usage      Example: str:format( "^1 rendered.", str:plural( nRendered, "photo" ) ) - "one photo" or "2 photos"
--  @usage      Case is adaptive when word form of singular is used. For example: str:plural( nRendered, "Photo" ) - yields "One Photo".
--
--  @param      count       Actual number of things.
--  @param      singularWord    The singular word form to be used if count is 1.
--  @param      useNumberForSingular        may be boolean or string<blockquote>
--      boolean true => use numeric form of singular for better aesthetics.<br>
--      string 'u' or 'upper' => use upper case of singular (first char only).<br>
--      string 'l' or 'lower' => use lower case of singular (first char only).<br>
--      default is adaptive case.</blockquote>
-- 
function String:plural( count, singularWord, useNumberForSingular )
	local countStr
	local suffix = singularWord
	if count then
	    if count == 1 then
			if bool:isBooleanTrue( useNumberForSingular ) then
				countStr = '1 '
			else
		        local firstChar = self:getFirstChar( singularWord )
		        local upperCase
			    if str:isString( useNumberForSingular ) then
			        local case = str:getFirstChar( useNumberForSingular )
			        if case == 'u' then 
    			        upperCase = true
    			    elseif case == 'l' then
    			        upperCase = false
    			    -- else adaptive
    			    end
    			end
    			if upperCase == nil then -- adaptive.
    			    upperCase = (firstChar >= 'A' and firstChar <= 'Z') -- adaptive
    			end
		        if upperCase then
		            countStr = "One "
		        else
		            countStr = "one "
		        end
			end
	    else
	        countStr = self:to( count ) .. " "
			suffix = self:makePlural( singularWord ) -- correct 99.9% of the time.
	    end
	else
		countStr = 'nil '
	end
	return countStr .. suffix
end



--- Make plural phrase from singular *** deprecated in favor of str-phrase method.
--
--  <p>Could be enhanced to force case of singular explicitly, instead of just adaptive.</p>
--
--  @param      count       Actual number of things.
--  @param      singular    The singular form to be used if count is 1.
-- 
--  @usage      Example: str:format( "^1 rendered.", str:pluralize( nRendered, "big photo" ) ) - "1 big photo" or "2 big photos".
--
function String:pluralize( count, singularPhrase )
	local countStr
	local suffix
	if count then
	    if count == 1 then
		    countStr = '1 '
			suffix = singularPhrase
	    else
	        countStr = self:to( count ) .. " "
            local index = self:lastIndexOf( singularPhrase, " " )
            local singularWord
            if index > 0 then
                singularWord = singularPhrase:sub( index + 1 )
            else
                singularWord = singularPhrase
            end
		    local pluralWord = str:makePlural( singularWord )
		    suffix = singularPhrase:sub( 1, index ) .. pluralWord
	    end
	else
		countStr = 'nil '
        suffix = singularPhrase		
	end
	return countStr .. suffix
end



--- A more general purposes version of pluralize, which excludes the numeric part - can be used in other grammatical contexts too, e.g. "are" vs. "is".
--  @usage str:fmtx( "If ^1 ^2 ^3", str:phrase( n, "I", "we" ), str:phrase( n, "was a", "were" ), str:phrase( n, "carpenter", "carpenters" ) ) -- If I was a carpenter; If we were carpenters.
--  @usage str:fmtx( "^1 collected.", str:phrase( n, "photo was", "photos were" ) ) -- 1 photo was collected; 2 photos were collected.
--  @param count number
--  @param singular word or phrase to return if count==1.
--  @param plural word or phrase to return if count~=1 (e.g. 0, or 2+).
function String:phrase( count, singular, plural )
    app:callingAssert( type( count ) == 'number', "first param must be number, not '^1'^2", type( count ), type(count)=='table' and " (call using colon, not dot)" or "" )
    -- assume if count is number that singular will be string, and plural too if it exists. If used in conjunction with str:fmtx no errors will result from passing other wrong params.
    if count == 1 then
        return singular
    elseif plural then
        return plural
    else -- lazy? (the elare script framework version just adds an 's' in this case).
        return self:makePlural( singular )
    end
end



--- Same purpose as pluralize, but faster and guaranteed correct (does not rely on imperfect plural-singular conversion).
function String:oneOrMore( count, singular, plural )
    return count.." "..self:phrase( count, singular, plural )
end



--- Return string with number of items in proper grammar.
--
--  @usage *** deprecated: having to remember which cases require exceptional handling is a bother - use pluralize instead, since pluralizing is more reliable than singularizing.
--
--  @usage not so sure this was a good idea. Seems making plural is more often correct than making singular. ###2
--      <br>e.g. str:nItems( 1, "updates" ) yields "1 updatis", unless you pass the exception param (exception should probably be the default, but for backward compatibility, it's not).
--
--  @param count number of items
--  @param pluralPhrase correct grammer for items if 0 or >1 item.
--  @param exception pass true iff singularizing requires special exception.
--
function String:nItems( count, pluralPhrase, exception )
    local suffix
	local countStr
	if count then
	    if count ~= 1 then -- most of the time.
	        countStr = self:to( count ) .. " "
			suffix = pluralPhrase
		else
		    countStr = '1 '
            local index = self:lastIndexOf( pluralPhrase, " " )
            local pluralWord
            if index > 0 then
                pluralWord = pluralPhrase:sub( index + 1 )
            else
                pluralWord = pluralPhrase
            end
		    local singularWord = str:makeSingular( pluralWord, exception )
		    suffix = pluralPhrase:sub( 1, index ) .. singularWord
	    end
	else
	    Debug.pause( "str--n-items count is nil" )
		countStr = 'nil '
		suffix = pluralPhrase
	end
	return countStr .. suffix
end



--- Determine if prospective string is non-empty - return false if nil (or empty), throw error if not string.
-- 
--  <p>Convenience function to avoid checking both aspects, or getting a "expected string, got nil" error.</p>
--      
--  @usage      If value type is not known to be string if not nil, then use 'is-string' instead.
--  @usage      Throws error if type is not string or nil.
--
--  @return     true iff non-empty string.
--
function String:is( s, name )
    if s ~= nil then
        if type( s ) == 'string' then
            if s:len() > 0 then
                return true
            else
                return false
            end
        else -- data-type error
            name = name or "String:is argument"
            local caller = app:func( 3 ) -- never nil.
            error( LOC( "$$$/X=^1 should be string, not ^2 (^3) - caller: ^4", name, type( s ), tostring( s ), caller ), 2 ) -- 2 => assert error in calling context instead of this one.
        end
    else
        return false
    end
end



--- Determine if prospective string is non-empty - return false if nil, empty, or not a string type value.
--      
--  @usage      Avoids checking aspects individually, or getting a "expected string, got nil or boolean" error.
--  @usage      Also weathers the case when s is a table (or number?)
--
--  @return true iff non-empty string.
--
function String:isString( s )
    if s and ( type( s ) == 'string' ) and ( s ~= "" ) then
        return true
    else
        return false
    end
end



--- Convert windows backslash format to mac/unix/ftp forward-slash notation.
--
--  @usage      Prefer lr-path-utils - standardize-path to assure path to disk file is in proper format for localhost.
--  @usage      This function is primarily used for converting windows sub-paths for use in FTP.
--              <br>Lightroom is pretty good about allowing mixtures of forward and backward slashes in ftp functions,
--              <br>but still - I find it more pleasing to handle explicitly.
--
function String:replaceBackSlashesWithForwardSlashes( _path )
    if _path ~= nil then
        local path = string.gsub( _path, "\\", "/" )
        return path
    else
        return ""
    end
end



--- Assure path separators are consistent with operating system file-system.
--
--  @usage Lr path utils - standardize path function will also do this and then some (making it less efficient).
--      <br>prefer this method if separators are the only potential issue with the path.
--
function String:formatPath( _path )
    if WIN_ENV then
        return string.gsub( _path, "/", "\\" )
    else
        return string.gsub( _path, "\\", "/" )
    end    
end



--- Strip non-ascii characters from binary string.
--
--  @usage Good for searching for text in binary files, otherwise string searcher stops upon first zero byte.</br>
--         could probably just strip zeros, but this gives a printable string that can be logged for debug...
-- 
function String:getAscii( binStr )
    local c = {}
    for i = 1, binStr:len() do
        local ch = str:getChar( binStr, i )
        local cn = string.byte( ch )
        if cn < 32 or cn > 126 then
            -- toss
        else
            c[#c + 1] = ch
        end
    end
    return table.concat( c, '' )
end



--- Global substitution of plain text.
--
--  @param  s           subject string
--  @param  search      search string
--  @param  replace     replacement string
--  @param  padChar     used to pad replacement area, to keep overall string length the same - invaluable for searching and replacing text in binary files.
--  @param  max         maximum number of replacements - default is a million (sanity only).
--
--  @return final string
--
function String:searchAndReplace( s, search, replace, padChar, max )
    local rslt = {}
    local p0 = 1
    local padString = nil
    local padReduce = nil
    if padChar then
        local rlen = replace:len()
        local slen = search:len()
        if  rlen < slen then
            padString = string.rep( padChar, slen - rlen )
        elseif rlen > slen then
            padReduce = rlen - slen
        end
    end
    max = max or 1000000 -- sanity: to prevent potential infinite loop.
    local p1, p2 = s:find( search, 1, true )
    local cnt = 0
    while p1 do
        rslt[#rslt + 1] = s:sub( p0, p1-1 )
        rslt[#rslt + 1] = replace
        p0 = p2 + 1
        if padString then
            rslt[#rslt + 1] = padString -- append pad string to compensate for short replacement.
        elseif padReduce then
            local char = str:getChar( s, p0 )
            local count = 0
            while char == padChar and count < padReduce do
                count = count + 1
                p0 = p0 + 1
                char = str:getChar( s, p0 )
            end
            if count == padReduce then -- all successive chars were padding
                -- good
            else
                error( "Pad fault" )            
            end
        end
        cnt = cnt + 1
        if cnt >= max then
            break
        else
            p1, p2 = s:find( search, p0, true )
        end
    end
    rslt[#rslt + 1] = s:sub( p0 )
    return table.concat( rslt, '' )
end



--- Returns iterator over lines in a string.
--
--  <p>For those times when you already have a file's contents as a string and you want to iterate its lines. This essential does the same thing as Lua's io.lines function.</p>
--
--  @usage      Handles \n or \r\n dynamically as EOL sequence.
--  @usage      Does not handle Mac legacy (\r alone) EOL sequence.
--  @usage      Works as well on binary as text file - no need to read as text file unless the lines must be zero-byte free.
--
function String:lines( s, delim )
    local pos = 1
    local last = false
    return function()
        local starts, ends = string.find( s, '\n', pos, true )
        if starts then
            if string.sub( s, starts - 1, starts - 1 ) == '\r' then
                starts = starts - 1
            end
            local retStr = string.sub( s, pos, starts - 1 )
            pos = ends + 1
            return retStr
        elseif last then
            return nil
        else
            last = true
            return s:sub( pos )
        end
    end
end



--- Breaks a string into tokens by getting rid of the whitespace between them.
--
--  @param              s - string to tokenize.
--  @param              nTokensMax - remainder of string returned as single token once this many tokens found in the first part of the string.
--      
--  @usage              Does similar thing as "split", except delimiter is any whitespace, not just true spaces.
--
--  @return             array of strings (tokens).
--
function String:tokenize( s, nTokensMax )
    local tokens = {}
    local parsePos = 1
    local starts, ends = string.find( s, '%s', parsePos, false ) -- respect magic chars.
    local substring = nil
    while starts do
        if nTokensMax ~= nil and #tokens == (nTokensMax - 1) then -- dont pass ntokens-max = 0.
            substring = LrStringUtils.trimWhitespace( string.sub( s, parsePos ) )
        else
            substring = LrStringUtils.trimWhitespace( string.sub( s, parsePos, starts ) )
        end
        if string.len( substring ) > 0 then
            tokens[#tokens + 1] = substring
        -- else - ignore
        end
        if nTokensMax ~= nil and #tokens == nTokensMax then
            break
        else
            parsePos = ends + 1
            starts, ends = string.find( s, '%s', parsePos, false ) -- respect magic chars.
        end
    end
    if #tokens < nTokensMax then
        tokens[#tokens + 1] = LrStringUtils.trimWhitespace( s:sub( parsePos ) )
    end
    return tokens
end



--- Get filename sans extension from path.
--      
--  @usage  *** I could have sworn this failed when I tried these ops in reverse, i.e. removing extension of leaf-name not sure why (maybe erroneous conclusion). Hmmm...
--
function String:getBaseName( fp )        
    return LrPathUtils.leafName( LrPathUtils.removeExtension( fp ) )
end



---     Return string suitable primarily for short (synopsis-style) debug output and/or display when precise format is not critical.
--      
--      @usage Feel free to pass a nil value and let 'nil' be returned.
--      @usage If object has an explicit to-string method, then it will be called, otherwise the lua global function.
--      @usage Use dump methods for objects and/or log-table..., if more verbose output is desired.
--
function String:to( var )
    if var ~= nil then
        if type( var ) == 'table' and var.toString ~= nil and type( var.toString ) == 'function' then
            return var:toString()
        else
            return tostring( var )
        end
    else
        return 'nil'
    end
end



--- Get root drive of specified path.
--
--  @param path (string, required) absolute path to folder or file.
--
--  @return root (string, always) root will always be non-nil, and "shouldn't" be blank.
--  @return leaves (string, always) leaves will be in least-sig-first order, i.e. path leaf will be at index 1. @19/Nov/2013 16:37 (long after initial writing/testing), I'm not sure if it's possible for last leaf to be same as root - I think not. Not sure if it can be blank either.
--
function String:getRoot( path ) -- ###1 test on mac
    if not str:is( path ) then
        app:callingError( 'path must be non-empty string' )
    end
    -- ###2: could use split-path method, except it returns components in most-sig-first order - I'd hate to break something at this point though (but also, it might fix some things..).
    local root = path
    local leaves = { LrPathUtils.leafName( path ) }
    local parent = LrPathUtils.parent( path )
    while parent ~= nil do
        root = parent
        leaves[#leaves + 1] = LrPathUtils.leafName( parent )
        parent = LrPathUtils.parent( parent )
    end
    return root, leaves
end



--- Get root drive and sub-path of specified path.
--
function String:getDriveAndSubPath( path )
    if not str:is( path ) then
        app:callingError( 'path must be non-empty string' )
    end
    -- ###2: could use split-path method - I'd hate to break something at this point though (but also, it might fix some things..).
    local root = path
    local leaves = { LrPathUtils.leafName( path ) }
    local parent = LrPathUtils.parent( path )
    while parent ~= nil do
        root = parent
        leaves[#leaves + 1] = LrPathUtils.leafName( parent )
        parent = LrPathUtils.parent( parent )
    end
    if #leaves > 1 then -- there are 2 parts
        leaves[#leaves] = nil -- remove root
        tab:reverseInPlace( leaves ) -- make most-sig 1st.
        return root, table.concat( leaves, WIN_ENV and "\\" or "/" ) -- standardize file-path... ###1 test on Mac
    else
        assert( path == root, "?" )
        return path, "" -- all root, no sub-path
    end
end



--- Determine whether start & stop indices, when applied to substring, have a chance of yielding a non-empty string.
--
--  @usage      Note: checking is independent of string len. If len is to be considered, it must be done in calling context.
--
--  @return     0 iff yes. (-1 means both are negative and no-go, +1 means both are positive and no-go).
--
function String:checkIndices( start, stop )
    if start < 0 and stop < start then -- always specifies the empty string.
        return -1
    elseif start > 0 and stop > 0 then
        if stop < start then
            return 1
        -- else OK
        end
    -- note: if one is positive and one is negative, then their relative positioning depends on the length of the string.
    end
    return 0
end



--- Append one string to another with a separator in between, but only if the first string is not empty.
--
--  @usage does NOT assure only a single separator in between - if you need that, use str--child instead.
--
function String:appendWithSep( s1, sep, s2 )
    if str:is( s1 ) then
        return s1 .. sep .. str:to( s2 )
    else
        return str:to( s2 )
    end
end



--- returns path with s2 as child of s1 - assures only 1 separator between them, whether s1 ends with a sep, or s2 begins with one.
--
--  @usage all 3 params are required, and sep is the middle one..
--
--  @param s1 required
--  @param sep required
--  @param s2 required
--
--  @return s1 sep s2
--
function String:child( s1, sep, s2 )
    if app:isAdvDbgEna() then -- check parameter sanity in pgmr debug mode only:
        app:callingAssert( type( s2 ) == 'string', "missing sep or child not string" ) -- more often than not, if s2 isn't string, it's nil
        app:callingAssert( #sep <= 2, "separator length can not be greater than 2 - if too restrictive, change it - it's just for debugging - you sure you got those parameters right?" )
    end
    local pfx
    local sfx
    if str:isEndingWith( s1, sep ) then
        pfx = s1:sub( 1, #s1 - #sep ) -- remove sep (could have just said sub( 1, -(#sep+1) )
    else
        pfx = s1 -- no sep
    end
    if str:isBeginningWith( s2, sep ) then -- until 25/Apr/2014 2:47 was sep was interpreted as regex, now plain text (###1 hope nothing breaks).
        sfx = s2:sub( 1 + #sep ) -- remove sep
    else
        sfx = s2 -- no sep
    end
    return pfx..sep..sfx -- assemble with exactly one sep between.
end
String.parentSepChild = String.child -- function String:parentSepChild(...) -- alternate name that reminds me: separator is required parameter (unlike Lr's child path method) and goes in the MIDDLE.



function String:leafName( path )
    if not str:is( path ) then
        return nil -- let error happen in calling context ;-}.
    end
    if path:sub( 1, 2 ) == "\\\\" then -- network path
        return LrPathUtils.leafName( path:sub( 3 ) ) -- bypass the double-backslashes then Lr func works.
    else
        return LrPathUtils.leafName( path ) -- normal/standard.
    end
end


function String:parent( path )
    if not str:is( path ) then
        return nil -- let error happen in calling context ;-}.
    end
    if path:sub( 1, 2 ) == "\\\\" then -- network path
        if #path == 2 then
            return nil -- this is what LrPathUtils returns when subject path has no parent
        else
            return "\\\\"..( LrPathUtils.parent( path:sub( 3 ) ) or "" ) -- bypass the double-backslashes then Lr func works.
        end
    else
        return LrPathUtils.parent( path ) -- normal/standard: nil if no parent.
    end
end



--- Determines if specified string is all upper case and alpha-numeric.
--
function String:isAllUpperCaseAlphaNum( s )
    if s:find( "[^%u%d]" ) then
        return false
    else
        if app:isAdvDbgEna() then
            assert( s:find( "[%u%d]" ), "no U" )
        end
    end
    return true
end


--- Determines if specified string is all lower case and alpha-numeric.

function String:isAllLowerCaseAlphaNum( s )
    if s:find( "[^%l%d]" ) then
        return false
    else
        if app:isAdvDbgEna() then
            assert( s:find( "[%l%d]" ), "no L" )
        end
    end
    return true
end



--- Get 'a' as string if string else nil.
--
function String:getString( a, nameToThrow )
    if a ~= nil then
        if type( a ) == 'string' then
            return a
        elseif nameToThrow then
            app:error( "'^1' must be string, not '^2'", nameToThrow, type( a ) )
        else
            return nil
        end
    else
        return nil
    end
end



--- Determine whether target string matches include/exclude criteria.
--
--  @usage the idea was for a general purpose filtering function which would be easy to specify parameters.
--      <br>initial use case was for specifying develop presets. Also used to specify folders and/or files for lua-doc'ing.
--
--  @param t string required.
--  @param incl (optional) - include criteria (substr (required), start, stop, regex) - or array of same.
--  @param excl (optional) - exclude criteria (substr (required), start, stop, regex) - or array of same.
--
--  @return true iff target string should be included and not excluded according to specified criteria.
--
function String:includedAndNotExcluded( t, incl, excl )
    local inclNotExcl
    local function check( crit )
        if crit.substr then
            local p1, p2 = t:find( crit.substr, crit.start or 1, not crit.regex )
            if p1 then
                if crit.stop then
                    if p1 <= crit.stop then
                        return true
                    else
                        return false
                    end
                else
                    return true
                end
            else
                --Debug.pause( crit.substr, t, crit.start or 1, not crit.regex )
                return false
            end
        else
            error( "no substr in incl/excl criteria" )
        end
    end
    if incl then
        if #incl == 0 then -- not an array of - just one.
            inclNotExcl = check( incl )
        else
            -- only has to inclNotExcl one inclusion.
            for i, v in ipairs( incl ) do
                if check( v ) then
                    inclNotExcl = true
                    break
                end
            end
        end
    else
        inclNotExcl = true
    end
    if inclNotExcl then
        if excl then
            if #excl == 0 then -- not an array of - just one.
                inclNotExcl = not check( excl )
            else
                -- if any exclusion matches, it's excluded.
                for i, v in ipairs( excl ) do
                    if check( v ) then
                        inclNotExcl = false
                        break
                    end
                end
            end
        -- else matches
        end
    end
    return inclNotExcl -- included, and not excluded.
end



--- Get image number (as string) from filename.
--
--  @usage algorithm: take last digit-sequence which is not smaller than nor greater what is expected.
--      <br> if none such, return nil.
--
--  @param filename (string, required) extension suffix may be OK (safer to strip it to assure it wont be interpreted as being or having the image number),
--      <br>    but folder-pathing prefix should be omitted.
--  @param minLen - minimum acceptable length for image number.
--  @param maxLen - maximum acceptable length for image number.
--
function String:getImageNumStr( filename, minLen, maxLen, atFront )
    minLen = minLen or 0
    maxLen = math.max( minLen, maxLen or math.huge )
    local d = {}
    for digits in string.gmatch( filename, "[%d]+" ) do
        d[#d + 1] = digits
    end
    if atFront then -- new option @10/Jun/2014.
        for i = 1, #d do
            local digits = d[i]
            if ( #digits >= minLen ) and #digits <= maxLen then -- last sequence that is not too small and not too big.
                return digits
            end        
        end
    else -- the default, and backward compatible handling:
        for i = #d, 1, -1 do
            local digits = d[i]
            if ( #digits >= minLen ) and #digits <= maxLen then -- last sequence that is not too small and not too big.
                return digits
            end        
        end
    end
    return nil
end



return String