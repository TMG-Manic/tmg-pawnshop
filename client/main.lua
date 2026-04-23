local TMGCore = exports['tmg-core']:GetCoreObject()



PawnState = {
    isMelting = false,
    canTake = false,
    meltTime = 0,
    meltedItem = {},
    zones = {}
}



local function IsShopOpen()
    if not Config.UseTimes then return true end
    local hour = GetClockHours()
    return (hour >= Config.TimeOpen and hour <= Config.TimeClosed)
end



local function OpenPawnMenu()
    if not IsShopOpen() then 
        return TMGCore.Functions.Notify(Lang:t('info.pawn_closed', { value = Config.TimeOpen, value2 = Config.TimeClosed })) 
    end

    local pawnShop = {
        { header = Lang:t('info.title'), isMenuHeader = true },
        { 
            header = Lang:t('info.sell'), 
            txt = Lang:t('info.sell_pawn'), 
            params = { event = 'tmg-pawnshop:client:openPawn', args = { items = Config.PawnItems } } 
        }
    }

    if not PawnState.isMelting then
        pawnShop[#pawnShop + 1] = {
            header = Lang:t('info.melt'),
            txt = Lang:t('info.melt_pawn'),
            params = { event = 'tmg-pawnshop:client:openMelt', args = { items = Config.MeltingItems } }
        }
    end

    if PawnState.canTake then
        pawnShop[#pawnShop + 1] = {
            header = Lang:t('info.melt_pickup'),
            params = { isServer = true, event = 'tmg-pawnshop:server:pickupMelted', args = { items = PawnState.meltedItem } }
        }
    end

    exports['tmg-menu']:openMenu(pawnShop)
    print("^5[TMG]^7 Pawn interface materialized.")
end



RegisterNetEvent('tmg-pawnshop:client:openPawn', function(data)
    TMGCore.Functions.TriggerCallback('tmg-pawnshop:server:getInv', function(inventory)
        local pawnMenu = { { header = Lang:t('info.title'), isMenuHeader = true } }
        for _, v in pairs(inventory) do
            for i = 1, #data.items do
                if v.name == data.items[i].item then
                    pawnMenu[#pawnMenu + 1] = {
                        header = TMGCore.Shared.Items[v.name].label,
                        txt = Lang:t('info.sell_items', { value = data.items[i].price }),
                        params = { event = 'tmg-pawnshop:client:pawnitems', args = { label = TMGCore.Shared.Items[v.name].label, price = data.items[i].price, name = v.name, amount = v.amount } }
                    }
                end
            end
        end
        pawnMenu[#pawnMenu + 1] = { header = Lang:t('info.back'), params = { event = 'tmg-pawnshop:client:openMenu' } }
        exports['tmg-menu']:openMenu(pawnMenu)
    end)
end)

RegisterNetEvent('tmg-pawnshop:client:pawnitems', function(item)
    local input = exports['tmg-input']:ShowInput({
        header = Lang:t('info.title'),
        submitText = Lang:t('info.sell'),
        inputs = { { type = 'number', isRequired = false, name = 'amount', text = Lang:t('info.max', { value = item.amount }) } }
    })
    if input and input.amount then
        local amt = tonumber(input.amount)
        if amt and amt > 0 then
            if amt <= item.amount then TriggerServerEvent('tmg-pawnshop:server:sellPawnItems', item.name, amt, item.price)
            else TMGCore.Functions.Notify(Lang:t('error.no_items'), 'error') end
        else TMGCore.Functions.Notify(Lang:t('error.negative'), 'error') end
    end
end)



RegisterNetEvent('tmg-pawnshop:client:startMelting', function(item, meltingAmount, time)
    if PawnState.isMelting then return end
    
    PawnState.isMelting = true
    PawnState.meltTime = time
    PawnState.meltedItem = {}

    CreateThread(function()
        while PawnState.isMelting do
            Wait(1000)
            if LocalPlayer.state.isLoggedIn then
                PawnState.meltTime -= 1
                if PawnState.meltTime <= 0 then
                    PawnState.canTake = true
                    PawnState.isMelting = false
                    PawnState.meltedItem[#PawnState.meltedItem + 1] = { item = item, amount = meltingAmount }
                    
                    if Config.SendMeltingEmail then
                        TriggerServerEvent('tmg-phone:server:sendNewMail', { sender = Lang:t('info.title'), subject = Lang:t('info.subject'), message = Lang:t('info.message'), button = {} })
                    else
                        TMGCore.Functions.Notify(Lang:t('info.message'), 'success')
                    end
                    print("^5[TMG]^7 Melting sequence concluded. Assets ready for extraction.")
                end
            else break end
        end
    end)
end)



CreateThread(function()
    
    for _, value in pairs(Config.PawnLocation) do
        local blip = AddBlipForCoord(value.coords.x, value.coords.y, value.coords.z)
        SetBlipSprite(blip, 431); SetBlipDisplay(blip, 4); SetBlipScale(blip, 0.7)
        SetBlipAsShortRange(blip, true); SetBlipColour(blip, 5)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentSubstringPlayerName(Lang:t('info.title')); EndTextCommandSetBlipName(blip)
    end

    
    if Config.UseTarget then
        for key, value in pairs(Config.PawnLocation) do
            exports['tmg-target']:AddBoxZone('PawnShop'..key, value.coords, value.length, value.width, {
                name = 'PawnShop'..key, heading = value.heading, minZ = value.minZ, maxZ = value.maxZ, debugPoly = value.debugPoly
            }, {
                options = { { type = 'client', event = 'tmg-pawnshop:client:openMenu', icon = 'fas fa-ring', label = 'Pawn Shop' } },
                distance = value.distance
            })
        end
    else
        local zones = {}
        for key, value in pairs(Config.PawnLocation) do
            zones[#zones+1] = BoxZone:Create(value.coords, value.length, value.width, { name = 'PawnShop'..key, heading = value.heading, minZ = value.minZ, maxZ = value.maxZ })
        end
        ComboZone:Create(zones, { name = 'PawnCombo' }):onPlayerInOut(function(inside)
            if inside then exports['tmg-menu']:showHeader({ { header = Lang:t('info.title'), txt = Lang:t('info.open_pawn'), params = { event = 'tmg-pawnshop:client:openMenu' } } })
            else exports['tmg-menu']:closeMenu() end
        end)
    end
    print("^5[TMG]^7 Pawn shop spatial nodes active.")
end)


RegisterNetEvent('tmg-pawnshop:client:openMenu', function() OpenPawnMenu() end)
RegisterNetEvent('tmg-pawnshop:client:resetPickup', function() PawnState.canTake = false end)
