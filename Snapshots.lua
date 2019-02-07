--[[
     File Name           :     Snapshots.lua
     Created By          :     tubiakou
     Creation Date       :     [2019-01-07 01:28]
     Last Modified       :     [2019-02-07 11:26]
     Description         :     Snapshots class for the WoW addon AllFriends

This module of AllFriends implements a Snapshot class, responsible for all
functionality related to Snapshots (e.g. of the Friend List, the Ignore list,
etc.). These snapshots are what will be serialized and deserialized to/from
SavedVariables storage whenever the player logs off and back on.
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
local string                = string
local strlower              = string.lower
local pairs                 = pairs


--- Class table
AF.Snapshot = {

    -- Class data prototypes (i.e. "default" values for new objects)
    ----------------------------------------------------------------------------
    class            = "snapshot", -- Class identifier
    tFriends         = {},         -- Tbl of snapshotted player friends
    numFriends       = 0,          -- Number of friends in snapshot
    Realm            = "",         -- Name of current realm
    tConnectedRealms = {},         -- Tbl of connected or local realms
    snapshotRestored = false,      -- Has a snapshot-restore completed
    doDeletions      = false,      -- Should the addon delete stale friends
    fullSync         = false,      -- Ignore doDeletions (turn TRUE for all currently connected realms)
    tSkipDelete      = {},         -- Table of stale friends to not delete
}
AF.Snapshot_mt          = {}            -- Metatable
AF.Snapshot_mt.__index  = AF.Snapshot   -- Look in the class for undefined methods


--- Class private method "wipeFriends"
-- Wipes all friends from the snapshot.
-- @param   self        Object context
local function wipeFriends( self )
    debug:trace( "entered" )
    wipe( self.tFriends )
    self.numFriends = 0
    debug:debug( "Snapshot wiped of all friends." )
    debug:trace( "exited" )
    return
end


--- class private method "setSkipDelete"
-- Takes the specified player object, treats them as a stale friend (i.e. in a
-- friend-list but not in the snapshot), and sets/clears their SkipDelete
-- status.  Having this status set causes the specified stale friend to not be
-- withheld from the friend list on subsequent snapshot restores.
-- @param   self        Object context
-- @param   playerObj   Player object to act on.
-- @param   status      (true/false) Sets/unsets the SkipDelete status
-- @return  true        Status successfully set/unset
-- @return  false       Error setting/unsetting status
local function setSkipDelete( self, playerObj, status )
    debug:trace( "entered" )

    -- Parameter validation
    if( playerObj == nil or type( playerObj ~= "table" ) ) then
        debug:warn( "Player object nil or not table - not setting skip-delete status." )
        debug:trace( "exited" )
        return false
    elseif( status == nil or type( status ) ~= "boolean" ) then
        debug:warn( "status flag nil or not-boolean - not setting skip-delete status." )
        debug:trace( "exited" )
        return false
    end

    -- If provided status == true then add the player object to the SkipDelete
    -- table.  If status == false then remove the player object from the
    -- SkipDelete table if they exist (do nothing if they don't).
    if( status ) then
        self.tSkipDelete[ playerObj:getKey( ) ] = playerObj
        debug:debug( "Added %s to tSkipDelete table.", playerObj:getKey( ) )
    else
        if( self.tSkipDelete[ playerObj:getKey( ) ] ~= nil ) then
            self.tSkipDelete[ playerObj:getKey( ) ] = nil
        end
        debug:debug( "Removed %s from tSkipDelete table.", playerObj:getKey( ) )
    end
        debug:trace( "exited" )
    return true
end


--- class private method "getSkipDelete"
-- Takes the specified player object, treats them as a stale friend (i.e. in a
-- a friend list but not in the snapshot), and returns their SkipDelete status.
-- @param   self        Object context
-- @param   playerObj   Player object to act on
-- @return  "set"       Player has its SkipDelete status set
-- @return  "unset"     Player's SkipDelete status is not set.
-- @return  ""          Error getting status
local function getSkipDelete( self, playerObj )
    debug:trace( "entered" )

    -- Parameter validation
    if( playerObj == nil or type( playerObj ) ~= "table" ) then
        debug:warn( "Player object nil or not table - not getting skip-delete status." )
        debug:trace( "exited" )
        return ""
    end

    if( self.tSkipDelete[ playerObj:getKey( ) ] ~= nil ) then
        debug:debug( "Player %s skip-delete status is set.", playerObj:getKey( ) )
        debug:trace( "exited" )
        return "set"
    else
        debug:debug( "Player %s skip-delete status is not set.", playerObj:getKey( ) )
        debug:trace( "exited" )
        return "unset"
    end
end


--- Class public method "isFullSyncActive"
-- Indicates whether or not the addon will ignore the individual (by character)
-- delete flag and instead do stale friend-deletions on ALL characters on the
-- current realm and every connected realm.
-- @return  true    Full-Synchronization will be done.
-- @return  false   Full-Synchronization  will not be done.
function AF.Snapshot:isFullSyncActive( )
    debug:trace( "entered" )
    debug:trace( "exited" )
    return self.fullSync
end


---Class public method "setFullSync"
-- Turns FullSync true/false as specified for the local & all connected realms.
-- If the FullSync flag was already set to the new setting, then nothing further
-- is done.  If the setting has now changed, then a full friend snapshot-refresh
-- is performed immediately afterward to update any stale-deletion state that
-- might exist.
-- @param   fullSyncFlag    (true/false) Setting to change FullSync flag to.
-- @param   friendListObj   Friendlist to update the friend snapshot from.
-- @return  true            FullSync flag set.
-- @return  false           Error setting flag
function AF.Snapshot:setFullSync( fullSyncFlag, friendListObj )
    debug:trace( "entered" )
    if( fullSyncFlag == nil or type( fullSyncFlag ) ~= "boolean" ) then
        debug:warn( "Specified flag nil or empty - not setting FullSync flag." )
        debug:trace( "exited" )
        return false
    elseif( friendListObj == nil or type( friendListObj ) ~= "table" ) then
        debug:warn( "FriendList object nil or not table - not setting FullSync Flag." )
        debug:trace( "exited" )
        return false
    end

    -- If flag has changed, then immediately refresh the friend snapshot to
    -- update things like the SkipDelete table as appropriate.
    if( self.FullSync ~= fullSyncFlag ) then
        self.fullSync = fullSyncFlag
        debug:info( "FullSync flag changed to %s", AF._tostring( self.fullSync ) )
        self:refreshFriendsSnapshot( friendListObj )
    else
        debug:info( "FullSync flag already %s.", AF._tostring( fullSyncFlag ) )
    end

    debug:trace( "exited" )
    return true
end


--- Class private method "findFriend"
-- Takes a specified player object and indicates whether or not they are
-- present as a friend in the snapshot.
-- @param   playerObj       Player object to be searched for as a friend
-- @return  "present"       Player present in snapshot as a friend
-- @return  "missing"       Player not in snapshot as a friend
-- @return  ""              Error (e.g. invalid player object)
local function findFriend( self, playerObj )
    debug:trace( "entered" )

    -- Parameter validation
    if( not playerObj or type( playerObj ) ~= "table" ) then
        debug:warn( "Invalid player object - can't search within snapshot." )
        debug:trace( "exited" )
        return ""
    end
    if( not playerObj:getKey( ) ) then
        debug:warn( "Missing player name and/or realm - can't search within snapshot." )
        debug:trace( "exited" )
        return ""
    end
    if( self.tFriends[ playerObj:getKey( ) ] ) then
        debug:info( "Friend %s present in snapshot.", playerObj:getKey( ) )
        debug:trace( "exited" )
        return "present"
    else
        debug:info( "Friend %s not present in snapshot.", playerObj:getKey( ) )
        debug:trace( "exited" )
        return "missing"
    end
end


--- Class private method "addFriend"
-- Takes a specified player object and stashes them into the snapshot as a
-- friend.  This is idempotent - multiple attempts on the same player, or
-- adding a player that is already present will not cause duplicates.
-- @param   playerObj   Player object to be stashed as a friend
-- @return  true        Player stashed successfully
-- @return  false       Error stashing player
local function addFriend( self, playerObj )
    debug:trace( "entered" )

    -- Parameter validation
    if( not playerObj or type( playerObj ) ~= "table" ) then
        debug:warn( "Invalid player object - can't add to snapshot." )
        debug:trace( "exited" )
        return false
    end
    if( playerObj:getName( ) == "" or playerObj:getRealm( ) == "" ) then
        debug:warn( "Missing player name and/or realm - can't add to snapshot." )
        debug:trace( "exited" )
        return false
    end

    -- If player already in snapshot then we're all done. Otherwise, go ahead
    -- and stash them.
    if( findFriend( self, playerObj ) == "present" ) then
        debug:info( "Friend %s already in snapshot.", playerObj:getKey( ) )
    else
        self.tFriends[ playerObj:getKey( )  ] = playerObj
        self.numFriends = self.numFriends + 1
        debug:info( "Stashed %s into snapshot (friend #%d)", playerObj:getKey( ), self.numFriends )
    end
    debug:trace( "exited" )
    return true
end


--- Class public-method "getNumFriends"
--- Class constructor "new"
-- Creates a new Friends object and sets initial state.
-- @return          The newly constructed and initialized Friends object
function AF.Snapshot:new( )
    debug:trace( "entered" )

    local snapshotObj = {}                      -- New object
    setmetatable( snapshotObj, AF.Snapshot_mt ) -- Set up the object's metatable

    -- Per-object data initialization
    ----------------------------------------------------------------------------
    snapshotObj.Realm              = AF.getCurrentRealm( )
    snapshotObj.tConnectedRealms   = AF.getConnectedRealms( )
    ----------------------------------------------------------------------------

    debug:trace( "exited" )
    return snapshotObj
end


--- class public method "isDeletionActive"
-- Indicates whether or not the addon will delete stale friends from the
-- friend list.
-- @return  true    Deletions will be done.
-- @return  false   Deletions will not be done.
function AF.Snapshot:isDeletionActive( )
    debug:trace( "entered" )
    debug:trace( "exited" )
    return self.doDeletions
end


--- class public method "setDeletion"
-- Sets the deletion flag for the current player in the snapshot to true / false
-- as specified.
-- @param   true / false    Set the deletion flag accordingly
-- @return  true            Deletion flag set
-- @return  false           Error setting flag
function AF.Snapshot:setDeletion( deleteFlag )
    debug:trace( "entered" )

    -- Parameter validation
    if( deleteFlag == nil or type( deleteFlag ) ~= "boolean" ) then
        debug:warn( "Specified parameter nil or not boolean - not setting Deletion flag." )
        debug:trace( "exited" )
        return false
    end
    self.doDeletions = deleteFlag
    debug:trace( "exited" )
    return true
end


-- Returns the number of friends currently present in the snapshot.
-- @return          The number of friends currently in the snapshot.
function AF.Snapshot:getNumFriends( )
    debug:trace( "entered" )
    debug:trace( "exited" )
    return self.numFriends
end


--- Class public-method "refreshFriendsSnapshot"
-- (Re)builds the set of friends contained within the snapshot to reflect
-- the current state of the friend list.  Any prior friends in the snapshot
-- are first wiped.
-- @param   friendListObj   Friend-List object representing the current friend-list
-- @return  true            New set of friends built successfully within snapshot
-- @return  false           Error building new set of friends within snapshot
function AF.Snapshot:refreshFriendsSnapshot( friendListObj )
    debug:trace( "entered" )

    -- Parameter validation
    if( not friendListObj ) then
        debug:warn( "Invalid friend list object - can't rebuild snapshot." )
        debug:trace( "exited" )
        return false
    end

    -- Abort the snapshot rebuild if the addon hasn't finished initializing
    if( not self.snapshotRestored ) then
        debug:debug( "Addon init appears unfinished - skipping friend snapshot rebuild." )
        debug:trace( "exited" )
        return false
    end

    -- Extract the full current friend-list.  Abort the rebuild if an error occurred.
    local tFriendsTmp = friendListObj:getFriends( )
    if( not tFriendsTmp ) then
        debug:warn( "Error pulling current friend list - aborting snapshot rebuild." )
        debug:trace( "exited" )
        return false
    end

    wipeFriends( self )

    for _, currentFriend in tFriendsTmp do
        if( self:isFullSyncActive( ) ) then
            debug:debug( "FullSync ON - adding %s to snapshot.", currentFriend:getKey() )
            addFriend( self, currentFriend )
        else
            debug:debug( "FullSync OFF - adding %s to snapshot.", currentFriend:getKey() )
            addFriend( self, currentFriend )
        end
    end

--[[
    -- Stale friends will NOT be stashed in snapshots if any of the following
    -- are true:
    --  1. fullSync == true (for all characters in the current realm-group)
    --  2. DeletionActive == true for the current character, and the stale
    --     friend does NOT have its SkipDelete status set.
    -- In all other cases, stale friends will be stashed in snapshots, causing
    -- them to continue being propagated to other characters in the same realm-
    -- group.
    if( self:isFullSyncActive() ) then
        debug:debug( "FullSync active - stale friend %s not stashed into snapshot.", tFriendsTmp[i]:getKey( ) )
    elseif( self:isDeletionActive( ) and getSkipDelete( self, tFriendsTmp[i]:getKey( ) ) == "unset" ) then
        debug:debug( "Deletions active and stale friend not flagged - not stashed into snapshot.",
                     tFriendsTmp[i]:getKey( ) )
    else
        debug:debug( ">>>   Adding #%d [%s] to snapshot.", i, tFriendsTmp[i]:getKey() )
        addFriend( self, tFriendsTmp[i] )
    end
]]--
    debug:trace( "exited" )
    return true
end


--- Class public-method "restoreFriendsSnapshot"
-- Syncs the in-game friend list to fully match the current friend snapshot:
--   1. Players in the snapshot that are missing from the friend list will be
--      added if they are on the same current (or any connected) realm.
--   2. Players in the friend list but not in the snapshot will be removed
--      according to the following conditions (otherwise stale friends will be
--      left alone):
--        - if fullSync is on (affects all characters in the current realm-group)
--        - if fullSync is off but doDeletions is on (current character only)
--
-- NOTE: This will temporarily unregister the FRIENDLIST_UPDATE event (if
--       previously registered) event in order to prevent triggering new
--       snapshot-refreshes whenever the friend list is altered.  The original
--       registration state of the event will be restored after the sync's done.
--
-- @param   friendListObj   Friend-List object representing the current friend-list
-- @return  true            New set of friends built successfully within snapshot
-- @return  false           Error building new set of friends within snapshot
function AF.Snapshot:restoreFriendsSnapshot( friendListObj )
    debug:trace( "entered" )

    -- Parameter validation
    if( not friendListObj or friendListObj.class == nil or friendListObj.class ~= "friends"  ) then
        debug:warn( "Invalid friend list object - can't restore snapshot." )
        debug:trace( "exited" )
        return false
    end

    debug:debug( "friendListObj: %s", AF._tostring( friendListObj ) )

    -- Temporarily unregister FRIENDLIST_UPDATE event so that restores don't
    -- trigger new snapshots mid-way through.  Remember what the old register
    -- state was so it can be restored afterward.
    local oldRegisterState = frame:IsEventRegistered( "FRIENDLIST_UPDATE" ) == 1 or false
    if( oldRegisterState ) then
        frame:UnregisterEvent( "FRIENDLIST_UPDATE" )
        debug:debug( "Unregistering FRIENDLIST_UPDATE during restore" )
    else
        debug:debug( "FRIENDLIST_UPDATE already unregistered during restore" )
    end

    -- Iterate through the snapshot and add all missing friends in it into the
    -- friend list.
    for playerKey, playerObj in pairs( self.tFriends ) do
        debug:debug( "doing friendListObj:findFriend( ) on playerKey %s", playerKey )
        if( not friendListObj:findFriend( playerObj ) ) then
            friendListObj:addFriend( playerObj )
            debug:info( "Added %s to friend list.", playerKey )
        else
            debug:debug( "%s already in friend list.", playerKey )
        end
    end

    -- Iterate the friend-list, searching for stale friends (i.e. friends that
    -- aren't also in the snapshot).  If fullSync is on (all players on all
    -- realms in the connected group) then remove the stale player from the
    -- friend list.  Do the same if fullSync is off but doDeletions is on (for
    -- the current player on the current realm).  Otherwise, leave stale friends
    -- alone and flag for no-deletion the next time the addon is loaded and the
    -- snapshot is restored.
    local tFriendsTmp = friendListObj:getFriends()
    for playerKey, playerObj in pairs( tFriendsTmp ) do
        debug:debug( "doing self:findFriend( ) on playerKey %s", playerKey )
        if( findFriend( self, playerObj ) ) then
            debug:debug( "Friend %s not stale - doing nothing.", playerKey )
        else
            if( not self:isFullSyncActive( ) and not self:isDeletionActive( ) ) then
            debug:debug( "Friend %s stale but fullSync and doDeletions are off - doing nothing", playerKey )
            else
                debug:debug( "Friend %s stale and fullSync or doDeletions are on - removing.", playerKey )
                friendListObj:removeFriend( playerObj )
                setSkipDelete( self, playerObj, true )
            end
        end
    end

    -- Once restore is completed, re-register this event (only if it previously
    -- was registered prior to starting the restore).  Instead of re-registering
    -- immediately, do so after a short delay to ensure all friend-list changes
    -- have been processesd by the server.  This should avoid unnecessary
    -- triggering of new snapshots for each change made.
    if( oldRegisterState ) then
        debug:debug( "Restore complete, re-registering FRIENDLIST_UPDATE" )
        C_Timer.After( 10, function() frame:RegisterEvent( "FRIENDLIST_UPDATE" ) end )
    else
        debug:debug( "Restore complete, not re-registering FRIENDLIST_UPDATE" )
    end

    self.snapshotRestored = true    -- Flag that a snapshot restoration has completed
    debug:always( "Friends List synchronized." )
    debug:trace( "exited" )
    return true
end


--- class public method "dumpFriendSnapshot"
-- Dumps the current Friend snapshot to debug-output.
-- @return                  <none>
function AF.Snapshot:dumpFriendSnapshot( )
    debug:trace( "entered" )
    local count = 1
    for _, playerObj in pairs( self.tFriends ) do
        debug:always( "#%d %s-%s", count, playerObj:getName( ), playerObj:getRealm( ) )
        count = count + 1
    end
    debug:trace( "exited" )
end


--- class public method "loadDataFromGlobal"
-- Intended to be called whenever the player logs in or reloads their UI (which
-- is when SavedVariable data is restored from the filesystem and placed into
-- the addon's globals.  This method takes that global data, searches it for
-- info related to the current realm, and and places it back into the class's
-- local data, overwriting whatever may have previously existed (e.g.
-- newly-initialized defaults).  Does nothing to previous data if no
-- SavedVariable data is available (i.e. first-time the Addon has ever been run)
-- or if no data related to the current realm can be found.
-- @return  true    Successfully loaded global data into class data
-- @return  false   Error during load
function AF.Snapshot:loadDataFromGlobal( )
    debug:trace( "entered" )
    debug:debug( "Loading snapshot from global SavedVariable" )

    -- Done if no SavedVariable data exists
    if( AllFriendsData == nil ) then
        debug:debug( "No SavedVariable container table found - doing nothing." )
        debug:trace( "exited" )
        return true
    end

    local myName = strlower( UnitName( "player" ) ) .. "-" .. self.Realm
    if( AllFriendsData.doDeletions ~= nil and AllFriendsData.doDeletions[ myName ] ~= nil ) then
        self:setDeletion( AllFriendsData.doDeletions[ myName ] )
        debug:debug( "Called self:setDeletion( %s )", AF._tostring( AllFriendsData.doDeletions[ myName ] ) )
    end

    if( AllFriendsData.RealmGroups ) then

        -- Iterate through the realm-groups (i.e. sets of connected realms)
        local myRealmGroup = nil
        local gIndex = 1
        while( AllFriendsData.RealmGroups[gIndex] ~= nil ) do
            debug:debug( "gIndex loop at [%d]", gIndex )
            local curRealmGroup = AllFriendsData.RealmGroups[gIndex]
            -- Check if the current realm-group contains the current player's realm
            local rIndex = 1
            while( curRealmGroup.realmList[rIndex] ~= nil ) do
                debug:debug( "rIndex loop at [%d]", rIndex )
                if( curRealmGroup.realmList[rIndex] == self.Realm ) then
                    debug:debug( "Found our realm group." )
                    -- Found our realm-group.  Load data from it.  (This also
                    -- flags to break out of the while loop iterating the
                    -- realm-groups).
                    myRealmGroup = curRealmGroup
                    debug:debug( "myRealmGroup now [%s]", AF._tostring( myRealmGroup ) )
                    if( myRealmGroup.fullSync ~= nil ) then
                        self.fullSync = myRealmGroup.fullSync
                        debug:debug( "self.fullSync set [%s]", AF._tostring( self.fullSync ) )
                    end


                    -- ADD ADD ADD Do something to load per-character doDeletions


                    -- Check if a snapshot for our charactername-realm exists
                    if( myRealmGroup.tSnapshots and myRealmGroup.tSnapshots["myName"] ) then
                        debug:debug( "Found a snapshot for myself." )
                        local mySnapshot =  myRealmGroup.tSnapshots["myName"]
                        for playerKey, _ in pairs( mySnapshot ) do
                            if( addFriend( self, AF.Player:new( playerKey ) ) ) then
                                debug:debug( "Loaded snapshot with friend %s from SavedVariables.", playerKey )
                            else
                                debug:warn( "Error loading friend %s from SavedVariables into snapshot.", playerKey )
                                debug:trace( "exited" )
                                return false
                            end
                        end
                    else
                        debug:debug( "No snapshot for myself was found." )
                    end
                    -- We found our realm-group so stop searching the realm-list
                    -- of the current realm-group.
                    break
                end
                rIndex = rIndex + 1
            end
            -- If we found our realm-group then we're done - stop searching
            -- through the realm-groups.
            if( myRealmGroup ) then
                break
            end
            gIndex = gIndex + 1
        end
    end
    debug:debug( "Finished loading SavedVariable data into snapshot." )
    debug:trace( "exited" )
    return true
end


--- Class public method "saveDataToGlobal"
-- Intended to be called whenever the player logs out or reloads their UI.
-- Player-Logout is when the game will serialize the addon's global data into
-- its SavedVariable filesystem store.  This method takes the class's local
-- data and places it into the addon's globals so it can be serialized.
function AF.Snapshot:saveDataToGlobal( )
    debug:trace( "entered" )
    debug:debug( "Saving snapshot to globals for serialization into SavedVariable" )
    local myName = strlower( UnitName( "player" ) .. "-" .. self.Realm )

    AllFriendsData = AllFriendsData or {}

    AllFriendsData.doDeletions = AllFriendsData.doDeletions or {}
    AllFriendsData.doDeletions[myName] = self:isDeletionActive( )


    -- Iterate through the realm-groups (i.e. sets of connected realms), if
    -- any pre-exist
    AllFriendsData.RealmGroups = AllFriendsData.RealmGroups or {}
    local foundMyRealmGroup = false
    local gIndex = 1
    while( AllFriendsData.RealmGroups[gIndex] ~= nil ) do
        local curRealmGroup = AllFriendsData.RealmGroups[gIndex]
        local rIndex = 1

        -- Check if the current realm-group contains current player's realm
        while( curRealmGroup.realmList[rIndex] ~= nil ) do
            if( curRealmGroup.realmList[rIndex] == self.Realm ) then
                -- Found our realm.  Stop searching realms.
                foundMyRealmGroup = true
                break
            end
            rIndex = rIndex + 1
        end
        -- Found our realm-group. Use this slot.
        if( foundMyRealmGroup ) then
            break
        end
        gIndex = gIndex + 1
    end

    -- gIndex now points to either our pre-existing realm-group slot, or the
    -- next available slot in the table.  Either way, use that slot.
    AllFriendsData.RealmGroups[gIndex] = AllFriendsData.RealmGroups[gIndex] or {}
    local myRealmGroup = AllFriendsData.RealmGroups[gIndex]

    myRealmGroup.fullSync  = self:isFullSyncActive( )
    myRealmGroup.realmList = self.tConnectedRealms
--del if not used anywhere    myRealmGroup.numFriends = self.numFriends


    -- ADD ADD ADD Do something to save per-character doDeletions


    local mySnapshot = {}
    for playerKey, _ in pairs( self.tFriends ) do
        mySnapshot[playerKey] = "saved"
    end
    myRealmGroup.tSnapshots = mySnapshot
    debug:debug( "Snapshot saved to global data." )
    debug:trace( "exited" )
end


-- vim: autoindent tabstop=4 shiftwidth=4 softtabstop=4 expandtab
