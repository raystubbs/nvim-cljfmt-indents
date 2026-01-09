local edn = require 'edn'
local plugin = {}
local vim = _G['vim']
local max_config_search_level = 15

-- Module-level cache to store indent configs per buffer.
-- This keeps Lua functions and mixed tables out of vim.b, preventing E5100.
local buffer_cache = {}

-- Utility: Decode EDN
local function decode_edn (x)
  return edn.decode(x, {
    tags = {re = function (s) return vim.regex('\\v' .. s) end},
    keyword = function (s) return ':' .. s end
  })
end

-- Utility: Read File
local function read_edn_file (path)
  local f = io.open(path)
  if f == nil then
    return false, nil
  end

  local success, value = pcall(function ()
    return decode_edn(f:read("*a"))
  end)
  io.close(f)
  return success, value
end

-- Config Resolution: Recursive search up the directory tree
local function resolve_config_file (dir_path, filename, level)
  local path = dir_path .. '/' .. filename
  if vim.fn.filereadable(path) == 1 then
    local success, value = read_edn_file(path)
    if success then return value end
    if value then
      print("Error reading config '" .. path .. "': " .. tostring(value))
    end
  end

  level = level or 0
  if level > max_config_search_level then return nil end

  local parent = vim.fn.fnamemodify(dir_path, ':h')
  if parent == dir_path then return nil end -- Hit root
  return resolve_config_file(parent, filename, level + 1)
end

local function resolve_cljfmt_config (buf)
  local buf_path = vim.api.nvim_buf_get_name(buf)
  local buf_dir = (buf_path ~= "") and vim.fn.fnamemodify(buf_path, ':p:h') or vim.fn.getcwd()

  -- 1. Try .lsp/config.edn
  local lsp_config = resolve_config_file(buf_dir, '.lsp/config.edn')
  
  -- 2. Check for embedded cljfmt config or path ref in lsp config
  if lsp_config then
    if type(lsp_config['cljfmt']) == 'table' then
      return lsp_config['cljfmt']
    elseif type(lsp_config['cljfmt-config-path']) == 'string' then
      local path = lsp_config['cljfmt-config-path']
      local success, value = read_edn_file(path)
      if success then return value end
    end
  end

  -- 3. Try cljfmt.edn / .cljfmt.edn
  local cljfmt = resolve_config_file(buf_dir, 'cljfmt.edn') or resolve_config_file(buf_dir, '.cljfmt.edn')
  return cljfmt or {}
end

local default_indent_edn_strings = {
  ["clojure.clj"] = [[
  {alt!            [[:block 0] ]
   alt!!           [[:block 0] ]
   are             [[:block 2] ]
   as->            [[:block 2] ]
   binding         [[:block 1] ]
   bound-fn        [[:inner 0] ]
   case            [[:block 1] ]
   catch           [[:block 2] ]
   comment         [[:block 0] ]
   cond            [[:block 0] ]
   condp           [[:block 2] ]
   cond->          [[:block 1] ]
   cond->>         [[:block 1] ]
   def             [[:inner 0] ]
   defmacro        [[:inner 0] ]
   defmethod       [[:inner 0] ]
   defmulti        [[:inner 0] ]
   defn            [[:inner 0] ]
   defn-           [[:inner 0] ]
   defonce         [[:inner 0] ]
   defprotocol     [[:block 1] [:inner 1] ]
   defrecord       [[:block 2] [:inner 1] ]
   defstruct       [[:block 1] ]
   deftest         [[:inner 0] ]
   deftype         [[:block 2] [:inner 1] ]
   delay           [[:block 0] ]
   do              [[:block 0] ]
   doseq           [[:block 1] ]
   dotimes         [[:block 1] ]
   doto            [[:block 1] ]
   extend          [[:block 1] ]
   extend-protocol [[:block 1] [:inner 1] ]
   extend-type     [[:block 1] [:inner 1] ]
   fdef            [[:inner 0] ]
   finally         [[:block 0] ]
   fn              [[:inner 0] ]
   for             [[:block 1] ]
   future          [[:block 0] ]
   go              [[:block 0] ]
   go-loop         [[:block 1] ]
   if              [[:block 1] ]
   if-let          [[:block 1] ]
   if-not          [[:block 1] ]
   if-some         [[:block 1] ]
   let             [[:block 1] ]
   letfn           [[:block 1] [:inner 2 0] ]
   locking         [[:block 1] ]
   loop            [[:block 1] ]
   match           [[:block 1] ]
   ns              [[:block 1] ]
   proxy           [[:block 2] [:inner 1] ]
   reify           [[:inner 0] [:inner 1] ]
   struct-map      [[:block 1] ]
   testing         [[:block 1] ]
   thread          [[:block 0] ]
   try             [[:block 0] ]
   use-fixtures    [[:inner 0] ]
   when            [[:block 1] ]
   when-first      [[:block 1] ]
   when-let        [[:block 1] ]
   when-not        [[:block 1] ]
   when-some       [[:block 1] ]
   while           [[:block 1] ]
   with-local-vars [[:block 1] ]
   with-open       [[:block 1] ]
   with-out-str    [[:block 0] ]
   with-precision  [[:block 1] ]
   with-redefs     [[:block 1] ]}
  ]],
  ["compojure.clj"] = [[
  {ANY        [[:inner 0] ]
   DELETE     [[:inner 0] ]
   GET        [[:inner 0] ]
   HEAD       [[:inner 0] ]
   OPTIONS    [[:inner 0] ]
   PATCH      [[:inner 0] ]
   POST       [[:inner 0] ]
   PUT        [[:inner 0] ]
   context    [[:inner 0] ]
   defroutes  [[:inner 0] ]
   let-routes [[:block 1] ]
   rfn        [[:inner 0] ]}
  ]],
  ["fuzzy.clj"] = [[
  {#re "^def"    [[:inner 0] ]
   default       [[:default] ]
   deflate       [[:default] ]
   defer         [[:default] ]
   #re "^with-"  [[:inner 0] ]}
  ]]
}

local core_names = {
  "let", "defn", "def", "if", "when", "do", "fn" 
  -- (Truncated list for brevity)
}

-- Namespace Analysis
local function get_aliasing(buf, root_node)
  local ns_node = root_node:named_child(0)
  if ns_node == nil or ns_node:type() ~= 'list_lit' then
    return nil
  end

  local ns_sym_node = ns_node:named_child(0)
  local ns_binding_node = ns_node:named_child(1)
  
  if ns_sym_node == nil
    or ns_sym_node:type() ~= 'sym_lit'
    or vim.treesitter.get_node_text(ns_sym_node, buf) ~= 'ns'
    or ns_binding_node == nil
    or ns_binding_node:type() ~= 'sym_lit' then
    return nil
  end

  local ns_aliases = {}
  local core_excluded = {} 

  for _, k in ipairs(core_names) do
    if not core_excluded[k] then
      ns_aliases[k] = 'clojure.core'
    end
  end

  return {
    aliases = ns_aliases,
    refers = {},
    ns = vim.treesitter.get_node_text(ns_binding_node, buf)
  }
end

local function get_qualified_name(buf, sym_node, indents_config)
  local namespace_node = sym_node:field('namespace')[1]
  local name_node = sym_node:field('name')[1]
  local namespace = namespace_node and vim.treesitter.get_node_text(namespace_node, buf)
  local name = name_node and vim.treesitter.get_node_text(name_node, buf)

  if indents_config[':alias-map'] and namespace then
     local mapping = indents_config[':alias-map'][namespace]
     if mapping then return mapping .. '/' .. name end
  end

  local root_node = sym_node:tree():root()
  local aliasing = get_aliasing(buf, root_node)
  
  if aliasing == nil then
    return (namespace and namespace .. '/' .. name) or name
  end

  if namespace then
    local resolved_ns = aliasing.aliases[namespace]
    return (resolved_ns or namespace) .. '/' .. name
  end
  
  return name 
end

local function get_rule (buf, ts_parent_node, index, depth, indents)
  if ts_parent_node == nil then return 'default' end

  local is_list = ts_parent_node:type() == 'list_lit'
  local first_child = is_list and ts_parent_node:named_child(0)

  if is_list and first_child and first_child:type() == 'sym_lit' then
    local first_child_str = get_qualified_name(buf, first_child, indents.config or {})
    
    for _, indent in ipairs(indents) do
      if indent.matcher(first_child_str) then
        for _, pattern_rule in ipairs(indent.rules) do
          if pattern_rule[1] == ":default" and depth == 0 then
            return 'default'
          elseif pattern_rule[1] == ":inner" then
            local rule_depth = pattern_rule[2]
            local rule_index = pattern_rule[3]
            if (type(rule_depth) ~= 'number' or rule_depth == depth)
              and (type(rule_index) ~= 'number' or rule_index == index - 1) then
              return 'inner'
            end
          elseif pattern_rule[1] == ':block'
            and type(pattern_rule[2]) == 'number'
            and depth == 0 then
            local rule_index = pattern_rule[2]
            local child_at_index = ts_parent_node:named_child(rule_index + 1)
            
            if child_at_index ~= nil then
              local row, col = child_at_index:start()
              local prefix = table.concat(
                 vim.api.nvim_buf_get_text(buf, row, 0, row, col, {})
              )
              if index > rule_index and string.match(prefix, "^%s*$") then
                return 'inner'
              else
                return 'default'
              end
            end
            return 'inner'
          end
        end
      end
    end
  end

  local ts_parent_node_index = 0
  local cursor = ts_parent_node:prev_named_sibling()
  while cursor ~= nil do
    ts_parent_node_index = ts_parent_node_index + 1
    cursor = cursor:prev_named_sibling()
  end
  return get_rule(buf, ts_parent_node:parent(), ts_parent_node_index, depth + 1, indents)
end

local function is_collection_node(node)
  local t = node:type()
  return t == 'list_lit'
    or t == 'map_lit'
    or t == 'set_lit'
    or t == 'vec_lit'
    or t == 'read_cond_lit'
    or t == 'anon_fn_lit'
end

local function build_indents(cljfmt_config)
  local indents = {}
  local function add_indent(k, v)
    if type(k) == 'string' then
      if string.match(k, "/") then
        table.insert(indents, {
          priority = 0,
          matcher = function(s) return s == k end,
          rules = v
        })
      else
        table.insert(indents,{
          priority = 0,
          matcher = function(s)
            return (k == s or string.match(s, "/" .. k .. "$") or false) and true
          end,
          rules = v
        })
      end
    elseif type(k) == 'userdata' and string.format('%s', k) == '<regex>' then
      table.insert(indents, {priority = 9, matcher = function(s) return k:match_str(s) end, rules = v})
    end
  end

  if type(cljfmt_config[':indents']) == 'table' then
    for k, v in pairs(cljfmt_config[':indents']) do add_indent(k, v) end
  else
    for _, indents_edn_string in pairs(default_indent_edn_strings) do
      for k, v in pairs(decode_edn(indents_edn_string)) do add_indent(k, v) end
    end
  end

  if type(cljfmt_config[':extra-indents']) == 'table' then
    for k, v in pairs(cljfmt_config[':extra-indents'] or {}) do add_indent(k, v) end
  end
  
  table.sort(indents, function(a, b) return a.priority < b.priority end)
  
  -- Store raw config for alias lookups, but keep it Lua-only
  indents.config = cljfmt_config 
  return indents
end

local function get_indentation(buf, pos)
  pos = pos or vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  buf = buf or vim.api.nvim_get_current_buf()

  local cur_row = pos[1] - 1
  local cur_col = pos[2]

  local parser = vim.treesitter.get_parser(buf, 'clojure')
  if parser == nil then return nil end

  local tree = parser:parse()[1] 
  local root = tree:root()
  
  local node = root:named_descendant_for_range(cur_row, cur_col, cur_row, cur_col)
  node = node or root
  
  local node_row, node_col = node:start()

  while node
    and (not is_collection_node(node)
         and node:type() ~= 'str_lit'
         or (node_row == cur_row and node_col == cur_col)) do
      if node:parent() == nil then break end
      node = node:parent()
      node_row, node_col = node:start()
  end

  if node == nil then return nil end

  if node:type() ~= 'list_lit' then
    if node:type() == 'str_lit' or node:type() == 'source' then return nil end
    local node_text = vim.treesitter.get_node_text(node, buf)
    local bracket_index = string.find(node_text, "[([{]")
    if bracket_index then
       return node_col + bracket_index
    end
    return node_col + 1
  end

  local index = 0
  local child = node:named_child(index)
  local child_row, child_col
  if child then child_row, child_col = child:end_() end
  
  while child and child_row < cur_row do
    index = index + 1
    child = node:named_child(index)
    if child then
      child_row, child_col = child:end_()
    end
  end

  -- Retrieve indents from local buffer_cache
  local indents = buffer_cache[buf]
  if not indents then 
    local cfg = resolve_cljfmt_config(buf)
    indents = build_indents(cfg)
    buffer_cache[buf] = indents
  end

  local rule = get_rule(buf, node, index, 0, indents)

  if rule == 'default' then
    local second_child = node:named_child(1)
    if second_child then
      local row, col = second_child:start()
      if row == node_row then
        return col
      end
    end
    return node_col + 1
  elseif rule == 'inner' then
    return node_col + 2
  end

  return nil
end

function plugin.setup ()
  -- Prevent double setup using the specific variable name
  if vim.g.nvim_cljfmt_loaded then return end
  vim.g.nvim_cljfmt_loaded = true

  local grp = vim.api.nvim_create_augroup("CljfmtIndent", { clear = true })
  
  vim.api.nvim_create_autocmd("FileType", {
    group = grp,
    pattern = "clojure",
    callback = function(args)
      local buf = args.buf
      
      -- 1. Load Config into local cache
      local cfg = resolve_cljfmt_config(buf)
      buffer_cache[buf] = build_indents(cfg)

      -- 2. Set indent expression
      vim.bo[buf].indentexpr = "v:lua.vim.g.GetCljfmtIndent()"
    end
  })

  -- Clear cache when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = grp,
    callback = function(args)
      buffer_cache[args.buf] = nil
    end
  })

  vim.g.GetCljfmtIndent = function()
    return get_indentation() or -1
  end
end

return plugin
