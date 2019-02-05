--[[
     File Name           :     AllFriends.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-03 23:31]
     Description         :     WoW addon that automatically synchronizes your friends-lists across multiple characters
--]]


-- WoW API treats LUA modules as "functions", and passes them two arguments:
--  1. The name of the addon, and
--  2. A table containing the globals for that addon.
-- Using these lets all modules within an addon share the addon's global information.
local addonName, AF = ...

AF.addonVersion = "0.1.0"


-- Some local overloads to optimize performance (i.e. stop looking up these
-- standard functions every single time they are called, and instead refer to
-- them by local variables.
local string            = string
local strfind           = string.find
local strlower          = string.lower
local strupper          = string.upper
local strsub            = string.sub
local tostring          = AF._tostring
local startswith        = AF.startswith


local function slashCommandHandler( msg, editbox )
    msg = strlower( msg )

    -- Isolate the specified command's option (e.g. "show" in "/afriends delete show" )
    local cmdDelim = strfind( msg, " " )
    local cmdOpt = ""
    if( cmdDelim ) then
        cmdOpt = strlower( strsub( msg, cmdDelim + 1 ) )
    end

    -- Set the debugging severity level
    if( startswith( msg, "debug" ) ) then
        if( cmdOpt == "show" or cmdOpt == "" ) then
            debug:always( "Debug level is currently %s.", strupper( debug:getLevel( ) ) )
        else
            debug:setLevel( cmdOpt )
            debug:always( "Debug level now %s.", strupper( cmdOpt ) )
        end
        return

    -- Show the contents of the current snapshot
    elseif( msg == "friends" ) then
        debug:always( "# of friends in snapshot: %d", snapshot:getNumFriends( ) )
        debug:always( "--------------------" )
        snapshot:dumpFriendSnapshot( )
        return

    -- Control whether the addon deletes stale friends from the friend list or not
    elseif( startswith( msg, "delete" ) ) then
        if( cmdOpt == "show" or cmdOpt == "" ) then
            if( friendList:isDeletionActive( ) ) then
                debug:always( "Stale friend deletion enabled." )
            else
                debug:always( "Stale friend deletion disabled." )
            end
        elseif( cmdOpt == "on" or cmdOpt == "true" or cmdOpt == "yes" ) then
            friendList:enableDeletion( )
            debug:always( "Stale friend deletion enabled." )
        elseif( cmdOpt == "off" or cmdOpt == "false" or cmdOpt == "no" ) then
            friendList:disableDeletion( )
            debug:always( "Stale friend deletion disabled." )
        else
            debug:always( "Bad / incomplete command: delete %s", cmdOpt )
        end
        return

    -- Control whether or not self.doDelete is ignored and instead stale-friend
    -- deletions are done for ALL characters on the current (and all connected)
    -- realms
    elseif( startswith( msg, "fullsync" ) ) then
        if( cmdOpt == "show" or cmdOpt == "" ) then
            if( friendList:isFullSyncActive( ) ) then
                debug:always( "Full-Sync is turned ON for the current (and all connected) realms." )
            else
                debug:always( "Full-Sync is turned OFF for the current (and all connected) realms." )
            end
        elseif( cmdOpt == "on" or cmdOpt == "true" or cmdOpt == "yes") then
            friendList:enableFullSync( )
            debug:always( "Full-Sync now ON for the current (and all connected) realms." )
        elseif( cmdOpt == "off" or cmdOpt == "false" or cmdOpt == "no" ) then
            friendList:disableFullSync( )
            debug:always( "Full-Sync now OFF for the current (and all connected) realms." )
        else
            debug:always( "Bad / incomplete command: fyllsync %s", cmdOpt )
        end
        return

    -- test of new player object
    elseif( startswith( msg, "testplayer" ) ) then
        if( cmdOpt == "new" ) then
            local someNewPlayer = AF.Player:new( )
            if( someNewPlayer ) then
                debug:always( "New player created: name=%s, realm=%s, isLocal=%s",
                              someNewPlayer.name, someNewPlayer.realm, tostring( someNewPlayer.isLocal ) )
            else
                  debug:always( "Player object not created." )
            end
        elseif( cmdOpt == "fulz" ) then
            local someNewPlayer = AF.Player:new( "FULzaMOth" )
            if( someNewPlayer ) then
                debug:always( "New player created: name=%s, realm=%s, isLocal=%s",
                              someNewPlayer.name, someNewPlayer.realm, tostring( someNewPlayer.isLocal ) )
            else
                    debug:always( "Player object not created." )
            end
        elseif( cmdOpt == "fulzveco" ) then
            local someNewPlayer = AF.Player:new( "FULzaMOth-theventureco" )
            if( someNewPlayer ) then
                debug:always( "New player created: name=%s, realm=%s, isLocal=%s",
                              someNewPlayer.name, someNewPlayer.realm, tostring( someNewPlayer.isLocal ) )
            else
                debug:always( "Player object not created." )
            end
        else
            debug:always( "Bad / incomplete command: testplayer %s", cmdOpt )
        end
        return
    end

    -- Unrecognized slashcommand - display help (with fancy colours!)
    local REGULAR = AF.DBG_REGULAR
    local COMMAND = AF.DBG_LIME
    local OPTION  = AF.DBG_CYAN
    local ARG     = AF.DBG_YELLOW
    debug:always( "%s/afriends %sdebug %s<%sdebug%s, %sinfo%s, %swarn%s, %serror%s, %salways%s>",
                   COMMAND, OPTION, REGULAR, ARG,REGULAR, ARG,REGULAR, ARG,REGULAR, ARG,REGULAR, ARG,REGULAR )
    debug:always( "     (Sets the debugging output severity)" )
    debug:always( "" )
    debug:always( "%s/afriends %sdelete %s<%son%s, %soff%s, %sshow%s>",
                   COMMAND, OPTION, REGULAR, ARG,REGULAR, ARG,REGULAR, ARG,REGULAR )
    debug:always( "     (Show or set whether the addon deletes stale friends)" )
    debug:always( "" )
    debug:always( "%s/afriends %sfullsync %s<%son%s, %soff%s, %sshow%s>",
                   COMMAND, OPTION, REGULAR, ARG,REGULAR, ARG,REGULAR, ARG,REGULAR )
    debug:always( "     (Show or set whether the addon ignores the 'delete' option" )
    debug:always( "      and instead deletes ALL stale friends for the current" )
    debug:always( "      and all connected realms" )
    debug:always( "" )
    debug:always( "%s/afriends %sfriends%s",
                   COMMAND, OPTION, REGULAR )
    debug:always( "     (Display contents of the current friends snapshot)" )
    return
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
    if( friendList:countFriendList( ) == 0 or friendList:isFriendListAvailable( ) == true ) then
        frame:SetScript( "OnUpdate", nil )
        debug:debug( "OnUpdate disabled." )
        snapshot:restoreFriendsSnapshot( friendList )
        frame:RegisterEvent( "PLAYER_LOGOUT" )

        -- For FRIENDLIST_UPDATE, delay a bit before registering the event to
        -- allow all changes made by the restore to complete first. This should
        -- help to avoid unnecessary triggering of new snapshots caused by the
        -- restore changes.
        C_Timer.After( 10, function()
            frame:RegisterEvent( "FRIENDLIST_UPDATE" )
            debug:debug( "Events registered." )
        end )

    else
        debug:debug( "Friend list contains friends but is currently unavailable - will check again." )
    end
end


local function setupSlashCommands( )
    SLASH_ALLFRIENDS1 = "/afriends"
    SlashCmdList["ALLFRIENDS"] = slashCommandHandler
end



-- See the various frame:RegisterEvent( ... ) statements below for triggering info
local function EventHandler( self, event, ... )

    debug:info( "Event %s passed to EventHandler().", event )

    -- Fires: Immediately before PLAYER_ENTERING_WORLD on login and UI reload,
    --        but NOT when entering/leaving instances.
    if( event == "PLAYER_LOGIN" ) then
        setupSlashCommands( )
        debug:loadDataFromGlobal( )
        snapshot:loadDataFromGlobal( )
        debug:always("v%s initialized.", AF.addonVersion )

        frame:SetScript( "OnUpdate", initialOnUpdateHandler )
        debug:debug( "OnUpdate has been set up." )

    -- Fires: Whenever the player logs out or the UI is reloaded, just-before
    --        SavedVariables are saved.  Fires after PLAYER_LEAVING_WORLD.
    elseif( event == "PLAYER_LOGOUT" ) then
        debug:saveDataToGlobal( )
        snapshot:saveDataToGlobal( )

    -- Fires whenever: - You login
    --                 - Opening friends window (twice?)
    --                 - Switching from ignore list to friends list
    --                 - Switching from guild/raid/who tab back to friends tab (twice?)
    --                 - Adding/removing friends, and
    --                 - Friends come online or go offline
    elseif( event == "FRIENDLIST_UPDATE" ) then
        snapshot:refreshFriendsSnapshot( friendList )
        debug:debug( "Took snapshot of friends-list - contains %d friends.", snapshot:getNumFriends( ) )

    -- Catchall for any registered but unhandled events
    else
        debug:debug( "Unexpected event %s passed to EventHandler() - ignored.", event )
    end
end


debug = AF.Debugging:new( )
debug:setLevel( ERROR )                  -- Default until persistent state loaded from Global

friendList = AF.Friends:new( )
snapshot = AF.Snapshot:new( )


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
