This plugin provides a `GetCljfmtIndent` global function
that can be used in an `indentexpr` to help keep things
indented according to your `cljfmt` rules as you work.

It's intended to be 'as good as possible,' but won't be
perfect.  Use it along-side `clojure-lsp`'s formatting,
with the latter having the final say.

## Setup
Put this in your Lazy dependency map (or the equivalent for
other package managers).
```lua
{'raystubbs/nvim-cljfmt-indents',
 config = function()
   require('nvim-cljfmt-indents').setup()
 end
}
```

Do something like this to use this plugin within Clojure
buffers.

```lua
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter' }, {
  pattern = { "*.clj", "*.cljs", "*.cljc", "*.edn" },
  callback = function(args)
    vim.o.indentexpr = "GetCljfmtIndent()"
  end 
})
```

> [!WARNING]
> This plugin relies on the clojure tree-sitter grammer,
> so make sure that's installed.

## Config
By default the plugin will loop in the `cwd` and parent
directories for either a `.lsp/config.edn` with cljfmt
config, or a `cljfmt.edn`, or a `.cljfmt.edn` file.

The the cljfmt config can also be given explicitly as
a table or path to the config file, by setting the `cljfmt`
option:

```lua
require('nvim-cljfmt-indents').setup {
  cljfmt = "./cljfmt.edn"
}

require('nvim-cljfmt-indents').setup {
  cljfmt = {
   [":indents"] = {
     "foo" = {{':inner' 0}}
   }
  }
}
```

> [!WARNING]
> Haven't tested this very well at all yet.  There are bound
> to be many bugs.  But so far works pretty well.  Use at your
> own risk.
