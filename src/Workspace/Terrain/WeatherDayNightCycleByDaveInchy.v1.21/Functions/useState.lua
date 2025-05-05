return function(initial): {get: () -> any, set: (state: any) -> any}

	local refObject = {}

	function refObject.create(valueType: "NumberValue" | "StringValue" | "ObjectValue" | "BoolValue")
		local instance = Instance.new(valueType)
		return instance;
	end

	local state = initial;
	local object = refObject;
	local valueType = "StringValue";

	local encodeJSON = function(data: any): string
		local http = game:GetService("HttpService");
		return http:JSONEncode(data);
	end

	if typeof(initial) == "table" then 
		local http = game:GetService("HttpService");
		local str = http:JSONEncode(initial);
		valueType = "JSONValue"
		object = object.create("StringValue");
		object.Value = str;

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

	else 
		warn("Error: Couldn't tell what type of data is.")
		return {get=nil,set=nil};
	end

	if not script:FindFirstChild("Values") then
		local folder = Instance.new("Folder", script)
		folder.Name = "Values"
	end

	object.Parent = script.Values;


	local function set(new): any
		state = new;
		if valueType == "JSONValue" then
			local json = encodeJSON(new)
			object.Value = json;
		else
			object.Value = new;
		end
		return state;
	end	
	local function get(): any
		return state
	end
	return {["get"] = get, ["set"] = set}
end