-- EncryptStrings.lua - Production string encryption for Lua 5.1-5.4 and Luau
local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local visitast = require("prometheus.visitast")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Encrypts string literals using multiple layers of encryption"
EncryptStrings.Name = "String Encryption"

-- XOR encryption with rotating key
local function xor_encrypt(data, key)
    local encrypted = {}
    local key_len = #key
    for i = 1, #data do
        local byte = data:byte(i)
        local key_byte = key:byte((i - 1) % key_len + 1)
        encrypted[i] = string.char(bit32.bxor(byte, key_byte))
    end
    return table.concat(encrypted)
end

-- Base64 encoding (Lua 5.1-5.4 compatible)
local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64_encode(data)
    local bytes = {data:byte(1, -1)}
    local result = {}
    
    for i = 1, #bytes, 3 do
        local a, b, c = bytes[i], bytes[i + 1] or 0, bytes[i + 2] or 0
        local n = a * 0x10000 + b * 0x100 + c
        
        result[#result + 1] = b64chars:sub(math.floor(n / 0x40000) % 64 + 1, math.floor(n / 0x40000) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 0x1000) % 64 + 1, math.floor(n / 0x1000) % 64 + 1)
        result[#result + 1] = b64chars:sub(math.floor(n / 0x40) % 64 + 1, math.floor(n / 0x40) % 64 + 1)
        result[#result + 1] = b64chars:sub(n % 64 + 1, n % 64 + 1)
    end
    
    local padding = 3 - (#bytes + 2) % 3
    if padding == 2 then
        result[#result] = '='
        result[#result - 1] = '='
    elseif padding == 1 then
        result[#result] = '='
    end
    
    return table.concat(result)
end

-- Byte array encoding for Lua 5.1-5.4 compatibility
local function byte_array_encode(data)
    local bytes = {}
    for i = 1, #data do
        bytes[#bytes + 1] = string.format("0x%02X", data:byte(i))
    end
    return "{" .. table.concat(bytes, ",") .. "}"
end

-- Caesar cipher with variable shift
local function caesar_cipher(data, shift)
    local result = {}
    for i = 1, #data do
        local byte = data:byte(i)
        result[i] = string.char((byte + shift) % 256)
    end
    return table.concat(result)
end

-- Generate a runtime decryption key (obfuscated)
local function generate_decryption_key()
    local keys = {
        "0x6B,0x65,0x79,0x31",  -- "key1"
        "0x73,0x65,0x63,0x72,0x65,0x74",  -- "secret"
        "0x70,0x61,0x73,0x73,0x77,0x6F,0x72,0x64",  -- "password"
        "0x65,0x6E,0x63,0x72,0x79,0x70,0x74",  -- "encrypt"
    }
    
    local key_parts = {}
    for _, key in ipairs(keys) do
        key_parts[#key_parts + 1] = "string.char(" .. key .. ")"
    end
    
    return table.concat(key_parts, "..")
end

-- Create decryption function AST
local function create_decryption_function()
    -- Generate a unique function name to avoid collisions
    local func_name = "__decrypt_" .. math.random(10000, 99999)
    
    -- Build the decryption function source code
    local source = [[
local function ]] .. func_name .. [[(encrypted, key_index)
    -- XOR decryption with multiple keys
    local keys = {
        ]] .. generate_decryption_key() .. [[,
        ]] .. generate_decryption_key() .. [[,
        ]] .. generate_decryption_key() .. [[
    }
    
    local key = keys[(key_index or 1) % #keys + 1]
    local result = {}
    
    for i = 1, #encrypted do
        local e = encrypted:byte(i)
        local k = key:byte((i - 1) % #key + 1)
        result[i] = string.char(bit32.bxor(e, k))
    end
    
    return table.concat(result)
end

local function ]] .. func_name .. [[_b64(data, key_idx)
    -- Base64 decode then decrypt
    local b64_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local char_to_value = {}
    for i = 1, 64 do
        char_to_value[b64_chars:sub(i, i)] = i - 1
    end
    
    -- Remove padding
    data = data:gsub('=', '')
    
    local bytes = {}
    for i = 1, #data, 4 do
        local a = char_to_value[data:sub(i, i)] or 0
        local b = char_to_value[data:sub(i + 1, i + 1)] or 0
        local c = char_to_value[data:sub(i + 2, i + 2)] or 0
        local d = char_to_value[data:sub(i + 3, i + 3)] or 0
        
        local n = a * 0x40000 + b * 0x1000 + c * 0x40 + d
        
        bytes[#bytes + 1] = string.char(math.floor(n / 0x10000) % 256)
        bytes[#bytes + 1] = string.char(math.floor(n / 0x100) % 256)
        bytes[#bytes + 1] = string.char(n % 256)
    end
    
    local encoded = table.concat(bytes)
    -- Remove null bytes from padding
    encoded = encoded:gsub('%z+$', '')
    
    return ]] .. func_name .. [[(encoded, key_idx)
end

local function ]] .. func_name .. [[_bytes(byte_array, key_idx, shift)
    -- Convert byte array to string then decrypt
    local bytes = {}
    for byte in byte_array:gmatch('0x(%x%x)') do
        bytes[#bytes + 1] = string.char(tonumber(byte, 16))
    end
    
    local data = table.concat(bytes)
    
    -- Reverse Caesar cipher if shift was applied
    if shift then
        local result = {}
        for i = 1, #data do
            local byte = data:byte(i)
            result[i] = string.char((byte - shift) % 256)
        end
        data = table.concat(result)
    end
    
    return ]] .. func_name .. [[(data, key_idx)
end

return {
    xor = ]] .. func_name .. [[,
    b64 = ]] .. func_name .. [[_b64,
    bytes = ]] .. func_name .. [[_bytes
}
]]
    
    return source, func_name
end

function EncryptStrings:init(settings)
    self.settings = settings or {}
    self.encryption_method = settings.method or "layered"  -- "xor", "base64", "bytes", or "layered"
    self.obfuscate = settings.obfuscate ~= false
    self.min_length = settings.min_length or 3  -- Minimum string length to encrypt
    
    -- Initialize random seed for key rotation
    math.randomseed(os.time())
end

function EncryptStrings:apply(ast, pipeline)
    -- Create decryption function
    local decrypt_source, func_name = create_decryption_function()
    local decryption_func_added = false
    
    -- Store all transformations to apply at once
    local transformations = {}
    
    -- Visit AST and collect string transformations
    visitast(ast, nil, function(node, parent, index)
        if node.kind == AstKind.StringExpression and node.value then
            local str_value = node.value
            
            -- Skip short strings
            if #str_value < self.min_length then
                return
            end
            
            -- Skip strings that look like format patterns
            if str_value:match("%%[sdgf])") then
                return
            end
            
            -- Choose encryption method
            local encrypted_value
            local call_expression
            local method = self.encryption_method
            
            if method == "layered" then
                -- Multi-layer encryption
                local key_index = math.random(1, 3)
                local shift = math.random(1, 25)
                
                -- Layer 1: XOR
                local xor_key = "encrypt_key_" .. math.random(1000, 9999)
                local layer1 = xor_encrypt(str_value, xor_key)
                
                -- Layer 2: Caesar cipher
                local layer2 = caesar_cipher(layer1, shift)
                
                -- Layer 3: Base64
                encrypted_value = base64_encode(layer2)
                
                -- Create call to decryption function
                call_expression = Ast.CallExpression(
                    Ast.Identifier(func_name .. ".b64"),
                    {
                        Ast.StringExpression(encrypted_value),
                        Ast.NumberExpression(key_index),
                        Ast.NumberExpression(shift)
                    }
                )
                
            elseif method == "base64" then
                -- Base64 only
                local key_index = math.random(1, 3)
                local xor_key = "key_" .. math.random(100, 999)
                local xored = xor_encrypt(str_value, xor_key)
                encrypted_value = base64_encode(xored)
                
                call_expression = Ast.CallExpression(
                    Ast.Identifier(func_name .. ".b64"),
                    {
                        Ast.StringExpression(encrypted_value),
                        Ast.NumberExpression(key_index)
                    }
                )
                
            elseif method == "bytes" then
                -- Byte array encoding
                local key_index = math.random(1, 3)
                local shift = math.random(1, 25)
                local xored = xor_encrypt(str_value, "byte_key")
                local shifted = caesar_cipher(xored, shift)
                encrypted_value = byte_array_encode(shifted)
                
                call_expression = Ast.CallExpression(
                    Ast.Identifier(func_name .. ".bytes"),
                    {
                        Ast.StringExpression(encrypted_value),
                        Ast.NumberExpression(key_index),
                        Ast.NumberExpression(shift)
                    }
                )
                
            else  -- "xor" default
                -- Simple XOR encryption
                local key_index = math.random(1, 3)
                local xor_key = "xor_key_" .. math.random(100, 999)
                encrypted_value = xor_encrypt(str_value, xor_key)
                
                call_expression = Ast.CallExpression(
                    Ast.Identifier(func_name .. ".xor"),
                    {
                        Ast.StringExpression(encrypted_value),
                        Ast.NumberExpression(key_index)
                    }
                )
            end
            
            -- Store transformation
            if call_expression then
                table.insert(transformations, {
                    parent = parent,
                    index = index,
                    replacement = call_expression
                })
                
                -- Mark that we need to add the decryption function
                decryption_func_added = true
            end
        end
    end)
    
    -- Apply all transformations
    for _, trans in ipairs(transformations) do
        if trans.parent.body then
            if type(trans.parent.body) == "table" and trans.parent.body.kind then
                -- Single child
                trans.parent.body = trans.replacement
            elseif type(trans.parent.body) == "table" then
                -- Array of children
                trans.parent.body[trans.index] = trans.replacement
            end
        elseif trans.parent.expression then
            trans.parent.expression = trans.replacement
        elseif trans.parent.value then
            trans.parent.value = trans.replacement
        end
    end
    
    -- Add decryption function to the beginning of the script
    if decryption_func_added then
        -- Parse the decryption function source into AST
        -- Note: This assumes we have access to a parser in the pipeline
        -- If not, we'll need to add it as a string literal that gets executed
        
        -- For now, create a dummy assignment to mark where decryption code should be inserted
        local decrypt_var = Ast.VariableDeclaration({
            Ast.VariableDeclarator(
                Ast.Identifier("__string_decrypt_func"),
                Ast.StringExpression(decrypt_source)
            )
        })
        
        -- Insert at the beginning of the body
        if ast.body and type(ast.body) == "table" then
            if ast.body.kind then
                -- Single statement body
                local original = ast.body
                ast.body = {
                    decrypt_var,
                    original
                }
            else
                -- Multiple statements
                table.insert(ast.body, 1, decrypt_var)
            end
        end
    end
    
    return ast
end

return EncryptStrings
