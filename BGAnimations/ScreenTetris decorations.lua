--[[
	GridActor handles the update and input callback registering.
	It also contains all the grid actors (Quads, or "Coloured rectangles")
	The config table has all the basic configurable game parameters
	The grid table contains a matrix of cells, used by gridActor quads to draw themselves
	A cell can either be nil (Empty) or have a block
	A block is a lua table which has a color
	the currentPiece variable is a table with a 1 character string (type), a
	a rotation (Number 0-3) and an offset (How many cells it has fallen) number
	inputCallback is the inputCallback function
]]


local piecesSprite
local piecesTexture
local piecesTextureProperties = {}

local pieceSprites
if config.pieces.texture then
	piecesSprite = Widg.Sprite {texture = "blockskin/" .. config.pieces.texture}
	piecesTextureProperties = {}
	pieceSprites = Def.ActorFrame {piecesSprite}
	piecesSprite.InitCommand = function(self)
		piecesTexture = self:GetTexture()
		self:visible(false)
		for i = 1, piecesTexture:GetNumFrames() do
			local left, top, right, bottom = piecesTexture:GetTextureCoordRect(i)
			piecesTextureProperties[#piecesTextureProperties + 1] = {Frame = i - 1}
		end
	end
end
-- Game globals
local currentSpeed = config.normalSpeed
local secondsSinceLastMovement = 0
local floorTicks = 0
local lastUpdateExecutionSeconds = nil
local grid = {}
local drawGrid = {}
setmetatable(drawGrid, {__index = grid})
local gridActor
local heldAlready = false

local pieceQueue = List.fromTable(shuffle(copyTable(pieceNames)))
local currentPiece = {name = "L", rotation = 0, offset = {x = 0, y = 0}}
local holdPiece = nil

--Tetris utility functions/tables, and game globals
function paintQuad(quad, block) -- If color is nil then its background
	local c = block and block.color or config.emptyColor
	local w = Color.White
	local b = Color.Black
	local shine = block and colorSum(c, w, 1 / 5, 4 / 5) or config.emptyColor
	local shadow = block and colorSum(c, b, 1 / 5, 4 / 5) or config.emptyColor
	if block and block.name then
		if piecesTexture then
			quad:zoomto(config.grid.blockWidth - 1, config.grid.blockHeight - 1)
			if not quad.orig then
				quad.orig = quad:GetTexture()
			end
			quad:SetTexture(piecesTexture)
			quad:SetStateProperties(piecesTextureProperties)
			quad:setstate(1 + piecesNamesToIndex[block.name])
			local c = block.ghost and colorSum(color("#FFFFFFFF"), config.emptyColor, 2 / 5, 3 / 5) or color("#FFFFFFFF")
			quad:diffuse(c)
			quad:diffuselowerright(c)
			quad:diffuseupperleft(c)
			quad:diffusealpha(1.0)
		else
			quad:diffuse(c)
			quad:diffuselowerright(shine)
			quad:diffuseupperleft(shadow)
			quad:diffusealpha(block and block.alpha or 1.0)
		end
	else
		if quad.orig then
			quad:SetTexture(quad.orig)
		end
		quad:diffuse(config.emptyColor)
		quad:diffusealpha(block and block.alpha or 1.0)
	end
	quad:zoomto(config.grid.blockWidth - 1, config.grid.blockHeight - 1)
end

function pushPieces()
	local pieces = shuffle(copyTable(pieceNames))
	for k, v in pairs(pieces) do
		List.pushright(pieceQueue, v)
	end
end
pushPieces()
pushPieces()
pushPieces()

function popPiece()
	currentPiece = {name = List.popleft(pieceQueue), rotation = 0, offset = {x = 0, y = 0}}
	if pieceQueue.last - pieceQueue.first < 15 then
		pushPieces()
	end
	heldAlready = false
	MESSAGEMAN:Broadcast("RedrawHints")
	MESSAGEMAN:Broadcast("RedrawHoldPiece")
	return currentPiece
end
popPiece() -- randomize the first piece

function rotateOnce(coord, center)
	local rel = {x = coord.x - center.x, y = coord.y - center.y}
	return {x = math.floor(center.x + center.y - coord.y), y = math.floor(center.y + coord.x - center.x)}
end

function rotatePos(coord, numberino, center)
	if numberino == 0 then
		return {x = coord.x, y = coord.y}
	elseif numberino == 2 then
		return rotateOnce(rotateOnce(coord, center), center)
	elseif numberino == 1 then
		return rotateOnce(coord, center)
	end
	return rotateOnce(rotateOnce(rotateOnce(coord, center), center), center)
end

function setSpeed(newSpeed)
	secondsSinceLastMovement = secondsSinceLastMovement * newSpeed / currentSpeed
	currentSpeed = newSpeed
end

function rotatePiece(piece, numberino)
	newPiece = {}
	for i, v in ipairs(piece) do
		newPiece[i] = rotatePos(v, numberino, piece.center)
	end
	return newPiece
end

function translatePiece(piece, offset)
	newPiece = {}
	for i, v in ipairs(piece) do
		newPiece[i] = {x = v.x, y = v.y}
		newPiece[i].y = offset.y + newPiece[i].y
		newPiece[i].x = offset.x + newPiece[i].x
	end
	return newPiece
end

local inputMappings = invertTable(config.buttons)

function getPieceBlocks(pieceData)
	local pieceBlocks = blocksByPiece[pieceData.name]
	if pieceData.name ~= "O" then
		pieceBlocks = rotatePiece(pieceBlocks, pieceData.rotation)
	end
	return translatePiece(
		pieceBlocks,
		{y = pieceData.offset.y, x = pieceData.offset.x + math.floor(config.grid.width / 2)}
	)
end

function collidesWithBlocks(piece)
	local pieceBlocks = getPieceBlocks(piece)
	for i, v in ipairs(pieceBlocks) do
		--collision
		local x = v.x + 1
		local y = v.y + 1
		if grid[x] and grid[x][y] then
			return true
		end
		--out of bounds
		if x > config.grid.width or x < 1 or y > config.grid.height then
			return true
		end
	end

	return false
end

function handleWallKick(oldRotation, newRotation, rotatedPiece)
	local tests = wallKickData[rotatedPiece.name]
	local d = {}
	for i, v in ipairs(tests) do
		local newPiece = copyTable(rotatedPiece)
		local translation = v[wallKickIndexing[oldRotation + 1][newRotation + 1]]
		newPiece.offset.x = newPiece.offset.x + translation.x
		newPiece.offset.y = newPiece.offset.y - translation.y
		d[#d + 1] = newPiece.offset
		if not collidesWithBlocks(newPiece) then
			return newPiece
		end
	end
	return nil
end

function rotateCurrentPiece(rotation)
	local newPiece = copyTable(currentPiece)
	newPiece.rotation = (currentPiece.rotation + rotation) % 4
	if not collidesWithBlocks(newPiece) then
		currentPiece = newPiece
		return newPiece
	end
	if currentPiece.name ~= "O" then
		local oldRot = currentPiece.rotation
		if rotation ~= -1 and rotation ~= 1 then
			oldRot = (oldRot + 2) % 4
		end
		local x = handleWallKick(oldRot, newPiece.rotation, newPiece)
		if x then
			currentPiece = x
		end
		return x
	end
	return nil
end

function moveCurrentPiece(offset)
	local newPiece = copyTable(currentPiece)
	newPiece.offset.x = newPiece.offset.x + offset.x
	newPiece.offset.y = newPiece.offset.y + offset.y
	if not collidesWithBlocks(newPiece) then
		currentPiece = newPiece
		return newPiece
	end
	return nil
end

local buttonMappings = {
	speedUp = function()
		setSpeed(config.highSpeed)
	end,
	rotateLeft = function()
		rotateCurrentPiece(-1)
	end,
	rotateRight = function()
		rotateCurrentPiece(1)
	end,
	rotate180 = function()
		rotateCurrentPiece(2)
	end,
	drop = function()
		while tickGravity() do
		end
		floorTicks = 10
		tickGravity()
	end,
	down = function()
		setSpeed(config.highSpeed)
	end,
	up = function()
		setSpeed(config.normalSpeed)
	end,
	left = function()
		moveCurrentPiece({x = -1, y = 0})
	end,
	right = function()
		moveCurrentPiece({x = 1, y = 0})
	end,
	leftRepeat = function()
		local b = true
		while b do
			b = moveCurrentPiece({x = -1, y = 0})
		end
	end,
	rightRepeat = function()
		local b = true
		while b do
			b = moveCurrentPiece({x = 1, y = 0})
		end
	end,
	hold = function()
		if heldAlready then
			return
		end
		heldAlready = true
		if not holdPiece then
			holdPiece = currentPiece.name
			popPiece()
		else
			local cur = currentPiece
			currentPiece = {name = holdPiece, rotation = 0, offset = {x = 0, y = 0}}
			holdPiece = cur.name
		end
		MESSAGEMAN:Broadcast("RedrawHoldPiece")
	end
}

-- input callback
function buttonForEvent(event)
	local button = inputMappings[string.gsub(event.DeviceInput.button, "DeviceButton_", "")]
	if not button then
		button = inputMappings[event.char]
	end
	return button
end

local lastInputs = {}
local pressedKeys = {}
local repeatButtons = {left = true, right = true}
function buttonPress(button, ignore)
	floorTicks = 0
	if not ignore then
		lastInputs[button] = os.clock()
	end
	pressedKeys[button] = not ignore
	buttonMappings[button]()
	updateColors()
end
function inputCallback(event)
	local button = buttonForEvent(event)
	if not button then
		return
	end
	if event.type == "InputEventType_Release" then
		pressedKeys[button] = nil
		if button == "down" then
			buttonPress("up", true)
		end
		return
	end
	buttonPress(button, event.type ~= "InputEventType_FirstPress")
end

function inputPolling(executionSeconds)
	for button, _ in pairs(pressedKeys) do
		if lastInputs[button] then
			local secondsPressed = executionSeconds - lastInputs[button]
			if repeatButtons[button] then
				if secondsPressed > config.inputPollingSeconds then
					buttonPress(button .. "Repeat")
				end
			end
		end
	end
end

-- Update all grid actor quad colors
function updateColors()
	drawGrid = {}
	if currentPiece.name then
		local pieceBlocks = getPieceBlocks(currentPiece)
		local pieceColor = config.pieces.colors[currentPiece.name]
		for i, v in ipairs(pieceBlocks) do
			v.x = v.x + 1
			v.y = v.y + 1
			if not drawGrid[v.x] then
				if not grid[v.x] then
					grid[v.x] = {}
				end
				drawGrid[v.x] = {}
				setmetatable(drawGrid[v.x], {__index = grid[v.x]})
			end
			drawGrid[v.x][v.y] = {name = currentPiece.name, color = pieceColor}
		end
	end
	setmetatable(drawGrid, {__index = grid})
	if config.drawGhostBlocks then
		local ghostGrid = {}
		local ghostPiece = copyTable(currentPiece)
		local b = true
		while b do
			ghostPiece.offset.y = ghostPiece.offset.y + 1
			b = not collidesWithBlocks(ghostPiece)
		end
		ghostPiece.offset.y = ghostPiece.offset.y - 1
		local ghostPieceBlocks = getPieceBlocks(ghostPiece)
		local pieceColor = config.pieces.colors[currentPiece.name]
		for i, v in ipairs(ghostPieceBlocks) do
			v.x = v.x + 1
			v.y = v.y + 1
			if not ghostGrid[v.x] then
				if not grid[v.x] then
					grid[v.x] = {}
				end
				if not drawGrid[v.x] then
					drawGrid[v.x] = {}
				end
				ghostGrid[v.x] = {}
				setmetatable(ghostGrid[v.x], {__index = grid[v.x]})
				setmetatable(drawGrid[v.x], {__index = ghostGrid[v.x]})
			end
			ghostGrid[v.x][v.y] = {
				ghost = true,
				name = currentPiece.name,
				color = colorSum(pieceColor, Color.White, 1 / 5, 4 / 5),
				alpha = 0.5
			}
		end
		setmetatable(ghostGrid, {__index = grid})
		setmetatable(drawGrid, {__index = ghostGrid})
	end
	MESSAGEMAN:Broadcast("RedrawQuads")
end

function isLineFull(i)
	for j = 1, config.grid.width do
		if not grid[j] or not grid[j][i] or not grid[j][i].color then
			return false
		end
	end
	return true
end

function emptyLine(i)
	for j = 1, config.grid.width do
		if grid[j] then
			grid[j][i] = nil
		end
	end
end

function checkFullLines()
	for i = 1, config.grid.height do
		local lineIsFull = isLineFull(i)
		if lineIsFull then
			emptyLine(i)
			for i = i, 1, -1 do
				for j = 1, config.grid.width do
					grid[j][i] = grid[j] and grid[j][i - 1] or nil
				end
			end
		end
	end
end

function tickGravity()
	local newPiece = copyTable(currentPiece)
	newPiece.offset.y = currentPiece.offset.y + 1
	if not collidesWithBlocks(newPiece) then
		currentPiece = newPiece
		return true
	else
		if floorTicks >= 2 then
			local pieceBlocks = getPieceBlocks(currentPiece)
			local pieceColor = config.pieces.colors[currentPiece.name]
			for i, v in ipairs(pieceBlocks) do
				v.x = v.x + 1
				v.y = v.y + 1
				if not grid[v.x] then
					grid[v.x] = {}
				end
				grid[v.x][v.y] = {color = pieceColor, name = currentPiece.name}
			end
			popPiece()
			checkFullLines()
			floorTicks = 0
		else
			floorTicks = floorTicks + 1
		end
	end
	return false
end
-- Tick function (Called every 'currentSpeed' interval, in seconds)
function makeGameTick()
	--make the currentPiece fall 1 cell
	--check if fall ends (If so set the new piece with -1 offset)
	--if the current piece has -1 offset
	tickGravity()
	updateColors()
end

-- Update function (Called all the time)
local function everyFrame()
	local executionSeconds = os.clock()
	if not lastUpdateExecutionSeconds then
		lastUpdateExecutionSeconds = executionSeconds
	end
	secondsSinceLastMovement = secondsSinceLastMovement + executionSeconds - lastUpdateExecutionSeconds
	lastUpdateExecutionSeconds = executionSeconds
	inputPolling(executionSeconds)
	if secondsSinceLastMovement > currentSpeed then
		secondsSinceLastMovement = secondsSinceLastMovement - currentSpeed
		makeGameTick()
	end
end

-- grid initialization code
gridActor =
	Def.ActorFrame {
	OnCommand = function(self)
		SCREENMAN:GetTopScreen():AddInputCallback(inputCallback)
	end,
	InitCommand = function(self)
		self:SetUpdateFunction(everyFrame)
	end
}

local gridBg =
	Widg.Rectangle {
	x = SCREEN_WIDTH / 2,
	y = SCREEN_HEIGHT / 2,
	color = config.bgColor,
	width = config.grid.width * config.grid.blockWidth - 1,
	height = config.grid.height * config.grid.blockHeight - 1,
	halign = 1,
	valign = 1
}

for i = 1, config.grid.width do
	local index = #gridActor + 1
	gridActor[index] = Def.ActorFrame {}
	grid[i] = {}
	for j = 1, config.grid.height do
		gridActor[index][#(gridActor[index]) + 1] =
			Def.Quad {
			InitCommand = function(self)
				self:xy(
					SCREEN_WIDTH / 2 + (i - 1 - math.floor(config.grid.width / 2)) * config.grid.blockWidth,
					(j - 1 - math.floor(config.grid.height / 2)) * config.grid.blockHeight + SCREEN_HEIGHT / 2
				):zoomto(config.grid.blockWidth - 1, config.grid.blockHeight - 1):halign(0):valign(0):diffuse(config.emptyColor)
			end,
			RedrawQuadsMessageCommand = function(self)
				paintQuad(self, drawGrid[i][j])
			end
		}
	end
end

local hintActors =
	Def.ActorFrame {
	BeginCommand = function()
		MESSAGEMAN:Broadcast("RedrawHints")
	end
}
function quadGrid(f)
	local container = Def.ActorFrame {}
	for j = 1, 4 do
		for k = 1, 4 do
			local quad = Def.Quad {}
			f(quad, j, k)
			container[#container + 1] = quad
		end
	end
	return container
end

local hintBgs = Def.ActorFrame {}
for i = 1, config.hints.num do
	hintBgs[#hintBgs + 1] =
		Widg.Rectangle {
		x = config.hints.x + i * config.hints.xSpan + config.grid.blockWidth - 1,
		y = config.hints.y + i * config.hints.ySpan + config.grid.blockHeight - 1,
		width = config.grid.blockWidth * 4,
		height = config.grid.blockHeight * 4,
		color = config.bgColor
	}
	local quads = {}
	local hintActor =
		quadGrid(
		function(quad, j, k)
			quad.InitCommand = function(self)
				self:xy(
					config.hints.x + i * config.hints.xSpan + j * config.grid.blockWidth,
					config.hints.y + i * config.hints.ySpan + k * config.grid.blockHeight
				):zoomto(config.grid.blockWidth - 1, config.grid.blockHeight - 1):halign(0):valign(0)
				paintQuad(self, nil)
				if not quads[j] then
					quads[j] = {}
				end
				quads[j][k] = self
			end
		end
	)
	hintActor.RedrawHintsMessageCommand = function(self)
		local blocksToDraw = {}
		local pieceName = pieceQueue[pieceQueue.first + (i - 1)]
		local blocks = rotatePiece(blocksByPiece[pieceName], 0)
		local color = config.pieces.colors[pieceQueue[pieceQueue.first + (i - 1)]]
		for i, v in ipairs(blocks) do
			if not blocksToDraw[v.x + 1] then
				blocksToDraw[v.x + 1] = {}
			end
			blocksToDraw[v.x + 1][v.y + 1] = true
		end
		for j = 1, 4 do
			for k = 1, 4 do
				local block = {color = color, name = pieceName}
				paintQuad(quads[j][k], blocksToDraw[j] and blocksToDraw[j][k] and block)
			end
		end
	end
	hintActors[#hintActors + 1] = hintActor
end

local holdBg =
	Widg.Rectangle {
	x = config.holdPiece.x + config.grid.blockWidth,
	y = config.holdPiece.y + config.grid.blockHeight,
	width = config.grid.blockWidth * 4 - 1,
	height = 4 * config.grid.blockHeight - 1,
	color = config.bgColor
}

local holdPieceQuads = {}
local holdPieceGrid =
	quadGrid(
	function(quad, j, k)
		quad.InitCommand = function(self)
			self:xy(config.holdPiece.x + j * config.grid.blockWidth, config.holdPiece.y + k * config.grid.blockHeight):zoomto(
				config.grid.blockWidth - 1,
				config.grid.blockHeight - 1
			):halign(0):valign(0)
			paintQuad(self, nil)
			if not holdPieceQuads[j] then
				holdPieceQuads[j] = {}
			end
			holdPieceQuads[j][k] = self
		end
	end
)
holdPieceGrid.RedrawHoldPieceMessageCommand = function(self)
	local blocksToDraw = {}
	local color = holdPiece and config.pieces.colors[holdPiece] or config.emptyColor
	if holdPiece then
		local blocks = rotatePiece(blocksByPiece[holdPiece], 0)
		for i, v in ipairs(blocks) do
			if not blocksToDraw[v.x + 1] then
				blocksToDraw[v.x + 1] = {}
			end
			blocksToDraw[v.x + 1][v.y + 1] = true
		end
	end
	for j = 1, 4 do
		for k = 1, 4 do
			local block = {color = color, name = holdPiece}
			paintQuad(holdPieceQuads[j][k], holdPiece and blocksToDraw[j] and blocksToDraw[j][k] and block)
		end
	end
end

local help = LoadFont("_myriad pro") .. {
	InitCommand=function(self)
		self:draworder(-math.huge):settext("Welcome to the not-so-easteregg easter egg!\nEnter = Restart\nEsc = Exit to the title screen\nZ and X rotate pieces\nC holds pieces"):zoom(.7):xy(SCREEN_CENTER_X-310,SCREEN_CENTER_Y+204)
	end
}

local music =
	Def.Sound{
	File="tetris.ogg",
		InitCommand=function(self)
			self:play()
		end
	}

return Def.ActorFrame {music, help, pieceSprites, gridBg, gridActor, hintBgs, hintActors, holdBg, holdPieceGrid, menu}