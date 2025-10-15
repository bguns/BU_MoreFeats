local _everyXLevels = 4
local _perCharacterLevel = true
local _debugOutput = false

local _classDescriptionData = {}
local _multiClassProgressions = {}

local _lastSelectedCharacterUuid = nil
local _lastSelectedCharacterLevel = nil
local _tickFunctionHandlerId = nil

local function UpdateProgressionsForFeatPerCharacterLevels(characterUuid)
	local character = Ext.Entity.Get(characterUuid)
	local currentLevel = character.EocLevel.Level
	local nextLevel = currentLevel+1

	local hasFeat = nextLevel % _everyXLevels == 0
	if not hasFeat and nextLevel == 2 and Mods.BU_MoreFeats_FeatLvl2 and Mods.BU_MoreFeats_FeatLvl2.Enabled then
		hasFeat = true
	end

	local currentClasses = character.Classes.Classes
	for _, class in ipairs(currentClasses) do
		local progression = _classDescriptionData[class.ClassUUID].progressions[class.Level+1]
		if _debugOutput then
			_PW("Setting allow improvement to " .. tostring(hasFeat) .. " for class " .. progression.name .. " level " .. tostring(nextLevel) .. " (classUuid = " .. class.ClassUUID .. "; progressionUuid = " .. progression.uuid .. ")")
		end
		Ext.StaticData.Get(progression.uuid, "Progression").AllowImprovement = hasFeat
	end
	for _, progression in ipairs(_multiClassProgressions) do
		if _debugOutput then
			_PW("Setting allow improvement to " .. tostring(hasFeat) .. " for multiclass progression for class " .. progression.name .. " (progressionUuid = " .. progression.uuid .. ")")
		end
		Ext.StaticData.Get(progression.uuid, "Progression").AllowImprovement = hasFeat
	end 
end

-- You must gather your Progressions before venturing forth
Ext.Events.SessionLoaded:Subscribe(function()
	-- sanity check - if we gain a feat every level it does not matter if it is per class or per character level
	-- and the former is much more simple to achieve
	if _everyXLevels == 1 then
		_perCharacterLevel = false
	end

	local isVanilla = _everyXLevels == 4 and not _perCharacterLevel

	local classProgressionTables = {}
	for _, uuid in ipairs(Ext.StaticData.GetAll("ClassDescription")) do
		local classDescriptionDatum = Ext.StaticData.Get(uuid, "ClassDescription")
		_classDescriptionData[uuid] = {
			name = classDescriptionDatum.Name,
			progressionTableUuid = classDescriptionDatum.ProgressionTableUUID,
			progressions = {}
		}
		classProgressionTables[classDescriptionDatum.ProgressionTableUUID] = uuid
	end

	local levelsValidation = {}
	local validationErrors = {}

	for _, uuid in ipairs(Ext.StaticData.GetAll("Progression")) do
		local progression = Ext.StaticData.Get(uuid, "Progression")
		if progression.ProgressionType == 0 and classProgressionTables[progression.TableUUID] then
			local name = progression.Name

			local level = progression.Level
			local isMulticlass = progression.IsMulticlass

			local progressionDatum = {
				uuid = uuid,
				name = name,
				isMulticlass = isMulticlass,
				originalAllowImprovement = progression.AllowImprovement
			}

			if isMulticlass then
				table.insert(_multiClassProgressions, progressionDatum)
			else		
				_classDescriptionData[classProgressionTables[progression.TableUUID]].progressions[level] = progressionDatum
			end

			if not isVanilla and not _perCharacterLevel and level > 1 then
				local hasFeat = level % _everyXLevels == 0
				progression.AllowImprovement = hasFeat
			end

			if not _perCharacterLevel and level == 2 and Mods.BU_MoreFeats_FeatLvl2 and Mods.BU_MoreFeats_FeatLvl2.Enabled then
				progression.AllowImprovement = true
			end

			if level == 1 and _everyXLevels == 1 and isMulticlass then
				progression.AllowImprovement = true
			end

			if not levelsValidation[name] then
				levelsValidation[name] = {}
			end
			if levelsValidation[name][level] 
				and (isMulticlass and levelsValidation[name][level]["isMulticlass"] 
					or not isMulticlass and levelsValidation[name][level]["nonMulticlass"]) then
				table.insert(validationErrors, string.format("  multiple progressions for class %s with IsMulticlass == %s", name, tostring(isMulticlass)))
			end
			if not levelsValidation[name][level] then
				levelsValidation[name][level] = {
					nonMulticlass = false,
					isMulticlass = false
				}
			end

			if isMulticlass then
				levelsValidation[name][level]["isMulticlass"] = true
			else
				levelsValidation[name][level]["nonMulticlass"] = true
			end
		end
	end

	-- Validation
	for name, levels in pairs(levelsValidation) do
		for i=1,12 do
			if not levels[i] or not levels[i]["nonMulticlass"] then
				table.insert(validationErrors, string.format("  no progression for class %s level %d", name, i))
			end
			if i == 1 and levels[i] and not levels[i]["isMulticlass"] then
				table.insert(validationErrors, string.format("  class %s has no level 1 progression with IsMulticlass == true", name, i))
			end
			if i > 1 and levels[i] and levels[i]["isMulticlass"] then
				table.insert(validationErrors, string.format("  progression for class %s level %d has IsMulticlass == true, but level > 1", name, i))
			end
		end
	end

	if _debugOutput and #validationErrors > 0 then
		_PW("[BU_MoreFeats] validation on progression entries resulted in warnings:")
		for _, warning in ipairs(validationErrors) do
			_PW(warning)
		end
	end

	if _perCharacterLevel then
		Ext.Events.GameStateChanged:Subscribe(function(e)
			if e.ToState == "Running" and not _tickFunctionHandlerId then
				_tickFunctionHandlerId = Ext.Events.Tick:Subscribe(function()
					local ok, selectedCharacter = pcall(GetHostCharacter)
					if ok then
						local currentLevel = Ext.Entity.Get(selectedCharacter).EocLevel.Level
						if selectedCharacter ~= _lastSelectedCharacterUuid or currentLevel ~= _lastSelectedCharacterLevel then
							_lastSelectedCharacterUuid = selectedCharacter
							_lastSelectedCharacterLevel = currentLevel
							if _debugOutput then
								_PW("Updating progressions for character " .. tostring(selectedCharacter) .. ", level " .. tostring(currentLevel))
							end
							UpdateProgressionsForFeatPerCharacterLevels(selectedCharacter)
						end
					end
				end)
			end
		end)
	end
end)