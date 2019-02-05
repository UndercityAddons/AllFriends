--[[
     File Name           :     Utils.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-03 22:00]
     Description         :     General / miscellaneous utilities for the WoW addon 'AllFriends'
--]]


-- WoW API treats LUA modules as "functions", and passes them two arguments:
--  1. The name of the addon, and
--  2. A table containing the globals for that addon.
-- Using these lets all modules within an addon share the addon's global information.
local addonName, AF = ...


-- Some local overloads to optimize performance (i.e. stop looking up these
-- standard functions every single time they are called, and instead refer to
-- them by local variables.
local ipairs                = ipairs
local pairs                 = pairs
local string                = string
local strfind               = string.find
local strfmt                = string.format
local strgsub               = string.gsub
local strlower              = string.lower
local table                 = table
local tblinsert             = table.insert
local tonumber              = tonumber
local origtostring          = tostring
local type                  = type


-- Table of connected realms.  Declared at file-level scope to try and improve
-- the chances of it remaining persistent until logout.
--
-- NOTE: The table is bi-directionally indexed.  The 1st half of the table
--       contains a numerically indexed list of connected realms (including the
--       local realm).  The 2nd half of the table contains those realms as keys,
--       with their values being their index into the 1st half of the table.
--       E.g:   tConnectedRealms = {
--                                   [1]                = "maelstrom",
--                                   [2]                = "theventureco",
--                                   [3]                = "lightninghoof",
--                                   ["maelstrom"]      = 1,
--                                   ["theventureco"]   = 2,
--                                   ["lightninghoof"]  = 3,
--                                 }
-- So, when iterating through the table by index, only iterate the 1st half of
-- the table.
local tConnectedRealms = {}


--- Helper function "startswith"
-- Identifies if specified string starts with the specified pattern
-- @param   someString  The string to check
-- @param   start       The pattern to search for at start of string
-- @return  true        Pattern found
-- @return  false       Pattern not found
function AF.startswith( someStr, start )
    return someStr:sub( 1, #start ) == start
end


--- Helper function "endswith"
-- Identifies if specified string ends with the specified pattern
-- @param   someStr     The string to check
-- @param   ending      The pattern to search for at end of string
-- @return  true        Pattern found
-- @return  false       Pattern not found
function AF.endswith( someStr, ending )
    return ending == "" or someStr:sub( -#ending ) == ending
end


--- Helper function "_tostring"
-- A variant of tostring() that can handle tables recursively
-- @param   value   table/string/number/etc. to be converted
-- @return  someStr Value converted into a string
function AF._tostring( value )
    local someStr = ""

    if ( type( value ) ~= 'table' ) then
        if ( type( value ) == 'string' ) then
            someStr = strfmt( "%q", value )
        else
            someStr = origtostring( value )
        end
    else
        local auxTable = {}
        for key in pairs( value ) do
            if (tonumber( key ) ~= key ) then
                tblinsert( auxTable, key )
            else
                tblinsert( auxTable, AF._tostring( key ) )
            end
        end
        table.sort( auxTable )

        someStr = someStr  .. '{'
        local separator = ""
        local entry
        for _, fieldName in ipairs( auxTable ) do
            if ( ( tonumber( fieldName ) ) and ( tonumber( fieldName ) > 0 ) ) then
                entry = AF._tostring( value[tonumber( fieldName )] )
            else
                entry = fieldName.." = " .. AF._tostring( value[fieldName] )
            end
            someStr = someStr .. separator..entry
            separator = ", "
        end
        someStr = someStr .. '}'
    end
    return someStr
end


--- Helper function "getCurrentRealm"
-- Returns the current realm name.  The name will be in all-lowercase format,
-- and will have all leading,trailing, and intervening spaces removed.
-- @return          Name of current realm (all lowercase, no spaces)
function AF.getCurrentRealm( )
    return strlower( strgsub( GetRealmName( ), "%s+", "" ) )
end


--- Helper function "getConnectedRealms"
-- Returns (and if necessary, first creates) a table containing all realms that
-- are connected to the current one (including the current one itself).
-- Since this is unlikely to ever change while logged in, the function attempts
-- to be efficient by only generating the table upon first invocation; there-
-- after it simply returns already-built table.
--
-- NOTE: The table is bi-directionally indexed.  The 1st half of the table
--       contains a numerically indexes list of realms.  The 2nd half of the
--       table contains those realms as keys (with the numeric indices as
--       values). Use ipairs() to iterate through only the numerically-
--       indexed keys.  Use #tablename to get the number of realms.
--
-- @return  Bi-indexed table of local + all connected realms.
function AF.getConnectedRealms( )

    -- tConnectedRealms must persist across multiple function calls, so it is
    -- delcared at file-level scope above...

    -- If tConnectedRealms hasn't already been constructed then do that now
    if( tConnectedRealms[1] == nil ) then
        -- Create table and count of connected (plus current) realms
        tConnectedRealms = GetAutoCompleteRealms( )
        local numConnectedRealms = #tConnectedRealms

        -- If not connected, at-least insert the local realm name
        if( numConnectedRealms < 1 ) then
            tConnectedRealms[1] = AF.getCurrentRealm( )
            numConnectedRealms = 1
        end

        -- Add a set of reverse entries to the table, allowing for bi-directional
        -- keying by either numeric index or realm-name.  While we're at it,
        -- change the realm names to all-lowercase.
        for i = 1, numConnectedRealms do
            tConnectedRealms[i] = strlower( tConnectedRealms[i] )
            tConnectedRealms[tConnectedRealms[i]] = i
        end
    end
    return tConnectedRealms
end


--- Helper function "getLocalizedRealm"
-- Takes a name in one of the following forms:
--    - "playername"            (gets treated as local realm)
--    - "playername-realmname"  (realm is as-specified)
--    - ""                      (gets treated as local realm)
--    - nil                     (gets treated as local realm)
--
-- Strips the player name if present, and treats the remainder as a realm-name.
-- Identifies whether this realm is:
--   1) local,
--   2) part of the current connected realm-group, or
--   3) non-local and not part of the current realm group.
--
-- NOTE: All returned realm-names will be in all-lowercase, and have all spaces
--       as well as any supplied player name compoenent stripped out.
--
-- @param   nameAndRealm                    Realm or "name-realm" to be localized
-- @return  true,  <name of local realm>    Specified realm is local
-- @return  true,  <name of local realm>    Specified realm is nil or empty
-- @return  false, <name of realm>          Specified realm is non-local but connected
-- @return  false, "unknown"                Specified realm non-local and not connected
function AF.getLocalizedRealm( nameAndRealm )

    -- Get the name of the local (i.e. current) realm
    local localRealm = AF.getCurrentRealm( )

    -- Handle cases where specified realm is nil or empty
    if( not nameAndRealm or nameAndRealm == "" ) then
        debug:debug( "Specified name/realm is nil or empty - not getting localized realm." )
        return true, localRealm
    end

    -- Isolate on the realm part of the passed name, discarding any player name
    -- that may have been included.  Convert what remains to all-lowercase, and
    -- strip any contained spaces.  Treat names without "-" as local player
    -- names.
    local realmName
    if( strfind( nameAndRealm, "-" ) ) then
        realmName = strlower( strgsub( strgsub( nameAndRealm, "^.*-", "" ), "%s+", "" ) )
        debug:debug( "realmName: %s", realmName )
    else
        realmName = localRealm
    end

    -- Handle case where specified realm is the local realm
    if( realmName == localRealm ) then
        debug:debug( "Specified realm == local realm." )
        return true, localRealm
    end

    local tConnectedRealmList = AF.getConnectedRealms( )

    -- Handle case where specified realm is non-local and the local realm is
    -- not connected to any others.  Note AF.getConnectedRealms( ) returns
    -- at-least one realm in the table - the local realm.
    if( tConnectedRealmList[2] == nil ) then
        debug:debug( "Specified realm non-local, local realm is not connected." )
        return false, "unknown"
    end

    -- Handle all cases where specified realm is non-local but not connected to
    -- the local realm.
    if(  tConnectedRealmList[localRealm] == nil ) then  -- specified realm not connected
        debug:debug( "Specified realm non-local, and not-connected to local realm." )
        return false, "unknown"
    else                                                -- specified realm is connected
        debug:debug( "Specified realm non-local and connected to local realm." )
        return false, realmName
    end
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
