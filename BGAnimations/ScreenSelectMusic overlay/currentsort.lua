local alphaInactive = 0.7

local frameWidth = 280
local frameHeight = 20
local frameX = SCREEN_WIDTH-10
local frameY = 10

local searchstring = ""
local lastsearchstring = ""
local englishes = {"a", "b", "c", "d", "e","f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",";"}
local active = false
local top
local wheel
local song

local sortTable = {
	SortOrder_Preferred 			= 'Preferred',
	SortOrder_Group 				= 'Group',
	SortOrder_Title 				= 'Title',
	SortOrder_BPM 					= 'BPM',
	SortOrder_Popularity 			= 'Popular',
	SortOrder_TopGrades 			= 'Grade',
	SortOrder_Artist 				= 'Artist',
	SortOrder_Genre 				= 'Genre',
	SortOrder_BeginnerMeter 		= 'Beginner Meter',
	SortOrder_EasyMeter 			= 'Easy Meter',
	SortOrder_MediumMeter 			= 'Normal Meter',
	SortOrder_HardMeter 			= 'Hard Meter',
	SortOrder_ChallengeMeter 		= 'Insane Meter',
	SortOrder_DoubleEasyMeter 		= 'Double Easy Meter',
	SortOrder_DoubleMediumMeter 	= 'Double Normal Meter',
	SortOrder_DoubleHardMeter 		= 'Double Hard Meter',
	SortOrder_DoubleChallengeMeter 	= 'Double Insane Meter',
	SortOrder_ModeMenu 				= 'Mode Menu',
	SortOrder_AllCourses 			= 'All Courses',
	SortOrder_Nonstop 				= 'Nonstop',
	SortOrder_Oni 					= 'Oni',
	SortOrder_Endless 				= 'Endless',
	SortOrder_Length 				= 'Song Length',
	SortOrder_Roulette 				= 'Roulette',
	SortOrder_Recent 				= 'Recently Played',
	SortOrder_Favorites				= 'Favorites',
}

local function searchInput(event)
	if event.type == "InputEventType_FirstPress" and (event.DeviceInput.button == "DeviceButton_left mouse button" or event.DeviceInput.button == "DeviceButton_right mouse button") then
		MESSAGEMAN:Broadcast("EndSearch")
	end
	if event.type ~= "InputEventType_Release" and active then
		local CtrlPressed = INPUTFILTER:IsBeingPressed("left ctrl") or INPUTFILTER:IsBeingPressed("right ctrl")
		if event.button == "Back" then
			searchstring = ""
			wheel:SongSearch(searchstring)
			MESSAGEMAN:Broadcast("EndSearch")

		elseif event.button == "Start" then
			MESSAGEMAN:Broadcast("EndSearch")

		elseif event.button == "MenuLeft" then
			wheel:Move(-1)
			wheel:Move(0)
		elseif event.button == "MenuRight" then
			wheel:Move(1)
			wheel:Move(0)
		elseif event.DeviceInput.button == "DeviceButton_space" then					-- add space to the string
			searchstring = searchstring.." "

		elseif event.DeviceInput.button == "DeviceButton_backspace" then
			if searchstring == "" then
				MESSAGEMAN:Broadcast("EndSearch")
			else
				searchstring = searchstring:sub(1, -2)
			end					-- remove the last element of the string

		elseif event.DeviceInput.button == "DeviceButton_delete"  then
			searchstring = ""

		elseif event.DeviceInput.button == "DeviceButton_="  then
			searchstring = searchstring.."="

		elseif event.DeviceInput.button == "DeviceButton_v" and CtrlPressed then
			searchstring = searchstring .. HOOKS:GetClipboard()

		else
			if CtrlPressed then
				return false
			end
			if event.char and event.char:match('[%%%+%-%!%@%#%$%^%&%*%(%)%=%_%.%,%:%;%\'%"%>%<%?%/%~%|%w]') and event.char ~= "" then
				searchstring = searchstring .. event.char
			end
		end
		if lastsearchstring ~= searchstring then
			wheel:SongSearch(searchstring)
			lastsearchstring = searchstring
			GHETTOGAMESTATE:setMusicSearch(searchstring)
		end
	end
end

local t = Def.ActorFrame{
	InitCommand = function(self)
		self:xy(frameX,frameY)
		SCREENMAN:set_input_redirected(PLAYER_1, false)
	end,
	OnCommand = function(self)
		top = SCREENMAN:GetTopScreen()
		GHETTOGAMESTATE:setSSM(top)
		wheel = top:GetMusicWheel()
		SCREENMAN:GetTopScreen():AddInputCallback(searchInput)
		self:y(-frameHeight/2)
		self:smooth(0.5)
		self:y(frameY)
		GHETTOGAMESTATE:checkForReplayToPlay()
	end,
	GhettoReplayStartMessageCommand = function(self, params)
		top:PlayReplay(params.score)
	end,
	OffCommand = function(self)
		self:smooth(0.5)
		self:y(-frameHeight/2)
	end,
	StartSearchMessageCommand = function(self)
		active = true
		if searchstring == "" then
			self:GetChild("SortBar"):settext("Type to Search..")
			self:GetChild("SortBar"):diffusealpha(alphaInactive)
		else
			self:GetChild("SortBar"):diffusealpha(1)
		end
		SCREENMAN:set_input_redirected(PLAYER_1, true)
	end,
	EndSearchMessageCommand = function(self)
		SCREENMAN:set_input_redirected(PLAYER_1, false)
		active = false
		if searchstring == "" then
			self:GetChild("SortBar"):playcommand("SetSortOrder")
		else
			self:GetChild("SortBar"):diffusealpha(alphaInactive)
		end
	end,

	MoveMusicWheelToSongMessageCommand = function(self, param)
		if #searchstring > 0 then
			searchstring = ""
			wheel:SongSearch(searchstring)
		end
		wheel:SelectSong(param.song)
		-- The Message sent from ChangeMusic() in the musicwheel goes to the wrong screen (ScreenPlayerProfiles). 
		-- So Send one manually to ScreenSelectMusic.
		top:PostScreenMessage('SM_SongChanged', 0)
	end
}

t[#t+1] = quadButton(4) .. {
	Name="CurrentSort",
	InitCommand = function(self)
		self:halign(1)
		self:zoomto(frameWidth,frameHeight)
		self:diffuse(getMainColor('highlight')):diffusealpha(0.8)
	end,
	TopPressedCommand = function(self)
		MESSAGEMAN:Broadcast("StartSearch")
	end
}

t[#t+1] = LoadFont("Common Normal") .. {
	Name="SortBar",
	InitCommand = function (self)
		self:x(5-frameWidth)
		self:halign(0)
		self:zoom(0.45)
		self:diffuse(color(colorConfig:get_data().main.headerFrameText))
		self:maxwidth((frameWidth-40)/0.45)
	end,
	SortOrderChangedMessageCommand = function(self)
		self:queuecommand("SetSortOrder")
	end,
	SetSortOrderCommand = function(self)
		if searchstring == "" then
			if not active then
				local sort = GAMESTATE:GetSortOrder()
				local song = GAMESTATE:GetCurrentSong()
				if sort == nil then
					self:settext("Sort: ")
				elseif sort == "SortOrder_Group" and song ~= nil then
					self:settext(song:GetGroupName())
				else
					self:settext("Sort: "..sortTable[sort])
				end
				self:diffusealpha(1)
			else
				self:settext("Type to Search..")
				self:diffusealpha(alphaInactive)
			end
		else
			if active then
				self:settext(searchstring)
				self:diffusealpha(1)
			else
				self:diffusealpha(alphaInactive)
			end
		end
	end,
	SortOrderChangedMessageCommand = function(self)
		self:queuecommand("SetSortOrder")
	end,
	CurrentSongChangedMessageCommand = function(self)
		self:queuecommand("SetSortOrder")
	end
}

t[#t+1] = LoadFont("Common Normal") .. {
	InitCommand=function(self)
		self:x(-5):halign(1):zoom(0.3):maxwidth(40/0.45)
	end,
	BeginCommand=function(self)
		self:queuecommand("Set")
	end,
	SetCommand=function(self)
		self:diffuse(color(colorConfig:get_data().main.headerFrameText))
		local top = SCREENMAN:GetTopScreen()
		if top:GetName() == "ScreenSelectMusic" or top:GetName() == "ScreenNetSelectMusic" then
			local wheel = top:GetMusicWheel()
			self:settextf("%d/%d",wheel:GetCurrentIndex()+1,wheel:GetNumItems())
		end
	end,
	SortOrderChangedMessageCommand = function(self)
		self:queuecommand("Set")
	end,
	CurrentSongChangedMessageCommand = function(self)
		self:queuecommand("Set")
	end
}

return t