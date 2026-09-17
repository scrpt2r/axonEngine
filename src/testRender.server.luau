--!native
--!strict
--!optimize 2

--// Services
local assetService = game:GetService("AssetService")
local starterGui = game:GetService("StarterGui")
local runService = game:GetService("RunService")
local userInputService = game:GetService("UserInputService")

--// Variables
local imageLabel = starterGui:WaitForChild("render"):WaitForChild("ImageLabel")
local editableImage = nil

local dx, dy, dz = 0, 0, 1

local fov = 70
local angleY = 0
local angleX = 0

local conn = nil
local bindConn = nil
local wheelConn1 = nil

local oldPos = userInputService:GetMouseLocation()

--// Constants
const SIZE = Vector2.new(800, 800)
const NEAR_CLIPPING = 0.45

const RECTANGLE_FILL_TYPE = Enum.ImageCombineType.Overwrite
const LINE_ANTI_ALIASING = Enum.AntiAliasing.Enabled
const FILL_COLOR = Color3.new(0, 0, 0)

const LIGHT_DIRECTION = Vector3.new(0, 1, -1)
const AMBIENT_LIGHT = 0.2

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
}

const FACE_COLORS = {
	Color3.fromRGB(255, 0, 0),
	Color3.fromRGB(255, 0, 255),
	Color3.fromRGB(0, 0, 255),
	Color3.fromRGB(0, 255, 0),
	Color3.fromRGB(255, 255, 0),
	Color3.fromRGB(200, 200, 200),
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

function _writeColorToBuffer(buf: buffer, color: Color3, size: Vector2)
	for i = 1, size.X * size.Y do
		local pixelIndex = (i - 1) * 4

		buffer.writeu8(buf, pixelIndex, math.floor(color.R * 255))
		buffer.writeu8(buf, pixelIndex + 1, math.floor(color.G * 255))
		buffer.writeu8(buf, pixelIndex + 2, math.floor(color.B * 255))
		buffer.writeu8(buf, pixelIndex + 3, 255)
	end
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

function _getDelta(): Vector2
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

function clipFaceAgainstNear(vertexList: { Vector3 }): { Vector3 }
	local finalVetreses = {}
	local n = #vertexList

	for k = 1, n do
		local A = vertexList[k]
		local B = vertexList[(k % n) + 1]

		local isSafeA = (A.Z >= NEAR_CLIPPING)
		local isSafeB = (B.Z >= NEAR_CLIPPING)

		if isSafeA and isSafeB then
			table.insert(finalVetreses, B)
			continue
		end

		if isSafeA and not isSafeB then
			local t = (NEAR_CLIPPING - A.Z) / (B.Z - A.Z)

			local intersaction = Vector3.new(A.X + t * (B.X - A.X), A.Y + t * (B.Y - A.Y), NEAR_CLIPPING)

			table.insert(finalVetreses, intersaction)
			continue
		end

		if not isSafeA and isSafeB then
			local t = (NEAR_CLIPPING - A.Z) / (B.Z - A.Z)

			local interpolation = Vector3.new(A.X + t * (B.X - A.X), A.Y + t * (B.Y - A.Y), NEAR_CLIPPING)

			table.insert(finalVetreses, interpolation)
			table.insert(finalVetreses, B)
			continue
		end

		if not isSafeA and not isSafeB then
			continue
		end
	end

	return finalVetreses
end

function drawRect(vertices: { Vector2 }, faceDepth: number, color: Color3)
	if not editableImage then
		return
	end

	local n = #vertices
	if n < 3 then
		return
	end

	local minY = math.huge
	local maxY = -math.huge

	for i = 1, n do
		local y = vertices[i].Y

		if y < minY then
			minY = y
		end

		if y > maxY then
			maxY = y
		end
	end

	for scanY = minY, maxY do
		local interpolitied = {}

		for k = 1, n do
			local A = vertices[k]
			local B = vertices[(k % n) + 1]

			local smallY = math.min(A.Y, B.Y)
			local bigY = math.max(A.Y, B.Y)

			if scanY < smallY or scanY > bigY or B.Y == A.Y then
				continue
			end

			local t = (scanY - A.Y) / (B.Y - A.Y)
			local interpolatedX = A.X + t * (B.X - A.X)
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

		local maxAllowedX = math.max(SIZE.X - width, 0)
		local safeX = math.clamp(minInterpolate, 0, maxAllowedX)
		local safeY = math.clamp(scanY, 0, SIZE.Y - 1)

		editableImage:DrawRectangle(Vector2.new(safeX, safeY), Vector2.new(width, 1), color, 0, RECTANGLE_FILL_TYPE)
	end
end

function autoFixWindingOrder(vertices: { Vector3 }, faces: { { number } })
	local center = Vector3.new(0, 0, 0)
	for _, v in vertices do
		center += v
	end
	center /= #vertices

	for i, face in faces do
		local v1 = vertices[face[1]]
		local v2 = vertices[face[2]]
		local v3 = vertices[face[3]]

		local edge1 = v2 - v1
		local edge2 = v3 - v1
		local normal = edge1:Cross(edge2)

		local dirFromCenter = v1 - center

		if normal:Dot(dirFromCenter) >= 0 then
			continue
		end

		local fixedFace = {}

		for j = #face, 1, -1 do
			table.insert(fixedFace, face[j])
		end

		faces[i] = fixedFace
	end
end

--stylua: ignore
function translateZ(vect: Vector3, dx: number, dy: number, dz: number): Vector3
	return Vector3.new(
		vect.X + dx, 
		vect.Y + dy, 
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
autoFixWindingOrder(VERTICIES, FACES)

if conn then
	conn:Disconnect()
end

conn = runService.Heartbeat:Connect(function(dt: number)
	local projectedVerticies = {}
	local viewSpace = {}
	local faceSorted = {}

	local delta = userInputService:GetMouseDelta() --getDelta()

	fov = math.clamp(fov, 70, 120)
	angleY += delta.X * dt --math.pi * dt --
	angleX += delta.Y * dt --math.pi * dt --

	--angleX = math.clamp(angleX, -3, 3)

	local matrisX = createRotationMatrixX(angleX)
	local matrisY = createRotationMatrixY(angleY)
	local multipliedRotation = multiplyMatrixes(matrisX, matrisY)

	setup()

	for i, v in VERTICIES do
		local rotated = applyMatrisToVector(multipliedRotation, v)
		local translated = translateZ(rotated, dx, dy, dz)
		local projected = project(translated)
		local screened = screen(projected)

		projectedVerticies[i] = screened
		viewSpace[i] = translated
	end

	--for i, edge in EDGES do
	--local a = projectedVerticies[edge[1]]
	--local b = projectedVerticies[edge[2]]

	--line(
	--a,
	--b
	--)
	--end

	for i, face in FACES do
		local mainViewVertex = { viewSpace[face[1]], viewSpace[face[2]], viewSpace[face[3]], viewSpace[face[4]] }
		local clippedVertexes = clipFaceAgainstNear(mainViewVertex)

		if #clippedVertexes < 3 then
			continue
		end

		local clippedVertexesScreen = {}
		for _, v in clippedVertexes do
			table.insert(clippedVertexesScreen, screen(project(v)))
		end

		if isBack(clippedVertexesScreen[1], clippedVertexesScreen[2], clippedVertexesScreen[3]) then
			continue
		end

		local faceDepth = 0
		for k = 1, #clippedVertexes do
			faceDepth += clippedVertexes[k].Z
		end
		faceDepth = faceDepth / #clippedVertexes

		--clippedVertexes (for luminance) TODO HERE
		-- L = (Nx, Ny, Nz) * LIGHT_DIRECTION
		-- N = surface normal vector

		table.insert(faceSorted, {
			index = i,
			depth = faceDepth,
			color = FACE_COLORS[i],
			vertices = clippedVertexesScreen,
		})
	end

	table.sort(faceSorted, function(a, b)
		return a.depth > b.depth
	end)

	for i, v in faceSorted do
		local color = v.color
		local depth = v.depth
		local vertices = v.vertices

		drawRect(vertices, depth, color)
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

	if input.Position.Z > 0 then
		dz += 0.1
	else
		dz -= 0.1
	end
end)
