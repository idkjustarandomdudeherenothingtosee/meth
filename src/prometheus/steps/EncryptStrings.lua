-- EncryptStrings.lua - Working Simple Version
-- Uses only documented Prometheus APIs

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitast = require("prometheus.visitast")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Simple string encryption using base64 encoding"
EncryptStrings.Name = "Encrypt Strings (Base64)"

function EncryptStrings:init(settings) end

function EncryptStrings:CreateEncryptionService()
    -- Base64 character set (URL-safe)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
    
    -- Simple XOR encryption with base64 encoding
    local function encrypt_string(str)
        local key = math.random(1, 255)
        local encoded = {}
        
        for i = 1, #str do
            local byte = string.byte(str, i)
            local encrypted = byte ~ key
            
            -- Convert to base64 (2 chars per byte)
            local high = math.floor(encrypted / 64)
            local low = encrypted % 64
            
            table.insert(encoded, chars:sub(high + 1, high + 1))
            table.insert(encoded, chars:sub(low + 1, low + 1))
        end
        
        return table.concat(encoded), key
    end
    
    -- Create a simple decryption function as AST
    local function createDecryptorAst(encoded_str, key, scope)
        -- This creates: function() return decrypted_string end
        
        local func_scope = Scope:new(scope)
        
        -- Build decryption logic
        local result_var = func_scope:addVariable("result")
        local key_var = func_scope:addVariable("key")
        
        -- Start with empty string
        local init_result = Ast.LocalVariableDeclaration(
            func_scope,
            {result_var},
            {Ast.StringExpression("")}
        )
        
        -- Set key
        local init_key = Ast.LocalVariableDeclaration(
            func_scope,
            {key_var},
            {Ast.NumberExpression(key)}
        )
        
        -- Create for loop
        local i_var = func_scope:addVariable("i")
        local for_loop = {
            kind = AstKind.ForNumericStatement,
            variable = i_var,
            start = Ast.NumberExpression(1),
            finish = Ast.NumberExpression(#encoded_str),
            step = Ast.NumberExpression(2),
            body = {
                kind = AstKind.Block,
                scope = func_scope,
                statements = {}
            }
        }
        
        -- Add loop body statements
        local loop_scope = for_loop.body.scope
        
        -- Get two chars: encoded_str:sub(i, i+1)
        local substr_call = Ast.FunctionCallExpression(
            Ast.IndexExpression(
                Ast.StringExpression(encoded_str),
                Ast.StringExpression("sub")
            ),
            {
                Ast.VariableExpression(loop_scope, i_var),
                Ast.BinaryOperatorExpression(
                    "+",
                    Ast.VariableExpression(loop_scope, i_var),
                    Ast.NumberExpression(1)
                )
            }
        )
        
        local chars_var = loop_scope:addVariable("chars")
        table.insert(for_loop.body.statements, Ast.LocalVariableDeclaration(
            loop_scope,
            {chars_var},
            {substr_call}
        ))
        
        -- Get first char index
        local high_char = Ast.IndexExpression(
            Ast.StringExpression(chars),
            Ast.FunctionCallExpression(
                Ast.IndexExpression(
                    Ast.VariableExpression(loop_scope, chars_var),
                    Ast.StringExpression("sub")
                ),
                {Ast.NumberExpression(1), Ast.NumberExpression(1)}
            )
        )
        
        local high_var = loop_scope:addVariable("high")
        table.insert(for_loop.body.statements, Ast.LocalVariableDeclaration(
            loop_scope,
            {high_var},
            {Ast.BinaryOperatorExpression(
                "-",
                Ast.FunctionCallExpression(
                    Ast.IndexExpression(
                        Ast.StringExpression(chars),
                        Ast.StringExpression("find")
                    ),
                    {high_char, Ast.StringExpression(chars)}
                ),
                Ast.NumberExpression(1)
            )}
        ))
        
        -- Get second char index
        local low_char = Ast.IndexExpression(
            Ast.StringExpression(chars),
            Ast.FunctionCallExpression(
                Ast.IndexExpression(
                    Ast.VariableExpression(loop_scope, chars_var),
                    Ast.StringExpression("sub")
                ),
                {Ast.NumberExpression(2), Ast.NumberExpression(2)}
            )
        )
        
        local low_var = loop_scope:addVariable("low")
        table.insert(for_loop.body.statements, Ast.LocalVariableDeclaration(
            loop_scope,
            {low_var},
            {Ast.BinaryOperatorExpression(
                "-",
                Ast.FunctionCallExpression(
                    Ast.IndexExpression(
                        Ast.StringExpression(chars),
                        Ast.StringExpression("find")
                    ),
                    {low_char, Ast.StringExpression(chars)}
                ),
                Ast.NumberExpression(1)
            )}
        ))
        
        -- Calculate encrypted value
        local encrypted_var = loop_scope:addVariable("encrypted")
        table.insert(for_loop.body.statements, Ast.LocalVariableDeclaration(
            loop_scope,
            {encrypted_var},
            {Ast.BinaryOperatorExpression(
                "+",
                Ast.BinaryOperatorExpression(
                    "*",
                    Ast.VariableExpression(loop_scope, high_var),
                    Ast.NumberExpression(64)
                ),
                Ast.VariableExpression(loop_scope, low_var)
            )}
        ))
        
        -- Decrypt
        local decrypted_var = loop_scope:addVariable("decrypted")
        table.insert(for_loop.body.statements, Ast.LocalVariableDeclaration(
            loop_scope,
            {decrypted_var},
            {Ast.BinaryOperatorExpression(
                "~",
                Ast.VariableExpression(loop_scope, encrypted_var),
                Ast.VariableExpression(loop_scope, key_var)
            )}
        ))
        
        -- Convert to char and append
        local char_var = loop_scope:addVariable("char")
        table.insert(for_loop.body.statements, Ast.LocalVariableDeclaration(
            loop_scope,
            {char_var},
            {Ast.FunctionCallExpression(
                Ast.IndexExpression(
                    Ast.StringExpression("string"),
                    Ast.StringExpression("char")
                ),
                {Ast.VariableExpression(loop_scope, decrypted_var)}
            )}
        ))
        
        -- result = result .. char
        table.insert(for_loop.body.statements, Ast.AssignmentStatement(
            loop_scope,
            {Ast.VariableExpression(loop_scope, result_var)},
            {Ast.BinaryOperatorExpression(
                "..",
                Ast.VariableExpression(loop_scope, result_var),
                Ast.VariableExpression(loop_scope, char_var)
            )}
        ))
        
        -- Build function body
        local body_statements = {
            init_result,
            init_key,
            for_loop,
            Ast.ReturnStatement(func_scope, {Ast.VariableExpression(func_scope, result_var)})
        }
        
        -- Create function expression
        return Ast.FunctionExpression(
            func_scope,
            {},  -- No parameters
            {kind = AstKind.Block, scope = func_scope, statements = body_statements}
        )
    end
    
    return {
        encrypt = encrypt_string,
        createDecryptorAst = createDecryptorAst,
        chars = chars
    }
end

function EncryptStrings:apply(ast, pipeline)
    local Encryptor = self:CreateEncryptionService()
    local scope = ast.body.scope
    
    -- Collect all string literals
    local string_literals = {}
    
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and not node.IsGenerated then
            table.insert(string_literals, node)
        end
    end)
    
    -- Create a string table
    local string_table_var = scope:addVariable("__str_table")
    
    -- Build table entries
    local table_entries = {}
    
    for i, str_node in ipairs(string_literals) do
        local encoded, key = Encryptor.encrypt(str_node.value)
        
        -- Create decryptor function for this string
        local decryptor_func = Encryptor.createDecryptorAst(encoded, key, scope)
        
        -- Immediately call the function
        local func_call = Ast.FunctionCallExpression(decryptor_func, {})
        
        -- Add to table: [i] = (function() ... end)()
        table.insert(table_entries, {
            kind = AstKind.TableEntry,
            key = Ast.NumberExpression(i),
            value = func_call
        })
        
        -- Mark the original node for replacement
        str_node.replace_with_index = i
    end
    
    -- Create the string table
    local string_table = {
        kind = AstKind.TableExpression,
        scope = scope,
        entries = table_entries
    }
    
    -- Add string table at the beginning
    table.insert(ast.body.statements, 1, {
        kind = AstKind.LocalVariableDeclaration,
        scope = scope,
        variables = {string_table_var},
        init = {string_table}
    })
    
    -- Replace string literals with table lookups
    visitast(ast, nil, function(node)
        if node.kind == AstKind.StringExpression and node.replace_with_index then
            -- Replace with: __str_table[index]
            return {
                kind = AstKind.IndexExpression,
                scope = scope,
                base = Ast.VariableExpression(scope, string_table_var),
                index = Ast.NumberExpression(node.replace_with_index),
                IsGenerated = true
            }
        end
    end)
    
    return ast
end

return EncryptStrings
