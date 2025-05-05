--[[
	Created by DaveInchy on 01.10.2024 [13:55:21]

	useState: (initial: any, name: string, parent: Instance?) -> State :: {
		get: () -> {any}?;
		set: (newState: {any}?) -> {any}?;
		object: ValueBase;
		instance: Instance;
		update: RBXScriptSignal;
		useEffect: RBXScriptSignal;
	}

	[Description]
	Stateful Instance/Model('s) anywhere in your game. Isn't specifically for UI. just use this function (useState) and read the notes inside the file.

	[Author] DaveInchy on Gi1Hu8

	[Notes]
	1. I recommend also using Promise's with your stateful models/instances, It will make your code execute a little bit more controlled then when only the value changes.

	2. useEffect isn't exactly like react's useState. It fires anytime the object's Value property changes, not just when it's first initialized.
	When the object's Value property changes, it's because you (or something else) set it to something new.
	So it's actually like a Changed signal. Where/which you can Connect to ofcourse.

	3. As an Example:
	```lua
		-- Instantiate the Mutable State
		local Announcement = useState("Announcement Message.", "LatestAnnouncement", workspace)

		-- observing the state for when you need to run code other then just changing states.
		-- For example in a GUI frame where it displays the announcement. or cash or level etc...
		local DestroyMeLater = Announcement.useEffect:Connect(function(newValue)
			print(`Updated Announcement to '{newValue or Announcement.get()}'`)
		end)

		print(Announcement.get()) -- prints "Announcement Message."
		Announcement.set(`Hello World.`) -- prints "Updated Announcement to 'Hello World.'"
		Announcement.object.Value = "Hello World." -- prints "Updated Announcement to 'Hello World.'"
	```

	[Extra]
	works both client and server -sided but the Server overwrites the Client. It will look if the value already exists on the server or client.
	on the client you're not able to find the server value. so if you want to observe it on the client when theres changes on the server...
	you need to instantiate it first on the server and then listen to it on the client by just using the same name (param #2) because the client
	will grab the previously instantiated State.

	[Version] 1.1.0
	[License] MIT (http://www.tldrlegal.com/licenses/MIT)

	[Contributors] (Add your name if you modified it and want to be able to share it as co-author)
		DaveInchy <dave@doonline.nl>
]]--

export type State = {
	get: () -> {any}?;
	set: (newState: {any}?) -> {any}?;
	object: ValueBase?;
	instance: Instance?; -- its a parent where the folder of Values will be stored. or its is the actual values folder, im unsure.
	update: RBXScriptSignal?;
	useEffect: RBXScriptSignal?;
}

local encodeJSON = function(data: any): string
	local http = game:GetService("HttpService");
	return http:JSONEncode(data);
end

local useState: (initial: any, name: string, parent: Instance?) -> State = function(initial: any, name: string, parent: Instance?): State

	local refObject = {}

	function refObject.create(valueType: "NumberValue" | "StringValue" | "ObjectValue" | "BoolValue")
		local instance = Instance.new(valueType)
		return instance;
	end

	local state = initial;
	local object = refObject;
	local valueType = "StringValue";

    parent = parent or nil;

	if initial == nil then
		warn("Initial State is nil (param #1), please value your state or something first. returning ni(u?)llified State. I mean...\n\r<spoiler msg=\"DAYUM! You a dumb betch! who creates something without value? get on that cash brother please...\"/>")
		return {get=nil,set=nil,object=nil,instance=nil,update=nil,useEffect=nil} :: State;
	end

	-- remember that if you restart the game and you use a json string, the usestate method will think its simply a string, and not a custom JSONStringValue anymore. so just keep that in mind.
	-- solution: just encode and decode the json yourself when setting and getting the StringValue.
	if typeof(initial) == "table" then
		local json = encodeJSON(initial);
		valueType = "JSONStringValue"
		object = object.create("StringValue");
		object.Value = json;

	elseif typeof(initial) == "boolean" then
		valueType = "BoolValue"
		object = object.create(valueType);
		object.Value = initial;

	elseif typeof(initial) == "string" then
		valueType = "StringValue"
		object = object.create(valueType);
		object.Value = initial;

	elseif typeof(initial) == "number" then
		valueType = "NumberValue"
		object = object.create(valueType);
		object.Value = initial;

	elseif typeof(initial) == "Instance" then
		valueType = "ObjectValue"
		object = object.create(valueType);
		object.Value = initial;

	elseif typeof(initial) == "CFrame" then
		valueType = "CFrameValue"
		object = object.create(valueType);
		object.Value = initial;

	elseif typeof(initial) == "Vector3" then
		valueType = "Vector3Value"
		object = object.create(valueType);
		object.Value = initial;

	else
		warn("Error: Couldn't tell what type of data is.")
		return {get=nil,set=nil,object=nil,instance=nil,update=nil,useEffect=nil} :: State;
	end

	if parent == nil then
		parent = (script:FindFirstAncestorWhichIsA("Player") or script:FindFirstAncestorWhichIsA("GuiBase") or script:FindFirstAncestorWhichIsA("BasePlayerGui") or script:FindFirstAncestorWhichIsA("Actor") or script:FindFirstAncestorWhichIsA("Model") or script:FindFirstAncestorWhichIsA("ModuleScript")) or script.Parent
	end

	assert(parent ~= nil, "There was no parent type to create the Values folder to bind the realtime state to")

	if parent == nil then
		parent = game.ReplicatedStorage;
	end

	-- if is client, then localplayer scripts folder as parent, if is server, then store value inside of replicatedstorage
	if game:GetService("RunService"):IsClient() then
		print("Created StateMachine inside LocalPlayer")
		parent = game.Players.LocalPlayer;
	end

	local folder = nil;
	if not parent:FindFirstChild("Values") and folder == nil then
		folder = Instance.new("Folder", parent)
		folder.Name = "Values";
	elseif parent:FindFirstChild("Values") and folder == nil then
		folder = parent:FindFirstChild("Values");
	end

	local prevValueBase = folder:FindFirstChild(`{name or "UnknownValueName"}`);
	if prevValueBase ~= nil then
		object = prevValueBase
		valueType = `{object.ClassName}`;
	else
		object.Parent = folder;
		object.Name = name or "UnknownValueName";
	end

	local function set(new): any
		if valueType == "NumberValue" then
			-- Ensure we're setting a number
			state = tonumber(new) or 0
			object.Value = state
		elseif valueType == "JSONStringValue" then
			local json = encodeJSON(new)
			state = new
			object.Value = json
		else
			state = new
			object.Value = new
		end
		return state
	end

	local function get(): any
		return object.Value or state or nil;
	end

	object.Changed:Connect(function(newValue)
		if state ~= newValue then
			print(`💾 Updating Values.{object.Name} inside {object.Parent.Parent.Name}`)
			set(newValue);
		end
	end)

	return {["get"] = get, ["set"] = set, object = object, instance = parent, update = object.Changed, useEffect = object.Changed} :: State
end :: () -> State

return useState;