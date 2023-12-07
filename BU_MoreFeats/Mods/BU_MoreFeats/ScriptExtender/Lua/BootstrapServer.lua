-- You must gather your Progressions before venturing forth
local _progressionData = {}
Ext.Events.SessionLoaded:Subscribe(function()
	for _, uuid in ipairs(Ext.StaticData.GetAll("Progression")) do
		local progression = Ext.StaticData.Get(uuid, "Progression")
	end
end)