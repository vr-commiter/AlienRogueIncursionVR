local truegear = require("TrueGearSDK")

local hookIds = {}
local resetHook = true
local hookRegistrationHadFailures = false
local grabbedItemByHand = {
    Left = nil,
    Right = nil
}
local grabbedItemObjectByHand = {
    Left = nil,
    Right = nil
}
local grabPollElapsedByPawn = {}
local holsteredItemStates = {}
local weaponInSlotStates = {}
local gearSlotStates = {}
local gearHandSides = {}
local medInjectorSlotStates = {}
local medInjectorHolsterRangeByItem = {}
local concussionIsInSlot = nil
local concussionHolsterRangeByItem = {}
local ammoSlotStates = {}
local ammoHolsterRangeByItem = {}
local collectedAmmoPickupStates = {}
local utilityShelfHolsterRangeByItem = {}
local ammoGrabAbilityPending = false
local currentIsLeftHanded = nil
local currentHandednessPawnName = nil
local activeUtilityShelfSide = nil
local lastUtilityShelfInputAt = -math.huge
local deadPlayerPawn = nil
local davisWireInsertionTickInterval = 0.07
local davisWireNormalizedPositionByItem = {}
local davisWirePenetrationPositionByItem = {}
local davisWireInsertionElapsedByItem = {}
local GetInteractorHandSide

local function PlayEffect(effectName)
	print(effectName)
	truegear.play_effect_by_uuid(effectName)
end

local function PlayAngle(event,tmpAngle,tmpVertical)
	local sourceEffect = truegear.find_effect(event)
	if sourceEffect == nil then
		return false
	end
	local rootObject = truegear.copy_effect(sourceEffect)
	if rootObject.tracks == nil then
		return false
	end
	local angle = (tmpAngle - 22.5 + 360) % 360
	local horCount = math.floor(angle / 45) + 1
	local verCount = (tmpVertical > 0.1) and -4 or (tmpVertical < 0 and 8 or 0)

	for _, track in pairs(rootObject.tracks) do
		if tostring(track.action_type) == "Shake" then
			for i = 1, #track.index do
				if verCount ~= 0 then
					track.index[i] = track.index[i] + verCount
				end
				if horCount < 8 then
					if track.index[i] < 50 then
						local remainder = track.index[i] % 4
						if horCount <= remainder then
							track.index[i] = track.index[i] - horCount
						elseif horCount <= (remainder + 4) then
							local num1 = horCount - remainder
							track.index[i] = track.index[i] - remainder + 99 + num1
						else
							track.index[i] = track.index[i] + 2
						end
					else
						local remainder = 3 - (track.index[i] % 4)
						if horCount <= remainder then
							track.index[i] = track.index[i] + horCount
						elseif horCount <= (remainder + 4) then
							local num1 = horCount - remainder
							track.index[i] = track.index[i] + remainder - 99 - num1
						else
							track.index[i] = track.index[i] - 2
						end
					end
				end
			end
			local filteredIndex = {}
			for _, v in pairs(track.index) do
				if not (v < 0 or (v > 19 and v < 100) or v > 119) then
					table.insert(filteredIndex, v)
				end
			end
			track.index = filteredIndex
		elseif tostring(track.action_type) == "Electrical" then
			for i = 1, #track.index do
				track.index[i] = horCount <= 4 and 0 or 100
			end
			if horCount == 1 or horCount == 8 or horCount == 4 or horCount == 5 then
				track.index = {0, 100}
			end
		end
	end

	print(event)
	truegear.play_effect_by_content(rootObject)
	return true
end

local function TryRegisterHook(funcName, callback, postCallback)
    local ok, hook1, hook2
    if postCallback ~= nil then
        ok, hook1, hook2 = pcall(RegisterHook, funcName, callback, postCallback)
    else
        ok, hook1, hook2 = pcall(RegisterHook, funcName, callback)
    end
	if not ok or hook1 == nil then
		hookRegistrationHadFailures = true
		return false
	end
	hookIds[funcName] = { id1 = hook1; id2 = hook2 }
	return true
end

local function RegisterHooks()
	hookRegistrationHadFailures = false

	for k,v in pairs(hookIds) do
		UnregisterHook(k, v.id1, v.id2)
	end

	hookIds = {}

	TryRegisterHook("/Game/Player/BP_PlayerPawn_Base.BP_PlayerPawn_Base_C:BndEvt__BP_PlayerPawn_FS_DamageableComponent_K2Node_ComponentBoundEvent_0_DeathDynamicSignature__DelegateSignature", BndEvt__BP_PlayerPawn_FS_DamageableComponent_K2Node_ComponentBoundEvent_0_DeathDynamicSignature__DelegateSignature)

	TryRegisterHook("/Game/Player/BP_PlayerPawn_VR.BP_PlayerPawn_VR_C:BndEvt__BP_PlayerPawn_VR_DamageableComponent_K2Node_ComponentBoundEvent_0_HealDynamicSignature__DelegateSignature", BndEvt__BP_PlayerPawn_VR_DamageableComponent_K2Node_ComponentBoundEvent_0_HealDynamicSignature__DelegateSignature)

    TryRegisterHook("/Game/Player/Equippables/Guns/BP_Weapon_Base.BP_Weapon_Base_C:BndEvt__BP_Weapon_FS_GunEventsComponent_K2Node_ComponentBoundEvent_0_SVRFireDynamicSignature__DelegateSignature", BndEvt__BP_Weapon_FS_GunEventsComponent_K2Node_ComponentBoundEvent_0_SVRFireDynamicSignature__DelegateSignature)

    TryRegisterHook("/Script/MNEquipmentVR.MNEquippableUserMode_VR:SetIsHolstered", SetIsHolstered)

    TryRegisterHook("/Script/MNEquipmentVR.MNEquippableUserMode_VR:ReceiveSetIsHolstered", ReceiveSetIsHolstered)

    TryRegisterHook("/Script/SVRGrabSlot.SVRGrabSlotActor:OnGrabbed", OnGrabbed)

    TryRegisterHook("/Script/MNItemVR.MNHolsterTransitionComponent:StartHolsterTransitionForHand", StartHolsterTransitionForHand)

    TryRegisterHook("/Game/Player/Equippables/Guns/BP_UserMode_Weapon_VR.BP_UserMode_Weapon_VR_C:OnAddActiveInteractor", WeaponAddActiveInteractor)

    TryRegisterHook("/Game/Player/Equippables/Guns/BP_UserMode_Weapon_VR.BP_UserMode_Weapon_VR_C:OnRemoveActiveInteractor", WeaponRemoveActiveInteractor)

    TryRegisterHook("/Game/Player/Equippables/Gear/PowerTool/BP_PowerTool_VR.BP_PowerTool_VR_C:ReceiveHandleFinishEquipping", PowerToolFinishedEquipping)

    TryRegisterHook("/Game/Player/Equippables/Gear/PowerTool/BP_PowerTool_VR.BP_PowerTool_VR_C:ReceiveHandleStartUnequipping", PowerToolStartedUnequipping)

    TryRegisterHook("/Game/Player/Equippables/Gear/MotionTracker/BP_MotionTracker_VR.BP_MotionTracker_VR_C:ReceiveHandleStartEquipping", MotionTrackerStartedEquipping)

    TryRegisterHook("/Game/Player/Equippables/Gear/MotionTracker/BP_MotionTracker_Base.BP_MotionTracker_Base_C:ReceiveHandleStartEquipping", MotionTrackerStartedEquipping)

    TryRegisterHook("/Game/Player/Equippables/Gear/MotionTracker/BP_MotionTracker_VR.BP_MotionTracker_VR_C:ReceiveHandleFinishUnequipping", MotionTrackerFinishedUnequipping)

    TryRegisterHook("/Game/Player/Equippables/Tacticals/Concussion/BP_Concussion_VR.BP_Concussion_VR_C:ReceiveHandleStartEquipping", ConcussionStartedEquipping)

    TryRegisterHook("/Game/Player/Equippables/Tacticals/Concussion/BP_Concussion_VR.BP_Concussion_VR_C:ReceiveHandleStartUnequipping", ConcussionStartedUnequipping)

    TryRegisterHook("/Game/Blueprints/Props/BP_DynamicProp.BP_DynamicProp_C:BndEvt__BP_DynamicProp_InteractableComponent_K2Node_ComponentBoundEvent_0_InteractorDynamicSignature__DelegateSignature", DynamicPropGrabbed)

    TryRegisterHook("/Game/Blueprints/Interactables/HardDrive/BP_HardDrive.BP_HardDrive_C:BndEvt__BP_HardDrive_InteractableComponent_K2Node_ComponentBoundEvent_5_InteractorHandDynamicSignature__DelegateSignature", PhysicalItemGrabbed)

    TryRegisterHook("/Game/Blueprints/Interactables/HardDrive/BP_HardDrive.BP_HardDrive_C:BndEvt__BP_HardDrive_InteractableComponent_K2Node_ComponentBoundEvent_6_InteractorHandDynamicSignature__DelegateSignature", PhysicalItemReleased)

    TryRegisterHook("/Game/Player/Equippables/Guns/Revolver/BP_AmmoItem_Revolver_VR.BP_AmmoItem_Revolver_VR_C:BndEvt__BP_AmmoItem_Revolver_VR_InteractableComponent_K2Node_ComponentBoundEvent_0_InteractorHandDynamicSignature__DelegateSignature", PhysicalItemGrabbed)

    TryRegisterHook("/Game/Blueprints/Interactables/HardDrive/BP_HardDrive.BP_HardDrive_C:BndEvt__BP_HardDrive_SVRAttachablePoint_K2Node_ComponentBoundEvent_1_SVRAttachableAttachmentCompletedDynamicSignature__DelegateSignature", BlueprintAttachmentCompleted)

    TryRegisterHook("/Game/Blueprints/Interactables/HardDrive/BP_HardDrive.BP_HardDrive_C:BndEvt__BP_HardDrive_SVRAttachablePoint_K2Node_ComponentBoundEvent_2_SVRAttachableAttachmentStoppedDynamicSignature__DelegateSignature", BlueprintAttachmentStopped)

    TryRegisterHook("/Game/Player/Equippables/Gear/DavisTablet/BP_Tablet_VR.BP_Tablet_VR_C:OnSetHolsteredEvent_Event", BlueprintSetHolstered)

    TryRegisterHook("/Game/Player/Equippables/Gear/MedInjector/BP_MedInjector_VR.BP_MedInjector_VR_C:BndEvt__BP_MedInjector_VR_HolsterDetectionStateComponent_K2Node_ComponentBoundEvent_1_HolsterRangeDynamicSignature__DelegateSignature", MedInjectorHolsterRangeChanged)

    TryRegisterHook("/Game/Player/Equippables/Gear/MedInjector/BP_MedInjector_VR.BP_MedInjector_VR_C:BndEvt__BP_MedInjector_VR_HolsterDetectionStateComponent_K2Node_ComponentBoundEvent_2_HolsterRangeDynamicSignature__DelegateSignature", MedInjectorHolsterRangeChanged)

    TryRegisterHook("/Game/Player/Equippables/Gear/MedInjector/BP_MedInjector_VR.BP_MedInjector_VR_C:OnHolsterTransitionBeginEvent", BlueprintHolsterBegin)

    TryRegisterHook("/Game/Player/GA/Equipping/GA_EquipItem_Base.GA_EquipItem_Base_C:K2_ActivateAbility", EquipmentTakenFromSlot)

    TryRegisterHook("/Game/Player/GA/Equipping/GA_GrabAmmoMagazine.GA_GrabAmmoMagazine_C:K2_ActivateAbility", AmmoMagazineGrabStarted, AmmoMagazineGrabbedPost)

    TryRegisterHook("/Game/Player/Equippables/Guns/BP_AmmoItemUserMode_VR.BP_AmmoItemUserMode_VR_C:BndEvt__BP_AmmoMagazine_VR_MagazineInteractionComponent_K2Node_ComponentBoundEvent_3_SVROnCompleteInsertionDynamicSignature__DelegateSignature", AmmoMagazineCompleteInsertion)

    TryRegisterHook("/Script/MNEquipmentVR.MNAmmoItemUserMode_VR:HandleCollectedMagazine", AmmoMagazineCollectedNative)

    TryRegisterHook("/Game/Blueprints/Pickups/Ammo/BP_Pickup_AmmoBox_Shotgun_VR.BP_Pickup_AmmoBox_Shotgun_VR_C:BndEvt__BP_Pickup_AmmoBox_Shotgun_VR_XReComponent_K2Node_ComponentBoundEvent_0_PickupCollectedSignature__DelegateSignature", AmmoPickupCollected)

    TryRegisterHook("/Game/Blueprints/Pickups/BP_Pickup_Base.BP_Pickup_Base_C:BndEvt__BP_Pickup_Base_XReComponent_K2Node_ComponentBoundEvent_0_PickupCollectedSignature__DelegateSignature", AmmoPickupCollected)

    TryRegisterHook("/Game/Blueprints/Pickups/BP_Pickup_Base.BP_Pickup_Base_C:BndEvt__BP_Pickup_Base_XReComponent_K2Node_ComponentBoundEvent_1_PickupCollectedSignature__DelegateSignature", AmmoPickupCollected)

    TryRegisterHook("/Game/Blueprints/Pickups/BP_Pickup_Base.BP_Pickup_Base_C:BndEvt__BP_Pickup_Base_XReComponent_K2Node_ComponentBoundEvent_2_PickupCollectedSignature__DelegateSignature", AmmoPickupCollected)

    TryRegisterHook("/Script/MNPickup.MNPickupXReComponent:HandlePickupForPlayer", AmmoPickupComponentCollected)

    TryRegisterHook("/Game/Player/GA/Equipping/GA_UnequipWeapon.GA_UnequipWeapon_C:K2_ActivateAbility", EquipmentPutIntoSlot)

    TryRegisterHook("/Game/Player/GA/Equipping/GA_UnequipGear.GA_UnequipGear_C:K2_ActivateAbilityFromEvent", EquipmentPutIntoSlot)

    TryRegisterHook("/Game/Player/GA/Equipping/GA_UnequipTactical.GA_UnequipTactical_C:K2_ActivateAbilityFromEvent", EquipmentPutIntoSlot)

    TryRegisterHook("/Game/Player/GA/Equipping/GA_OpenItemShelf_Left.GA_OpenItemShelf_Left_C:K2_ActivateAbility", UtilityShelfOpenedLeft)

    TryRegisterHook("/Game/Player/GA/Equipping/GA_OpenItemShelf_Right.GA_OpenItemShelf_Right_C:K2_ActivateAbility", UtilityShelfOpenedRight)

    TryRegisterHook("/Game/Player/BodySlot/BP_GrabSlot_Equippable_ItemShelf.BP_GrabSlot_Equippable_ItemShelf_C:OnGrabbed", ItemShelfGrabbed)

    TryRegisterHook("/Game/Player/Equippables/Guns/PulseRifle/BP_PulseRifle_VR.BP_PulseRifle_VR_C:OnHolsterTransitionComplete", BlueprintHolsterComplete)

    TryRegisterHook("/Game/Player/Equippables/Guns/Shotgun/BP_Shotgun_VR.BP_Shotgun_VR_C:OnHolsterTransitionComplete", BlueprintHolsterComplete)

    TryRegisterHook("/Game/Player/Equippables/Guns/Revolver/VR/ABP_Revolver_CylinderRigidBody.ABP_Revolver_CylinderRigidBody_C:On Holster Transition Complete", RevolverHolsterComplete)

	TryRegisterHook("/Game/Player/BP_PlayerPawn_Base.BP_PlayerPawn_Base_C:ReceiveTick", PlayerGrabStateTick)

    TryRegisterHook("/Game/Blueprints/Synths/Davis/BP_DavisHead_WireEnd.BP_DavisHead_WireEnd_C:ReceiveTick", DavisHeadWireInsertionTick)

    TryRegisterHook("/Game/Blueprints/Synths/Davis/BP_DavisHead.BP_DavisHead_C:PlayFeedbackOnWireInsertionStarted", DavisHeadWireInsertionStarted)


    TryRegisterHook("/Game/Player/BP_PlayerPawn_VR.BP_PlayerPawn_VR_C:BndEvt__BP_PlayerPawn_VR_DamageableComponent_K2Node_ComponentBoundEvent_2_DamageDynamicSignature__DelegateSignature", PlayerDamage)

    TryRegisterHook("/Game/Player/BP_PlayerPawn_VR.BP_PlayerPawn_VR_C:OnPhysicalCrouchStateChanged", PlayerPhysicalCrouchChanged)

    TryRegisterHook("/Game/Player/BP_PlayerPawn_VR.BP_PlayerPawn_VR_C:OnFootJoystickEdgeLeapEvent", PlayerJump)

    TryRegisterHook("/Game/Player/Equippables/Guns/Shotgun/BP_Shotgun_VR.BP_Shotgun_VR_C:OnCompleteInsertion", ShotgunShellInserted)

    TryRegisterHook("/Game/Player/Equippables/Guns/PulseRifle/BP_PulseRifle_VR.BP_PulseRifle_VR_C:OnSlideExitDeadzone", PulseRifleSlide)

    TryRegisterHook("/Game/Player/Equippables/Guns/Revolver/BP_Revolver_VR.BP_Revolver_VR_C:BndEvt__BP_Revolver_VR_SVRGunStateMachine_TransformingMagazine_K2Node_ComponentBoundEvent_5_SVROnChamberSlotsOccupiedIncreasedDynamicSignature__DelegateSignature", RevolverRoundInserted)

    TryRegisterHook("/Script/MNEquipment.MNGearComponent:StartActivate", GearActivateStart)

    TryRegisterHook("/Script/MNEquipment.MNGearComponent:StopActivate", GearActivateStop)

    TryRegisterHook("/Game/Player/Equippables/Gear/MotionTracker/BP_MotionTracker_Base.BP_MotionTracker_Base_C:MotionTrackerWidget_OnPulseStarted", MotionTrackerPulse)

    TryRegisterHook("/Game/Blueprints/Facehugger/Abilities/GA/GA_Facehugger_Attack.GA_Facehugger_Attack_C:OnHitPlayerFace", FacehuggerHitFace)


    TryRegisterHook("/Script/SVRHaptics.SVRHapticsStatics:PlayHapticEffectOnFirstLocalPlayerController", PlayHapticEffectOnFirstLocalPlayerController)


    TryRegisterHook("/Game/Player/BP_PlayerPawn_VR.BP_PlayerPawn_VR_C:HandleAdditionalLowHealthFX", HandleAdditionalLowHealthFX)


	return not hookRegistrationHadFailures
end

function HandleAdditionalLowHealthFX(self)
    PlayEffect("HeartBeat")
end

function PlayHapticEffectOnFirstLocalPlayerController(self,WorldContextObject,InHapticEffect,InHapticDevice)
    if string.find(InHapticEffect:get():GetFullName(),"FallLand") then
        if string.find(InHapticEffect:get():GetFullName(),"FallLandHard") then
            PlayEffect("FallLandHard")
        else
            PlayEffect("FallLand")
        end
    elseif string.find(InHapticEffect:get():GetFullName(),"StartLeap") then
        PlayEffect("Leap")
    elseif string.find(InHapticEffect:get():GetFullName(),"Facehugger_Shutup_Shootout") then
        PlayEffect("FacehuggerHitFace")
    end
end

local function Unwrap(value)
    if value == nil then
        return nil
    end

    local ok, unwrapped = pcall(function()
        return value:get()
    end)
    if ok then
        return unwrapped
    end
    return value
end

local function SafeFullName(value)
    local object = Unwrap(value)
    if object == nil then
        return "nil"
    end

    local validityChecked, isValid = pcall(function()
        return object:IsValid()
    end)
    if validityChecked and not isValid then
        return "nil"
    end

    local ok, fullName = pcall(function()
        return object:GetFullName()
    end)
    if ok and fullName ~= nil then
        return tostring(fullName)
    end
    return tostring(object)
end

local function SafeField(value, ...)
    local current = Unwrap(value)
    for _, key in ipairs({...}) do
        if current == nil then
            return nil
        end
        local ok, nextValue = pcall(function()
            return current[key]
        end)
        if not ok then
            return nil
        end
        current = Unwrap(nextValue)
    end
    return current
end

local function SafeNumberField(value, fieldName)
    local fieldValue = SafeField(value, fieldName)
    if fieldValue == nil then
        return nil
    end
    return tonumber(fieldValue)
end

local function TryGetActorLocation(actor)
    local object = Unwrap(actor)
    if object == nil then
        return nil
    end

    local ok, location = pcall(function()
        return object:K2_GetActorLocation()
    end)
    if ok then
        return location
    end
    return nil
end

local function TryGetPlayerCenter(player)
    local ok, center = pcall(function()
        return player:GetWorldCenterLocation()
    end)
    if ok then
        return center
    end
    return TryGetActorLocation(player)
end

local function TryGetHeadYaw(player)
    local ok, rotation = pcall(function()
        return player.CameraComponent:K2_GetComponentRotation()
    end)
    if not ok then
        return nil
    end
    return SafeNumberField(rotation, "Yaw")
end

local function NormalizeAngle360(angle)
    angle = angle % 360.0
    if angle < 0 then
        angle = angle + 360.0
    end
    return angle
end

local function CalculateDamageAngle(self, DamageResult)
    local player = Unwrap(self)
    if player == nil then
        return nil
    end

    local damageCauser = SafeField(DamageResult, "DamageEvent", "DamageCauser")
    if damageCauser == nil then
        return nil
    end

    local validityChecked, isValid = pcall(function()
        return damageCauser:IsValid()
    end)
    if validityChecked and not isValid then
        return nil
    end

    local headYaw = TryGetHeadYaw(player)
    if headYaw == nil then
        return nil
    end

    local playerCenter = TryGetPlayerCenter(player)
    local damageCauserLocation = TryGetActorLocation(damageCauser)
    if playerCenter == nil or damageCauserLocation == nil then
        return nil
    end

    local playerX = SafeNumberField(playerCenter, "X")
    local playerY = SafeNumberField(playerCenter, "Y")
    local causerX = SafeNumberField(damageCauserLocation, "X")
    local causerY = SafeNumberField(damageCauserLocation, "Y")
    if playerX == nil or playerY == nil or causerX == nil or causerY == nil then
        return nil
    end

    local sourceX = causerX - playerX
    local sourceY = causerY - playerY

    if math.abs(sourceX) < 0.001 and math.abs(sourceY) < 0.001 then
        return nil
    end

    local sourceWorldYaw = math.deg(math.atan(sourceY, sourceX))

    local damageAngle = NormalizeAngle360(headYaw - sourceWorldYaw)
    return damageAngle
end

local function IsDeadPlayerPawn(playerValue)
    local player = Unwrap(playerValue)
    return player ~= nil and deadPlayerPawn ~= nil and player == deadPlayerPawn
end

local function GetDominantHandSide()
    if currentIsLeftHanded == true then
        return "Left"
    end
    if currentIsLeftHanded == false then
        return "Right"
    end
    return "Unknown"
end

local function GetNonDominantHandSide()
    if currentIsLeftHanded == true then
        return "Right"
    end
    if currentIsLeftHanded == false then
        return "Left"
    end
    return "Unknown"
end

local function GetTacticalSlotName()
    return GetNonDominantHandSide() .. "Elbow"
end

local function GetMedInjectorSlotName()
    return GetNonDominantHandSide() .. "Wrist"
end

local function GetMotionTrackerSlotName()
    return GetDominantHandSide() .. "Elbow"
end

local function GetMirroredSlotName(rightHandedSlotName)
    if currentIsLeftHanded == nil then
        return "Unknown"
    end
    if currentIsLeftHanded == false then
        return rightHandedSlotName
    end
    if string.find(rightHandedSlotName, "Left", 1, true) == 1 then
        return "Right" .. string.sub(rightHandedSlotName, 5)
    end
    if string.find(rightHandedSlotName, "Right", 1, true) == 1 then
        return "Left" .. string.sub(rightHandedSlotName, 6)
    end
    return rightHandedSlotName
end

local function GetPhysicalSlotName(itemValue)
    local itemName = SafeFullName(itemValue)

    if string.find(itemName, "BP_GrabSlot_Equippable_ItemShelf", 1, true) ~= nil then
        return (activeUtilityShelfSide or "Unknown") .. "UtilityShelf"
    end

    if string.find(itemName, "AmmoItem", 1, true) ~= nil or
        string.find(itemName, "BP_Pickup_Ammo", 1, true) ~= nil or
        string.find(itemName, "BodySlot_Ammo", 1, true) ~= nil then
        return GetMirroredSlotName("LeftHip")
    end
    if string.find(itemName, "MedInjector", 1, true) ~= nil then
        return GetMedInjectorSlotName()
    end
    if string.find(itemName, "Concussion", 1, true) ~= nil then
        return GetTacticalSlotName()
    end
    if string.find(itemName, "MotionTracker", 1, true) ~= nil then
        return GetMotionTrackerSlotName()
    end
    if string.find(itemName, "PulseRifle", 1, true) ~= nil or
        string.find(itemName, "PRifle", 1, true) ~= nil then
        return GetMirroredSlotName("RightBack")
    end
    if string.find(itemName, "Shotgun", 1, true) ~= nil then
        return GetMirroredSlotName("LeftBack")
    end
    if string.find(itemName, "Revolver", 1, true) ~= nil or
        string.find(itemName, "Pistol", 1, true) ~= nil then
        return GetMirroredSlotName("RightHip")
    end
    if string.find(itemName, "Tablet", 1, true) ~= nil or
        string.find(itemName, "PowerTool", 1, true) ~= nil or
        string.find(itemName, "PowerBoxTool", 1, true) ~= nil or
        string.find(itemName, "HackingTool", 1, true) ~= nil or
        string.find(itemName, "PlasmaTorch", 1, true) ~= nil or
        string.find(itemName, "WireStripper", 1, true) ~= nil or
        string.find(itemName, "ClearanceCard", 1, true) ~= nil then
        return (activeUtilityShelfSide or "Unknown") .. "UtilityShelf"
    end
    return "Unknown"
end

local function GetResolvedPhysicalSlotName(itemValue, slotObjectValue)
    local slotName = GetPhysicalSlotName(itemValue)
    if slotName == "Unknown" and slotObjectValue ~= nil then
        slotName = GetPhysicalSlotName(slotObjectValue)
    end
    return slotName
end

local function RememberItemHandSide(itemValue, handSide)
    if handSide ~= "Left" and handSide ~= "Right" then
        return
    end
    local itemName = SafeFullName(itemValue)
    if itemName ~= "nil" then
        gearHandSides[itemName] = handSide
    end
end

local function GetSlotEffectName(itemValue, slotObjectValue, isInput)
    local slotName = GetResolvedPhysicalSlotName(itemValue, slotObjectValue)
    if string.find(slotName, "UtilityShelf", 1, true) ~= nil then
        return slotName .. (isInput and "InputItem" or "OutputItem")
    end
    return slotName .. "Slot" .. (isInput and "InputItem" or "OutputItem")
end

local function PlaySlotEffect(effectName)
    if type(effectName) ~= "string" or string.find(effectName, "Unknown", 1, true) == 1 then
        return false
    end
    PlayEffect(effectName)
    return true
end

local function IsUtilityShelfItemName(itemName)
    if type(itemName) ~= "string" then
        return false
    end
    return string.find(itemName, "Tablet", 1, true) ~= nil or
        string.find(itemName, "PowerTool", 1, true) ~= nil or
        string.find(itemName, "PowerBoxTool", 1, true) ~= nil or
        string.find(itemName, "HackingTool", 1, true) ~= nil or
        string.find(itemName, "PlasmaTorch", 1, true) ~= nil or
        string.find(itemName, "WireStripper", 1, true) ~= nil or
        string.find(itemName, "ClearanceCard", 1, true) ~= nil
end

local function IsUtilityShelfNonTabletItemName(itemName)
    return IsUtilityShelfItemName(itemName) and
        string.find(itemName, "Tablet", 1, true) == nil
end

local function PlayUtilityShelfInput()
    local now = os.clock()
    if now - lastUtilityShelfInputAt < 0.2 then
        return false
    end

    local effectName = (activeUtilityShelfSide or "Unknown") .. "UtilityShelfInputItem"
    if not PlaySlotEffect(effectName) then
        return false
    end

    lastUtilityShelfInputAt = now
    return true
end

local function IsAmmoItem(itemName)
    return itemName ~= nil and
        (string.find(itemName, "BP_AmmoItem_", 1, true) ~= nil or
         string.find(itemName, "BP_Pickup_Ammo", 1, true) ~= nil)
end

local function SetAmmoHolsterRange(itemValue, isInRange)
    local item = Unwrap(itemValue)
    if item == nil then
        return
    end
    local itemName = SafeFullName(item)
    if IsAmmoItem(itemName) then
        ammoHolsterRangeByItem[itemName] = isInRange == true
    end
end

local function ReportAmmoInserted(itemValue)
    local item = Unwrap(itemValue)
    if item == nil then
        return
    end
    local itemName = SafeFullName(item)
    if not IsAmmoItem(itemName) or ammoSlotStates[itemName] == true then
        return
    end

    ammoSlotStates[itemName] = true
    ammoHolsterRangeByItem[itemName] = nil
    local effectName = GetSlotEffectName(item, nil, true)
    PlaySlotEffect(effectName)
end


local function UpdatePlayerHandedness(playerValue, interactorPawnComponentValue)
    local player = Unwrap(playerValue)
    if player == nil then
        return
    end

    if deadPlayerPawn ~= nil and player ~= deadPlayerPawn then
        deadPlayerPawn = nil
    end
    local isLeftHanded = SafeField(player, "IsLeftHanded")
    if type(isLeftHanded) ~= "boolean" then
        local interactorPawnComponent = Unwrap(interactorPawnComponentValue)
        local ok, isRightHandDominant = pcall(function()
            return interactorPawnComponent:IsRightHandDominant()
        end)
        isRightHandDominant = Unwrap(isRightHandDominant)
        if ok and type(isRightHandDominant) == "boolean" then
            isLeftHanded = not isRightHandDominant
        else
            return
        end
    end

    local playerName = SafeFullName(player)
    local isNewPawn = currentHandednessPawnName ~= playerName
    if not isNewPawn and currentIsLeftHanded == isLeftHanded then
        return
    end

    currentIsLeftHanded = isLeftHanded
    currentHandednessPawnName = playerName
end

local function IsMedInjector(itemName)
    return itemName ~= nil and
        string.find(itemName, "BP_MedInjector_VR_C", 1, true) ~= nil
end

local function SetMedInjectorHolsterRange(itemValue, isInRange)
    local item = Unwrap(itemValue)
    if item == nil then
        return
    end
    local itemName = SafeFullName(item)
    if IsMedInjector(itemName) then
        medInjectorHolsterRangeByItem[itemName] = isInRange == true
    end
end

local function ReportMedInjectorInserted(itemValue)
    local item = Unwrap(itemValue)
    if item == nil then
        return
    end
    local itemName = SafeFullName(item)
    if not IsMedInjector(itemName) or medInjectorSlotStates[itemName] == true then
        return
    end

    medInjectorSlotStates[itemName] = true
    medInjectorHolsterRangeByItem[itemName] = nil
    local effectName = GetSlotEffectName(item, nil, true)
    PlaySlotEffect(effectName)
end

local function IsConcussionGrenade(itemName)
    return itemName ~= nil and
        string.find(itemName, "BP_Concussion_VR_C", 1, true) ~= nil
end

local function SetConcussionHolsterRange(itemValue, isInRange)
    local item = Unwrap(itemValue)
    if item == nil then
        return
    end
    local itemName = SafeFullName(item)
    if IsConcussionGrenade(itemName) then
        concussionHolsterRangeByItem[itemName] = isInRange == true
    end
end

local function ReportConcussionRemoved(itemValue)
    local item = Unwrap(itemValue)
    if item == nil then
        return
    end
    local itemName = SafeFullName(item)
    if not IsConcussionGrenade(itemName) or concussionIsInSlot == false then
        return
    end

    concussionIsInSlot = false
    local effectName = GetSlotEffectName(item, nil, false)
    PlaySlotEffect(effectName)
end

local function ReportConcussionInserted(itemValue)
    local item = Unwrap(itemValue)
    if item == nil then
        return
    end
    local itemName = SafeFullName(item)
    if not IsConcussionGrenade(itemName) or concussionIsInSlot == true then
        return
    end

    concussionIsInSlot = true
    concussionHolsterRangeByItem[itemName] = nil
    local effectName = GetSlotEffectName(item, nil, true)
    PlaySlotEffect(effectName)
end

local function RecordKnownHeldItem(handSide, eventSuffix, itemValue)
    if handSide ~= "Left" and handSide ~= "Right" then
        return
    end

    local itemName = SafeFullName(itemValue)
    if itemName == "nil" then
        return
    end

    if eventSuffix == "GrabbedItem" then
        grabbedItemByHand[handSide] = itemName
    elseif eventSuffix == "ReleasedItem" and grabbedItemByHand[handSide] == itemName then
        if not IsUtilityShelfNonTabletItemName(itemName) then
            grabbedItemByHand[handSide] = nil
        end
    end
end

local function ResolveEquippableActor(value)
    local object = Unwrap(value)
    if object == nil then
        return nil
    end

    local ok, equippable = pcall(function()
        return object:GetOwnerEquippable()
    end)
    if ok and equippable ~= nil then
        return Unwrap(equippable)
    end
    return object
end

local function SetWeaponInSlot(value, inSlot)
    local object = Unwrap(value)
    if object == nil then
        return
    end
    local actor = ResolveEquippableActor(object)
    weaponInSlotStates[SafeFullName(object)] = inSlot
    weaponInSlotStates[SafeFullName(actor)] = inSlot

    local userMode = SafeField(actor, "UserMode")
    if userMode ~= nil then
        weaponInSlotStates[SafeFullName(userMode)] = inSlot
    end
end

local function ReportWeaponRemovedFromSlot(userModeValue, handValue)
    local userMode = Unwrap(userModeValue)
    if userMode == nil then
        return
    end
    local weapon = ResolveEquippableActor(userMode)
    local wasInSlot = weaponInSlotStates[SafeFullName(userMode)] == true or
        weaponInSlotStates[SafeFullName(weapon)] == true or
        SafeField(userMode, "bIsHolstered") == true or
        SafeField(userMode, "bIsCurrentlyUnholstering") == true
    if not wasInSlot then
        return
    end

    SetWeaponInSlot(userMode, false)
    local hand = Unwrap(handValue)
    local handSide = GetInteractorHandSide(hand)
    RememberItemHandSide(weapon, handSide)
    local effectName = GetSlotEffectName(weapon, nil, false)
    PlaySlotEffect(effectName)
end

local function GetEquippableHandSide(userMode)
    local hand = SafeField(userMode, "CurrentDominantInteractorHand")
    if hand == nil then
        hand = SafeField(userMode, "PrimaryInitiatorHand")
    end
    hand = Unwrap(hand)
    if hand == nil then
        return nil
    end

    local ok, isLeft = pcall(function()
        return hand:IsLeft()
    end)
    if ok then
        return isLeft and "Left" or "Right"
    end
    return nil
end

local function UpdateHolsteredItemState(selfValue, stateValue)
    local userMode = Unwrap(selfValue)
    local isHolstered = Unwrap(stateValue)
    if userMode == nil or type(isHolstered) ~= "boolean" then
        return
    end

    local itemName = SafeFullName(userMode)
    local previousState = holsteredItemStates[itemName]
    holsteredItemStates[itemName] = isHolstered
    SetWeaponInSlot(userMode, isHolstered)
    if previousState == isHolstered then
        return
    end

    local handSide = GetEquippableHandSide(userMode)
    local equippable = ResolveEquippableActor(userMode)
    RememberItemHandSide(equippable, handSide)
    if isHolstered then
        local effectName = GetSlotEffectName(equippable, nil, true)
        PlaySlotEffect(effectName)
    else
        local effectName = GetSlotEffectName(equippable, nil, false)
        PlaySlotEffect(effectName)
    end

end

GetInteractorHandSide = function(interactor)
    local ok, isLeft = pcall(function()
        return interactor:IsLeft()
    end)
    if ok and isLeft then
        return "Left"
    end

    local rightOk, isRight = pcall(function()
        return interactor:IsRight()
    end)
    if rightOk and isRight then
        return "Right"
    end
    return nil
end

local function GetGearUserMode(itemValue)
    local item = Unwrap(itemValue)
    if item == nil then
        return nil
    end
    local userMode = SafeField(item, "UserMode")
    if userMode == nil then
        userMode = SafeField(item, "MNEquippableUserMode_VR")
    end
    return Unwrap(userMode)
end

local function GetHandSideFromEnum(value)
    local rawValue = Unwrap(value)
    if rawValue == nil then
        return nil
    end
    local text = tostring(rawValue)
    local numericValue = tonumber(text)
    if numericValue == 0 or string.find(text, "Left", 1, true) then
        return "Left"
    end
    if numericValue == 1 or string.find(text, "Right", 1, true) then
        return "Right"
    end
    return nil
end

local function GetGearHandSide(itemValue)
    local item = Unwrap(itemValue)
    local itemName = SafeFullName(item)
    local handSide = GetEquippableHandSide(GetGearUserMode(item))
    if handSide == nil then
        handSide = GetHandSideFromEnum(SafeField(item, "LastActiveHandSide"))
    end
    if handSide ~= nil then
        gearHandSides[itemName] = handSide
        return handSide
    end
    return gearHandSides[itemName] or "Unknown"
end

local function ReportGearGrabbed(itemValue, removedFromSlot)
    local item = Unwrap(itemValue)
    if item == nil then
        return
    end
    local itemName = SafeFullName(item)

    if removedFromSlot and gearSlotStates[itemName] ~= false then
        local handSide = GetGearHandSide(item)
        RememberItemHandSide(item, handSide)
        gearSlotStates[itemName] = false
        local effectName = GetSlotEffectName(item, nil, false)
        PlaySlotEffect(effectName)
    end
end

local function ReportGearUnequipped(itemValue, insertedIntoSlot)
    local item = Unwrap(itemValue)
    if item == nil then
        return
    end
    local itemName = SafeFullName(item)

    if insertedIntoSlot and gearSlotStates[itemName] ~= true then
        local handSide = GetGearHandSide(item)
        RememberItemHandSide(item, handSide)
        gearSlotStates[itemName] = true
        local effectName = GetSlotEffectName(item, nil, true)
        PlaySlotEffect(effectName)
    end
end

local function GetGrabbedItemFromInteractor(interactor)
    local stateOk, isInteracting = pcall(function()
        return interactor:IsInteracting()
    end)
    if stateOk and not isInteracting then
        return nil
    end

    local gripData = SafeField(interactor, "CurrentGripData")
    if gripData == nil then
        local ok, result = pcall(function()
            return interactor:GetCurrentGripData()
        end)
        if not ok then
            return nil
        end
        gripData = result
    end

    local interactable = SafeField(gripData, "Interactable")
    if interactable == nil then
        return nil
    end

    local validOk, isValid = pcall(function()
        return interactable:IsValid()
    end)
    if validOk and not isValid then
        return nil
    end

    local ownerOk, owner = pcall(function()
        return interactable:GetOwner()
    end)
    if ownerOk and owner ~= nil then
        return owner
    end
    return interactable
end

local function UpdateGrabbedItemFromInteractor(interactorValue)
    local interactor = Unwrap(interactorValue)
    if interactor == nil then
        return
    end

    local handSide = GetInteractorHandSide(interactor)
    if handSide == nil then
        return
    end

    local grabbedItem = GetGrabbedItemFromInteractor(interactor)
    local grabbedItemName = nil
    if grabbedItem ~= nil then
        grabbedItemName = SafeFullName(grabbedItem)
    end

    if IsAmmoItem(grabbedItemName) then
        SetAmmoHolsterRange(
            grabbedItem,
            SafeField(grabbedItem, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
        )
    elseif IsMedInjector(grabbedItemName) then
        SetMedInjectorHolsterRange(
            grabbedItem,
            SafeField(grabbedItem, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
        )
    elseif IsConcussionGrenade(grabbedItemName) then
        SetConcussionHolsterRange(
            grabbedItem,
            SafeField(grabbedItem, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
        )
    elseif IsUtilityShelfNonTabletItemName(grabbedItemName) then
        utilityShelfHolsterRangeByItem[grabbedItemName] =
            SafeField(grabbedItem, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
    end

    local previousItemName = grabbedItemByHand[handSide]
    if grabbedItemName ~= nil and grabbedItemName ~= previousItemName then
        grabbedItemByHand[handSide] = grabbedItemName
        grabbedItemObjectByHand[handSide] = grabbedItem
        RememberItemHandSide(grabbedItem, handSide)

        if string.find(grabbedItemName, "BP_DavisHead_WireEnd_C", 1, true) ~= nil then
            davisWireNormalizedPositionByItem[grabbedItemName] = nil
            davisWirePenetrationPositionByItem[grabbedItemName] = nil
            davisWireInsertionElapsedByItem[grabbedItemName] = nil
        end

        if IsAmmoItem(grabbedItemName) and ammoGrabAbilityPending then
            ammoSlotStates[grabbedItemName] = false
            ammoGrabAbilityPending = false
        elseif IsMedInjector(grabbedItemName) and medInjectorSlotStates[grabbedItemName] ~= false then
            medInjectorSlotStates[grabbedItemName] = false
            local effectName = GetSlotEffectName(grabbedItem, nil, false)
            PlaySlotEffect(effectName)
        elseif IsConcussionGrenade(grabbedItemName) then
            ReportConcussionRemoved(grabbedItem)
        end

        PlayEffect(handSide .. "HandGrabbedItem")
    elseif grabbedItemName == nil and previousItemName ~= nil then
        local releasedItem = grabbedItemObjectByHand[handSide]
        grabbedItemByHand[handSide] = nil
        grabbedItemObjectByHand[handSide] = nil

        if string.find(previousItemName, "BP_DavisHead_WireEnd_C", 1, true) ~= nil then
            davisWireNormalizedPositionByItem[previousItemName] = nil
            davisWirePenetrationPositionByItem[previousItemName] = nil
            davisWireInsertionElapsedByItem[previousItemName] = nil
        end

        if IsAmmoItem(previousItemName) then
            local wasInHolsterRange = ammoHolsterRangeByItem[previousItemName] == true or
                SafeField(releasedItem, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
            if wasInHolsterRange then
                ReportAmmoInserted(releasedItem)
            else
                ammoHolsterRangeByItem[previousItemName] = nil
            end
        elseif IsMedInjector(previousItemName) then
            local wasInHolsterRange = medInjectorHolsterRangeByItem[previousItemName] == true or
                SafeField(releasedItem, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
            if wasInHolsterRange then
                ReportMedInjectorInserted(releasedItem)
            else
                medInjectorHolsterRangeByItem[previousItemName] = nil
            end
        elseif IsConcussionGrenade(previousItemName) then
            local wasInHolsterRange = concussionHolsterRangeByItem[previousItemName] == true or
                SafeField(releasedItem, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
            if wasInHolsterRange then
                ReportConcussionInserted(releasedItem)
            else
                concussionHolsterRangeByItem[previousItemName] = nil
            end
        elseif IsUtilityShelfNonTabletItemName(previousItemName) then
            local wasInHolsterRange = utilityShelfHolsterRangeByItem[previousItemName] == true or
                SafeField(releasedItem, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
            utilityShelfHolsterRangeByItem[previousItemName] = nil
            if wasInHolsterRange then
                PlayUtilityShelfInput()
            end
        end
    end
end

function PlayerGrabStateTick(self,DeltaSeconds)
    local player = Unwrap(self)
    if player == nil then
        return
    end

    local playerName = SafeFullName(player)
    if string.find(playerName, "BP_PlayerPawn_VR_Menu_C", 1, true) ~= nil then
        return
    end

    local delta = tonumber(Unwrap(DeltaSeconds)) or 0.0
    local elapsed = (grabPollElapsedByPawn[playerName] or 0.0) + delta
    if elapsed < 0.05 then
        grabPollElapsedByPawn[playerName] = elapsed
        return
    end
    grabPollElapsedByPawn[playerName] = 0.0

    local interactorPawnComponent = SafeField(player, "InteractorPawnComponent")
    UpdatePlayerHandedness(player, interactorPawnComponent)
    if interactorPawnComponent == nil then
        return
    end

    UpdateGrabbedItemFromInteractor(SafeField(interactorPawnComponent, "LeftInteractor"))
    UpdateGrabbedItemFromInteractor(SafeField(interactorPawnComponent, "RightInteractor"))
end

local function IsDavisHeadWire(itemValue)
    return string.find(
        SafeFullName(itemValue),
        "BP_DavisHead_WireEnd_C",
        1,
        true
    ) ~= nil
end

local function IsDavisWireActivelyAttached(wireValue)
    local attachableObject = SafeField(wireValue, "SVRAttachableObject")
    if attachableObject == nil then
        return false
    end

    local ok, isAttached = pcall(function()
        return attachableObject:IsActivelyAttached()
    end)
    return ok and isAttached == true
end

local function DavisWireHasInteractor(wireValue)
    local interactable = SafeField(wireValue, "SVRInteractable")
    if interactable == nil then
        return false
    end

    local ok, hasInteractor = pcall(function()
        return interactable:HasAnyInteractors()
    end)
    return ok and hasInteractor == true
end

local function GetDavisWireHandSide(wireValue)
    local wireName = SafeFullName(wireValue)
    if grabbedItemByHand["Left"] == wireName then
        return "Left"
    end
    if grabbedItemByHand["Right"] == wireName then
        return "Right"
    end

    local activeInteractors = SafeField(wireValue, "SVRInteractable", "ActiveInteractors")
    if activeInteractors == nil then
        return nil
    end

    local ok, handSide = pcall(function()
        for _, interactor in ipairs(activeInteractors) do
            local side = GetInteractorHandSide(Unwrap(interactor))
            if side ~= nil then
                return side
            end
        end
        return nil
    end)
    return ok and handSide or nil
end

local function GetDavisWireNormalizedPosition(wireValue)
    local transformConstraint = SafeField(
        wireValue,
        "Posable_Slide",
        "TransformConstraint"
    )
    return SafeNumberField(transformConstraint, "CurrentNormalizedPosition")
end

function DavisHeadWireInsertionStarted(self,InWireIndex)
    local requestedWireIndex = tonumber(Unwrap(InWireIndex))
    local fallbackWire = nil
    local fallbackCount = 0

    for _, handSide in ipairs({"Left", "Right"}) do
        local wire = grabbedItemObjectByHand[handSide]
        if wire ~= nil and IsDavisHeadWire(wire) then
            fallbackWire = wire
            fallbackCount = fallbackCount + 1

            local wireIndex = SafeNumberField(wire, "WireIndex")
            if requestedWireIndex == nil or wireIndex == requestedWireIndex then
                local position = GetDavisWireNormalizedPosition(wire)
                if position ~= nil then
                    davisWirePenetrationPositionByItem[SafeFullName(wire)] = position
                    return
                end
            end
        end
    end

    if fallbackCount == 1 then
        local position = GetDavisWireNormalizedPosition(fallbackWire)
        if position ~= nil then
            davisWirePenetrationPositionByItem[SafeFullName(fallbackWire)] = position
        end
    end
end

function DavisHeadWireInsertionTick(self,DeltaSeconds)
    local wire = Unwrap(self)
    if wire == nil then
        return
    end

    local wireName = SafeFullName(wire)
    local currentPosition = GetDavisWireNormalizedPosition(wire)
    if currentPosition == nil then
        return
    end

    local previousPosition = davisWireNormalizedPositionByItem[wireName]
    davisWireNormalizedPositionByItem[wireName] = currentPosition
    if previousPosition == nil then
        return
    end

    local penetrationPosition = davisWirePenetrationPositionByItem[wireName]
    if penetrationPosition == nil or currentPosition + 0.0001 < penetrationPosition then
        return
    end
    if currentPosition <= previousPosition + 0.0001 or
        not IsDavisWireActivelyAttached(wire) or
        not DavisWireHasInteractor(wire) then
        return
    end

    local handSide = GetDavisWireHandSide(wire)
    if handSide ~= "Left" and handSide ~= "Right" then
        return
    end

    local delta = tonumber(Unwrap(DeltaSeconds)) or 0.0
    local elapsed = (davisWireInsertionElapsedByItem[wireName] or
        davisWireInsertionTickInterval) + delta
    if elapsed < davisWireInsertionTickInterval then
        davisWireInsertionElapsedByItem[wireName] = elapsed
        return
    end
    davisWireInsertionElapsedByItem[wireName] = 0.0

    local effectName = handSide .. "HandDavisHeadWireInsertion"
    PlayEffect(effectName)
end

function PlayerDamage(self, DamageResult)
    if IsDeadPlayerPawn(self) then
        return
    end
    local damageAngle = CalculateDamageAngle(self, DamageResult)
    if damageAngle ~= nil then
        PlayAngle("DefaultDamage", damageAngle, 0)
    else
        PlayEffect("NoDirectionDamage")
    end
end

function PlayerPhysicalCrouchChanged(self, bIsCrouching)
    PlayEffect("Crouch")
end

function PlayerJump(self)
    PlayEffect("Jump")
end

function ShotgunShellInserted(self)
    PlayEffect("LeftHandInteract")
    PlayEffect("RightHandInteract")
end

function PulseRifleSlide(self, DeadZoneSide)
    PlayEffect("LeftHandInteract")
    PlayEffect("RightHandInteract")
end

function RevolverRoundInserted(self)
    PlayEffect("LeftHandInteract")
    PlayEffect("RightHandInteract")
end

function GearActivateStart(self, ActivationMode)
    local gearComponent = Unwrap(self)
    local gear = gearComponent
    local ownerOk, owner = pcall(function()
        return gearComponent:GetOwner()
    end)
    if ownerOk and owner ~= nil then
        gear = Unwrap(owner)
    end

    local handSide = GetGearHandSide(gear)
    if handSide ~= "Left" and handSide ~= "Right" then
        local gearName = SafeFullName(gear)
        for _, side in ipairs({"Left", "Right"}) do
            if grabbedItemByHand[side] == gearName or grabbedItemObjectByHand[side] == gear then
                handSide = side
                break
            end
        end
    end

    if handSide == "Left" or handSide == "Right" then
        RememberItemHandSide(gear, handSide)
        local effectName = handSide .. "HandInteract"
        PlayEffect(effectName)
    end
end

function GearActivateStop(self)
    PlayEffect("GearActivateStop")
end

function MotionTrackerPulse(self, Source)
    if grabbedItemByHand["Left"] == self:get():GetFullName() then
        PlayEffect("LeftHandMotionTrackerPulse")
    end
    if grabbedItemByHand["Right"] == self:get():GetFullName() then
        PlayEffect("RightHandMotionTrackerPulse")
    end
end


function FacehuggerHitFace(self)
    PlayEffect("FacehuggerHitFace")
end

local function LogWeaponInteractorEvent(eventSuffix, userModeValue, handValue)
	local userMode = Unwrap(userModeValue)
	local hand = Unwrap(handValue)
	local handSide = GetInteractorHandSide(hand) or "Unknown"
	local item = ResolveEquippableActor(userMode)
	RecordKnownHeldItem(handSide, eventSuffix, item)
	PlayEffect(handSide .. "Hand" .. eventSuffix)
end

function WeaponAddActiveInteractor(self,InteractionHand)
	ReportWeaponRemovedFromSlot(self, InteractionHand)
	LogWeaponInteractorEvent("GrabbedItem", self, InteractionHand)
end

function WeaponRemoveActiveInteractor(self,InteractionHand)
	LogWeaponInteractorEvent("ReleasedItem", self, InteractionHand)
end

function PowerToolFinishedEquipping(self)
    ReportGearGrabbed(self, false)
end

function PowerToolStartedUnequipping(self)
    ReportGearUnequipped(self, false)
end

function MotionTrackerStartedEquipping(self)
    ReportGearGrabbed(self, true)
end

function MotionTrackerFinishedUnequipping(self)
    ReportGearUnequipped(self, true)
end

function ConcussionStartedEquipping(self)
    ReportConcussionRemoved(self)
end

function ConcussionStartedUnequipping(self)
    local item = Unwrap(self)
    local itemName = SafeFullName(item)
    local isInHolsterRange = concussionHolsterRangeByItem[itemName] == true or
        SafeField(item, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
    if isInHolsterRange then
        ReportConcussionInserted(item)
    end
end

local function PlayPhysicalItemHandEffect(eventSuffix, itemValue, handValue)
	local item = Unwrap(itemValue)
	local hand = Unwrap(handValue)
	local handSide = GetInteractorHandSide(hand) or "Unknown"
	RecordKnownHeldItem(handSide, eventSuffix, item)
	PlayEffect(handSide .. "Hand" .. eventSuffix)
end

function PhysicalItemGrabbed(self,InteractionHand)
	if IsAmmoItem(SafeFullName(self)) then
		return
	end
	PlayPhysicalItemHandEffect("GrabbedItem", self, InteractionHand)
end

function PhysicalItemReleased(self,InteractionHand)
	if IsAmmoItem(SafeFullName(self)) then
		return
	end
	PlayPhysicalItemHandEffect("ReleasedItem", self, InteractionHand)
end

function DynamicPropGrabbed(self,InteractionArgs)
	local args = Unwrap(InteractionArgs)
	local hand = SafeField(args, "Interactor")
	PlayPhysicalItemHandEffect("GrabbedItem", self, hand)
end

function BlueprintAttachmentCompleted(self)
	local item = Unwrap(self)
	local slot = SafeField(item, "AttachableObjectComponent", "CurrentAttachmentPoint")
	local effectName = GetSlotEffectName(item, slot, true)
	PlaySlotEffect(effectName)
end

function BlueprintAttachmentStopped(self,Attachment)
	local item = Unwrap(self)
	local effectName = GetSlotEffectName(item, Attachment, false)
	PlaySlotEffect(effectName)
end

function BlueprintSetHolstered(self,bInIsHolstered)
	UpdateHolsteredItemState(self, bInIsHolstered)
end

function MedInjectorHolsterRangeChanged(self)
	local item = Unwrap(self)
	SetMedInjectorHolsterRange(
		item,
		SafeField(item, "HolsterDetectionStateComponent", "bIsInHolsterRange") == true
	)
end

function BlueprintHolsterBegin(self)
	ReportMedInjectorInserted(self)
end

function AmmoMagazineGrabStarted(self)
	ammoGrabAbilityPending = true
	local effectName = GetMirroredSlotName("LeftHip") .. "SlotOutputItem"
	PlaySlotEffect(effectName)
end

function AmmoMagazineGrabbedPost(self)
	local ability = Unwrap(self)
	local item = SafeField(ability, "SpawnedAmmoItem")
	if item == nil then
		item = SafeField(ability, "SpawnedMagazine")
	end
	item = Unwrap(item)
	if item == nil or not IsAmmoItem(SafeFullName(item)) then
		return
	end

	local itemName = SafeFullName(item)
	ammoSlotStates[itemName] = false
	ammoGrabAbilityPending = false
end

function AmmoMagazineCompleteInsertion(self)
	local userMode = Unwrap(self)
	if userMode == nil then
		return
	end

	local item = nil
	local ok, result = pcall(function()
		return userMode:GetOwnerAmmoItem()
	end)
	if ok then
		item = Unwrap(result)
	end
	if item == nil then
		item = Unwrap(SafeField(userMode, "OwnerAmmoItem"))
	end

	ReportAmmoInserted(item)
end

function AmmoMagazineCollectedNative(self,InInteractorHand)
	local userMode = Unwrap(self)
	if userMode == nil then
		return
	end

	local item = nil
	local ok, result = pcall(function()
		return userMode:GetOwnerAmmoItem()
	end)
	if ok then
		item = Unwrap(result)
	end

	ReportAmmoInserted(item)
end

function AmmoPickupCollected(self,InCollectingPawn)
	local pickup = Unwrap(self)
	if pickup == nil then
		return
	end

	local pickupName = SafeFullName(pickup)
	if string.find(pickupName, "BP_Pickup_Ammo", 1, true) == nil then
		return
	end
	if collectedAmmoPickupStates[pickupName] == true then
		return
	end
	collectedAmmoPickupStates[pickupName] = true

	local hipSlot = GetMirroredSlotName("LeftHip")
	local effectName = hipSlot .. "SlotInputItem"
	PlaySlotEffect(effectName)
end

function AmmoPickupComponentCollected(self,InPlayer)
	local component = Unwrap(self)
	if component == nil then
		return
	end

	local pickup = nil
	local ok, result = pcall(function()
		return component:GetOwner()
	end)
	if ok then
		pickup = Unwrap(result)
	end
	if pickup == nil then
		return
	end
	AmmoPickupCollected(pickup, InPlayer)
end

function EquipmentTakenFromSlot(self)
	local ability = Unwrap(self)
	local equippable = SafeField(ability, "Equippable")
	local effectName = GetSlotEffectName(equippable or ability, nil, false)
	PlaySlotEffect(effectName)
end

function EquipmentPutIntoSlot(self)
	local ability = Unwrap(self)
	local equippable = SafeField(ability, "Equippable")
	local effectName = GetSlotEffectName(equippable or ability, nil, true)
	PlaySlotEffect(effectName)
end

function UtilityShelfOpenedLeft(self)
	activeUtilityShelfSide = "Left"
end

function UtilityShelfOpenedRight(self)
	activeUtilityShelfSide = "Right"
end

function ItemShelfGrabbed(self,InHandSide)
	local slot = Unwrap(self)
	local handSide = GetHandSideFromEnum(InHandSide)
	local item = SafeField(slot, "GrabbedEquippable")
	if item == nil then
		local ok, result = pcall(function()
			return slot:GetEquippableDataAsset()
		end)
		if ok then
			item = result
		end
	end
	RememberItemHandSide(item, handSide)
	local effectName = GetSlotEffectName(item, slot, false)
	PlaySlotEffect(effectName)
end

function BlueprintHolsterComplete(self)
	local item = Unwrap(self)
	local handSide = GetGearHandSide(item)
	RememberItemHandSide(item, handSide)
	SetWeaponInSlot(item, true)
	local effectName = GetSlotEffectName(item, nil, true)
	PlaySlotEffect(effectName)
end

function RevolverHolsterComplete(self)
	local animInstance = Unwrap(self)
	local weapon = SafeField(animInstance, "OwnerEquippable")
	local handSide = GetGearHandSide(weapon or animInstance)
	RememberItemHandSide(weapon or animInstance, handSide)
	SetWeaponInSlot(weapon or animInstance, true)
	local effectName = GetSlotEffectName(weapon or animInstance, nil, true)
	PlaySlotEffect(effectName)
end

function StartHolsterTransitionForHand(self,InHandInterface)
	local transition = Unwrap(self)
	local hand = Unwrap(InHandInterface)
	local owner = transition
	local ownerOk, result = pcall(function()
		return transition:GetOwner()
	end)
	if ownerOk and result ~= nil then
		owner = result
	end
	local handSide = GetInteractorHandSide(hand) or "Unknown"
	RememberItemHandSide(owner, handSide)
	if IsAmmoItem(SafeFullName(owner)) then
		ReportAmmoInserted(owner)
		return
	end
	if IsMedInjector(SafeFullName(owner)) then
		ReportMedInjectorInserted(owner)
		return
	end
	if IsConcussionGrenade(SafeFullName(owner)) then
		ReportConcussionInserted(owner)
		return
	end

	local effectName = GetSlotEffectName(owner, nil, true)
	PlaySlotEffect(effectName)
end

function OnGrabbed(self,InHandSide)
	local slot = Unwrap(self)
	local handSide = GetHandSideFromEnum(InHandSide) or Unwrap(InHandSide)
	local item = SafeField(slot, "GrabbedEquippable")
	if item == nil then
		local ok, result = pcall(function()
			return slot:GetEquippableDataAsset()
		end)
		if ok then
			item = result
		end
	end
	RememberItemHandSide(item, handSide)
	local effectName = GetSlotEffectName(item, slot, false)
	PlaySlotEffect(effectName)
end

function SetIsHolstered(self,bInIsHolstered)
	UpdateHolsteredItemState(self, bInIsHolstered)
end

function ReceiveSetIsHolstered(self,bInIsHolstered)
	UpdateHolsteredItemState(self, bInIsHolstered)
end

function BndEvt__BP_Weapon_FS_GunEventsComponent_K2Node_ComponentBoundEvent_0_SVRFireDynamicSignature__DelegateSignature(self)
    if string.find(self:get():GetFullName(),"Rifle") then
        if grabbedItemByHand["Left"] == self:get():GetFullName() then
            PlayEffect("LeftHandRifleShoot")
        end
        if grabbedItemByHand["Right"] == self:get():GetFullName() then
            PlayEffect("RightHandRifleShoot")
        end
    elseif string.find(self:get():GetFullName(),"Shotgun") then
        if grabbedItemByHand["Left"] == self:get():GetFullName() then
            PlayEffect("LeftHandShotgunShoot")
        end
        if grabbedItemByHand["Right"] == self:get():GetFullName() then
            PlayEffect("RightHandShotgunShoot")
        end
    elseif string.find(self:get():GetFullName(),"PlasmaTorch") then
        if grabbedItemByHand["Left"] == self:get():GetFullName() then
            PlayEffect("LeftHandPlasmaTorchShoot")
        end
        if grabbedItemByHand["Right"] == self:get():GetFullName() then
            PlayEffect("RightHandPlasmaTorchShoot")
        end
    else
        if grabbedItemByHand["Left"] == self:get():GetFullName() then
            PlayEffect("LeftHandPistolShoot")
        end
        if grabbedItemByHand["Right"] == self:get():GetFullName() then
            PlayEffect("RightHandPistolShoot")
        end
    end
end

function BndEvt__BP_PlayerPawn_VR_DamageableComponent_K2Node_ComponentBoundEvent_0_HealDynamicSignature__DelegateSignature(self,HealAmount)
	if IsDeadPlayerPawn(self) then
		return
	end
	PlayEffect("Healing")
end

function BndEvt__BP_PlayerPawn_FS_DamageableComponent_K2Node_ComponentBoundEvent_0_DeathDynamicSignature__DelegateSignature(self,DamageResult)
	deadPlayerPawn = Unwrap(self)
	PlayEffect("PlayerDeath")
end

truegear.init("1850050", "Alien: Rogue Incursion VR")
truegear.seek_by_uuid("DefaultDamage")

local function CheckPlayerSpawned()
	local function InitializeWeaponSlotStates()
		local ok, userModes = pcall(FindAllOf, "BP_UserMode_Weapon_VR_C")
		if ok and userModes ~= nil then
			for _, userMode in ipairs(userModes) do
				if SafeField(userMode, "bIsHolstered") == true then
					SetWeaponInSlot(userMode, true)
				end
			end
		end
	end

	local function InstallAvailableHooks()
		local ran, allHooksRegistered = pcall(RegisterHooks)
		if not ran then
			resetHook = true
			return
		end

		resetHook = not allHooksRegistered

		pcall(InitializeWeaponSlotStates)
	end

	InstallAvailableHooks()
	pcall(RegisterHook,
		"/Script/Engine.PlayerController:ClientRestart",
		function()
			if resetHook then
				InstallAvailableHooks()
			end
		end
	)
end

CheckPlayerSpawned()
