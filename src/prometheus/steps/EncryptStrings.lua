-- EncryptStrings.lua - Lua 5.4 Compatible Version
-- Uses hexadecimal escapes to ensure compatibility with Lua 5.4's stricter string parsing

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local Parser = require("prometheus.parser")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local util = require("prometheus.util")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Encrypts strings and converts bytes into unique hexadecimal escape sequences."
EncryptStrings.Name = "Encrypt Strings (Lua 5.4 Hex Escape)"

function EncryptStrings:init(settings) end

function EncryptStrings:CreateEncryptionService()
    local usedSeeds = {}
    
    -- Use a mix of alphanumeric and safe symbols to avoid Lua parsing issues
    local syms = {
        "A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
        "a","b","c","d","e","f","g","h","i","j","k","l","m","n","o","p","q","r","s","t","u","v","w","x","y","z",
        "0","1","2","3","4","5","6","7","8","9"
    }
    
    -- Generate unique 2-character sequences for each byte (0-255)
    -- 62^2 = 3844 possible sequences, more than enough for 256 bytes
    local byteToSymbol = {}
    local symbolToByte = {}
    
    for byte = 0, 255 do
        local idx1 = math.floor(byte / #syms) + 1
        local idx2 = (byte % #syms) + 1
        local seq = syms[idx1] .. syms[idx2]
        byteToSymbol[byte] = seq
        symbolToByte[seq] = byte
    end

    -- Random keys for encryption
    local secret_key_6 = math.random(0, 63)
    local secret_key_7 = math.random(0, 127)
    local secret_key_44 = math.random(0, 17592186044415)
    local secret_key_8 = math.random(0, 255)

    local floor = math.floor
    local function primitive_root_257(idx)
        local g, m, d = 1, 128, 2 * idx + 1
        repeat
            g = g * g * (d >= m and 3 or 1) % 257
            m = m / 2
            d = d % m
        until m < 1
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
        repeat
            state_8 = state_8 * param_mul_8 % 257
        until state_8 ~= 1
        
        local r = state_8 % 32
        local n = floor(state_45 / 2 ^ (13 - (state_8 - r) / 32)) % 2 ^ 32 / 2 ^ r
        return floor(n % 1 * 2 ^ 32) + floor(n)
    end

    local function get_next_pseudo_random_byte()
        if #prev_values == 0 then
            local rnd = get_random_32()
            prev_values = {
                rnd % 256,
                floor(rnd / 256) % 256,
                floor(rnd / 65536) % 256,
                floor(rnd / 16777216) % 256
            }
        end
        return table.remove(prev_values, 1)
    end

    local function encrypt(str)
        local seed = math.random(0, 35184372088832)
        set_seed(seed)
        
        local out_chunks = {}
        local prevVal = secret_key_8
        
        for i = 1, #str do
            local byte = string.byte(str, i)
            local encryptedByte = (byte - (get_next_pseudo_random_byte() + prevVal)) % 256
            table.insert(out_chunks, byteToSymbol[encryptedByte])
            prevVal = byte
        end
        
        -- Convert to hexadecimal escape sequences for Lua 5.4 compatibility
        local concatenated = table.concat(out_chunks)
        local hex_escaped = ""
        
        for j = 1, #concatenated do
            local char = concatenated:sub(j, j)
            local byte = string.byte(char)
            -- Use \xHH format for all non-alphanumeric characters to be safe
            if (byte >= 48 and byte <= 57) or    -- 0-9
               (byte >= 65 and byte <= 90) or    -- A-Z
               (byte >= 97 and byte <= 122) then -- a-z
                hex_escaped = hex_escaped .. char
            else
                hex_escaped = hex_escaped .. string.format("\\x%02X", byte)
            end
        end
        
        return hex_escaped, seed
    end

    local function genCode()
        -- Build the symbol map using hexadecimal escapes for safety
        local mapLines = {}
        
        for seq, byte in pairs(symbolToByte) do
            -- Escape each character in the sequence
            local escapedSeq = ""
            for i = 1, #seq do
                local char = seq:sub(i, i)
                local byte = string.byte(char)
                escapedSeq = escapedSeq .. string.format("\\x%02X", byte)
            end
            
            table.insert(mapLines, string.format("[%q]=%d", escapedSeq, byte))
        end
        
        local mapStr = "local symMap = {\n    " .. table.concat(mapLines, ",\n    ") .. "\n}"
        
        return mapStr .. [[

do
    ]] .. mapStr .. [[
    
    local floor, char, sub = math.floor, string.char, string.sub
    local state_45, state_8, prev_values = 0, 2, {}
    
    local function get_next_pseudo()
        if #prev_values == 0 then
            state_45 = (state_45 * ]] .. param_mul_45 .. [[ + ]] .. param_add_45 .. [[) % 35184372088832
            repeat
                state_8 = state_8 * ]] .. param_mul_8 .. [[ % 257
            until state_8 ~= 1
            
            local r = state_8 % 32
            local n = floor(state_45 / 2 ^ (13 - (state_8 - r) / 32)) % 2 ^ 32 / 2 ^ r
            local rnd = floor(n % 1 * 2 ^ 32) + floor(n)
            prev_values = {
                rnd % 256,
                floor(rnd / 256) % 256,
                floor(rnd / 65536) % 256,
                floor(rnd / 16777216) % 256
            }
        end
        return table.remove(prev_values, 1)
    end
    
    local cache = {}
    STRINGS = setmetatable({}, {
        __index = function(t, key)
            return cache[key]
        end
    })
    
    function DECRYPT(hexStr, seed)
        if cache[seed] then
            return seed
        end
        
        -- Reset PRNG state
        state_45 = seed % 35184372088832
        state_8 = seed % 255 + 2
        prev_values = {}
        
        -- Convert hex escape string back to symbol sequence
        local symbolStr = hexStr:gsub("\\x(%x%x)", function(hex)
            return string.char(tonumber(hex, 16))
        end)
        
        local res = {}
        local prevVal = ]] .. secret_key_8 .. [[
        
        -- Process in chunks of 2 characters (each symbol)
        for i = 1, #symbolStr, 2 do
            local symbol = sub(symbolStr, i, i + 1)
            local encryptedByte = symMap[symbol]
            
            if encryptedByte == nil then
                error("Invalid symbol in encrypted string: " .. symbol)
            end
            
            prevVal = (encryptedByte + get_next_pseudo() + prevVal) % 256
            table.insert(res, char(prevVal))
        end
        
        cache[seed] = table.concat(res)
        return seed
    end
end]]
    end

    return {
        encrypt = encrypt,
        genCode = genCode,
        byteToSymbol = byteToSymbol,
        symbolToByte = symbolToByte
    }
end

function EncryptStrings:apply(ast, pipeline)
    local Encryptor = self:CreateEncryptionService()
    
    -- Parse the decryption code into AST
    local newAst = Parser:new({ LuaVersion = Enums.LuaVersion.Lua54 }):parse(Encryptor.genCode())
    local doStat = newAst.body.statements[1]
    local scope = ast.body.scope
    
    -- Add variables for the decrypt function and strings table
    local decryptVar = scope:addVariable()
    local stringsVar = scope:addVariable()
    
    -- Set parent scope for the new code
    doStat.body.scope:setParent(scope)
    
    -- Rename internal variables to use the generated variable names
    visitast(newAst, nil, function(node, data)
        if node.kind == AstKind.FunctionDeclaration and node.scope:getVariableName(node.id) == "DECRYPT" then
            node.id = decryptVar
        elseif (node.kind == AstKind.AssignmentVariable or node.kind == AstKind.VariableExpression) and
               node.scope:getVariableName(node.id) == "STRINGS" then
            node.id = stringsVar
        end
    end)
    
    -- Replace all string literals with decrypt calls
    visitast(ast, nil, function(node, data)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local encrypted, seed = Encryptor.encrypt(node.value)
            
            -- Create a call to DECRYPT(encrypted, seed)
            local decryptCall = Ast.FunctionCallExpression(
                Ast.VariableExpression(scope, decryptVar),
                {
                    Ast.StringExpression(encrypted),
                    Ast.NumberExpression(seed)
                }
            )
            
            -- Create index expression: STRINGS[DECRYPT(...)]
            local indexExpr = Ast.IndexExpression(
                Ast.VariableExpression(scope, stringsVar),
                decryptCall
            )
            
            indexExpr.IsGenerated = true
            return indexExpr
        end
    end)
    
    -- Insert the decryption code at the beginning
    table.insert(ast.body.statements, 1, doStat)
    table.insert(ast.body.statements, 1, Ast.LocalVariableDeclaration(scope, {decryptVar, stringsVar}, {}))
end

return EncryptStrings
