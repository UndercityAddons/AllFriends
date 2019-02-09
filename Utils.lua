--[[
     File Name           :     Utils.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-09 02:12]
     Description         :     General / miscellaneous utilities for the WoW addon 'AllFriends'
--]]


-- WoW API treats LUA modules as "functions", and passes them two arguments:
--  1. The name of the addon, and
--  2. A table containing the globals for that addon.
-- Using these lets all modules within an addon share the addon's global information.
--local addonName, AF = ...
local addonName, AF_G = ...


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
local tblsort               = table.sort
local tonumber              = tonumber
local origtostring          = tostring
local type                  = type


-- Table of connected realms.  Declared at file-level scope to try and improve
-- the chances of it remaining persistent until logout.
local tConnectedRealms   = { "empty" }
local numConnectedRealms = 0


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
        tblsort( auxTable )

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
-- Returns a table of the current realm group (i.e. the local realm + all
-- connected realms), along with the size of the realm-group.
-- The first time this function is called, it will populate the table and
-- return it.  Subsequent calls will simply return the same table, since
-- realm-group composition should never change while a player is online.
-- @return  tConnectedRealms    Table representing the current realm-group
-- @return  numConnectedRealms  Number of realms in the realm-group.
function AF.getConnectedRealms( )

    -- tConnectedRealms must persist across multiple function calls, so it is
    -- delcared at file-level scope above...

    -- If tConnectedRealms has not already been populated with the current
    -- realm-group (local realm + any connected realms) then load it now.  The
    -- list provided by the WoW API is numerically indexed. To make lookups
    -- easier, convert it into a hashed table where the keys are the realm-
    -- names.  Make all names all-lowercase.
    if( numConnectedRealms == 0 ) then
        debug:debug( "tConnectedRealms not populated - initializing now." )
        wipe( tConnectedRealms )
        local tmpRealmList = GetAutoCompleteRealms( )
        if( #tmpRealmList == 0 ) then
            tblinsert( tConnectedRealms, AF.getCurrentRealm( ) )
            numConnectedRealms = 1
        else
            for i = 1, #tmpRealmList do
                tblinsert( tConnectedRealms, strlower( tmpRealmList[i] ) )
            end
            numConnectedRealms = #tmpRealmList
        end
    else
        debug:debug( "tConnectedRealms already populated." )
    end

    debug:info ("Returning %d realms: [%s]", numConnectedRealms, AF._tostring( tConnectedRealms ) )
    return tConnectedRealms, numConnectedRealms
end


--- Helper function "isRealmConnected"
-- Takes the specified realm and returns true/false to indicate whether or not
-- it is connected to the current realm (or is equal to the local realm).
-- @param   realmName       Name of realm to check
-- @return  true            Realm is connected to (or equals) the local realm
-- @return  false           Realm is not connected to and not equal the local realm
function AF:isRealmConnected( realmName )

    realmName = strlower( realmName )

    local tRealmGroup, _ = AF.getConnectedRealms( )
    for _, v in pairs(tRealmGroup) do
        if( realmName == v ) then
            debug:info( "Realm %s is connected to our realm.", realmName )
            return true
        end
    end
    debug:info( "Realm %s is not connected to our realm." , realmName )
    return false
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
function AF:getLocalizedRealm( nameAndRealm )

    debug:debug( "Received arg [%s]", nameAndRealm )
    -- Get the name of the local (i.e. current) realm
    local localRealm = AF:getCurrentRealm( )

    -- Handle cases where specified realm is nil or empty
    if( nameAndRealm == nil or nameAndRealm == "" ) then
        debug:info( "Specified name/realm is nil or empty - not getting localized realm." )
        return true, localRealm
    else
        nameAndRealm = strlower( nameAndRealm )
    end

    -- Isolate on the realm part of the passed name, discarding any player name
    -- that may have been included.  Convert what remains to all-lowercase, and
    -- strip any contained spaces.  Treat names without "-" as local player
    -- names.
    local realmName
    if( strfind( nameAndRealm, "-" ) ) then
        realmName = strgsub( strgsub( nameAndRealm, "^.*-", "" ), "%s+", "" )
    else
        realmName = localRealm
    end
    debug:debug( "Specified realm: %s", realmName )

    -- Handle case where specified realm equals the local realm
    if( realmName == localRealm ) then
        debug:debug( "realm %s == local realm.", realmName )
        return true, localRealm
    end

    local tConnectedRealmList, numConnectedRealmList = AF.getConnectedRealms( )
    debug:debug( "tConnectedRealmList: %d realms [%s]", numConnectedRealmList, AF._tostring( tConnectedRealmList ) )

    if( AF:isRealmConnected( realmName ) == true ) then
        debug:info( "Realm %s different than local realm, but is connected.", realmName )
        return false, realmName
    end

    debug:info( "Realm %s not connected to local realm.", realmName )
    return false, "unknown"
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
