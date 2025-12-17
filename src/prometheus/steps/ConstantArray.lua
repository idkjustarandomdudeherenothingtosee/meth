-- This Script is Part of the Prometheus Obfuscator by Levno_710
--
-- ConstantArray.lua - Strengthened for Luau & Lua 5.1 with Nil Safety
--
-- Provides XOR encoding, Symbolic Mapping, and compiler-safe escaping.

local Step = require("prometheus.step");
local Ast = require("prometheus.ast");
local Scope = require("prometheus.scope");
local visitast = require("prometheus.visitast");
local util     = require("prometheus.util")
local Parser   = require("prometheus.parser");
local enums = require("prometheus.enums")

local LuaVersion = enums.LuaVersion;
local AstKind = Ast.AstKind;

-- Bitwise XOR implementation for Lua 5.1 (Fallback for environments without bit32)
local function bxor(a, b)
    local p = 1
    local c = 0
    while a > 0 or b > 0 do
        local ra = a % 2
        local rb = b % 2
        if ra ~= rb then
            c = c + p
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        p = p * 2
    end
    return c
end

local ConstantArray = Step:extend();
ConstantArray.Description = "Extracts constants into a XOR-encoded, symbolic array with Luau-safe escaping.";
ConstantArray.Name = "Constant Array (Luau Safe)";

ConstantArray.SettingsDescriptor = {
    -- [Existing settings: Treshold, StringsOnly, Shuffle, Rotate, etc.]
	Treshold = { name = "Treshold", type = "number", default = 1 },
	StringsOnly = { name = "StringsOnly", type = "boolean", default = false },
	Shuffle = { name = "Shuffle", type = "boolean", default = true },
	Rotate = { name = "Rotate", type = "boolean", default = true },
	LocalWrapperTreshold = { name = "LocalWrapperTreshold", type = "number", default = 1 },
	LocalWrapperCount = { name = "LocalWrapperCount", type = "number", default = 0 },
	LocalWrapperArgCount = { name = "LocalWrapperArgCount", type = "number", default = 10 },
	MaxWrapperOffset = { name = "MaxWrapperOffset", type = "number", default = 65535 },
}

-- Symbol Mapping Table (Symbols chosen for maximum Luau/Lua compatibility)
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

function ConstantArray:init(settings)
    self.xorKey = math.random(1, 255);
end

function ConstantArray:createArray()
	local entries = {};
	for i, v in ipairs(self.constants) do
		if type(v) == "string" then
			v = self:encode(v);
		end
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
		"local arr = ARR;",
		"local type = type;",
		"local len = string.len;",
		"local sub = string.sub;",
		"local char = string.char;",
		"local concat = table.concat;",
		"local map = REV_MAP;",
        "local xorKey = XOR_KEY;"
	}) .. [[
        -- Safety Check: Luau environment might have bit32 or need fallback
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
                local encoded_data = arr[i];
                if type(encoded_data) == "string" then
                    local xored_string = "";
                    local j = 1;
                    while j <= len(encoded_data) do
                        local char_at = sub(encoded_data, j, j);
                        local original_char = map[char_at];
                        
                        if original_char then
                            xored_string = xored_string .. original_char;
                            j = j + 1;
                        elseif char_at == "\\" then
                            -- Safety: Handle Luau/Lua numeric escapes (\xxx)
                            local byte_str = sub(encoded_data, j + 1, j + 3);
                            local byte_val = tonumber(byte_str);
                            if byte_val then
                                xored_string = xored_string .. char(byte_val);
                                j = j + 4;
                            else
                                xored_string = xored_string .. char_at;
                                j = j + 1;
                            end
                        else
                            xored_string = xored_string .. char_at;
                            j = j + 1; 
                        end
                    end

                    local parts = {}
                    for k = 1, len(xored_string) do
                        local byte_value = string.byte(sub(xored_string, k, k));
                        table.insert(parts, char(bxor(byte_value, xorKey)));
                    end
                    arr[i] = concat(parts)
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
                return Ast.NumberExpression(self.xorKey);
			end
		end
	end)
	table.insert(ast.body.statements, 1, forStat);
end

function ConstantArray:encode(str)
    local xored_parts = {};
    for i = 1, #str do
        table.insert(xored_parts, string.char(bxor(string.byte(str, i), self.xorKey)));
    end

    local xored_string = table.concat(xored_parts);
    local symbolic_parts = {};

    for i = 1, #xored_string do
        local b = string.byte(xored_string, i);
        local char = string.char(b);
        local symbol = SYMBOL_MAP[char];

        if symbol then
            table.insert(symbolic_parts, symbol);
        elseif b < 32 or b > 126 or char == "\\" or char == "\"" or char == "'" then
            -- SAFETY FOR LUAU: Convert non-printable/unsafe chars to \xxx
            table.insert(symbolic_parts, string.format("\\%03d", b));
        else
            table.insert(symbolic_parts, char);
        end
    end

    return table.concat(symbolic_parts);
end

-- [Apply, indexing, getConstant, etc. logic remains consistent with previous version]
function ConstantArray:apply(ast, pipeline)
	self.rootScope = ast.body.scope;
	self.arrId     = self.rootScope:addVariable();
    self.mapId     = self.rootScope:addVariable();
	self.constants = {};
	self.lookup    = {};

    -- Extract constants and process array
	visitast(ast, nil, function(node, data)
		if math.random() <= self.Treshold then
			node.__apply_constant_array = true;
			if node.kind == AstKind.StringExpression then
				self:addConstant(node.value);
			elseif not self.StringsOnly and node.isConstant and node.value ~= nil then
				self:addConstant(node.value);
			end
		end
	end);

	if self.Shuffle then self.constants = util.shuffle(self.constants); self.lookup = {}; for i, v in ipairs(self.constants) do self.lookup[v] = i; end end
	self.wrapperOffset = math.random(-self.MaxWrapperOffset, self.MaxWrapperOffset);
	self.wrapperId     = self.rootScope:addVariable();

    -- Finalize AST modifications
	self:addDecodeCode(ast);
	table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(self.rootScope, {self.arrId}, {self:createArray()}));
end

return ConstantArray;
