--[[
     File Name           :     AllFriends.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-01-15 01:45]
     Description         :     WoW addon that automatically synchronizes your friends-lists across multiple characters
--]]

local addonName, AF = ...

AF.addonVersion = "0.1.0"


--- Helper function "startswith"
-- Identifies if specified string starts with the specified pattern
-- @param   someString  The string to check
-- @param   start       The pattern to search for at start of string
-- @return  true        Pattern found
-- @return  false       Pattern not found
local function startswith( someStr, start )
    local res = string.sub( someStr, 0, #start ) == start
    debug:debug( "Is '%s' (len. %d) at start of '%s' (len. %d): %s", start, #start, someStr, #someStr, tostring( res ) )
    return res
end

--- Helper function "endswith"
-- Identifies if specified string ends with the specified pattern
-- @param   someString  The string to check
-- @param   ending      The pattern to search for at end of string
-- @return
local function endswith( someStr, ending )
    local res = ending == "" or someStr:sub( -#ending ) == ending
    debug:debug( "res = '%s' for '%s' (len. %d) at end of '%s' (len. %d)", res, start, #start, someStr, #someStr )
    return res
end


local function slashCommandHandler( msg, editbox )
    msg = string.lower( msg )
    if( startswith( msg, "debug" ) ) then
        local p = string.find( msg, " " )
        debug:setLevel( string.upper( string.sub( msg, p + 1 ) ) )
        return
    end
    if( msg == "dumpfriends" ) then
        friends:dumpFriendSnapshot( )
    else
        debug:always( "/afriends debug <debug|info|warn|error|always>   Set debugging output severity" )
        debug:always( "/afriends dumpfriends: Display the current friends snapshot" )
    end
end

-- See the various frame:RegisterEvent( ... ) statements below for triggering info
local function EventHandler( self, event, ... )

    debug:debug( "Event %s passed to EventHandler().", event )

    -- Fires: Immediately before PLAYER_ENTERING_WORLD on login and UI reload,
    --        but NOT when entering/leaving instances.
        if( event == "PLAYER_LOGIN" ) then
        setupSlashCommands( )
--        loadClassDataFromGlobals( )
        debug:always("v%s initialized.", AF.addonVersion )
    elseif( event == "PLAYER_LOGOUT" ) then
    elseif( event == "FRIENDLIST_UPDATE" ) then
        else
        end
end


function setupSlashCommands( )
    SLASH_ALLFRIENDS1 = "/afriends"
    SlashCmdList["ALLFRIENDS"] = slashCommandHandler
end


function loadClassDataFromGlobals( )
    friends:loadDataFromGlobal( )
end


function saveClassDataToGlobals( )
    friends:saveDataToGlobal( )
end

-- main

-- Set up debugging as required
debug = AF.Debugging_mt:new( )
debug:setLevel( DEBUG )

friends = AF.Friends_mt:new( )          -- Create a new empty, Friends object

local frame = CreateFrame( "Frame" )

-- Set up event-handling.  See the actual event-handler function for info on
-- when each event fires.
frame:RegisterEvent( "PLAYER_LOGIN" )
frame:RegisterEvent( "PLAYER_LOGOUT" )
frame:RegisterEvent( "FRIENDLIST_UPDATE" )

frame:SetScript( "OnEvent", EventHandler )


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
