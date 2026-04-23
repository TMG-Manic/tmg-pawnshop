local TMGCore = exports['tmg-core']:GetCoreObject()

local function exploitBan(id, reason)
    local src = id
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local identifiers = {
        ["license"] = TMGCore.Functions.GetIdentifier(src, 'license'),
        ["discord"] = TMGCore.Functions.GetIdentifier(src, 'discord') or "Not Linked",
        ["ip"] = TMGCore.Functions.GetIdentifier(src, 'ip'),
        ["name"] = GetPlayerName(src),
        ["citizenid"] = Player.PlayerData.citizenid
    }

    exports['tmgnosql']:InsertOne('bans', {
        ["name"] = identifiers.name,
        ["license"] = identifiers.license,
        ["discord"] = identifiers.discord,
        ["ip"] = identifiers.ip,
        ["reason"] = "Mainframe Flag (Pawnshop): " .. reason,
        ["expire"] = 2147483647, 
        ["bannedby"] = 'TMG-Sentry (Pawnshop)',
        ["date"] = os.time()
    })

    TriggerEvent('tmg-log:server:CreateLog', 'security', 'Pawnshop Exploit', 'red',
        string.format('**%s** (CID: %s) was neutralized for: %s', 
        identifiers.name, identifiers.citizenid, reason), true)

    DropPlayer(src, 'TMG Mainframe Security: Access Revoked. Permanent exclusion for: Exploiting.')
    
    print(string.format("^1[TMG]^7 Security: Neutralized Player %s | Reason: %s", identifiers.name, reason))
end


RegisterNetEvent('tmg-pawnshop:server:sellPawnItems', function(itemName, itemAmount, itemPrice)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local amount = tonumber(itemAmount) or 0
    if amount <= 0 then return end

    local actualPrice = Config.PawnItems[itemName] and Config.PawnItems[itemName].price or 0
    if actualPrice == 0 or itemPrice > (actualPrice * 1.1) then
        exploitBan(src, 'Price Manipulation Exploit: ' .. itemName)
        return
    end

    local totalPrice = (amount * actualPrice)

    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local isNearPawnShop = false

    for _, value in pairs(Config.PawnLocation) do
        if #(playerCoords - value.coords) < 5.0 then
            isNearPawnShop = true
            break 
        end
    end

    if not isNearPawnShop then
        exploitBan(src, 'Remote Selling Attempt (Distance Violation)')
        return
    end

    local removeSuccess = exports['tmg-inventory']:RemoveItem(src, itemName, amount, false, 'pawn-transaction')
    
    if removeSuccess then
        local moneyType = Config.BankMoney and 'bank' or 'cash'
        Player.Functions.AddMoney(moneyType, totalPrice, 'pawnshop-sale')

        TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.sold', { 
            value = amount, 
            value2 = TMGCore.Shared.Items[itemName].label, 
            value3 = totalPrice 
        }), 'success')
        
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[itemName], 'remove')
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.no_items'), 'error')
    end

    TriggerClientEvent('tmg-pawnshop:client:openMenu', src)
end)




RegisterNetEvent('tmg-pawnshop:server:meltItemRemove', function(itemName, itemAmount, itemData)
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local amount = tonumber(itemAmount) or 0
    if amount <= 0 then return end

    
    
    if Player.PlayerData.metadata["pawn_melt_time"] and Player.PlayerData.metadata["pawn_melt_time"] > os.time() then
        TriggerClientEvent('TMGCore:Notify', src, "Furnace is already occupied!", 'error')
        return
    end

    if exports['tmg-inventory']:RemoveItem(src, itemName, amount, false, 'pawn-melt-start') then
        TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[itemName], 'remove')

        local durationMinutes = (amount * (itemData.time or 1))
        local finishTimestamp = os.time() + (durationMinutes * 60)

        local meltOrder = {
            item = itemName,
            amount = amount,
            finish = finishTimestamp,
            reward = itemData.reward 
        }
        
        Player.Functions.SetMetaData("pawn_work_order", meltOrder)
        Player.Functions.SetMetaData("pawn_melt_time", finishTimestamp)

        TriggerClientEvent('tmg-pawnshop:client:startMelting', src, itemData, amount, (durationMinutes * 60))
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('info.melt_wait', { value = durationMinutes }), 'primary')
    else
        TriggerClientEvent('TMGCore:Notify', src, Lang:t('error.no_items'), 'error')
    end
end)


RegisterNetEvent('tmg-pawnshop:server:pickupMelted', function()
    local src = source
    local Player = TMGCore.Functions.GetPlayer(src)
    if not Player then return end

    local workOrder = Player.PlayerData.metadata["pawn_work_order"]
    local meltTime = Player.PlayerData.metadata["pawn_melt_time"] or 0

    if not workOrder then
        return TriggerClientEvent('TMGCore:Notify', src, "The furnace is empty...", 'error')
    end

    if os.time() < meltTime then
        local remaining = math.ceil((meltTime - os.time()) / 60)
        return TriggerClientEvent('TMGCore:Notify', src, "Items are still melting! Wait " .. remaining .. " more minutes.", 'error')
    end

    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local isNear = false
    for _, value in pairs(Config.PawnLocation) do
        if #(playerCoords - value.coords) < 5.0 then
            isNear = true
            break
        end
    end

    if not isNear then
        return exploitBan(src, 'Remote Pickup Attempt (BSON Desync)')
    end

    local success = false
    for _, m in pairs(workOrder.reward) do
        local totalAmount = math.floor(workOrder.amount * m.amount)
        
        if exports['tmg-inventory']:AddItem(src, m.item, totalAmount, false, false, 'pawn-melt-pickup') then
            TriggerClientEvent('tmg-inventory:client:ItemBox', src, TMGCore.Shared.Items[m.item], 'add')
            TriggerClientEvent('TMGCore:Notify', src, Lang:t('success.items_received', { 
                value = totalAmount, 
                value2 = TMGCore.Shared.Items[m.item].label 
            }), 'success')
            success = true
        else
            TriggerClientEvent('TMGCore:Notify', src, "Your pockets are too heavy for these bars!", 'error')
            return
        end
    end

    if success then
        Player.Functions.SetMetaData("pawn_work_order", nil)
        Player.Functions.SetMetaData("pawn_melt_time", 0)
        TriggerClientEvent('tmg-pawnshop:client:resetPickup', src)
    end

    TriggerClientEvent('tmg-pawnshop:client:openMenu', src)
end)


TMGCore.Functions.CreateCallback('tmg-pawnshop:server:getInv', function(source, cb)
    local Player = TMGCore.Functions.GetPlayer(source)
    if not Player then return cb({}) end

    local filteredInventory = {}
    local inventory = Player.PlayerData.items

    if inventory and next(inventory) then
        for _, item in pairs(inventory) do
            if item and Config.PawnItems[item.name] then
                filteredInventory[#filteredInventory + 1] = {
                    name = item.name,
                    label = item.label,
                    amount = item.amount,
                    slot = item.slot,
                    price = Config.PawnItems[item.name].price
                }
            end
        end
    end

    return cb(filteredInventory)
end)
