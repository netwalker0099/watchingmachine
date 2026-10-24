-- Watching Machine: Blizzard windows Frame Mover can move
-- The game's windows on TBC Anniversary (2.5.6), as facts: each window's
-- frame name, the load-on-demand Blizzard addon that creates it (nil: part
-- of the base UI), and its parts, the inner panels, tabs and pop-outs that
-- cover it, so a drag on any part moves the whole window. Compiled with
-- the help of BlizzMove's research; only the facts are kept, in Watching
-- Machine's own format.
--
-- A name with a dot ("A.B") is a child key of a named frame. Names this
-- client doesn't have are skipped, so a window that only some 2.5.x builds
-- have is harmless. Left out on purpose: GameMenuFrame (the Escape menu,
-- where taint once blocked Log Out) and the loot roll and widget bars that
-- move by themselves.

local _, WM = ...
WM.FrameMoverData = {
    -- Base UI
    { frame = "AddonList" },
    { frame = "ArenaFrame" },
    { frame = "ArenaRegistrarFrame" },
    { frame = "BankFrame" },
    { frame = "BattlefieldFrame" },
    { frame = "CharacterFrame", parts = { "PaperDollFrame", "PetPaperDollFrame", "ReputationFrame",
        "ReputationDetailFrame", "SkillFrame", "PVPFrame", "PVPFrameArena", "PVPFrameHonor", "PVPTeam1", "PVPTeam2",
        "PVPTeam3", "TokenFrame", "TokenFrameContainer", "TokenFramePopup" } },
    { frame = "ChatConfigFrame" },
    { frame = "DressUpFrame" },
    { frame = "FriendsFrame", parts = { "FriendsFrameFriendsScrollFrame", "FriendsFrameBattlenetFrame.BroadcastFrame",
        "GuildFrame", "GuildInfoFrame", "GuildInfoFrameScrollFrame", "GuildControlPopupFrame", "GuildEventLogFrame",
        "RaidInfoFrame" } },
    { frame = "GossipFrame" },
    { frame = "GuildRegistrarFrame" },
    { frame = "HelpFrame" },
    { frame = "ItemTextFrame" },
    { frame = "LootFrame" },
    { frame = "MailFrame", parts = { "MailFrameInset", "SendMailFrame", "OpenMailFrame", "OpenMailFrameInset",
        "OpenMailSender" } },
    { frame = "MerchantFrame" },
    { frame = "ModelPreviewFrame" },
    { frame = "PVPBannerFrame" },
    { frame = "PetStableFrame" },
    { frame = "PetitionFrame" },
    { frame = "QuestFrame" },
    { frame = "QuestLogFrame" },
    { frame = "ReadyCheckFrame" },
    { frame = "SettingsPanel" },
    { frame = "SpellBookFrame" },
    { frame = "TabardFrame" },
    { frame = "TaxiFrame" },
    { frame = "TradeFrame" },
    { frame = "TutorialFrame" },
    { frame = "WorldMapFrame", parts = { "WorldMapTitleButton" } },
    { frame = "WorldStateScoreFrame" },

    -- Load-on-demand Blizzard addons
    { addon = "Blizzard_AchievementUI", frame = "AchievementFrame", parts = { "AchievementFrameHeader",
        "AchievementFrameCategoriesContainer", "AchievementFrameAchievementsContainer" } },
    { addon = "Blizzard_AuctionHouseUI", frame = "AuctionHouseFrame" },
    { addon = "Blizzard_AuctionUI", frame = "AuctionFrame" },
    { addon = "Blizzard_BindingUI", frame = "KeyBindingFrame" },
    { addon = "Blizzard_Calendar", frame = "CalendarFrame", parts = { "CalendarCreateEventFrame",
        "CalendarViewEventFrame", "CalendarViewEventFrame.HeaderFrame", "CalendarViewHolidayFrame" } },
    { addon = "Blizzard_Channels", frame = "ChannelFrame" },
    { addon = "Blizzard_Communities", frame = "CommunitiesFrame", parts = { "CommunitiesFrame.GuildMemberDetailFrame",
        "CommunitiesFrame.NotificationSettingsDialog" } },
    { addon = "Blizzard_Communities", frame = "CommunitiesSettingsDialog" },
    { addon = "Blizzard_Communities", frame = "CommunitiesGuildLogFrame" },
    { addon = "Blizzard_Communities", frame = "CommunitiesGuildNewsFiltersFrame" },
    { addon = "Blizzard_Communities", frame = "CommunitiesGuildTextEditFrame" },
    { addon = "Blizzard_CraftUI", frame = "CraftFrame" },
    { addon = "Blizzard_GroupFinder_VanillaStyle", frame = "LFGParentFrame" },
    { addon = "Blizzard_GuildBankUI", frame = "GuildBankFrame" },
    { addon = "Blizzard_GuildControlUI", frame = "GuildControlUI" },
    { addon = "Blizzard_InspectUI", frame = "InspectFrame", parts = { "InspectPaperDollFrame", "InspectPVPFrame",
        "InspectPVPFrameArena", "InspectPVPFrameHonor", "InspectPVPTeam1", "InspectPVPTeam2", "InspectPVPTeam3",
        "InspectTalentFrame" } },
    { addon = "Blizzard_ItemSocketingUI", frame = "ItemSocketingFrame" },
    { addon = "Blizzard_MacroUI", frame = "MacroFrame" },
    { addon = "Blizzard_TalentUI", frame = "PlayerTalentFrame" },
    { addon = "Blizzard_TimeManager", frame = "TimeManagerFrame" },
    { addon = "Blizzard_TradeSkillUI", frame = "TradeSkillFrame" },
    { addon = "Blizzard_TrainerUI", frame = "ClassTrainerFrame" },
}

-- Names shown in Frame Mover's list (anything else shows its frame name)
WM.FrameMoverNames = {
    AddonList = "AddOns list", ArenaFrame = "Arena queue", ArenaRegistrarFrame = "Arena registrar",
    BankFrame = "Bank", BattlefieldFrame = "Battleground queue", CharacterFrame = "Character",
    ChatConfigFrame = "Chat settings", DressUpFrame = "Dressing room", FriendsFrame = "Social (friends, guild)",
    GossipFrame = "NPC chat", GuildRegistrarFrame = "Guild registrar", HelpFrame = "Help",
    ItemTextFrame = "Books and letters", LootFrame = "Loot", MailFrame = "Mailbox", MerchantFrame = "Vendor",
    ModelPreviewFrame = "Model preview", PVPBannerFrame = "Arena banner", PetStableFrame = "Stable",
    PetitionFrame = "Petition", QuestFrame = "Quest (NPC)", QuestLogFrame = "Quest log", ReadyCheckFrame = "Ready check",
    SettingsPanel = "Game settings", SpellBookFrame = "Spellbook", TabardFrame = "Tabard designer", TaxiFrame = "Flight map",
    TradeFrame = "Trade", TutorialFrame = "Tutorial", WorldMapFrame = "World map", WorldStateScoreFrame = "Battleground score",
    AchievementFrame = "Achievements", AuctionHouseFrame = "Auction house", AuctionFrame = "Auction house",
    KeyBindingFrame = "Key bindings", CalendarFrame = "Calendar", ChannelFrame = "Chat channels",
    CommunitiesFrame = "Communities", CommunitiesSettingsDialog = "Community settings",
    CommunitiesGuildLogFrame = "Guild log", CommunitiesGuildNewsFiltersFrame = "Guild news filters",
    CommunitiesGuildTextEditFrame = "Guild text", CraftFrame = "Crafting (enchanting)", LFGParentFrame = "Looking for group",
    GuildBankFrame = "Guild bank", GuildControlUI = "Guild ranks", InspectFrame = "Inspect",
    ItemSocketingFrame = "Gem sockets", MacroFrame = "Macros", PlayerTalentFrame = "Talents", TimeManagerFrame = "Clock",
    TradeSkillFrame = "Professions", ClassTrainerFrame = "Trainer",
}
