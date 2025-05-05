local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Roact = require(ReplicatedStorage.Packages.Roact) -- Adjust path if needed

local Dealership = Roact.Component:extend("Dealership")

function Dealership:init()
	-- Initial state: the window is not visible
	self.state = {
		windowVisible = false,
	}

	-- Bind methods to self so they can correctly access 'self' when used as callbacks
	self.onOpenButtonClick = function()
		self:setState({
			windowVisible = true,
		})
	end

	self.onCloseButtonClick = function()
		self:setState({
			windowVisible = false,
		})
	end
end

function Dealership:render()
	local window = nil

	-- Conditionally create the window element if state says it should be visible
	if self.state.windowVisible then
		window = Roact.createElement("Frame", {
			Size = UDim2.new(0.4, 0, 0.5, 0), -- 40% width, 50% height
			Position = UDim2.new(0.5, 0, 0.5, 0), -- Center
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.fromRGB(50, 50, 60),
			BorderSizePixel = 2,
			BorderColor3 = Color3.fromRGB(200, 200, 200),
		}, {
			-- Add a title label (optional)
			Title = Roact.createElement("TextLabel", {
				Size = UDim2.new(1, 0, 0, 30), -- Full width, 30 pixels height
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundColor3 = Color3.fromRGB(70, 70, 80),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Text = "My Window",
				Font = Enum.Font.SourceSansBold,
				TextSize = 18,
			}),

			-- Add a close button inside the window
			CloseButton = Roact.createElement("TextButton", {
				Size = UDim2.new(0, 80, 0, 30),
				Position = UDim2.new(0.5, 0, 0.9, 0), -- Near the bottom center
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = Color3.fromRGB(72, 50, 200),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Text = "X",
				Font = Enum.Font.SourceSans,
				TextSize = 16,
				[Roact.Event.MouseButton1Click] = self.onCloseButtonClick, -- Use the bound close function
			}),
		})
	end

	-- Return the main UI structure
	return Roact.createElement("Frame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
    }, {
		-- The button that opens the window
		OpenButton = Roact.createElement("TextButton", {
			Size = UDim2.new(0, 150, 0, 50),
			Position = UDim2.new(0.1, 0, 0.2, 0), -- Position near top-left
			BackgroundColor3 = Color3.fromRGB(200, 84, 80),
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Text = "Open Window",
			Font = Enum.Font.SourceSansBold,
			TextSize = 18,
			[Roact.Event.MouseButton1Click] = self.onOpenButtonClick, -- Use the bound open function
		}),

		-- Render the window element (will be nil if not visible)
		PopupWindow = window,
	})
end

return Dealership