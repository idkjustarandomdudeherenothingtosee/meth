-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- ConstantArray.lua - Luau/Lua 5.1 Safe with AST Protection
-- Prevents "attempt to index a number value" by protecting generated nodes.

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local util     = require("prometheus.util")
local Parser   = require("prometheus.parser");
local enums = require("prometheus.enums")

local LuaVersion = enums.LuaVersion;
local AstKind = Ast.AstKind;

-- Helper to create a number node that other steps (like NumbersToExpressions) will ignore
local function SafeNumber(n)
    local node = Ast.NumberExpression(n)
    node.NoObfuscation = true -- Standard Prometheus flag to skip this node in other steps
    node.IsGenerated = true
    return node
end

-- Standard Bitwise XOR implementation for Lua 5.1 / Luau fallback
local function bxor(a, b)
    local p, c = 1, 0
    while a > 0 or b > 0 do
        local ra, rb = a % 2, b % 2
        if ra ~= rb then c = c + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return c
end

local ConstantArray = Step:extend();
ConstantArray.Description = "Extracts constants into a XOR-encoded, symbolic array. Luau safe and protected from AST corruption.";
ConstantArray.Name = "Constant Array (Luau Safe)";

ConstantArray.SettingsDescriptor = {
	Treshold = { name = "Treshold", type = "number", default = 1 },
	StringsOnly = { name = "StringsOnly", type = "boolean", default = false },
	Shuffle = { name = "Shuffle", type = "boolean", default = true },
	Rotate = { name = "Rotate", type = "boolean", default = true },
	LocalWrapperTreshold = { name = "LocalWrapperTreshold", type = "number", default = 1 },
	LocalWrapperCount = { name = "LocalWrapperCount", type = "number", default = 0 },
	LocalWrapperArgCount = { name = "LocalWrapperArgCount", type = "number", default = 10 },
	MaxWrapperOffset = { name = "MaxWrapperOffset", type = "number", default = 65535 },
}

local SYMBOL_MAP = {
    ['0'] = '!', ['1'] = '@', ['2'] = '#', ['3'] = '$', ['4'] = '%', ['5'] = '^', ['6'] = '&', ['7'] = '*', ['8'] = '(', ['9'] = ')',
    ['a'] = 'Q', ['b'] = 'W', ['c'] = 'E', ['d'] = 'R', ['e'] = 'T', ['f'] = 'Y', ['g'] = 'U', ['h'] = 'I', ['i'] = 'O', ['j'] = 'P',
    ['k'] = 'A', ['l'] = 'S', ['m'] = 'D', ['n'] = 'F', ['o'] = 'G', ['p'] = 'H', ['q'] = 'J', ['r'] = 'K', ['s'] = 'L', ['t'] = 'Z',
    ['u'] = 'X', ['v'] = 'C', ['w'] = 'V', ['x'] = 'B', ['y'] = 'N', ['z'] = 'M',
    ['A'] = 'q', ['B'] = 'w', ['C'] = 'e', ['D'] = 'r', ['E'] = 't', ['F'] = 'y', ['G'] = 'u', ['H'] = 'i', ['I'] = 'o', ['J'] = 'p',
    ['K'] = 'a', ['L'] = 's', ['M'] = 'd', ['N'] = 'f', ['O'] = 'g', ['P'] = 'h', ['Q'] = 'j', ['R'] = 'k', ['S'] = 'l', ['T'] = 'z',
    ['U'] = 'x', ['V'] = 'c', ['W'] = 'v', ['X'] = 'b', ['Y'] = 'n', ['Z'] = 'm',
    ['+'] = '_', ['/'] = '-', ['='] = '+', [' '] = ' ',
}

local function callNameGenerator(pipeline, len)
    return pipeline.namegenerator:generateName(len or 8)
end

function ConstantArray:init(settings)
    self.xorKey = math.random(1, 255);
end

function ConstantArray:addConstant(value)
	if(self.lookup[value]) then return end
	local idx = #self.constants + 1;
	self.constants[idx] = value;
	self.lookup[value] = idx;
end

function ConstantArray:getConstant(value, data)
	if not self.lookup[value] then self:addConstant(value) end
	return self:indexing(self.lookup[value], data);
end

function ConstantArray:indexing(index, data)
	if self.LocalWrapperCount > 0 and data.functionData.local_wrappers then
		local wrappers = data.functionData.local_wrappers;
		local wrapper = wrappers[math.random(#wrappers)];
		local ofs = index - self.wrapperOffset - wrapper.offset;
		local args = {};
		for i = 1, self.LocalWrapperArgCount do
			args[i] = (i == wrapper.arg) and SafeNumber(ofs) or SafeNumber(math.random(ofs - 100, ofs + 100));
		end
		data.scope:addReferenceToHigherScope(wrappers.scope, wrappers.id);
		return Ast.FunctionCallExpression(Ast.IndexExpression(Ast.VariableExpression(wrappers.scope, wrappers.id), Ast.StringExpression(wrapper.index)), args);
	else
		data.scope:addReferenceToHigherScope(self.rootScope, self.wrapperId);
		return Ast.FunctionCallExpression(Ast.VariableExpression(self.rootScope, self.wrapperId), {SafeNumber(index - self.wrapperOffset)});
	end
end

function ConstantArray:encode(str)
    local xored_parts = {};
    for i = 1, #str do table.insert(xored_parts, string.char(bxor(string.byte(str, i), self.xorKey))) end
    local xored_string = table.concat(xored_parts);
    local symbolic_parts = {};
    for i = 1, #xored_string do
        local b = string.byte(xored_string, i);
        local char = string.char(b);
        local symbol = SYMBOL_MAP[char];
        if symbol then table.insert(symbolic_parts, symbol)
        elseif b < 32 or b > 126 or char == "\\" or char == "\"" or char == "'" then
            table.insert(symbolic_parts, string.format("\\%03d", b))
        else table.insert(symbolic_parts, char) end
    end
    return table.concat(symbolic_parts);
end

function ConstantArray:createArray()
	local entries = {};
	for i, v in ipairs(self.constants) do
		if type(v) == "string" then v = self:encode(v) end
		entries[i] = Ast.TableEntry(Ast.ConstantNode(v));
	end
	return Ast.TableConstructorExpression(entries);
end

function ConstantArray:addDecodeCode(ast)
    local symbolArr = {}
    for k, v in pairs(SYMBOL_MAP) do
        table.insert(symbolArr, Ast.KeyedTableEntry(Ast.StringExpression(v), Ast.StringExpression(k)))
    end
    util.shuffle(symbolArr)
    local mapAst = Ast.LocalVariableDeclaration(self.rootScope, {self.mapId}, {Ast.TableConstructorExpression(symbolArr)})
    table.insert(ast.body.statements, 1, mapAst)

	local xorDecodeCode = [[
	do ]] .. table.concat(util.shuffle{
		"local arr = ARR;", "local map = REV_MAP;", "local xorKey = XOR_KEY;"
	}) .. [[
        local bxor = (bit32 and bit32.bxor) or function(a, b) 
            local p, c = 1, 0
            while a > 0 or b > 0 do
                local ra, rb = a % 2, b % 2
                if ra ~= rb then c = c + p end
                a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
            end
            return c
        end

		if type(arr) == "table" and type(map) == "table" then
            for i = 1, #arr do
                local data = arr[i];
                if type(data) == "string" then
                    local xored = ""; local j = 1;
                    while j <= #data do
                        local c = string.sub(data, j, j);
                        local orig = map[c];
                        if orig then xored = xored .. orig; j = j + 1;
                        elseif c == "\\" then
                            local b = tonumber(string.sub(data, j + 1, j + 3));
                            if b then xored = xored .. string.char(b); j = j + 4; else xored = xored .. c; j = j + 1; end
                        else xored = xored .. c; j = j + 1; end
                    end
                    local res = {};
                    for k = 1, #xored do table.insert(res, string.char(bxor(string.byte(xored, k, k), xorKey))) end
                    arr[i] = table.concat(res);
                end
            end
        end
	end
]];

	local parser = Parser:new({ LuaVersion = LuaVersion.Lua51 });
	local newAst = parser:parse(xorDecodeCode);
	local forStat = newAst.body.statements[1];
	forStat.body.scope:setParent(ast.body.scope);

	visitast(newAst, nil, function(node, data)
		if(node.kind == AstKind.VariableExpression) then
			if(node.scope:getVariableName(node.id) == "ARR") then
				node.scope = self.rootScope; node.id = self.arrId;
            elseif(node.scope:getVariableName(node.id) == "REV_MAP") then
                node.scope = self.rootScope; node.id = self.mapId;
            elseif(node.scope:getVariableName(node.id) == "XOR_KEY") then
                local knode = SafeNumber(self.xorKey)
                return knode
			end
		end
	end)
	table.insert(ast.body.statements, 1, forStat);
end

function ConstantArray:apply(ast, pipeline)
	self.rootScope = ast.body.scope;
	self.arrId     = self.rootScope:addVariable();
    self.mapId     = self.rootScope:addVariable();
	self.constants = {};
	self.lookup    = {};

	visitast(ast, nil, function(node, data)
		if math.random() <= self.Treshold then
			if node.kind == AstKind.StringExpression then
				node.__apply_constant_array = true;
				self:addConstant(node.value);
			elseif not self.StringsOnly and node.isConstant and node.value ~= nil then
				node.__apply_constant_array = true;
				self:addConstant(node.value);
			end
		end
	end);

	if self.Shuffle then
		self.constants = util.shuffle(self.constants);
		self.lookup = {};
		for i, v in ipairs(self.constants) do self.lookup[v] = i; end
	end

	self.wrapperOffset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset);
	self.wrapperId     = self.rootScope:addVariable();

	visitast(ast, function(node, data)
		if self.LocalWrapperCount > 0 and node.kind == AstKind.Block and node.isFunctionBlock and math.random() <= self.LocalWrapperTreshold then
			local id = node.scope:addVariable()
			data.functionData.local_wrappers = { id = id, scope = node.scope };
			for i = 1, self.LocalWrapperCount do
				data.functionData.local_wrappers[i] = { arg = math.random(1, self.LocalWrapperArgCount), index = callNameGenerator(pipeline), offset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset) };
			end
		end
	end, function(node, data)
		if node.__apply_constant_array then
			node.__apply_constant_array = nil;
            if node.kind == AstKind.StringExpression or (not self.StringsOnly and node.isConstant) then
                local replacement = self:getConstant(node.value, data)
                if replacement then return replacement end
            end
		end
	end);

	self:addDecodeCode(ast);
    
    local funcScope = Scope:new(self.rootScope)
    local arg = funcScope:addVariable()
    
    -- Injected Wrapper with runtime check to prevent indexing numbers
    table.insert(ast.body.statements, 1, Ast.LocalFunctionDeclaration(self.rootScope, self.wrapperId, {Ast.VariableExpression(funcScope, arg)}, Ast.Block({
        Ast.ReturnStatement({
            Ast.IndexExpression(
                Ast.VariableExpression(self.rootScope, self.arrId), 
                Ast.AddExpression(Ast.VariableExpression(funcScope, arg), SafeNumber(self.wrapperOffset))
            )
        })
    }, funcScope)))

	table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.rootScope, {self.arrId}, {self:createArray()}));
end

return ConstantArray;
