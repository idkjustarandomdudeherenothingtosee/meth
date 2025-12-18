-- EncryptStrings.lua - Fortified Debug Version
-- Enhanced with comprehensive API exploration, defensive programming,
-- and advanced debugging capabilities

local Step = require("prometheus.step")
local Ast = require("prometheus.ast")
local Scope = require("prometheus.scope")
local visitast = require("prometheus.visitast")
local AstKind = Ast.AstKind

local EncryptStrings = Step:extend()
EncryptStrings.Description = "Fortified string transformation debugger with 100x enhanced diagnostics"
EncryptStrings.Name = "String Debug Fortified"
EncryptStrings.Version = "2.0.0"

-- Enhanced configuration with defensive defaults
function EncryptStrings:init(settings)
    self.settings = settings or {}
    self.debug_level = settings.debug_level or 3  -- 1=Minimal, 2=Normal, 3=Verbose, 4=Extreme
    self.max_samples = settings.max_samples or 10
    self.capture_metadata = settings.capture_metadata ~= false
    self.enable_stress_test = settings.enable_stress_test or false
    self.log_file = settings.log_file or "encrypt_strings_debug.log"
    
    -- Initialize logging system
    self.log_handle = io.open(self.log_file, "w")
    if self.log_handle then
        self.log_handle:write(string.format("[%s] EncryptStrings Debug Session Started\n", os.date()))
    end
end

-- Enhanced logging with multiple levels
function EncryptStrings:log(level, message, data)
    if level <= self.debug_level then
        local prefix = string.format("[L%d] %s: ", level, os.date("%H:%M:%S"))
        print(prefix .. message)
        
        if self.log_handle then
            self.log_handle:write(prefix .. message .. "\n")
            if data then
                self.log_handle:write("  Data: " .. vim.inspect(data, {depth = 3}) .. "\n")
            end
        end
    end
end

-- Comprehensive API exploration
function EncryptStrings:explore_api()
    self:log(1, "=== FORTIFIED API EXPLORATION ===")
    
    -- 1. AST Module Structure Analysis
    self:log(2, "Ast Module Structure:")
    local ast_functions = {}
    local ast_tables = {}
    local ast_constants = {}
    
    for k, v in pairs(Ast) do
        local t = type(v)
        if t == "function" then
            table.insert(ast_functions, k)
        elseif t == "table" then
            table.insert(ast_tables, k)
        else
            table.insert(ast_constants, k .. " = " .. tostring(v))
        end
    end
    
    self:log(3, string.format("  Functions (%d): %s", #ast_functions, table.concat(ast_functions, ", ")))
    self:log(3, string.format("  Tables (%d): %s", #ast_tables, table.concat(ast_tables, ", ")))
    self:log(3, string.format("  Constants (%d): %s", #ast_constants, table.concat(ast_constants, ", ")))
    
    -- 2. AstKind Deep Analysis
    self:log(2, "\nAstKind Enumeration (Complete):")
    local kind_groups = {}
    for k, v in pairs(AstKind) do
        local group = math.floor(v / 10) * 10
        kind_groups[group] = kind_groups[group] or {}
        table.insert(kind_groups[group], string.format("%s=%d", k, v))
    end
    
    for group, members in pairs(kind_groups) do
        table.sort(members)
        self:log(3, string.format("  Group %d-%d: %s", 
            group, group+9, table.concat(members, ", ")))
    end
    
    -- 3. Metatable Analysis
    self:log(2, "\nMetatable Analysis:")
    local mt = getmetatable(Ast)
    if mt then
        self:log(3, "Ast has metatable:")
        for k, v in pairs(mt) do
            self:log(4, "  " .. k .. ": " .. type(v))
        end
    else
        self:log(3, "No metatable found on Ast")
    end
    
    -- 4. Constructor Discovery
    self:log(2, "\nConstructor Discovery:")
    local constructors = {}
    for name, func in pairs(Ast) do
        if type(func) == "function" then
            local success, result = pcall(function()
                -- Try to call with minimal arguments
                if name:match("Expression$") or name:match("Statement$") then
                    local test_node
                    if name:match("String") then
                        test_node = func("test")
                    elseif name:match("Number") then
                        test_node = func(42)
                    elseif name:match("Boolean") then
                        test_node = func(true)
                    else
                        test_node = func()
                    end
                    
                    if test_node and type(test_node) == "table" then
                        return {name = name, node = test_node}
                    end
                end
            end)
            
            if success and result then
                table.insert(constructors, result.name)
                self:log(4, string.format("✓ %s -> kind: %s", 
                    result.name, 
                    tostring(result.node.kind)))
            end
        end
    end
    
    self:log(3, string.format("Valid constructors: %s", table.concat(constructors, ", ")))
    
    return {
        functions = ast_functions,
        tables = ast_tables,
        constants = ast_constants,
        constructors = constructors
    }
end

-- Enhanced AST traversal with statistics
function EncryptStrings:analyze_ast(ast)
    self:log(1, "=== AST STRUCTURAL ANALYSIS ===")
    
    local stats = {
        total_nodes = 0,
        by_kind = {},
        string_nodes = {},
        max_depth = 0,
        parent_child_relationships = {}
    }
    
    local function traverse(node, depth, parent)
        if not node then return end
        
        stats.total_nodes = stats.total_nodes + 1
        stats.max_depth = math.max(stats.max_depth, depth)
        
        -- Track kind distribution
        local kind_name = "Unknown"
        for k, v in pairs(AstKind) do
            if v == node.kind then
                kind_name = k
                break
            end
        end
        
        stats.by_kind[kind_name] = (stats.by_kind[kind_name] or 0) + 1
        
        -- Capture string nodes for analysis
        if node.kind == AstKind.StringExpression then
            local str_info = {
                value = node.value,
                depth = depth,
                parent_kind = parent and parent.kind or nil,
                location = node.loc
            }
            table.insert(stats.string_nodes, str_info)
            
            if #stats.string_nodes <= self.max_samples then
                self:log(3, string.format("String node #%d: %s", 
                    #stats.string_nodes, 
                    vim.inspect(str_info, {depth = 1})))
            end
        end
        
        -- Track parent-child relationships
        if parent then
            local parent_kind = "Unknown"
            local child_kind = "Unknown"
            
            for k, v in pairs(AstKind) do
                if v == parent.kind then parent_kind = k end
                if v == node.kind then child_kind = k end
            end
            
            local rel = parent_kind .. "->" .. child_kind
            stats.parent_child_relationships[rel] = 
                (stats.parent_child_relationships[rel] or 0) + 1
        end
        
        -- Recursively traverse children
        if node.body and type(node.body) == "table" then
            if node.body.kind then
                traverse(node.body, depth + 1, node)
            else
                for _, child in ipairs(node.body) do
                    if child and child.kind then
                        traverse(child, depth + 1, node)
                    end
                end
            end
        end
        
        -- Check common child properties
        local child_props = {"expression", "left", "right", "test", "consequent", 
                           "alternate", "argument", "callee", "object"}
        for _, prop in ipairs(child_props) do
            if node[prop] and node[prop].kind then
                traverse(node[prop], depth + 1, node)
            end
        end
    end
    
    traverse(ast, 0, nil)
    
    -- Report statistics
    self:log(2, string.format("Total Nodes: %d", stats.total_nodes))
    self:log(2, string.format("Maximum Depth: %d", stats.max_depth))
    self:log(2, string.format("String Nodes Found: %d", #stats.string_nodes))
    
    self:log(2, "\nNode Distribution by Kind:")
    for kind, count in pairs(stats.by_kind) do
        local percentage = (count / stats.total_nodes) * 100
        self:log(3, string.format("  %-25s: %5d (%5.1f%%)", 
            kind, count, percentage))
    end
    
    self:log(2, "\nTop Parent-Child Relationships:")
    local sorted_rels = {}
    for rel, count in pairs(stats.parent_child_relationships) do
        table.insert(sorted_rels, {rel = rel, count = count})
    end
    table.sort(sorted_rels, function(a, b) return a.count > b.count end)
    
    for i = 1, math.min(10, #sorted_rels) do
        self:log(3, string.format("  %-30s: %d", 
            sorted_rels[i].rel, sorted_rels[i].count))
    end
    
    return stats
end

-- Enhanced node creation with validation
function EncryptStrings:test_node_creation(api_info)
    self:log(1, "=== NODE CREATION VALIDATION ===")
    
    local test_cases = {
        {type = "StringExpression", args = {"Hello World"}},
        {type = "NumberExpression", args = {42}},
        {type = "NumberExpression", args = {3.14159}},
        {type = "BooleanExpression", args = {true}},
        {type = "BooleanExpression", args = {false}},
        {type = "NilExpression", args = {}},
        {type = "Identifier", args = {"myVariable"}},
    }
    
    local created_nodes = {}
    local failures = {}
    
    for _, test in ipairs(test_cases) do
        self:log(3, string.format("Testing %s...", test.type))
        
        local constructor = Ast[test.type]
        if constructor and type(constructor) == "function" then
            local success, node = pcall(constructor, unpack(test.args))
            
            if success and node then
                table.insert(created_nodes, {
                    type = test.type,
                    node = node,
                    kind = node.kind,
                    valid = self:validate_node(node)
                })
                
                self:log(4, string.format("✓ Created %s (kind=%d)", 
                    test.type, node.kind))
                
                -- Log node structure for first few
                if #created_nodes <= 3 then
                    self:log(5, "  Structure:")
                    for k, v in pairs(node) do
                        if k ~= "loc" or self.debug_level >= 4 then
                            self:log(5, string.format("    %s: %s", 
                                k, tostring(v)))
                        end
                    end
                end
            else
                table.insert(failures, test.type)
                self:log(4, string.format("✗ Failed to create %s: %s", 
                    test.type, tostring(node)))
            end
        else
            table.insert(failures, test.type)
            self:log(4, string.format("✗ Constructor not found for %s", test.type))
        end
    end
    
    -- Attempt composite node creation
    self:log(3, "\nTesting Composite Node Creation...")
    if Ast.BinaryExpression then
        local left = Ast.NumberExpression(5)
        local right = Ast.NumberExpression(10)
        
        if left and right then
            local binary = Ast.BinaryExpression("+", left, right)
            if binary then
                table.insert(created_nodes, {
                    type = "BinaryExpression",
                    node = binary,
                    kind = binary.kind,
                    valid = true
                })
                self:log(4, "✓ Created BinaryExpression with children")
            end
        end
    end
    
    self:log(2, string.format("\nNode Creation Summary: %d successes, %d failures", 
        #created_nodes, #failures))
    
    return {
        created = created_nodes,
        failures = failures,
        success_rate = (#created_nodes / #test_cases) * 100
    }
end

-- Node validation utility
function EncryptStrings:validate_node(node)
    if not node then return false end
    if not node.kind then return false end
    if type(node.kind) ~= "number" then return false end
    
    -- Check for required properties based on kind
    if node.kind == AstKind.StringExpression then
        return node.value ~= nil and type(node.value) == "string"
    elseif node.kind == AstKind.NumberExpression then
        return node.value ~= nil and (type(node.value) == "number" or 
               (type(node.value) == "table" and getmetatable(node.value)))
    end
    
    return true
end

-- Stress test for large ASTs
function EncryptStrings:stress_test()
    if not self.enable_stress_test then return end
    
    self:log(1, "=== STRESS TEST INITIATED ===")
    
    -- Create a deep nested structure
    local function create_nested_ast(depth)
        if depth <= 0 then
            return Ast.StringExpression("leaf")
        end
        
        local left = create_nested_ast(depth - 1)
        local right = create_nested_ast(depth - 1)
        
        if Ast.BinaryExpression then
            return Ast.BinaryExpression("+", left, right)
        end
        
        return left
    end
    
    -- Test with various depths
    local depths = {5, 10, 15}
    local results = {}
    
    for _, depth in ipairs(depths) do
        self:log(3, string.format("Creating nested AST depth %d...", depth))
        
        local start_time = os.clock()
        local ast = create_nested_ast(depth)
        local creation_time = os.clock() - start_time
        
        -- Traverse and count
        local node_count = 0
        visitast(ast, nil, function() node_count = node_count + 1 end)
        
        table.insert(results, {
            depth = depth,
            creation_time = creation_time,
            node_count = node_count,
            nodes_per_second = node_count / math.max(creation_time, 0.001)
        })
        
        self:log(4, string.format("  Nodes: %d, Time: %.3fs, Rate: %.0f nodes/s",
            node_count, creation_time, node_count / math.max(creation_time, 0.001)))
    end
    
    return results
end

-- Main apply function with enhanced debugging
function EncryptStrings:apply(ast, pipeline)
    self:log(1, "=== ENCRYPTSTRINGS FORTIFIED DEBUG SESSION ===")
    self:log(1, string.format("Debug Level: %d", self.debug_level))
    self:log(1, string.format("Timestamp: %s", os.date("%Y-%m-%d %H:%M:%S")))
    
    -- Phase 1: API Exploration
    local api_info = self:explore_api()
    
    -- Phase 2: AST Analysis
    local ast_stats = self:analyze_ast(ast)
    
    -- Phase 3: Node Creation Tests
    local creation_results = self:test_node_creation(api_info)
    
    -- Phase 4: Stress Testing (if enabled)
    local stress_results = self:stress_test()
    
    -- Phase 5: Transformation Simulation
    self:log(1, "=== TRANSFORMATION SIMULATION ===")
    
    -- Create a sample transformation to understand mutation patterns
    local transformed_count = 0
    local function simulate_transform(node)
        if node.kind == AstKind.StringExpression then
            transformed_count = transformed_count + 1
            
            if transformed_count <= 3 then
                self:log(3, string.format("Would transform string #%d: '%s'", 
                    transformed_count, node.value))
                
                -- Show what a transformed node might look like
                local transformed_value = "ENCRYPTED(" .. #node.value .. ")"
                self:log(4, string.format("  -> '%s'", transformed_value))
            end
            
            return node  -- Return unchanged for now
        end
    end
    
    -- Use visitast to simulate traversal
    local original_ast_string = vim.inspect(ast, {depth = 2})
    visitast(ast, nil, simulate_transform)
    
    self:log(2, string.format("Would transform %d string nodes", transformed_count))
    
    -- Generate comprehensive report
    self:generate_report({
        api_info = api_info,
        ast_stats = ast_stats,
        creation_results = creation_results,
        stress_results = stress_results,
        transformation_summary = {
            strings_found = #ast_stats.string_nodes,
            would_transform = transformed_count
        }
    })
    
    -- Close log file
    if self.log_handle then
        self.log_handle:write(string.format("[%s] Session completed\n", os.date()))
        self.log_handle:close()
    end
    
    self:log(1, "=== DEBUG SESSION COMPLETE ===")
    self:log(1, string.format("Log written to: %s", self.log_file))
    
    return ast  -- Return unchanged AST for debugging
end

-- Generate comprehensive report
function EncryptStrings:generate_report(data)
    local report = {}
    
    table.insert(report, "=":rep(60))
    table.insert(report, "ENCRYPTSTRINGS FORTIFIED DEBUG REPORT")
    table.insert(report, "=":rep(60))
    table.insert(report, "")
    
    table.insert(report, "1. API CAPABILITIES")
    table.insert(report, string.format("   Functions available: %d", #data.api_info.functions))
    table.insert(report, string.format("   Constructors found: %d", #data.api_info.constructors))
    table.insert(report, string.format("   Node creation success: %.1f%%", 
        data.creation_results.success_rate))
    
    table.insert(report, "")
    table.insert(report, "2. AST ANALYSIS")
    table.insert(report, string.format("   Total nodes: %d", data.ast_stats.total_nodes))
    table.insert(report, string.format("   String nodes: %d", #data.ast_stats.string_nodes))
    table.insert(report, string.format("   Maximum depth: %d", data.ast_stats.max_depth))
    
    table.insert(report, "")
    table.insert(report, "3. TRANSFORMATION POTENTIAL")
    table.insert(report, string.format("   Strings available for encryption: %d", 
        data.transformation_summary.strings_found))
    
    if data.stress_results then
        table.insert(report, "")
        table.insert(report, "4. PERFORMANCE METRICS")
        for _, result in ipairs(data.stress_results) do
            table.insert(report, string.format("   Depth %d: %d nodes in %.3fs (%.0f nodes/s)",
                result.depth, result.node_count, result.creation_time, result.nodes_per_second))
        end
    end
    
    table.insert(report, "")
    table.insert(report, "=":rep(60))
    
    -- Print report
    for _, line in ipairs(report) do
        print(line)
    end
    
    -- Save report to file
    local report_file = io.open("encrypt_strings_report.txt", "w")
    if report_file then
        for _, line in ipairs(report) do
            report_file:write(line .. "\n")
        end
        report_file:close()
    end
end

-- Cleanup method
function EncryptStrings:cleanup()
    if self.log_handle and not self.log_handle:closed() then
        self.log_handle:close()
    end
end

return EncryptStrings
