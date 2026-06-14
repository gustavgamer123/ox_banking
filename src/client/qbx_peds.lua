-- QBX bank ped spawning for ox_banking
-- Spawns NPC peds at bank locations matching Renewed-Banking behaviour

local config = lib.loadJson('data.config')
local peds   = lib.loadJson('data.peds')

-- Allow server owners to disable peds entirely via config.json
if not config or config.UsePeds == false then return end
if not peds or #peds == 0 then return end

local pedSpawned = false
local blips = {}
local points = {}

local function openBank()
    exports.ox_banking:openBank()
end

local function createPeds()
    if pedSpawned then return end

    for k = 1, #peds do
        local pedData = peds[k]
        local x, y, z, w = pedData.coords[1], pedData.coords[2], pedData.coords[3], pedData.coords[4]

        local targetOptions = {
            {
                name   = 'ox_banking_open_' .. k,
                icon   = 'fas fa-money-check',
                label  = locale('target_access_bank'),
                distance = 2.5,
                onSelect = openBank,
            }
        }

        local point = lib.points.new({
            coords       = vector3(x, y, z),
            distance     = 300,
            model        = joaat(pedData.model),
            heading      = w or 0.0,
            ped          = nil,
            targetOptions = targetOptions,
        })

        function point:onEnter()
            lib.requestModel(self.model, 10000)
            self.ped = CreatePed(0, self.model, self.coords.x, self.coords.y, self.coords.z - 1, self.heading, false, false)
            SetEntityHeading(self.ped, self.heading)
            SetModelAsNoLongerNeeded(self.model)
            TaskStartScenarioInPlace(self.ped, 'PROP_HUMAN_STAND_IMPATIENT', 0, true)
            FreezeEntityPosition(self.ped, true)
            SetEntityInvincible(self.ped, true)
            SetBlockingOfNonTemporaryEvents(self.ped, true)

            if config and config.UseOxTarget then
                exports.ox_target:addLocalEntity(self.ped, self.targetOptions)
            end
        end

        function point:onExit()
            if config and config.UseOxTarget and self.ped then
                exports.ox_target:removeLocalEntity(self.ped)
            end
            if self.ped and DoesEntityExist(self.ped) then
                DeletePed(self.ped)
            end
            self.ped = nil
        end

        points[k] = point

        blips[k] = AddBlipForCoord(x, y, z - 1)
        SetBlipSprite(blips[k], 108)
        SetBlipDisplay(blips[k], 4)
        SetBlipScale(blips[k], 0.80)
        SetBlipColour(blips[k], 2)
        SetBlipAsShortRange(blips[k], true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString('Bank')
        EndTextCommandSetBlipName(blips[k])
    end

    pedSpawned = true
end

local function deletePeds()
    if not pedSpawned then return end

    for i = 1, #points do
        if points[i] then
            if points[i].ped and DoesEntityExist(points[i].ped) then
                DeletePed(points[i].ped)
            end
            points[i]:remove()
        end
    end

    for i = 1, #blips do
        if blips[i] then RemoveBlip(blips[i]) end
    end

    points = {}
    blips = {}
    pedSpawned = false
end

-- ────────────────────────────────────────────────────────────
--  Framework events (QBX / QB compatible)
-- ────────────────────────────────────────────────────────────

-- Handle resource restart while player is already logged in
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Wait(500)
    if LocalPlayer.state.isLoggedIn then
        createPeds()
    end
end)

-- QBX / QB player loaded event
AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    Wait(500)
    createPeds()
end)

-- QBX / QB player unloaded event
RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    deletePeds()
end)

-- State bag fallback for QBX (catches edge cases)
AddStateBagChangeHandler('isLoggedIn', nil, function(bagName, _, value)
    if bagName ~= ('player:%s'):format(cache.serverId) then return end
    if value then
        Wait(500)
        createPeds()
    else
        deletePeds()
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    deletePeds()
end)
