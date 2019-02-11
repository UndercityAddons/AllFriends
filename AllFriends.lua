--[[ File Name           :     AllFriends.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-11 11:58]
     Description         :     WoW addon that automatically synchronizes your friends-lists across multiple characters
--]]


-- WoW API treats LUA modules as "functions", and passes them two arguments:
--  1. The name of the addon, and
--  2. A table containing the globals for that addon.
-- Using these lets all modules within an addon share the addon's global information.
--local addonName, AF = ...
local addonName, AF_G= ...

AF.addonVersion = "0.1.0"


-- Some local overloads to optimize performance (i.e. stop looking up these
-- standard functions every single time they are called, and instead refer to
-- them by local variables.
local string            = string
local strfind           = string.find
local strlower          = string.lower
local strupper          = string.upper
local strsub            = string.sub


--- Addon local function "outputFriendSnapshotList"
-- Dumps the contents of the current snapshot to debugging output.
local function outputFriendSnapshotList( snapshotObj, whichSnap )
        snapshotObj:dumpFriendSnapshot( whichSnap )
end


--- Addon local function "outputFriendSnapshotList"
-- Displays a colourized count of friends in the current snapshot.
local function outputFriendSnapshotCount( snapshotObj, whichSnap )
    debug:always( "Friends in %s%s%s-snapshot: %s%d%s", CLR_OPT, whichSnap, CLR_REG,
    CLR_VALUE, snapshotObj:countFriends( whichSnap ), CLR_REG )
end


--- Addon local function "outputDeleteStatus"
-- Displays a colourized indicator of the current friend-deletion setting.
local function outputDeleteStatus( snapshotObj )
    if( snapshotObj:isDeletionActive( ) ) then
        debug:always( "Stale friend deletion: %senabled%s", CLR_OPT_ON, CLR_REG )
    else
        debug:always( "Stale friend deletion: %sdisabled%s", CLR_OPT_OFF, CLR_REG )
    end
end


--- Addon local function "outputDebuggingStatus"
-- Displays a colourized indicator of the current debugging severity level.
local function outputDebuggingStatus( debugObj )
    debug:always( "Debug level is currently %s%s%s.", CLR_VALUE, strupper( debugObj:getLevel( ) ), CLR_REG )
end


--- Addon local function "outputFullSyncStatus"
-- Displays a colourized indicator of the current full-sync setting.
local function outputFullSyncStatus( snapshotObj )
    if( snapshotObj:isFullSyncActive( ) ) then
        debug:always( "Full-Sync (current and connected realms): %sON%s", CLR_OPT_ON, CLR_REG )
    else
        debug:always( "Full-Sync (current and connected realms): %sOFF%s", CLR_OPT_OFF, CLR_REG )
    end
end


local function slashCommandHandler( msg, editbox )
    msg = strlower( msg )

    -- Isolate the specified command's option (e.g. "show" in "/af delete show" )
    local cmdDelim = strfind( msg, " " )
    local cmdOpt = ""
    if( cmdDelim ) then
        cmdOpt = strlower( strsub( msg, cmdDelim + 1 ) )
    end

    -- Display current state/status for the addon
    if( AF.startswith( msg, "status" ) ) then
        outputFriendSnapshotCount( snapshot, "player" )
        outputFriendSnapshotCount( snapshot, "master" )
        outputDeleteStatus( snapshot )
        outputFullSyncStatus( snapshot )
        outputDebuggingStatus( debug )
        return

    -- Set the debugging severity level
    elseif( AF.startswith( msg, "debug" ) ) then
        if( cmdOpt == "show" or cmdOpt == "" ) then
            outputDebuggingStatus( debug )
        else
            debug:setLevel( cmdOpt )
            debug:always( "Debug level now %s.", strupper( cmdOpt ) )
        end
        return

    -- Show the contents of the current snapshot
    elseif( msg == "friends" ) then
            outputFriendSnapshotCount( snapshot, "player" )
            outputFriendSnapshotList( snapshot, "player" )
            debug:always( "--------------------" )
            outputFriendSnapshotCount( snapshot, "master" )
            outputFriendSnapshotList( snapshot, "master" )
            debug:always( "--------------------" )
        return

    -- Control whether the addon deletes stale friends from the friend list or not
    elseif( AF.startswith( msg, "delete" ) ) then
        if( cmdOpt == "show" or cmdOpt == "" ) then
            outputDeleteStatus( snapshot )
        elseif( cmdOpt == "on" or cmdOpt == "true" or cmdOpt == "yes" ) then
            snapshot:setDeletion( true )
            outputDeleteStatus( snapshot )
        elseif( cmdOpt == "off" or cmdOpt == "false" or cmdOpt == "no" ) then
            snapshot:setDeletion( false )
            outputDeleteStatus( snapshot )
        else
            debug:always( "Bad / incomplete command: delete %s", cmdOpt )
        end
        return

    -- Control whether or not self.doDelete is ignored and instead stale-friend
    -- deletions are done for ALL characters on the current (and all connected)
    -- realms
    elseif( AF.startswith( msg, "fullsync" ) ) then
        if( cmdOpt == "show" or cmdOpt == "" ) then
            outputFullSyncStatus( snapshot )
        elseif( cmdOpt == "on" or cmdOpt == "true" or cmdOpt == "yes") then
            snapshot:setFullSync( true, friendList )
            outputFullSyncStatus( snapshot )
        elseif( cmdOpt == "off" or cmdOpt == "false" or cmdOpt == "no" ) then
            snapshot:setFullSync( false, friendList )
            outputFullSyncStatus( snapshot )
        else
            debug:always( "Bad / incomplete command: fyllsync %s", cmdOpt )
        end
        return
    end

    -- Unrecognized slashcommand - display help (with fancy colours!)
    debug:always( "%s/af %sstatus%s",
                   CLR_CMD, CLR_OPT, CLR_REG )
    debug:always( "     (Displays current settings/status)" )
    debug:always( "" )
    debug:always( "%s/af %sdebug %s<%sdebug%s, %sinfo%s, %swarn%s, %serror%s, %salways%s>",
                   CLR_CMD, CLR_OPT, CLR_REG, CLR_ARG,CLR_REG, CLR_ARG,CLR_REG,
                   CLR_ARG,CLR_REG, CLR_ARG,CLR_REG, CLR_ARG,CLR_REG )
    debug:always( "     (Sets the debugging output severity)" )
    debug:always( "" )
    debug:always( "%s/af %sdelete %s<%son%s, %soff%s, %sshow%s>",
                   CLR_CMD, CLR_OPT, CLR_REG, CLR_ARG,CLR_REG, CLR_ARG,CLR_REG, CLR_ARG,CLR_REG )
    debug:always( "     (Show or set whether the addon deletes stale friends)" )
    debug:always( "" )
    debug:always( "%s/af %sfullsync %s<%son%s, %soff%s, %sshow%s>",
                   CLR_CMD, CLR_OPT, CLR_REG, CLR_ARG,CLR_REG, CLR_ARG,CLR_REG, CLR_ARG,CLR_REG )
    debug:always( "     (Show or set whether the addon ignores the 'delete' option" )
    debug:always( "      and instead deletes ALL stale friends for the current" )
    debug:always( "      and all connected realms" )
    debug:always( "" )
    debug:always( "%s/af %sfriends%s",
                   CLR_CMD, CLR_OPT, CLR_REG )
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
        snapshot:restoreFriendsSnapshot( friendList )   -- Push snapshot contents into friend-list
        frame:RegisterEvent( "PLAYER_LOGOUT" )

        -- For FRIENDLIST_UPDATE, delay a bit before registering the event to
        -- allow all changes made by the restore to complete first. This should
        -- help to avoid unnecessary triggering of new snapshots caused by the
        -- restore changes.
        C_Timer.After( 10, function()
            snapshot:refreshFriendsSnapshot( friendList )   -- Force an initial snapshot refresh
            frame:RegisterEvent( "FRIENDLIST_UPDATE" )
            debug:debug( "Events registered." )
        end )

    else
        debug:debug( "Friend list contains friends but is currently unavailable - will check again." )
    end
end


local function setupSlashCommands( )
    SLASH_ALLFRIENDS1 = "/af"
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
        snapshot:saveDataToGlobal( )
        debug:saveDataToGlobal( )

    -- Fires whenever: - You login
    --                 - Opening friends window (twice?)
    --                 - Switching from ignore list to friends list
    --                 - Switching from guild/raid/who tab back to friends tab (twice?)
    --                 - Adding/removing friends, and
    --                 - Friends come online or go offline
    elseif( event == "FRIENDLIST_UPDATE" ) then
        snapshot:refreshFriendsSnapshot( friendList )
        debug:debug( "Took snapshot of friends-list - contains %d friends.", snapshot:countFriends( "master" ) )

    -- Catchall for any registered but unhandled events
    else
        debug:debug( "Unexpected event %s passed to EventHandler() - ignored.", event )
    end
end


debug = AF.Debugging:new( )
--debug:setLevel( WARN )  -- Default until persistent state loaded from Global
debug:setLevel( DEBUG ) -- Default until persistent state loaded from Global

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
