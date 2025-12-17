-- EncryptStrings.lua - Symbol Mapping Edition
-- Maps every encrypted byte to a unique sequence of special characters.

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Encrypts strings and converts bytes into unique symbol sequences."
EncryptStrings.Name = "Encrypt Strings (Symbolic)"

function EncryptStrings:init(settings) end

function EncryptStrings:CreateEncrypionService()
    local usedSeeds = {}
    local syms = {"!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "-", "+", "=", "{", "}"}
    
    -- Generate a unique 3-character symbol sequence for every byte (0-255)
    local byteToSymbol = {}
    local symbolToByte = {}
    local count = 0
    for i = 1, #syms do
        for j = 1, #syms do
            for k = 1, #syms do
                if count <= 255 then
                    local seq = syms[i] .. syms[j] .. syms[k]
                    byteToSymbol[count] = seq
                    symbolToByte[seq] = count
                    count = count + 1
                end
            end
        end
    end

    local secret_key_6 = math.random(0, 63)
    local secret_key_7 = math.random(0, 127)
    local secret_key_44 = math.random(0, 17592186044415)
    local secret_key_8 = math.random(0, 255)

    local floor = math.floor
    local function primitive_root_257(idx)
        local g, m, d = 1, 128, 2 * idx + 1
        repeat g, m, d = g * g * (d >= m and 3 or 1) % 257, m / 2, d % m until m < 1
        return g
    end

    local param_mul_8 = primitive_root_257(secret_key_7)
    local param_mul_45 = secret_key_6 * 4 + 1
    local param_add_45 = secret_key_44 * 2 + 1
    local state_45, state_8 = 0, 2
    local prev_values = {}

    local function set_seed(seed_53)
        state_45 = seed_53 % 35184372088832
        state_8 = seed_53 % 255 + 2
        prev_values = {}
    end

    local function get_random_32()
        state_45 = (state_45 * param_mul_45 + param_add_45) % 35184372088832
        repeat state_8 = state_8 * param_mul_8 % 257 until state_8 ~= 1
        local r = state_8 % 32
        local n = floor(state_45 / 2 ^ (13 - (state_8 - r) / 32)) % 2 ^ 32 / 2 ^ r
        return floor(n % 1 * 2 ^ 32) + floor(n)
    end

    local function get_next_pseudo_random_byte()
        if #prev_values == 0 then
            local rnd = get_random_32()
            prev_values = { rnd % 256, floor(rnd / 256) % 256, floor(rnd / 65536) % 256, floor(rnd / 16777216) % 256 }
        end
        return table.remove(prev_values)
    end

    local function encrypt(str)
        local seed = math.random(0, 35184372088832)
        set_seed(seed)
        local out = {}
        local prevVal = secret_key_8
        for i = 1, #str do
            local byte = string.byte(str, i)
            local encryptedByte = (byte - (get_next_pseudo_random_byte() + prevVal)) % 256
            table.insert(out, byteToSymbol[encryptedByte])
            prevVal = byte
        end
        return table.concat(out), seed
    end

    local function genCode()
        -- Construct the Reverse Symbol Map for the Lua environment
        local mapStr = "local symMap = {"
        for seq, byte in pairs(symbolToByte) do
            mapStr = mapStr .. string.format("['%s']=%d,", seq, byte)
        end
        mapStr = mapStr .. "};"

        return [[
do
    ]] .. mapStr .. [[
    local floor, char, sub = math.floor, string.char, string.sub
    local state_45, state_8, prev_values = 0, 2, {}

    local function get_next_pseudo()
        if #prev_values == 0 then
            state_45 = (state_45 * ]] .. param_mul_45 .. [[ + ]] .. param_add_45 .. [[) % 35184372088832
            repeat state_8 = state_8 * ]] .. param_mul_8 .. [[ % 257 until state_8 ~= 1
            local r = state_8 % 32
            local n = floor(state_45 / 2 ^ (13 - (state_8 - r) / 32)) % 2 ^ 32 / 2 ^ r
            local rnd = floor(n % 1 * 2 ^ 32) + floor(n)
            prev_values = { rnd % 256, floor(rnd / 256) % 256, floor(rnd / 65536) % 256, floor(rnd / 16777216) % 256 }
        end
        return table.remove(prev_values)
    end

    local cache = {}
    STRINGS = setmetatable({}, {__index = cache})

    function DECRYPT(str, seed)
        if cache[seed] then return seed end
        state_45, state_8, prev_values = seed % 35184372088832, seed % 255 + 2, {}
        local res, prevVal = {}, ]] .. secret_key_8 .. [[
        for i = 1, #str, 3 do
            local sym = sub(str, i, i + 2)
            local encryptedByte = symMap[sym]
            prevVal = (encryptedByte + get_next_pseudo() + prevVal) % 256
            table.insert(res, char(prevVal))
        end
        cache[seed] = table.concat(res)
        return seed
    end
end]]
    end

    return { encrypt = encrypt, genCode = genCode }
end

function EncryptStrings:apply(ast, pipeline)
    local Encryptor = self:CreateEncrypionService()
    local newAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua51 }):parse(Encryptor.genCode())
    local doStat = newAst.body.statements[1]
    local scope = ast.body.scope
    local decryptVar, stringsVar = scope:addVariable(), scope:addVariable()
    
    doStat.body.scope:setParent(scope)

    -- Rename internal variables for obfuscation
    visitast(newAst, nil, function(node, data)
        if node.kind == AstKind.FunctionDeclaration and node.scope:getVariableName(node.id) == "DECRYPT" then
            node.id = decryptVar
        elseif (node.kind == AstKind.AssignmentVariable or node.kind == AstKind.VariableExpression) and node.scope:getVariableName(node.id) == "STRINGS" then
            node.id = stringsVar
        end
    end)

    -- Replace String Literals with Decrypt Calls
    visitast(ast, nil, function(node, data)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encrypted, seed = Encryptor.encrypt(node.value)
            local call = Ast.IndexExpression(
                Ast.VariableExpression(scope, stringsVar),
                Ast.FunctionCallExpression(Ast.VariableExpression(scope, decryptVar), {
                    Ast.StringExpression(encrypted),
                    Ast.NumberExpression(seed)
                })
            )
            call.IsGenerated = true
            return call
        end
    end)

    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(scope, {decryptVar, stringsVar}, {}))
end

return EncryptStrings
