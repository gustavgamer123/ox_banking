-- QBX / QB backwards compatibility layer for ox_banking
-- Provides: qb-management exports, esx_society events, givecash command

local function ExportHandler(resource, name, cb)
    AddEventHandler(('__cfx_export_%s_%s'):format(resource, name), function(setCB)
        setCB(cb)
    end)
end

local function getQBXPlayer(source)
    if GetResourceState('qbx_core') == 'started' then
        return exports.qbx_core:GetPlayer(source)
    elseif GetResourceState('qb-core') == 'started' then
        return exports['qb-core']:GetCoreObject().Functions.GetPlayer(source)
    end
end

local function getQBXPlayerByCitizenId(citizenid)
    citizenid = citizenid:upper()
    if GetResourceState('qbx_core') == 'started' then
        return exports.qbx_core:GetPlayerByCitizenId(citizenid)
    elseif GetResourceState('qb-core') == 'started' then
        return exports['qb-core']:GetCoreObject().Functions.GetPlayerByCitizenId(citizenid)
    end
end

local function getCharName(player)
    return ('%s %s'):format(player.PlayerData.charinfo.firstname, player.PlayerData.charinfo.lastname)
end

-- ────────────────────────────────────────────────────────────
--  Organisation account helpers (work directly with ox_banking's `accounts` table)
-- ────────────────────────────────────────────────────────────

local function GetGroupAccountMoney(group)
    if not group then return 0 end
    local result = MySQL.scalar.await(
        'SELECT `balance` FROM `accounts` WHERE `group` = ? AND `type` != "inactive" LIMIT 1',
        { group }
    )
    return result or 0
end

local function AddGroupAccountMoney(group, amount)
    if not group or not amount then return false end
    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end
    local rows = MySQL.update.await(
        'UPDATE `accounts` SET `balance` = `balance` + ? WHERE `group` = ? AND `type` != "inactive"',
        { amount, group }
    )
    return (rows or 0) > 0
end

local function RemoveGroupAccountMoney(group, amount)
    if not group or not amount then return false end
    amount = tonumber(amount)
    if not amount or amount <= 0 then return false end
    local rows = MySQL.update.await(
        'UPDATE `accounts` SET `balance` = `balance` - ? WHERE `group` = ? AND `type` != "inactive" AND `balance` >= ?',
        { amount, group, amount }
    )
    return (rows or 0) > 0
end

-- Auto-create an accounts row for a QBX group that has no account yet
local function ensureGroupAccount(groupName, label)
    local exists = MySQL.scalar.await(
        'SELECT 1 FROM `accounts` WHERE `group` = ? LIMIT 1',
        { groupName }
    )
    if not exists then
        MySQL.insert.await(
            'INSERT INTO `accounts` (`label`, `owner`, `group`, `balance`, `type`, `isDefault`) VALUES (?, NULL, ?, 0, "shared", 0)',
            { label or groupName, groupName }
        )
    end
end
exports('ensureGroupAccount', ensureGroupAccount)

-- On resource start: make sure every QBX job/gang has an account row
CreateThread(function()
    Wait(1000)
    if GetResourceState('qbx_core') ~= 'started' and GetResourceState('qb-core') ~= 'started' then return end

    local jobs, gangs

    if GetResourceState('qbx_core') == 'started' then
        jobs  = exports.qbx_core:GetJobs()
        gangs = exports.qbx_core:GetGangs()
    else
        local QBCore = exports['qb-core']:GetCoreObject()
        jobs  = QBCore.Shared.Jobs
        gangs = QBCore.Shared.Gangs
    end

    for name, data in pairs(jobs or {}) do
        ensureGroupAccount(name, data.label)
    end

    for name, data in pairs(gangs or {}) do
        ensureGroupAccount(name, data.label)
    end
end)

-- ────────────────────────────────────────────────────────────
--  qb-management backwards compatibility exports
-- ────────────────────────────────────────────────────────────

ExportHandler('qb-management', 'GetAccount',      GetGroupAccountMoney)
ExportHandler('qb-management', 'GetGangAccount',  GetGroupAccountMoney)
ExportHandler('qb-management', 'AddMoney',        AddGroupAccountMoney)
ExportHandler('qb-management', 'AddGangMoney',    AddGroupAccountMoney)
ExportHandler('qb-management', 'RemoveMoney',     RemoveGroupAccountMoney)
ExportHandler('qb-management', 'RemoveGangMoney', RemoveGroupAccountMoney)

-- Direct exports (accessible without provide)
exports('getGroupAccountMoney',    GetGroupAccountMoney)
exports('addGroupAccountMoney',    AddGroupAccountMoney)
exports('removeGroupAccountMoney', RemoveGroupAccountMoney)

-- ────────────────────────────────────────────────────────────
--  esx_society backwards compatibility events
-- ────────────────────────────────────────────────────────────

RegisterServerEvent('esx_society:getSociety', function(societyName)
    local balance = GetGroupAccountMoney(societyName)
    TriggerClientEvent('esx_society:getSocietyBack', source, { money = balance })
end)

RegisterServerEvent('esx_society:depositMoney', function(societyName, amount)
    AddGroupAccountMoney(societyName, amount)
end)

RegisterServerEvent('esx_society:withdrawMoney', function(societyName, amount)
    RemoveGroupAccountMoney(societyName, amount)
end)

-- ────────────────────────────────────────────────────────────
--  /givecash command
-- ────────────────────────────────────────────────────────────

lib.addCommand('givecash', {
    help = 'Give cash to a nearby player',
    params = {
        { name = 'target', type = 'playerId', help = 'Player Server ID' },
        { name = 'amount', type = 'number',   help = 'Amount to give' },
    },
    restricted = false,
}, function(source, args)
    local Player = getQBXPlayer(source)
    if not Player then return end

    local targetPlayer = getQBXPlayer(args.target)
    if not targetPlayer then
        TriggerClientEvent('ox_lib:notify', source, { title = 'Bank', description = 'Player not found', type = 'error' })
        return
    end

    if args.amount <= 0 then
        TriggerClientEvent('ox_lib:notify', source, { title = 'Bank', description = 'Invalid amount', type = 'error' })
        return
    end

    if #(GetEntityCoords(GetPlayerPed(source)) - GetEntityCoords(GetPlayerPed(args.target))) > 10.0 then
        TriggerClientEvent('ox_lib:notify', source, { title = 'Bank', description = 'Player is too far away', type = 'error' })
        return
    end

    if Player.Functions.RemoveMoney('cash', args.amount, 'givecash') then
        targetPlayer.Functions.AddMoney('cash', args.amount, 'givecash')
        local nameA = getCharName(Player)
        local nameB = getCharName(targetPlayer)
        TriggerClientEvent('ox_lib:notify', source,      { title = 'Bank', description = ('You gave $%s to %s'):format(args.amount, nameB),    type = 'success' })
        TriggerClientEvent('ox_lib:notify', args.target, { title = 'Bank', description = ('%s gave you $%s'):format(nameA, args.amount),        type = 'success' })
    else
        TriggerClientEvent('ox_lib:notify', source, { title = 'Bank', description = 'Not enough cash', type = 'error' })
    end
end)
