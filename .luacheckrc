-- luacheck configuration for Toolbox.
--
-- The game runs MoonSharp (Lua 5.2 semantics), so the standard library is lua52.
-- Every global below is taken from the SotA Lua API reference for API version 14
-- (https://catnipgames.net/lua/reference.html). Anything not listed is reported,
-- so a misspelled API name shows up as "accessing undefined variable".

std = "lua52"
max_line_length = 120
exclude_files = { "dist/" }   -- build output; the sources in toolbox/ are checked
-- 311 "value assigned to a local is unused": every local starts with an explicit `= nil`
-- (in game a bare `local x` seemed to keep an old value; tools/build.py enforces it), and those
-- defaults are often overwritten before use on purpose.
ignore = { "311" }

-- Functions and values the host provides (read-only for add-ons).
local api_functions = {
  "ConsoleLog",
  "ShroudButton", "ShroudButtonRepeat", "ShroudClearBeacon", "ShroudConsoleLog", "ShroudCurrentDeck",
  "ShroudDeckList", "ShroudDeleteInkVariable", "ShroudDeleteSavedVar", "ShroudDestroyObject",
  "ShroudDrawTexture", "ShroudDrawTextureTooltip", "ShroudEmoteList", "ShroudFlushSavedVars", "ShroudForceGC",
  "ShroudGetAchievements", "ShroudGetActiveTitle", "ShroudGetAttenuationAdventurerStatus",
  "ShroudGetAttenuationProducerStatus", "ShroudGetBeacon", "ShroudGetBuffCount", "ShroudGetBuffDescription",
  "ShroudGetBuffIcon", "ShroudGetBuffName", "ShroudGetBuffTimeRemaining", "ShroudGetBuffTooltip",
  "ShroudGetCharacterSheetPosition", "ShroudGetClientInfo", "ShroudGetCompassMarkers",
  "ShroudGetCurrentDungeonName", "ShroudGetCurrentDungeonOwner", "ShroudGetCurrentSceneIsPOT",
  "ShroudGetCurrentSceneIsPVP", "ShroudGetCurrentSceneMaxPlayerCount", "ShroudGetCurrentSceneName",
  "ShroudGetCurrentSceneNameRaw", "ShroudGetCurrentSceneOrientation", "ShroudGetDeckCardList",
  "ShroudGetDescriptionUnderMouse", "ShroudGetEquipmentIcons", "ShroudGetEquipmentItems", "ShroudGetEquipments",
  "ShroudGetFullScreen", "ShroudGetGameTime", "ShroudGetIdUnderMouse", "ShroudGetInputText", "ShroudGetInventory",
  "ShroudGetInventoryIcons", "ShroudGetInventoryItems", "ShroudGetKeyDown", "ShroudGetKindUnderMouse",
  "ShroudGetKnownRecipes", "ShroudGetLevelProgress", "ShroudGetNameUnderMouse", "ShroudGetNotifications",
  "ShroudGetOnKeyDown", "ShroudGetOnKeyUp", "ShroudGetParentID", "ShroudGetParentObjectKind",
  "ShroudGetPartyMemberCount", "ShroudGetPartyMemberCountInScene", "ShroudGetPartyMemberCurrentFocus",
  "ShroudGetPartyMemberCurrentFocusInScene", "ShroudGetPartyMemberCurrentHealth",
  "ShroudGetPartyMemberCurrentHealthInScene", "ShroudGetPartyMemberMaxFocus", "ShroudGetPartyMemberMaxFocusInScene",
  "ShroudGetPartyMemberMaxHealth", "ShroudGetPartyMemberMaxHealthInScene", "ShroudGetPartyMemberName",
  "ShroudGetPartyMemberNamesInScene", "ShroudGetPetBuff", "ShroudGetPetInfo", "ShroudGetPlayerBuff",
  "ShroudGetPlayerCombatMode", "ShroudGetPlayerCompassHeading", "ShroudGetPlayerName", "ShroudGetPlayerOrientation",
  "ShroudGetPooledAdventurerExperience", "ShroudGetPooledProducerExperience", "ShroudGetPosition",
  "ShroudGetResurrectTimeRemaining", "ShroudGetSavedVar", "ShroudGetSceneCap", "ShroudGetSceneInfo",
  "ShroudGetScreenX", "ShroudGetScreenY", "ShroudGetSkill", "ShroudGetSkillIcon", "ShroudGetSkills",
  "ShroudGetSocialSummary", "ShroudGetSpecializations", "ShroudGetStatCount", "ShroudGetStatDescriptionByNumber",
  "ShroudGetStatNameByNumber", "ShroudGetStatValueByName", "ShroudGetStatValueByNumber", "ShroudGetTargetBuff",
  "ShroudGetTargetBuffCount", "ShroudGetTargetBuffDescription", "ShroudGetTargetBuffIcon",
  "ShroudGetTargetBuffName", "ShroudGetTargetBuffTimeRemaining", "ShroudGetTargetBuffTooltip",
  "ShroudGetTargetCurrentFocus", "ShroudGetTargetCurrentHealth", "ShroudGetTargetId", "ShroudGetTargetMaxFocus",
  "ShroudGetTargetMaxHealth", "ShroudGetTargetName", "ShroudGetTargetStatValueByName",
  "ShroudGetTargetStatValueByNumber", "ShroudGetTasks", "ShroudGetTextureSize", "ShroudGetTitles",
  "ShroudGetToggle", "ShroudGetTotalAdventurerExperience", "ShroudGetTotalProducerExperience", "ShroudGetWeather",
  "ShroudGUILabel", "ShroudGUITooltip", "ShroudHasInkVariable", "ShroudHasTarget", "ShroudHideLuaUI",
  "ShroudHideObject", "ShroudHttpGet", "ShroudIsChannelPlaying", "ShroudIsCharacterSheetActive",
  "ShroudIsPlayerDead", "ShroudIsStatVisible", "ShroudIsTargetDead", "ShroudIsTargetHealthHidden",
  "ShroudIsUIActive", "ShroudIsWindowOpen", "ShroudListPeriodics", "ShroudListSound", "ShroudListSoundReset",
  "ShroudListStockWindows", "ShroudLoadInkVariable", "ShroudLoadSound", "ShroudLoadTexture", "ShroudMinMaxSize",
  "ShroudModifyImage", "ShroudModifyText", "ShroudPlayEmote", "ShroudPlayEmoteText", "ShroudPlaySound",
  "ShroudPlaySoundChannel", "ShroudRaycastObject", "ShroudRegisterPeriodic", "ShroudRemovePeriodic",
  "ShroudRotateObject", "ShroudSaveInkVariable", "ShroudSceneMusic", "ShroudSetAnchorMax", "ShroudSetAnchorMin",
  "ShroudSetBeacon", "ShroudSetButtonColor", "ShroudSetButtonImage", "ShroudSetButtonParent",
  "ShroudSetButtonTransition", "ShroudSetClickListener", "ShroudSetColor", "ShroudSetDragguable",
  "ShroudSetFontSize", "ShroudSetImageParent", "ShroudSetInOutListener", "ShroudSetInputBackgroundColor",
  "ShroudSetInputCharacterLimit", "ShroudSetInputContentType", "ShroudSetInputReadonly", "ShroudSetInputText",
  "ShroudSetMask", "ShroudSetPanelParent", "ShroudSetParent", "ShroudSetPivot", "ShroudSetPlaceholderText",
  "ShroudSetPosition", "ShroudSetResizable", "ShroudSetSavedVar", "ShroudSetScale", "ShroudSetSize",
  "ShroudSetTextAlignment", "ShroudSetTextParent", "ShroudSetTextureClamp", "ShroudSetToggle",
  "ShroudSetToggleReadonly", "ShroudSetTransparency", "ShroudShowLuaUI", "ShroudShowObject", "ShroudStopFX",
  "ShroudStopSound", "ShroudStopUISound", "ShroudSwitchDeck", "ShroudToggleWindow", "ShroudUIButton",
  "ShroudUIImage", "ShroudUIInput", "ShroudUIPanel", "ShroudUIText", "ShroudUIToggle", "ShroudUnsetClickListener",
  "ShroudUnsetDragguable", "ShroudUnsetInOutListener", "ShroudUnsetMask", "ShroudUseLuaConsoleForPrint",
  "ShroudWorldToScreenPoint",
}

-- Per-frame values, set-once constants and registered enum/helper types.
local api_values = {
  "ShroudPlayerX", "ShroudPlayerY", "ShroudPlayerZ", "ShroudPlayerCurrentHealth", "ShroudPlayerCurrentFocus",
  "ShroudPlayerGold", "ShroudTime", "ShroudDeltaTime", "ShroudRealDeltaTime", "ShroudServerTime",
  "ShroudMouseX", "ShroudMouseY",
  "ShroudLuaApiVersion", "ShroudLuaPath", "ShroudDataPath", "InvalidStatResult",
  "UI", "ButtonMode", "Transition", "ContentType", "AudioType", "TextAnchor", "LuaVector2", "LuaVector3",
}

-- Callbacks an add-on may define. Listed as writable globals.
local api_callbacks = {
  "ShroudOnAchievementsChanged", "ShroudOnBuffsChanged", "ShroudOnCombatEvents", "ShroudOnCombatModeChanged",
  "ShroudOnConsoleInput", "ShroudOnDeathChanged", "ShroudOnDisableScript", "ShroudOnExperienceChanged",
  "ShroudOnExperienceGain", "ShroudOnGUI", "ShroudOnHttpResponse", "ShroudOnInputChange",
  "ShroudOnInventoryChanged", "ShroudOnItemsGained", "ShroudOnLogOut", "ShroudOnMouseClick", "ShroudOnMouseOut",
  "ShroudOnMouseOver", "ShroudOnNotificationsChanged", "ShroudOnPlayEmote", "ShroudOnPlayFX", "ShroudOnPlaySound",
  "ShroudOnRecipesChanged", "ShroudOnSceneLoaded", "ShroudOnSceneUnloaded", "ShroudOnSkillsChanged",
  "ShroudOnSocialChanged", "ShroudOnStart", "ShroudOnTargetChanged", "ShroudOnTasksChanged",
  "ShroudOnTitlesChanged", "ShroudOnToggleChange", "ShroudOnUpdate",
}

-- The early global `Shroud` (read-only userdata) and its documented fields.
local shroud_global = {
  fields = {
    Command = {}, RemoveCommand = {},
    Keybind = {}, GetKeybind = {}, RemoveKeybind = {},
    UI = {
      fields = {
        Window = {}, HudFrame = {}, Row = {}, Column = {}, Scroll = {}, Grid = {},
        Label = {}, Button = {}, IconButton = {}, Image = {}, Bar = {},
        TextField = {}, Toggle = {}, Slider = {}, Dropdown = {},
      },
    },
  },
}

local function concat(...)
  local out = {}
  for _, list in ipairs({ ... }) do
    for _, name in ipairs(list) do out[#out + 1] = name end
  end
  return out
end

read_globals = concat(api_functions, api_values)
read_globals.Shroud = shroud_global

-- The add-on's own namespace plus the callbacks it defines.
globals = concat({ "Toolbox", "ToolboxCopies" }, api_callbacks)

-- Tests stub the whole API, so they may assign to any of it.
files["tests/"] = {
  std = "+lua51",   -- the runner also supports LuaJIT (setfenv-free, but allow the 5.1 names)
  globals = concat({ "Toolbox", "ToolboxCopies", "Shroud" }, api_functions, api_values, api_callbacks),
  ignore = { "122" },   -- the harness replaces os.date to control the local date
}
