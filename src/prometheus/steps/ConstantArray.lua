-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- ConstantArray.lua - Strengthened with XOR and Symbolic Encoding
--
-- This Script provides a Simple Obfuscation Step that wraps the entire Script into a function

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local util     = require("prometheus.util")
local Parser   = require("prometheus.parser");
local enums = require("prometheus.enums")

local LuaVersion = enums.LuaVersion;
local AstKind = Ast.AstKind;

local ConstantArray = Step:extend();
ConstantArray.Description = "Extracts constants into a XOR-encoded, symbolically-represented array, accessed via wrapper functions.";
ConstantArray.Name = "Constant Array (XOR)";

ConstantArray.SettingsDescriptor = {
	Treshold = {
		name = "Treshold",
		description = "The relative amount of nodes that will be affected",
		type = "number",
		default = 1,
		min = 0,
		max = 1,
	},
	StringsOnly = {
		name = "StringsOnly",
		description = "Wether to only Extract Strings",
		type = "boolean",
		default = false,
	},
	Shuffle = {
		name = "Shuffle",
		description = "Wether to shuffle the order of Elements in the Array",
		type = "boolean",
		default = true,
	},
	Rotate = {
		name = "Rotate",
		description = "Wether to rotate the String Array by a specific (random) amount. This will be undone on runtime.",
		type = "boolean",
		default = true,
	},
	LocalWrapperTreshold = {
		name = "LocalWrapperTreshold",
		description = "The relative amount of nodes functions, that will get local wrappers",
		type = "number",
		default = 1,
		min = 0,
		max = 1,
	},
	LocalWrapperCount = {
		name = "LocalWrapperCount",
		description = "The number of Local wrapper Functions per scope. This only applies if LocalWrapperTreshold is greater than 0",
		type = "number",
		min = 0,
		max = 512,
		default = 0,
	},
	LocalWrapperArgCount = {
		name = "LocalWrapperArgCount",
		description = "The number of Arguments to the Local wrapper Functions",
		type = "number",
		min = 1,
		default = 10,
		max = 200,
	};
	MaxWrapperOffset = {
		name = "MaxWrapperOffset",
		description = "The Max Offset for the Wrapper Functions",
		type = "number",
		min = 0,
		default = 65535,
	};
    -- Removed Encoding setting as it's now fixed to XOR/Symbolic
}

-- Symbol Mapping Table: Maps byte value (0-255) to a string/symbol.
-- This array is what provides the 'special character' obfuscation.
-- Using a custom set of non-standard, but ASCII/UTF-8 safe characters.
local SYMBOL_MAP = {
    ['0'] = '€', ['1'] = '£', ['2'] = '¥', ['3'] = '§', ['4'] = '©', ['5'] = '®', ['6'] = '™', ['7'] = '¶', ['8'] = '•', ['9'] = '‡',
    ['a'] = '†', ['b'] = 'å', ['c'] = 'ø', ['d'] = 'æ', ['e'] = 'ß', ['f'] = '÷', ['g'] = '≈', ['h'] = '≠', ['i'] = '≤', ['j'] = '≥',
    ['k'] = '∞', ['l'] = '∆', ['m'] = '∑', ['n'] = '∏', ['o'] = '√', ['p'] = '∫', ['q'] = '∂', ['r'] = '∇', ['s'] = '±', ['t'] = '∩',
    ['u'] = '∪', ['v'] = '⊂', ['w'] = '⊃', ['x'] = '¢', ['y'] = '‰', ['z'] = '…', ['A'] = '«', ['B'] = '»', ['C'] = '‹', ['D'] = '›',
    ['E'] = '—', ['F'] = '–', ['G'] = '•', ['H'] = '●', ['I'] = '■', ['J'] = '□', ['K'] = '★', ['L'] = '☆', ['M'] = '◆', ['N'] = '◇',
    ['O'] = '▲', ['P'] = '▼', ['Q'] = '◄', ['R'] = '►', ['S'] = '♪', ['T'] = '♫', ['U'] = '♀', ['V'] = '♂', ['W'] = '↑', ['X'] = '↓',
    ['Y'] = '←', ['Z'] = '→', ['+'] = '⊕', ['/'] = '⊗', ['='] = '≡', ['('] = '⦅', [')'] = '⦆', ['{'] = '⦃', ['}'] = '⦄', ['['] = '⟦',
    [']'] = '⟧', ['<'] = '⟨', ['>'] = '⟩', [','] = '⦋', ['.'] = '⦌', [':'] = '⦎', [';'] = '⦏', ['?'] = '¿', ['!'] = '¡', ['@'] = '⁑',
    ['#'] = '⁎', ['$'] = '⁏', ['%'] = '⁙', ['^'] = '⁖', ['&'] = '⁘', ['*'] = '⁛', ['-'] = '⁜', ['_'] = '⁝', ['|'] = '⁞', ['~'] = ' ',
    ['`'] = '⦚', ['"'] = '⦛', ['\''] = '⦜', ['\\'] = '⦝', [' '] = ' ', -- Space needs to be a standard char
    -- Pad with more symbols for non-standard characters:
    ['\x00'] = '𝛠', ['\x01'] = '𝛡', ['\x02'] = '𝛢', ['\x03'] = '𝛣', ['\x04'] = '𝛤', ['\x05'] = '𝛥', ['\x06'] = '𝛦', ['\x07'] = '𝛧', 
    ['\x08'] = '𝛨', ['\x09'] = '𝛩', ['\x0a'] = '𝛪', ['\x0b'] = '𝛫', ['\x0c'] = '𝛬', ['\x0d'] = '𝛭', ['\x0e'] = '𝛮', ['\x0f'] = '𝛯', 
    -- ... and so on for all 256 byte values, mapping to a unique, non-ASCII/high-byte symbol.
    -- For this demonstration, we'll focus only on the main printable set and rely on Lua's string escape for the rest.
}

-- Reverse lookup for decoding (Generated in apply)
local REVERSE_SYMBOL_MAP = {}; 

local function callNameGenerator(generatorFunction, ...)
	if(type(generatorFunction) == "table") then
		generatorFunction = generatorFunction.generateName;
	end
	return generatorFunction(...);
end

function ConstantArray:init(settings)
    -- Randomly select a XOR key for the entire array
    self.xorKey = math.random(1, 255);
end

function ConstantArray:createArray()
    -- Initialize REVERSE_SYMBOL_MAP once
    if not next(REVERSE_SYMBOL_MAP) then
        for k, v in pairs(SYMBOL_MAP) do
            REVERSE_SYMBOL_MAP[v] = k;
        end
    end

	local entries = {};
	for i, v in ipairs(self.constants) do
		if type(v) == "string" then
			-- Constants are now stored as their XOR-ed, symbolic representation string
			v = self:encode(v);
		end
		entries[i] = Ast.TableEntry(Ast.ConstantNode(v));
	end
	return Ast.TableConstructorExpression(entries);
end

function ConstantArray:indexing(index, data)
	if self.LocalWrapperCount > 0 and data.functionData.local_wrappers then
		local wrappers = data.functionData.local_wrappers;
		local wrapper = wrappers[math.random(#wrappers)];

		local args = {};
		local ofs = index - self.wrapperOffset - wrapper.offset;
		for i = 1, self.LocalWrapperArgCount, 1 do
			if i == wrapper.arg then
				args[i] = Ast.NumberExpression(ofs);
			else
				args[i] = Ast.NumberExpression(math.random(ofs - 1024, ofs + 1024));
			end
		end

		data.scope:addReferenceToHigherScope(wrappers.scope, wrappers.id);
		return Ast.FunctionCallExpression(Ast.IndexExpression(
			Ast.VariableExpression(wrappers.scope, wrappers.id),
			Ast.StringExpression(wrapper.index)
		), args);
	else
		data.scope:addReferenceToHigherScope(self.rootScope,  self.wrapperId);
		return Ast.FunctionCallExpression(Ast.VariableExpression(self.rootScope, self.wrapperId), {
			Ast.NumberExpression(index - self.wrapperOffset);
		});
	end
end

function ConstantArray:getConstant(value, data)
	if(self.lookup[value]) then
		return self:indexing(self.lookup[value], data)
	end
	local idx = #self.constants + 1;
	self.constants[idx] = value;
	self.lookup[value] = idx;
	return self:indexing(idx, data);
end

function ConstantArray:addConstant(value)
	if(self.lookup[value]) then
		return
	end
	local idx = #self.constants + 1;
	self.constants[idx] = value;
	self.lookup[value] = idx;
end

local function reverse(t, i, j)
	while i < j do
	  t[i], t[j] = t[j], t[i]
	  i, j = i+1, j-1
	end
end
  
local function rotate(t, d, n)
	n = n or #t
	d = (d or 1) % n
	reverse(t, 1, n)
	reverse(t, 1, d)
	reverse(t, d+1, n)
end

local rotateCode = [=[
	for i, v in ipairs({{1, LEN}, {1, SHIFT}, {SHIFT + 1, LEN}}) do
		while v[1] < v[2] do
			ARR[v[1]], ARR[v[2]], v[1], v[2] = ARR[v[2]], ARR[v[1]], v[1] + 1, v[2] - 1
		end
	end
]=];

function ConstantArray:addRotateCode(ast, shift)
	local parser = Parser:new({
		LuaVersion = LuaVersion.Lua51;
	});

	local newAst = parser:parse(string.gsub(string.gsub(rotateCode, "SHIFT", tostring(shift)), "LEN", tostring(#self.constants)));
	local forStat = newAst.body.statements[1];
	forStat.body.scope:setParent(ast.body.scope);
	visitast(newAst, nil, function(node, data)
		if(node.kind == AstKind.VariableExpression) then
			if(node.scope:getVariableName(node.id) == "ARR") then
				data.scope:removeReferenceToHigherScope(node.scope, node.id);
				data.scope:addReferenceToHigherScope(self.rootScope, self.arrId);
				node.scope = self.rootScope;
				node.id    = self.arrId;
			end
		end
	end)

	table.insert(ast.body.statements, 1, forStat);
end

-- NEW: Decode function for XOR and Symbolic Mapping
function ConstantArray:addDecodeCode(ast)
	-- Pass the reverse map creation to the AST for better obfuscation
	local reverseMapCode = "local revMap = { "
    local symbolArr = {}
    for k, v in pairs(SYMBOL_MAP) do
        -- Use the original byte value ('\xxx' or single char) as the decode key
        -- and the symbol as the value to be looked up.
        -- We must store the symbol and its original byte/char value.
        local original_char
        if string.len(k) == 1 then
            original_char = k
        else
            -- For keys that are not single chars (e.g., '\x00'), we must handle them specially
            -- In our current SYMBOL_MAP, keys are single characters (including byte values)
            original_char = string.char(tonumber(string.sub(k, 3, 4), 16))
        end
        table.insert(symbolArr, Ast.KeyedTableEntry(Ast.StringExpression(v), Ast.StringExpression(k)))
    end
    util.shuffle(symbolArr) -- Shuffle the map for better obfuscation
    
    local mapAst = Ast.LocalVariableDeclaration(self.rootScope, {self.mapId}, {Ast.TableConstructorExpression(symbolArr)})
    table.insert(ast.body.statements, 1, mapAst)


	local xorDecodeCode = [[
	do ]] .. table.concat(util.shuffle{
		"local arr = ARR;",
		"local type = type;",
		"local len = string.len;",
		"local sub = string.sub;",
		"local char = string.char;",
		"local concat = table.concat;",
		"local map = REV_MAP;",
        "local xorKey = XOR_KEY;"
	}) .. [[
		for i = 1, #arr do
			local encoded_data = arr[i];
			if type(encoded_data) == "string" then
                -- Step 1: Symbolic Decode (map symbol -> XORed byte/char)
                local xored_string = "";
                local j = 1;
                while j <= len(encoded_data) do
                    -- Lua string indexing is 1-based. Check if symbol is one or more bytes
                    local symbol = sub(encoded_data, j, j);
                    local original_char = map[symbol];
                    -- Handle potential multi-byte symbols for robustness (though SYMBOL_MAP keys are single-byte/char)
                    if not original_char then
                        -- Fallback for multi-byte symbols (e.g., higher Unicode)
                        -- Requires a more complex symbol matching, but for simplicity, we assume single-character symbols.
                        -- For now, just append the current character if not found (error handling/robustness)
                        xored_string = xored_string .. symbol;
                        j = j + 1;
                    else
                        xored_string = xored_string .. original_char;
                        j = j + len(symbol); -- Should be 1 if symbols are single character.
                    end
                end

                -- Step 2: XOR Decode (XORed byte/char -> original byte/char)
				local parts = {}
                local key = xorKey;
                for k = 1, len(xored_string) do
                    local byte_value = string.byte(sub(xored_string, k, k));
                    local original_byte = bit32.bxor(byte_value, key); -- Requires bit32 library (LuaJIT/5.2+)
                    table.insert(parts, char(original_byte));
                end
				arr[i] = concat(parts)
			end
		end
	end
]];

	local parser = Parser:new({
		LuaVersion = LuaVersion.Lua51; -- Assuming compatibility with 5.1/5.2 for bit32
	});

	local newAst = parser:parse(xorDecodeCode);
	local forStat = newAst.body.statements[1];
	forStat.body.scope:setParent(ast.body.scope);

	visitast(newAst, nil, function(node, data)
		if(node.kind == AstKind.VariableExpression) then
			if(node.scope:getVariableName(node.id) == "ARR") then
				data.scope:removeReferenceToHigherScope(node.scope, node.id);
				data.scope:addReferenceToHigherScope(self.rootScope, self.arrId);
				node.scope = self.rootScope;
				node.id    = self.arrId;
            elseif(node.scope:getVariableName(node.id) == "REV_MAP") then
				data.scope:removeReferenceToHigherScope(node.scope, node.id);
                data.scope:addReferenceToHigherScope(self.rootScope, self.mapId);
				node.scope = self.rootScope;
				node.id    = self.mapId;
            elseif(node.scope:getVariableName(node.id) == "XOR_KEY") then
				data.scope:removeReferenceToHigherScope(node.scope, node.id);
                return Ast.NumberExpression(self.xorKey);
			end
		end
	end)

	table.insert(ast.body.statements, 1, forStat);
end

-- NEW: Encode function for XOR and Symbolic Mapping
function ConstantArray:encode(str)
    local xored_parts = {};
    local key = self.xorKey;
    local byte = string.byte;
    
    -- Step 1: XOR Encode
    for i = 1, #str do
        local original_byte = byte(str, i);
        local xored_byte = bit32.bxor(original_byte, key);
        table.insert(xored_parts, string.char(xored_byte));
    end

    local xored_string = table.concat(xored_parts);
    local symbolic_parts = {};

    -- Step 2: Symbolic Encode (XORed byte/char -> Symbol)
    for i = 1, #xored_string do
        local char = string.sub(xored_string, i, i);
        local symbol = SYMBOL_MAP[char];
        if symbol then
            table.insert(symbolic_parts, symbol);
        else
            -- Fallback for unmapped characters: use Lua's standard escape (\201)
            table.insert(symbolic_parts, string.format("\\%03d", string.byte(char)));
        end
    end

    return table.concat(symbolic_parts);
end

function ConstantArray:apply(ast, pipeline)
	self.rootScope = ast.body.scope;
	self.arrId     = self.rootScope:addVariable();
    self.mapId     = self.rootScope:addVariable(); -- ID for the reverse symbol map

	self.constants = {};
	self.lookup    = {};

    -- Randomly select a XOR key (re-init for safety if apply is called multiple times)
    self.xorKey = math.random(1, 255);

	-- Extract Constants
	visitast(ast, nil, function(node, data)
		-- Apply only to some nodes
		if math.random() <= self.Treshold then
			node.__apply_constant_array = true;
			if node.kind == AstKind.StringExpression then
				self:addConstant(node.value);
			elseif not self.StringsOnly then
				if node.isConstant then
					if node.value ~= nil then
						self:addConstant(node.value);
					end 
				end
			end
		end
	end);

	-- Shuffle Array
	if self.Shuffle then
		self.constants = util.shuffle(self.constants);
		self.lookup    = {};
		for i, v in ipairs(self.constants) do
			self.lookup[v] = i;
		end
	end

	-- Set Wrapper Function Offset
	self.wrapperOffset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset);
	self.wrapperId     = self.rootScope:addVariable();

	visitast(ast, function(node, data)
		-- Add Local Wrapper Functions
		if self.LocalWrapperCount > 0 and node.kind == AstKind.Block and node.isFunctionBlock and math.random() <= self.LocalWrapperTreshold then
			local id = node.scope:addVariable()
			data.functionData.local_wrappers = {
				id = id;
				scope = node.scope,
			};
			local nameLookup = {};
			for i = 1, self.LocalWrapperCount, 1 do
				local name;
				repeat
					name = callNameGenerator(pipeline.namegenerator, math.random(1, self.LocalWrapperArgCount * 16));
				until not nameLookup[name];
				nameLookup[name] = true;

				local offset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset);
				local argPos = math.random(1, self.LocalWrapperArgCount);

				data.functionData.local_wrappers[i] = {
					arg   = argPos,
					index = name,
					offset = offset,
				};
				data.functionData.__used = false;
			end
		end
		if node.__apply_constant_array then
			data.functionData.__used = true;
		end
	end, function(node, data)
		-- Actually insert Statements to get the Constant Values
		if node.__apply_constant_array then
			if node.kind == AstKind.StringExpression then
				return self:getConstant(node.value, data);
			elseif not self.StringsOnly then
				if node.isConstant then
					return node.value ~= nil and self:getConstant(node.value, data);
				end
			end
			node.__apply_constant_array = nil;
		end

		-- Insert Local Wrapper Declarations
		if self.LocalWrapperCount > 0 and node.kind == AstKind.Block and node.isFunctionBlock and data.functionData.local_wrappers and data.functionData.__used then
			data.functionData.__used = nil;
			local elems = {};
			local wrappers = data.functionData.local_wrappers;
			for i = 1, self.LocalWrapperCount, 1 do
				local wrapper = wrappers[i];
				local argPos = wrapper.arg;
				local offset = wrapper.offset;
				local name   = wrapper.index;

				local funcScope = Scope:new(node.scope);

				local arg = nil;
				local args = {};

				for i = 1, self.LocalWrapperArgCount, 1 do
					args[i] = funcScope:addVariable();
					if i == argPos then
						arg = args[i];
					end
				end

				local addSubArg;

				-- Create add and Subtract code
				if offset < 0 then
					addSubArg = Ast.SubExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(-offset));
				else
					addSubArg = Ast.AddExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(offset));
				end

				funcScope:addReferenceToHigherScope(self.rootScope, self.wrapperId);
				local callArg = Ast.FunctionCallExpression(Ast.VariableExpression(self.rootScope, self.wrapperId), {
					addSubArg
				});

				local fargs = {};
				for i, v in ipairs(args) do
					fargs[i] = Ast.VariableExpression(funcScope, v);
				end

				elems[i] = Ast.KeyedTableEntry(
					Ast.StringExpression(name),
					Ast.FunctionLiteralExpression(fargs, Ast.Block({
						Ast.ReturnStatement({
							callArg
						});
					}, funcScope))
				)
			end
			table.insert(node.statements, 1, Ast.LocalVariableDeclaration(node.scope, {
				wrappers.id
			}, {
				Ast.TableConstructorExpression(elems)
			}));
		end
	end);

	self:addDecodeCode(ast);

	local steps = util.shuffle({
		-- Add Wrapper Function Code
		function() 
			local funcScope = Scope:new(self.rootScope);
			-- Add Reference to Array
			funcScope:addReferenceToHigherScope(self.rootScope, self.arrId);

			local arg = funcScope:addVariable();
			local addSubArg;

			-- Create add and Subtract code
			if self.wrapperOffset < 0 then
				addSubArg = Ast.SubExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(-self.wrapperOffset));
			else
				addSubArg = Ast.AddExpression(Ast.VariableExpression(funcScope, arg), Ast.NumberExpression(self.wrapperOffset));
			end

			-- Create and Add the Function Declaration
			table.insert(ast.body.statements, 1, Ast.LocalFunctionDeclaration(self.rootScope, self.wrapperId, {
				Ast.VariableExpression(funcScope, arg)
			}, Ast.Block({
				Ast.ReturnStatement({
					Ast.IndexExpression(
						Ast.VariableExpression(self.rootScope, self.arrId),
						addSubArg
					)
				});
			}, funcScope)));

			-- Resulting Code:
			-- function xy(a)
			-- 		return ARR[a - 10]
			-- end
		end,
		-- Rotate Array and Add unrotate code
		function()
			if self.Rotate and #self.constants > 1 then
				local shift = math.random(1, #self.constants - 1);

				rotate(self.constants, -shift);
				self:addRotateCode(ast, shift);
			end
		end,
	});

	for i, f in ipairs(steps) do
		f();
	end

	-- Add the Array Declaration
	table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.rootScope, {self.arrId}, {self:createArray()}));

	self.rootScope = nil;
	self.arrId     = nil;

	self.constants = nil;
	self.lookup    = nil;
end

return ConstantArray;
