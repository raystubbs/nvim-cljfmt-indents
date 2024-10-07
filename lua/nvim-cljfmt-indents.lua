local edn = require 'edn'
local plugin = {}
local vim = _G['vim']
local max_config_search_level = 15

local function decode_edn (x)
  return edn.decode(x, {
    tags = {re = function (s) return vim.regex('\\v' .. s) end},
    keyword = function (s) return ':' .. s end
  })
end

local function read_edn_file (path)
  local f = io.open(path)
  if f == nil then
    return false, nil
  end

  local success, value = pcall(
    function ()
      return decode_edn(f)
    end
  )
  io.close(f)
  return success, value
end

local function resolve_lsp_config_edn (dir_path, level)
  local path = dir_path .. '.lsp/config.edn'
  local success, value = read_edn_file(path)
  if success then
    return value
  end

  if value ~= nil then
    print("Error reading the clojure-lsp config file at '" .. path .. "': " .. value)
  end

  level = level or 0
  if level > max_config_search_level then
    return nil
  else
    return resolve_lsp_config_edn(dir_path .. '../', level + 1)
  end
end

local function resolve_cljfmt_config_edn (dir_path, level)
  for _, path in ipairs({dir_path .. 'cljfmt.edn', dir_path .. '.cljfmt.edn'}) do
    local success, value = read_edn_file(path)
    if success then
      return value
    end

    if value ~= nil then
      print("Error reading the cljfmt config file at '" .. path .. "': " .. value)
    end
  end

  level = level or 0
  if level > max_config_search_level then
    return nil
  else
    return resolve_cljfmt_config_edn(dir_path .. '../', level + 1)
  end
end

local function resolve_cljfmt_config (dir_path)
  local lsp_config = resolve_lsp_config_edn(dir_path)
  if lsp_config ~= nil and type(lsp_config['cljfmt']) == 'table' then
    return lsp_config['cljfmt']
  end

  if lsp_config ~= nil and type(lsp_config['cljfmt-config-path']) == 'string' then
    local path = lsp_config['cljfmt-config-path']
    local success, value = read_edn_file(path)
    if success then
      return value
    else
      print("Error reading the cljfmt config file at '" .. path .. "'")
    end
  end

  return resolve_cljfmt_config_edn(dir_path)
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
  "*", "*'", "*1", "*2", "*3", "*agent*",
  "*allow-unresolved-vars*", "*assert*", "*clojure-version*",
  "*comand-line-args*", "*compile-files*", "*compile-path*",
  "*compiler-options*", "*data-readers*", "*default-data-reader-fn*",
  "*e", "*err*", "*file*", "*flush-on-newline*", "*fn-loader*", "*in*",
  "*math-context*", "*ns*", "*out*", "*print-dup*", "*print-length*",
  "*print-level*", "*print-meta*", "*print-namespace-maps*", "*print-readably*",
  "*read-eval*", "*reader-resolver*", "*source-path*", "*suppress-read*",
  "*unchecked-math*", "*use-context-classloader*", "verbose-defrecords*",
  "*warn-on-reflection*", "+", "+'", "-", "-'", "->", "->>", "->ArrayChunk",
  "->Eduction", "->Vec", "->VecNode", "->VecSeq", "-cache-protocol-fn", "-reset-methods",
  ".", "..", "/", "<", "<=", "=", "==", ">", ">=", "abs", "accessor", "aclone",
  "add-classpath", "add-tap", "add-watch", "agent", "agent-error", "agent-errors",
  "aget", "alength", "alias", "all-ns", "alter", "alter-meta!", "alter-var-root!",
  "amap", "ancestors", "and", "any?", "apply", "areduce", "array-map", "as->", "aset",
  "aset-boolean", "aset-byte", "aset-char", "aset-double", "aset-float", "aset-int",
  "aset-long", "aset-short", "assert", "assoc", "assoc!", "assoc-in", "associative?",
  "atom", "await", "await-for", "await1", "bases", "bean", "bigdec", "bigint",
  "biginteger", "binding", "bit-and", "bit-and-not", "bit-clear", "bit-flip", "bit-not",
  "bit-or", "bit-set", "big-shift-left", "bit-shift-right", "bit-test", "bit-xor",
  "boolean", "boolean-array", "boolean?", "booleans", "bound-fn", "bound-fn*",
  "bound?", "bounded-count", "butlast", "byte", "byte-array", "bytes", "bytes?",
  "case", "cast", "cat", "catch", "char", "char-array", "char-escape-string",
  "char-name-string", "char?", "chars", "chunk", "chunk-append", "chunk-buffer",
  "chunk-cons", "chunk-first", "chunk-next", "chunk-rest", "chunked-seq?",
  "class", "class?", "clear-agent-errors", "clojure-version", "coll?", "comment",
  "commute", "comp", "comparator", "compare", "compare-and-set!", "compile",
  "complement", "completing", "concat", "cond", "cond->", "cond->>", "condp",
  "conj", "conj!", "cons", "constantly", "construct-proxy", "contains?", "count",
  "counted?", "create-ns", "create-struct", "cycle", "dec", "dec'", "decimal?",
  "declare", "dedupe", "def", "default-data-readers", "definline", "definterface",
  "defmacro", "defmethod", "defmulti", "defn", "defn-", "defonce", "defprotocol",
  "defrecord", "defstruct", "deftype", "delay", "delay?", "deliver", "denominator",
  "deref", "derive", "descendants", "disj", "disj!", "dissoc", "distinct", "distinct?",
  "do", "doall", "dorun", "doseq", "dosync", "dotimes", "doto", "double", "double-array",
  "double?", "doubles", "drop", "drop-last", "drop-while"
  -- TODO: add the rest
}

local function get_ts_node_text (buf, node)
  local start_row, start_col = node:start()
  local end_row, end_col = node:end_()
  local text = table.concat(vim.api.nvim_buf_get_text(
    buf, start_row, start_col, end_row, end_col, {}
  ), '\n')
  return text
end

local function get_aliasing(buf, root_node)
  local ns_node = root_node:named_child(0)
  if ns_node == nil or ns_node:type() ~= 'list_lit' then
    return nil
  end

  local ns_sym_node = ns_node:named_child(0)
  local ns_binding_node = ns_node:named_child(1)
  if ns_sym_node == nil
    or ns_sym_node:type() ~= 'sym_lit'
    or get_ts_node_text(buf, ns_sym_node) ~= 'ns'
    or ns_binding_node == nil
    or ns_binding_node:type() ~= 'sym_lit' then
    return nil
  end

  local require_node, refer_clojure_node
  for i = 1, ns_node:named_child_count() - 1 do
    local child = ns_node:named_child(i)
    if child:type() == 'list_lit' then
      local head = child:named_child(0)
      local head_text = get_ts_node_text(buf, head)
      if head_text == ':require' then
        require_node = child
      elseif head_text == ':refer_clojure' then
        refer_clojure_node = child
      end
    end
  end

  local core_excluded = {}
  if refer_clojure_node then
    for i = 1, refer_clojure_node:named_child_count() - 1 do
      if get_ts_node_text(buf, refer_clojure_node:named_child(i)) == ':exclude' then
        local exclude_coll = refer_clojure_node:named_child(i+1)
        local exclude_coll_type = exclude_coll and exclude_coll:type()
        if exclude_coll_type == 'list_lit'
          or exclude_coll_type == 'set_lit'
          or exclude_coll_type == 'vec_lit' then
          for j = 0, exclude_coll:named_child_count() - 1 do
            local excluded_node = exclude_coll:named_child(j)
            local excluded_name_node = excluded_node:field('name')[1]
            if excluded_name_node then
              core_excluded[get_ts_node_text(buf, excluded_name_node)] = true
            end
          end
        end
      end
    end
  end

  local ns_aliases = {}
  for _, k in ipairs(core_names) do
    if not core_excluded[k] then
      ns_aliases[k] = 'clojure.core'
    end
  end

  local ns_refers = {}
  if require_node then
    for i = 1, require_node:named_child_count() - 1 do
      local requirement_node = require_node:named_child(i)
      local type = requirement_node:type()
      if type == 'vec_lit' or type == 'list_lit' then
        local required_ns_node = requirement_node:named_child(0)
        local required_ns_text = get_ts_node_text(buf, required_ns_node)
        if required_ns_node and required_ns_node:type() == 'sym_lit' then
          for j = 1, requirement_node:named_child_count() - 1 do
            local requirement_child_node = requirement_node:named_child(j)
            if requirement_child_node:type() == 'kwd_lit' then
              local keyword_text = get_ts_node_text(buf, requirement_child_node)
              if keyword_text == ':as' or keyword_text == ':as-alias' then
                local alias_node = requirement_node:named_child(j+1)
                if alias_node and alias_node:type() == 'sym_lit' then
                  ns_aliases[get_ts_node_text(buf, alias_node)] = required_ns_text
                end
              elseif keyword_text == ':refer' or keyword_text == ':refer-macros' then
                local refers_coll_node = requirement_node:named_child(j+1)
                local refers_coll_type = refers_coll_node and refers_coll_node:type()
                if refers_coll_type == 'list_lit'
                  or refers_coll_type == 'vec_lit'
                  or refers_coll_type == 'set_lit' then
                  for k = 0, refers_coll_node:named_child_count() - 1 do
                    local referred_node = refers_coll_node:named_child(k)
                    if referred_node:type() == 'sym_lit' then
                      ns_refers[get_ts_node_text(buf, referred_node)] = required_ns_text
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  return {
    aliases = ns_aliases,
    refers = ns_refers,
    ns = get_ts_node_text(buf, ns_binding_node)
  }
end

local function get_qualified_name(buf, sym_node)
  local namespace_node = sym_node:field('namespace')[1]
  local name_node = sym_node:field('name')[1]
  local namespace = namespace_node and get_ts_node_text(buf, namespace_node)
  local name = name_node and get_ts_node_text(buf, name_node)

  local config_alias_map = plugin.config.cljfmt[':alias-map']
  if config_alias_map and config_alias_map[namespace] then
    return config_alias_map[namespace] .. '/' .. name
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

  return (aliasing.refers[name] or aliasing.ns) .. '/' .. name
end

local function get_rule (buf, ts_parent_node, index, depth)
  if ts_parent_node == nil then
    return 'default'
  end

  local is_list = ts_parent_node:type() == 'list_lit'
  local first_child = is_list and ts_parent_node:named_child(0)
  if first_child == nil or first_child:type() ~= 'sym_lit' then
    return 'default'
  end
  if first_child then
    local first_child_str = get_qualified_name(buf, first_child)
    for _, indent in ipairs(plugin.config.indents) do
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
  return get_rule(buf, ts_parent_node:parent(), ts_parent_node_index, depth + 1)
end


local function get_indentation(buf, pos)
  pos = pos or vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  buf = buf or vim.api.nvim_get_current_buf()
  local cur_row, cur_col
  if pos[2] == 0 then
    local line = vim.api.nvim_buf_get_lines(buf, pos[1], pos[1] + 1, false)[1]
    cur_row = pos[1] - 2
    cur_col = string.len(line) - 1
  else
   cur_row = pos[1] - 1
   cur_col = pos[2]
  end

  local parser = (plugin.parsers and plugin.parsers[buf]) or vim.treesitter.get_parser(buf, 'clojure')
  if plugin.parsers then
    plugin.parsers[buf] = parser
  else
    plugin.parsers = {[buf] = parser}
  end

  if parser == nil then
    return nil
  end

  local tree = parser:parse(true)[1]
  local node = tree:root():named_descendant_for_range(cur_row, cur_col, cur_row, cur_col)

  while node
    and node:type() ~= 'list_lit'
    and node:type() ~= 'map_lit'
    and node:type() ~= 'vec_lit'
    and node:type() ~= 'set_lit'
    and node:type() ~= 'str_lit' do
      node = node:parent()
    end

  if node == nil then
    return nil
  end

  local node_row, node_col = node:start()

  if node:type() == 'str_lit' then
    return nil
  elseif node:type() ~= 'list_lit' then
    return node_col + 1
  end

  local index = 0
  local child_row, child_col = node:named_child(index):end_()
  while node:named_child(index) and child_row < cur_row do
    index = index + 1
    child_row, child_col = node:named_child(index):end_()
  end

  local rule = get_rule(buf, node, index, 0)

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

function plugin.setup (opts)
  opts = opts or {}
  plugin.config = {}

  if type(opts.cljfmt) == 'table' then
    plugin.config.cljfmt = opts.cljfmt
  elseif type(opts.cljfmt) == 'string' then
    local success, value = read_edn_file(opts.cljfmt)
    if success then
      plugin.config.cljfmt = value
    else
      print("Error reading the cljfmt config file at '" .. plugin.config .. "'")
    end
    plugin.config.cljfmt = resolve_cljfmt_config('./')
  else
    plugin.config.cljfmt = resolve_cljfmt_config('./') or {}
  end

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
  if type(plugin.config.cljfmt[':indents']) == 'table' then
    for k, v in pairs(plugin.config.cljfmt[':indents']) do
      add_indent(k, v)
    end
  else
    for _, indents_edn_string in pairs(default_indent_edn_strings) do
      for k, v in pairs(decode_edn(indents_edn_string)) do
        add_indent(k, v)
      end
    end
  end
  if type(plugin.config.cljfmt[':extra-indents']) == 'table' then
    for k, v in pairs(plugin.config.cljfmt[':extra-indents'] or {}) do
      add_indent(k, v)
    end
  end

  table.sort(indents, function(a, b) return a.priority < b.priority end)

  plugin.config.indents = indents
  vim.g.GetCljfmtIndent = function()
    return get_indentation() or -1
  end
end

return plugin
