--[[
     File Name           :     AllFriends.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-01-22 15:32]
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


--- Addon local function "initialOnUpdateHandler"
-- Responsible for doing everything required during addon-startup, prior to
-- commencing normal event-based operation.
-- @param    self      Addon context
-- @param    elapsed   How long since the last updated call cycle
local function initialOnUpdateHandler( self, elapsed )
    debug:debug( "Entered initialOnUpdateHandler( )" )

    -- If no players in current friend list then don't bother checking if the
    -- friend-list is available yet, because all we will potentially be doing
    -- are inserts.  Just proceed with the snapshot-restore; any adds to the
    -- friend-list will queue up until the list becomes available.
    --
    -- If the friend-list contains players, then we need to check availability
    -- of the friend list because we may need to remove stale entries.  Do not
    -- proceed with the snapshot-restore until the list becomes available.
    if( friends:countFriendList( ) == 0 or friends:isFriendListAvailable( ) == true ) then
        frame:SetScript( "OnUpdate", nil )
        debug:debug( "OnUpdate disabled." )
        friends:restoreSnapshot( )
        frame:RegisterEvent( "PLAYER_LOGOUT" )
        frame:RegisterEvent( "FRIENDLIST_UPDATE" )
        debug:debug( "Events registered." )
    else
        debug:debug( "Friend list contains friends but is currently unavailable - will check again." )
    end
end

-- See the various frame:RegisterEvent( ... ) statements below for triggering info
local function EventHandler( self, event, ... )

    debug:info( "Event %s passed to EventHandler().", event )

    -- Fires: Immediately before PLAYER_ENTERING_WORLD on login and UI reload,
    --        but NOT when entering/leaving instances.
    if( event == "PLAYER_LOGIN" ) then
        setupSlashCommands( )
        debug:loadDataFromGlobal( )
        friends:loadDataFromGlobal( )
        debug:always("v%s initialized.", AF.addonVersion )

        frame:SetScript( "OnUpdate", initialOnUpdateHandler )
        debug:debug( "OnUpdate has been set up." )

    -- Fires: Whenever the player logs out or the UI is reloaded, just-before
    --        SavedVariables are saved.  Fires after PLAYER_LEAVING_WORLD.
    elseif( event == "PLAYER_LOGOUT" ) then
        debug:saveDataToGlobal( )
        friends:saveDataToGlobal( )

    -- Fires whenever: - You login
    --                 - Opening friends window (twice?)
    --                 - Switching from ignore list to friends list
    --                 - Switching from guild/raid/who tab back to friends tab (twice?)
    --                 - Adding/removing friends, and
    --                 - Friends come online or go offline
    elseif( event == "FRIENDLIST_UPDATE" ) then
        friends:takeSnapshot( )
        debug:debug( "Took snapshot of friends-list - contains %d friends.", friends:countFriendsInSnapshot( ) )

    -- Catchall for any registered but unhandled events
    else
        debug:debug( "Unexpected event %s passed to EventHandler() - ignored.", event )
    end
end


function setupSlashCommands( )
    SLASH_ALLFRIENDS1 = "/afriends"
    SlashCmdList["ALLFRIENDS"] = slashCommandHandler
end



debug = AF.Debugging_mt:new( )          
debug:setLevel( ERROR )                  -- Default until persistent state loaded from Global

friends = AF.Friends_mt:new( )          


-- There seems to be issues with the player's friend-list not being available at
-- the point events like PLAYER_LOGIN or even PLAYER_ENTERING_WORLD are fired.
-- To accomodate this, we do almost nothing on PLAYER_LOGIN, except for setting
-- up an Onpdate timer that frequently checks for the friends-list availability,
-- irrespective of events.  The OnUpdate timer handler will do the initial
-- friend-list sync and set up any subsequent event-handling we want (and
-- disable itself in the proocess).
frame = CreateFrame( "Frame" )
frame:RegisterEvent( "PLAYER_LOGIN" )
frame:SetScript( "OnEvent", EventHandler )


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
