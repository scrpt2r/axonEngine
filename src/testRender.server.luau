--!native
--!strict

--// Services
local assetService = game:GetService("AssetService")
local starterGui = game:GetService("StarterGui")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")

--// Variables
local imageLabel = starterGui:WaitForChild("render"):WaitForChild("ImageLabel")
local editableImage = nil

local dz = 1

local fov = 70
local angleY = 0
local angleX = 0

local conn = nil
local bindConn = nil
local wheelConn1 = nil

local oldPos = userInputService:GetMouseLocation()

--// Constants
const SIZE = Vector2.new(800, 800)
const RECTANGLE_FILL_TYPE = Enum.ImageCombineType.Overwrite
const LINE_ANTI_ALIASING = Enum.AntiAliasing.Enabled
const FILL_COLOR = Color3.new(0, 0, 0)

const VERTICIES = {
	Vector3.new(0.25, 0.25, 0.25),
	Vector3.new(-0.25, 0.25, 0.25),
	Vector3.new(-0.25, -0.25, 0.25),
	Vector3.new(0.25, -0.25, 0.25),

	Vector3.new(0.25, 0.25, -0.25),
	Vector3.new(-0.25, 0.25, -0.25),
	Vector3.new(-0.25, -0.25, -0.25),
	Vector3.new(0.25, -0.25, -0.25),
}

--stylua: ignore
const _EDGES = {
	{ 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
	{ 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
	{ 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

const FACES = {
	{ 1, 2, 3, 4 },
	{ 5, 8, 7, 6 },
	{ 1, 5, 6, 2 },
	{ 4, 3, 7, 8 },
	{ 1, 4, 8, 5 },
	{ 2, 6, 7, 3 },

	--[[
	1 = front,
	2 = back,
	3 = top,
	4 = bottom,
	5 = right,
	6 = left
	]]
}

const FACE_COLORS = {
	Color3.fromRGB(255, 0, 0),
	Color3.fromRGB(255, 0, 255),
	Color3.fromRGB(0, 0, 255),

	Color3.fromRGB(0, 255, 0),
	Color3.fromRGB(255, 255, 0),
	Color3.fromRGB(0, 0, 0),

	--[[
	1 = front,
	2 = back,
	3 = top,
	4 = bottom,
	5 = right,
	6 = left
	]]
}

--// Functions
function createEditableImage(): EditableImage?
	local succ, editableImage = pcall(function()
		return assetService:CreateEditableImage({ Size = SIZE })
	end)

	if not succ then
		warn("cannot create editable")
		return nil
	end

	return editableImage
end

function setup()
	local toSetEditableImage = createEditableImage()

	if not toSetEditableImage then
		return
	end

	editableImage = toSetEditableImage
	imageLabel.ImageContent = Content.fromObject(editableImage)
end

function isBack(vect1: Vector2, vect2: Vector2, vect3: Vector2): boolean
	local crossProduct = (vect2.X - vect1.X) * (vect3.Y - vect1.Y) - (vect2.Y - vect1.Y) * (vect3.X - vect1.X)
	return (crossProduct <= 0)
end

--stylua: ignore
function screen(pointVect: Vector2): Vector2
	return Vector2.new(
		(pointVect.X + 1) / 2 * SIZE.X, 
		(-pointVect.Y + 1) / 2 * SIZE.Y
	)
end

function getScreenAspectRatio(size: Vector2): number
	local ratio = size.X / size.Y
	return ratio
end

function getFocalLength(): number
	local fovFixed = fov * (math.pi / 180)
	return 1 / math.tan(fovFixed / 2)
end

--stylua: ignore
function getFocalAspectAsync(): Vector2
	local aspectRatio = getScreenAspectRatio(SIZE)
	local focalLength = getFocalLength()

	return Vector2.new(
		focalLength / aspectRatio,
		focalLength
	)
end

function getDelta(): Vector2
	local mousePos = userInputService:GetMouseLocation()
	local delta = (mousePos - oldPos)

	oldPos = mousePos
	return delta
end

--stylua: ignore
function project(vect: Vector3): Vector2
	local focalVect = getFocalAspectAsync()

	return Vector2.new(
		vect.X  * focalVect.X / vect.Z, 
		vect.Y * focalVect.Y / vect.Z
	)
end

function _point(pointVect: Vector2)
	if not editableImage then
		return
	end

	local size = 20
	local sizeVector2 = Vector2.new(size, size)
	local imageSize = editableImage.Size

	local x = math.clamp(pointVect.X - size / 2, 0, imageSize.X - size)
	local y = math.clamp(pointVect.Y - size / 2, 0, imageSize.Y - size)

	editableImage:DrawRectangle(Vector2.new(x, y), sizeVector2, FILL_COLOR, 0, RECTANGLE_FILL_TYPE)
end

function _line(pointVect1: Vector2, pointVect2: Vector2)
	if not editableImage then
		return
	end

	editableImage:DrawLine(pointVect1, pointVect2, FILL_COLOR, 0, RECTANGLE_FILL_TYPE, LINE_ANTI_ALIASING)
end

function drawRect(vect1: Vector2, vect2: Vector2, vect3: Vector2, vect4: Vector2, faceDepth: number, color: Color3)
	if not editableImage then
		return
	end

	--[[
	local minX = math.min(vect1.X, vect2.X, vect3.X, vect4.X)
	local maxX = math.max(vect1.X, vect2.X, vect3.X, vect4.X)
	]]

	local minY = math.min(vect1.Y, vect2.Y, vect3.Y, vect4.Y)
	local maxY = math.max(vect1.Y, vect2.Y, vect3.Y, vect4.Y)

	for scanY = minY, maxY do -- ceil, floor
		local interpolitied = {}

		local A1, B4 = vect1, vect1
		local B1, A2 = vect2, vect2
		local B2, A3 = vect3, vect3
		local B3, A4 = vect4, vect4

		local smallY1 = math.min(A1.Y, B1.Y)
		local bigY1 = math.max(A1.Y, B1.Y)

		local smallY2 = math.min(A2.Y, B2.Y)
		local bigY2 = math.max(A2.Y, B2.Y)

		local smallY3 = math.min(A3.Y, B3.Y)
		local bigY3 = math.max(A3.Y, B3.Y)

		local smallY4 = math.min(A4.Y, B4.Y)
		local bigY4 = math.max(A4.Y, B4.Y)

		if scanY >= smallY1 and scanY <= bigY1 then
			local t = (scanY - A1.Y) / (B1.Y - A1.Y)
			local interpolatedX = A1.X + t * (B1.X - A1.X)

			table.insert(interpolitied, interpolatedX)
		end

		if scanY >= smallY2 and scanY <= bigY2 then
			local t = (scanY - A2.Y) / (B2.Y - A2.Y)
			local interpolatedX = A2.X + t * (B2.X - A2.X)

			table.insert(interpolitied, interpolatedX)
		end

		if scanY >= smallY3 and scanY <= bigY3 then
			local t = (scanY - A3.Y) / (B3.Y - A3.Y)
			local interpolatedX = A3.X + t * (B3.X - A3.X)

			table.insert(interpolitied, interpolatedX)
		end

		if scanY >= smallY4 and scanY <= bigY4 then
			local t = (scanY - A4.Y) / (B4.Y - A4.Y)
			local interpolatedX = A4.X + t * (B4.X - A4.X)

			table.insert(interpolitied, interpolatedX)
		end

		if #interpolitied < 2 then
			continue
		end

		local minInterpolate = math.min(table.unpack(interpolitied))
		local maxInterpolate = math.max(table.unpack(interpolitied))

		if maxInterpolate - minInterpolate <= 0 then
			continue
		end

		local width = math.abs(maxInterpolate - minInterpolate)
		if width < 1 then
			width = 1
		end

		editableImage:DrawRectangle(
			Vector2.new(minInterpolate, scanY),
			Vector2.new(width, 1),
			color,
			0,
			RECTANGLE_FILL_TYPE
		)
	end
end

--stylua: ignore
function translateZ(vect: Vector3, dz: number): Vector3
	return Vector3.new(
		vect.X, vect.Y, 
		vect.Z + dz
	)
end

--stylua: ignore
function createRotationMatrixY(angle: number): {number}
	local cos = math.cos(angle)
	local sin = math.sin(angle)

	return {
		cos,  0, sin,
		0, 	  1,   0,
		-sin, 0, cos
	}
end

--stylua: ignore
function createRotationMatrixX(angle: number): {number}
	local cos = math.cos(angle)
	local sin = math.sin(angle)

	return {
		1,    0,    0,
		0, 	cos, -sin,
		0,  sin,  cos
	}
end

function multiplyMatrixes(matrisA: { number }, matrisB: { number }): { number }
	local finalMatris = {}

	for i = 1, 3 do
		for j = 1, 3 do
			local total = 0

			for k = 1, 3 do
				total += (matrisA[(i - 1) * 3 + k] * matrisB[(k - 1) * 3 + j])
			end

			finalMatris[(i - 1) * 3 + j] = total
		end
	end

	return finalMatris
end

--stylua: ignore
function applyMatrisToVector(matris: {number}, vect: Vector3): Vector3
	return Vector3.new(
		(matris[1] * vect.X) + (matris[2] * vect.Y) + (matris[3] * vect.Z),
		(matris[4] * vect.X) + (matris[5] * vect.Y) + (matris[6] * vect.Z),
		(matris[7] * vect.X) + (matris[8] * vect.Y) + (matris[9] * vect.Z)
	)
end

--// Connections
if conn then
	conn:Disconnect()
end

conn = runService.Heartbeat:Connect(function(dt: number)
	local projectedVerticies = {}
	local viewSpace = {}
	local faceSorted = {}

	local delta = getDelta()

	angleY += delta.X * dt
	angleX += delta.Y * dt

	local matrisX = createRotationMatrixX(angleX)
	local matrisY = createRotationMatrixY(angleY)
	local multipliedRotation = multiplyMatrixes(matrisX, matrisY)

	setup()

	for i, v in VERTICIES do
		local rotated = applyMatrisToVector(multipliedRotation, v)
		local translated = translateZ(rotated, dz)
		local projected = project(translated)
		local screened = screen(projected)

		projectedVerticies[i] = screened
		viewSpace[i] = translated
	end

	--for i, edge in EDGES do
	--local a = VERTICIES[edge[1]]
	--local b = VERTICIES[edge[2]]

	--line(
	--screen(project(translateZ(rotateYZPlane(rotateXZPlane(a, angleY), -angleX), dz))),
	--screen(project(translateZ(rotateYZPlane(rotateXZPlane(b, angleY), -angleX), dz)))
	--)
	--end

	for i, face in FACES do
		local vect1 = projectedVerticies[face[1]]
		local vect2 = projectedVerticies[face[2]]
		local vect3 = projectedVerticies[face[3]]

		if isBack(vect1, vect2, vect3) then
			continue
		end

		local faceDepth = (viewSpace[face[1]].Z + viewSpace[face[2]].Z + viewSpace[face[3]].Z + viewSpace[face[4]].Z)
			/ 4

		table.insert(faceSorted, { index = i, depth = faceDepth })
	end

	table.sort(faceSorted, function(a: { index: number, depth: number }, b: { index: number, depth: number })
		return a.depth > b.depth
	end)

	for i, v in faceSorted do
		local face = FACES[v.index]
		local color = FACE_COLORS[v.index]
		local depth = v.depth

		local vect1 = projectedVerticies[face[1]]
		local vect2 = projectedVerticies[face[2]]
		local vect3 = projectedVerticies[face[3]]
		local vect4 = projectedVerticies[face[4]]

		drawRect(vect1, vect2, vect3, vect4, depth, color)
	end
end)

if bindConn then
	bindConn:Disconnect()
end

if wheelConn1 then
	wheelConn1:Disconnect()
end

bindConn = userInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if input.KeyCode ~= Enum.KeyCode.R then
		return
	end

	setup()

	if conn then
		conn:Disconnect()
	end

	if bindConn then
		bindConn:Disconnect()
	end

	if wheelConn1 then
		wheelConn1:Disconnect()
	end
end)

wheelConn1 = userInputService.InputChanged:Connect(function(input, gameProcessed)
	if input.UserInputType ~= Enum.UserInputType.MouseWheel then
		return
	end

	--[[
	if input.Position.Z > 0 then
		fov -= 5
	else
		fov += 5
	end
	]]
end)
