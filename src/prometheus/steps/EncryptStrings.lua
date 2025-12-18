-- EncryptStrings.lua - Minimal Version
-- Doesn't generate code, just encrypts strings directly

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local Enums = require("prometheus.enums")
local visitast = require("prometheus.visitast")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Encrypts strings with simple XOR encryption"
EncryptStrings.Name = "Encrypt Strings (Simple)"

function EncryptStrings:init(settings) end

function EncryptStrings:CreateEncryptionService()
    -- Create a simple XOR-based encryption
    local function encrypt_string(str)
        -- Generate a random key
        local key = math.random(1, 255)
        -- Generate a random seed for variation
        local seed = math.random(1, 255)
        
        local encrypted_chars = {}
        local hex_result = {}
        
        -- Convert to hex string for safety
        for i = 1, #str do
            local byte = string.byte(str, i)
            -- XOR with key and add seed for variation
            local encrypted = (byte ~ key) + seed
            -- Make sure it stays in byte range
            encrypted = encrypted % 256
            -- Convert to hex
            table.insert(hex_result, string.format("%02X", encrypted))
        end
        
        -- Return hex string, key, and seed
        return table.concat(hex_result), key, seed
    end
    
    -- Generate inline decryption code as an expression
    local function createDecryptionExpression(hex_str, key, seed)
        -- This creates an anonymous function that decrypts when called
        local code = string.format([[
            (function()
                local hex = "%s"
                local key = %d
                local seed = %d
                local result = ""
                
                for i = 1, #hex, 2 do
                    local hex_byte = hex:sub(i, i + 1)
                    local encrypted = tonumber(hex_byte, 16)
                    local decrypted = (encrypted - seed) %% 256
                    local char = string.char(decrypted ~ key)
                    result = result .. char
                end
                
                return result
            end)()
        ]], hex_str, key, seed)
        
        return code
    end
    
    return {
        encrypt = encrypt_string,
        createDecryptionExpression = createDecryptionExpression
    }
end

function EncryptStrings:apply(ast, pipeline)
    local Encryptor = self:CreateEncryptionService()
    
    -- Track all encrypted strings to create a lookup table
    local encrypted_strings = {}
    local string_id = 1
    
    -- First pass: collect all strings and encrypt them
    visitast(ast, nil, function(node, data)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            local hex_str, key, seed = Encryptor.encrypt(node.value)
            
            -- Store the encrypted string with metadata
            encrypted_strings[string_id] = {
                original = node.value,
                hex = hex_str,
                key = key,
                seed = seed,
                node = node
            }
            
            -- Mark the node with an ID for replacement
            node.string_id = string_id
            string_id = string_id + 1
        end
    end)
    
    -- Create a string table in the AST
    local scope = ast.body.scope
    
    -- Create a lookup table variable
    local string_table_var = scope:addVariable()
    
    -- Build the string table initialization
    local table_entries = {}
    
    for id, str_data in pairs(encrypted_strings) do
        -- Create the decryption function for this string
        local decryption_code = Encryptor.createDecryptionExpression(str_data.hex, str_data.key, str_data.seed)
        
        -- Parse this as an expression
        -- We'll create a simple function call instead
        local func_call = self:createInlineDecryptor(str_data.hex, str_data.key, str_data.seed, scope)
        
        table.insert(table_entries, Ast.TableEntry(
            scope,
            Ast.NumberExpression(id),
            func_call
        ))
    end
    
    -- Create the string table
    local string_table = Ast.TableExpression(scope, table_entries)
    
    -- Create variable declaration for the string table
    local table_declaration = Ast.LocalVariableDeclaration(
        scope,
        {string_table_var},
        {string_table}
    )
    
    -- Insert at the beginning
    table.insert(ast.body.statements, 1, table_declaration)
    
    -- Second pass: replace string literals with table lookups
    visitast(ast, nil, function(node, data)
        if node.kind == AstKind.StringExpression and not node.IsGenerated and node.string_id then
            -- Replace with: string_table[string_id]
            local index_expr = Ast.IndexExpression(
                Ast.VariableExpression(scope, string_table_var),
                Ast.NumberExpression(node.string_id)
            )
            
            index_expr.IsGenerated = true
            return index_expr
        end
    end)
    
    return ast
end

function EncryptStrings:createInlineDecryptor(hex_str, key, seed, scope)
    -- Create an anonymous function that decrypts the string
    -- (function() ... return decrypted_string end)()
    
    -- Create a new scope for the function
    local func_scope = Scope:new(scope)
    
    -- Create the function body
    local body_statements = {}
    
    -- hex = "hex_str"
    local hex_var = func_scope:addVariable()
    table.insert(body_statements, Ast.LocalVariableDeclaration(
        func_scope,
        {hex_var},
        {Ast.StringExpression(hex_str)}
    ))
    
    -- key = key_value
    local key_var = func_scope:addVariable()
    table.insert(body_statements, Ast.LocalVariableDeclaration(
        func_scope,
        {key_var},
        {Ast.NumberExpression(key)}
    ))
    
    -- seed = seed_value
    local seed_var = func_scope:addVariable()
    table.insert(body_statements, Ast.LocalVariableDeclaration(
        func_scope,
        {seed_var},
        {Ast.NumberExpression(seed)}
    ))
    
    -- result = ""
    local result_var = func_scope:addVariable()
    table.insert(body_statements, Ast.LocalVariableDeclaration(
        func_scope,
        {result_var},
        {Ast.StringExpression("")}
    ))
    
    -- Create a for loop: for i = 1, #hex, 2 do
    local i_var = func_scope:addVariable()
    
    local for_loop = Ast.ForNumericStatement(
        func_scope,
        i_var,
        Ast.NumberExpression(1),
        Ast.UnaryOperatorExpression("#", Ast.VariableExpression(func_scope, hex_var)),
        Ast.NumberExpression(2),
        Ast.Block(func_scope)
    )
    
    -- Loop body: decrypt each byte
    local hex_byte_var = for_loop.body.scope:addVariable()
    local encrypted_var = for_loop.body.scope:addVariable()
    local decrypted_var = for_loop.body.scope:addVariable()
    local char_var = for_loop.body.scope:addVariable()
    
    local loop_body = {
        -- hex_byte = hex:sub(i, i + 1)
        Ast.LocalVariableDeclaration(
            for_loop.body.scope,
            {hex_byte_var},
            {Ast.FunctionCallExpression(
                Ast.IndexExpression(
                    Ast.VariableExpression(for_loop.body.scope, hex_var),
                    Ast.StringExpression("sub")
                ),
                {
                    Ast.VariableExpression(for_loop.body.scope, i_var),
                    Ast.BinaryOperatorExpression(
                        "+",
                        Ast.VariableExpression(for_loop.body.scope, i_var),
                        Ast.NumberExpression(1)
                    )
                }
            )}
        ),
        
        -- encrypted = tonumber(hex_byte, 16)
        Ast.LocalVariableDeclaration(
            for_loop.body.scope,
            {encrypted_var},
            {Ast.FunctionCallExpression(
                Ast.VariableExpression(for_loop.body.scope, for_loop.body.scope:getVariable("tonumber")),
                {
                    Ast.VariableExpression(for_loop.body.scope, hex_byte_var),
                    Ast.NumberExpression(16)
                }
            )}
        ),
        
        -- decrypted = (encrypted - seed) % 256
        Ast.LocalVariableDeclaration(
            for_loop.body.scope,
            {decrypted_var},
            {Ast.BinaryOperatorExpression(
                "%",
                Ast.BinaryOperatorExpression(
                    "-",
                    Ast.VariableExpression(for_loop.body.scope, encrypted_var),
                    Ast.VariableExpression(for_loop.body.scope, seed_var)
                ),
                Ast.NumberExpression(256)
            )}
        ),
        
        -- char = string.char(decrypted ~ key)
        Ast.LocalVariableDeclaration(
            for_loop.body.scope,
            {char_var},
            {Ast.FunctionCallExpression(
                Ast.IndexExpression(
                    Ast.VariableExpression(for_loop.body.scope, for_loop.body.scope:getVariable("string")),
                    Ast.StringExpression("char")
                ),
                {Ast.BinaryOperatorExpression(
                    "~",
                    Ast.VariableExpression(for_loop.body.scope, decrypted_var),
                    Ast.VariableExpression(for_loop.body.scope, key_var)
                )}
            )}
        ),
        
        -- result = result .. char
        Ast.AssignmentStatement(
            for_loop.body.scope,
            {Ast.VariableExpression(for_loop.body.scope, result_var)},
            {Ast.BinaryOperatorExpression(
                "..",
                Ast.VariableExpression(for_loop.body.scope, result_var),
                Ast.VariableExpression(for_loop.body.scope, char_var)
            )}
        )
    }
    
    for_loop.body.statements = loop_body
    table.insert(body_statements, for_loop)
    
    -- return result
    table.insert(body_statements, Ast.ReturnStatement(
        func_scope,
        {Ast.VariableExpression(func_scope, result_var)}
    ))
    
    -- Create the anonymous function
    local func_expr = Ast.FunctionExpression(
        func_scope,
        {},  -- No parameters
        Ast.Block(func_scope, body_statements)
    )
    
    -- Call the function immediately: (function() ... end)()
    return Ast.FunctionCallExpression(func_expr, {})
end

return EncryptStrings
