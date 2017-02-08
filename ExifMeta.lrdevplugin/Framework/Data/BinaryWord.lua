--[[================================================================================

        BinaryWord.lua
        
        *** originally intended for sha1 computation, but such was never used.
        You can try using if you want, just be aware it's had only limited test exercise..
        
        Word meaning 32-bit word.

================================================================================--]]


local BinaryWord, dbg, dbgf = Object:newClass{ className = 'BinaryWord', register = false }



--- Constructor for extending class.
--
function BinaryWord:newClass( t )
    return Object.newClass( self, t )
end



--- Constructor for new instance.
--
function BinaryWord:new( t )
    return Object.new( self, t )
end



function BinaryWord:getString( a )
    
    if a >= math.pow( 2, 32 ) then
        app:callingError( "bad a: ^1", a )
    end

    local s = {}
    local mask = math.pow( 2, 31 )
    for i = 1, 32 do
        if LrMath.bitAnd( a, mask ) == mask then
            s[i] = "1"
        else
            s[i] = "0"
        end
        mask = mask / 2
    end
    return table.concat( s, "" )

end



return BinaryWord