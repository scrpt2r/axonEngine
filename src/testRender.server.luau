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

local renderSurfaceNormals = false

--// Constants
const SIZE = Vector2.new(1861, 834)
const NEAR_CLIPPING = 0.45

const RECTANGLE_FILL_TYPE = Enum.ImageCombineType.Overwrite
const LINE_ANTI_ALIASING = Enum.AntiAliasing.Enabled
const FILL_COLOR = Color3.new(1, 1, 1)

const LIGHT_DIRECTION = Vector3.new(0, 1, -1).Unit
const AMBIENT_LIGHT = 0.35

const INSIDE = 0 -- 0000
const LEFT = 1 -- 0001
const RIGHT = 2 -- 0010
const BOTTOM = 4 -- 0100
const TOP = 8 -- 1000

--// Algoritmik Donut (Torus) Jeneratörü
local function generateTorus(majorRadius: number, minorRadius: number, rings: number, segments: number, color: Color3)
	local vertices = {}
	local faces = {}
	local colors = {}

	for i = 0, rings - 1 do
		local theta = i * (math.pi * 2) / rings
		local cosTheta = math.cos(theta)
		local sinTheta = math.sin(theta)

		for j = 0, segments - 1 do
			local phi = j * (math.pi * 2) / segments
			local cosPhi = math.cos(phi)
			local sinPhi = math.sin(phi)

			-- Donut yüzeyindeki X, Y, Z noktaları hesaplanıyor
			local x = (majorRadius + minorRadius * cosPhi) * cosTheta
			local y = minorRadius * sinPhi
			local z = (majorRadius + minorRadius * cosPhi) * sinTheta

			table.insert(vertices, Vector3.new(x, y, z))
		end
	end

	for i = 0, rings - 1 do
		for j = 0, segments - 1 do
			local nextI = (i + 1) % rings
			local nextJ = (j + 1) % segments

			local a = (i * segments) + j + 1
			local b = (nextI * segments) + j + 1
			local c = (nextI * segments) + nextJ + 1
			local d = (i * segments) + nextJ + 1

			table.insert(faces, { a, d, c, b })
			table.insert(colors, color)
		end
	end

	return vertices, faces, colors
end

local VERTICIES, FACES, FACE_COLORS = generateTorus(0.5, 0.22, 64, 32, Color3.fromRGB(255, 105, 180))

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

function getSurfaceNormal(vect1: Vector3, vect2: Vector3, vect3: Vector3): Vector3
	local edge1 = vect2 - vect1
	local edge2 = vect3 - vect1

	local normal = edge1:Cross(edge2)
	return normal
end

function getSurfaceNormalUnit(vect1: Vector3, vect2: Vector3, vect3: Vector3): Vector3
	local edge1 = vect2 - vect1
	local edge2 = vect3 - vect1

	local normal = edge1:Cross(edge2)

	return normal.Unit
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

-- used Chen-Sutherland algorithm:
-- https://en.wikipedia.org/wiki/Cohen%E2%80%93Sutherland_algorithm
function computeCode(x: number, y: number, xMax: number, yMax: number): number
	local code = INSIDE

	if x < 0 then
		code = bit32.bor(code, LEFT)
	elseif x > xMax then
		code = bit32.bor(code, RIGHT)
	end

	if y < 0 then
		code = bit32.bor(code, BOTTOM)
	elseif y > yMax then
		code = bit32.bor(code, TOP)
	end

	return code
end

-- used Chen-Sutherland algorithm:
-- https://en.wikipedia.org/wiki/Cohen%E2%80%93Sutherland_algorithm
function line(pointVect1: Vector2, pointVect2: Vector2)
	if not editableImage then
		return
	end

	local xMin, yMin = 0, 0
	local xMax = editableImage.Size.X - 1
	local yMax = editableImage.Size.Y - 1

	local x1, y1 = pointVect1.X, pointVect1.Y
	local x2, y2 = pointVect2.X, pointVect2.Y

	local code1 = computeCode(x1, y1, xMax, yMax)
	local code2 = computeCode(x2, y2, xMax, yMax)
	local accept = false

	while true do
		if code1 == 0 and code2 == 0 then
			accept = true
			break
		elseif bit32.band(code1, code2) ~= 0 then
			break
		else
			local codeOut = if code1 ~= 0 then code1 else code2
			local x, y = 0, 0

			if bit32.band(codeOut, TOP) ~= 0 then
				x = x1 + (x2 - x1) * (yMax - y1) / (y2 - y1)
				y = yMax
			elseif bit32.band(codeOut, BOTTOM) ~= 0 then
				x = x1 + (x2 - x1) * (yMin - y1) / (y2 - y1)
				y = yMin
			elseif bit32.band(codeOut, RIGHT) ~= 0 then
				y = y1 + (y2 - y1) * (xMax - x1) / (x2 - x1)
				x = xMax
			elseif bit32.band(codeOut, LEFT) ~= 0 then
				y = y1 + (y2 - y1) * (xMin - x1) / (x2 - x1)
				x = xMin
			end

			if codeOut == code1 then
				x1, y1 = x, y
				code1 = computeCode(x1, y1, xMax, yMax)
			else
				x2, y2 = x, y
				code2 = computeCode(x2, y2, xMax, yMax)
			end
		end
	end

	if not accept then
		return
	end

	editableImage:DrawLine(
		Vector2.new(x1, y1),
		Vector2.new(x2, y2),
		FILL_COLOR,
		0,
		RECTANGLE_FILL_TYPE,
		LINE_ANTI_ALIASING
	)
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

	for scanY = math.ceil(minY), math.floor(maxY) do
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

		local normal = getSurfaceNormal(v1, v2, v3)
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
--autoFixWindingOrder(VERTICIES, FACES)

if conn then
	conn:Disconnect()
end

conn = runService.Heartbeat:Connect(function(dt: number)
	local projectedVerticies = {}
	local viewSpace = {}
	local faceSorted = {}

	local delta = userInputService:GetMouseDelta() --getDelta()

	fov = math.clamp(fov, 70, 120)
	angleY += math.pi * dt --delta.X * dt --
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

		-- clippedVertexes (for luminance)
		-- L = (Nx, Ny, Nz) * LIGHT_DIRECTION
		-- N = surface normal vector

		local vect1 = clippedVertexes[1]
		local vect2 = clippedVertexes[2]
		local vect3 = clippedVertexes[3]

		local surfaceNormalUnit = getSurfaceNormalUnit(vect1, vect2, vect3)

		local L = surfaceNormalUnit:Dot(LIGHT_DIRECTION)
		local luminance = math.max(AMBIENT_LIGHT, L)

		local baseColor = FACE_COLORS[i]
		local finalCalculateds = Color3.new(baseColor.R * luminance, baseColor.G * luminance, baseColor.B * luminance)

		local center3D = Vector3.new(0, 0, 0)
		for _, v in clippedVertexes do
			center3D += v
		end
		center3D /= #clippedVertexes

		local lineLength = 0.5
		local end3D = center3D + (surfaceNormalUnit * lineLength)

		local startPos = screen(project(center3D))
		local endPos = screen(project(end3D))

		if renderSurfaceNormals then
			line(startPos, endPos)
		end

		table.insert(faceSorted, {
			index = i,
			depth = faceDepth,
			color = finalCalculateds,
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
	if input.KeyCode == Enum.KeyCode.V then
		renderSurfaceNormals = not renderSurfaceNormals
	end

	if input.KeyCode == Enum.KeyCode.R then
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
