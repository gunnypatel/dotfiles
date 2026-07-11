-- [[ init.lua ]]
-- Personal Neovim config: single-file, inspired by kickstart.nvim
-- (https://github.com/nvim-lua/kickstart.nvim). Plugins are managed by Neovim's
-- built-in `vim.pack`; LSPs and formatters are installed automatically by Mason
-- on first launch. Requires Neovim >= 0.12 (for `vim.pack` and the
-- `vim.lsp.config` / `vim.lsp.enable` API). See the repo README for prerequisites.
--
-- Organized into sections:
--   1. Options   2. Keymaps   3. Plugin manager (vim.pack)   4. UI / core UX
--   5. Search (Telescope)   6. LSP   7. Formatting   8. Autocomplete   9. Treesitter

-- ============================================================
-- SECTION 1: OPTIONS
-- Core Neovim settings, leaders, options, basic keymaps, basic autocmds
-- ============================================================
do
  -- Enable faster startup by caching compiled Lua modules
  vim.loader.enable()

  -- Set <space> as the leader key. See `:help mapleader`.
  -- NOTE: Must happen before plugins are loaded (otherwise wrong leader is used).
  vim.g.mapleader = ' '
  vim.g.maplocalleader = ' '

  -- A Nerd Font is installed and selected in the terminal (JetBrains Mono Nerd
  -- Font — see the repo README). This enables icons across the UI.
  vim.g.have_nerd_font = true

  -- [[ Setting options ]]  See `:help vim.o`
  -- Make line numbers default
  vim.o.number = true
  -- Relative line numbers help with jumping. Try it and see if you like it:
  -- vim.o.relativenumber = true

  -- Enable mouse mode, useful for resizing splits
  vim.o.mouse = 'a'

  -- Don't show the mode, since it's already in the status line
  vim.o.showmode = false

  -- Sync clipboard between OS and Neovim. Scheduled after `UiEnter` because it
  -- can increase startup time. See `:help 'clipboard'`.
  vim.schedule(function()
    vim.o.clipboard = 'unnamedplus'
  end)

  vim.o.breakindent = true
  vim.o.undofile = true

  -- Case-insensitive searching UNLESS \C or one or more capital letters
  vim.o.ignorecase = true
  vim.o.smartcase = true

  vim.o.signcolumn = 'yes'
  vim.o.updatetime = 250
  vim.o.timeoutlen = 300
  vim.o.splitright = true
  vim.o.splitbelow = true

  -- Render certain whitespace. See `:help 'list'` and `:help 'listchars'`.
  vim.o.list = true
  vim.opt.listchars = { tab = '» ', trail = '·', nbsp = '␣' }

  -- Preview substitutions live, as you type
  vim.o.inccommand = 'split'
  vim.o.cursorline = true
  vim.o.scrolloff = 10

  -- On an operation that would fail due to unsaved changes (like `:q`), raise a
  -- save dialog instead. See `:help 'confirm'`.
  vim.o.confirm = true
end

-- ============================================================
-- SECTION 2: KEYMAPS
-- basic keymaps + diagnostic config
-- ============================================================
do
  -- Clear highlights on search when pressing <Esc> in normal mode
  vim.keymap.set('n', '<Esc>', '<cmd>nohlsearch<CR>')

  -- Diagnostic config & keymaps. See `:help vim.diagnostic.Opts`
  vim.diagnostic.config {
    update_in_insert = false,
    severity_sort = true,
    float = { border = 'rounded', source = 'if_many' },
    underline = { severity = { min = vim.diagnostic.severity.WARN } },
    virtual_text = true, -- show text at the end of the line
    virtual_lines = false, -- or underneath, with virtual lines
    jump = {
      -- Auto-open the float when jumping with `[d` / `]d`
      on_jump = function(_, bufnr)
        vim.diagnostic.open_float { bufnr = bufnr, scope = 'cursor', focus = false }
      end,
    },
  }

  vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostic [Q]uickfix list' })

  -- Exit terminal mode with <Esc><Esc>
  vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })

  -- Keybinds to make split navigation easier. Use CTRL+hjkl to move focus.
  vim.keymap.set('n', '<C-h>', '<C-w><C-h>', { desc = 'Move focus to the left window' })
  vim.keymap.set('n', '<C-l>', '<C-w><C-l>', { desc = 'Move focus to the right window' })
  vim.keymap.set('n', '<C-j>', '<C-w><C-j>', { desc = 'Move focus to the lower window' })
  vim.keymap.set('n', '<C-k>', '<C-w><C-k>', { desc = 'Move focus to the upper window' })

  -- Highlight when yanking (copying) text. See `:help vim.hl.on_yank()`
  vim.api.nvim_create_autocmd('TextYankPost', {
    desc = 'Highlight when yanking (copying) text',
    group = vim.api.nvim_create_augroup('kickstart-highlight-yank', { clear = true }),
    callback = function()
      vim.hl.on_yank()
    end,
  })
end

-- ============================================================
-- SECTION 3: PLUGIN MANAGER INTRO
-- `vim.pack` (built-in) + build hooks for plugins that need compiling
-- ============================================================
do
  -- `vim.pack` is the plugin manager built into Neovim (>= 0.12).
  -- See `:help vim.pack`, `:help vim.pack-examples`, or
  -- https://echasnovski.com/blog/2026-03-13-a-guide-to-vim-pack
  --
  -- Inspect state / pending updates:  :lua vim.pack.update(nil, { offline = true })
  -- Update plugins:                   :lua vim.pack.update()

  local function run_build(name, cmd, cwd)
    local result = vim.system(cmd, { cwd = cwd }):wait()
    if result.code ~= 0 then
      local stderr = result.stderr or ''
      local stdout = result.stdout or ''
      local output = stderr ~= '' and stderr or stdout
      if output == '' then
        output = 'No output from build command.'
      end
      vim.notify(('Build failed for %s:\n%s'):format(name, output), vim.log.levels.ERROR)
    end
  end

  -- Run build steps after a plugin is installed or updated. See `:help vim.pack-events`
  vim.api.nvim_create_autocmd('PackChanged', {
    callback = function(ev)
      local name = ev.data.spec.name
      local kind = ev.data.kind
      if kind ~= 'install' and kind ~= 'update' then
        return
      end

      if name == 'telescope-fzf-native.nvim' and vim.fn.executable 'make' == 1 then
        run_build(name, { 'make' }, ev.data.path)
        return
      end

      if name == 'LuaSnip' then
        if vim.fn.has 'win32' ~= 1 and vim.fn.executable 'make' == 1 then
          run_build(name, { 'make', 'install_jsregexp' }, ev.data.path)
        end
        return
      end

      if name == 'nvim-treesitter' then
        if not ev.data.active then
          vim.cmd.packadd 'nvim-treesitter'
        end
        vim.cmd 'TSUpdate'
        return
      end
    end,
  })
end

---Most plugins are on GitHub, so this helper cuts down the repetition below.
---@param repo string
---@return string
local function gh(repo)
  return 'https://github.com/' .. repo
end

-- ============================================================
-- SECTION 4: UI / CORE UX PLUGINS
-- guess-indent, gitsigns, which-key, colorscheme, todo-comments, mini, neo-tree
-- ============================================================
do
  -- Detect tabstop and shiftwidth automatically
  vim.pack.add { gh 'NMAC427/guess-indent.nvim' }
  require('guess-indent').setup {}

  -- Git signs in the gutter + hunk utilities. See `:help gitsigns`
  vim.pack.add { gh 'lewis6991/gitsigns.nvim' }
  require('gitsigns').setup {
    signs = {
      add = { text = '+' },
      change = { text = '~' },
      delete = { text = '_' },
      topdelete = { text = '‾' },
      changedelete = { text = '~' },
    },
  }

  -- Show pending keybinds. See `:help which-key.nvim`
  vim.pack.add { gh 'folke/which-key.nvim' }
  require('which-key').setup {
    delay = 0,
    icons = { mappings = vim.g.have_nerd_font },
    spec = {
      { '<leader>s', group = '[S]earch', mode = { 'n', 'v' } },
      { '<leader>t', group = '[T]oggle' },
      { '<leader>h', group = 'Git [H]unk', mode = { 'n', 'v' } },
      { 'gr', group = 'LSP Actions', mode = { 'n' } },
    },
  }

  -- [[ Colorscheme ]]
  -- Catppuccin (mocha) — matches the kitty/tmux/wezterm catppuccin-mocha theme.
  vim.pack.add { gh 'catppuccin/nvim' }
  require('catppuccin').setup {
    flavour = 'mocha', -- latte, frappe, macchiato, mocha
    background = { light = 'latte', dark = 'mocha' },
    term_colors = true,
    -- catppuccin auto-detects installed plugins (telescope, gitsigns, mini,
    -- treesitter, mason, which-key, etc.) so explicit integrations aren't needed.
  }
  vim.cmd.colorscheme 'catppuccin'

  -- Highlight todo/notes/etc. in comments
  vim.pack.add { gh 'folke/todo-comments.nvim' }
  require('todo-comments').setup { signs = false }

  -- [[ mini.nvim ]] — small independent modules
  vim.pack.add { gh 'nvim-mini/mini.nvim' }

  if vim.g.have_nerd_font then
    require('mini.icons').setup()
    -- Backwards compat for plugins that want nvim-web-devicons (e.g. telescope)
    MiniIcons.mock_nvim_web_devicons()
  end

  -- Better around/inside textobjects. Examples: va) yinq ci'
  require('mini.ai').setup {
    -- Avoid conflicts with built-in incremental selection on Neovim >= 0.12
    mappings = { around_next = 'aa', inside_next = 'ii' },
    n_lines = 500,
  }

  -- Add/delete/replace surroundings: saiw) sd' sr)'
  require('mini.surround').setup()

  -- Simple statusline. (Remove this and try another if you prefer.)
  local statusline = require 'mini.statusline'
  statusline.setup { use_icons = vim.g.have_nerd_font }
  ---@diagnostic disable-next-line: duplicate-set-field
  statusline.section_location = function()
    return '%2l:%-2v'
  end

  -- [[ neo-tree ]] — file explorer sidebar. `<leader>e` toggles it.
  -- nui.nvim is required by neo-tree; plenary is already loaded (via Telescope),
  -- and nvim-web-devicons provides file icons.
  vim.pack.add {
    gh 'nvim-neo-tree/neo-tree.nvim',
    gh 'MunifTanjim/nui.nvim',
    gh 'nvim-tree/nvim-web-devicons',
  }
  require('neo-tree').setup {
    sources = { 'filesystem', 'buffers', 'git_status' },
    -- Don't replace these window types when opening a file from the tree
    open_files_do_not_replace_types = { 'terminal', 'Trouble', 'trouble', 'qf', 'edgy' },
    window = {
      width = 30,
      mappings = {
        ['<space>'] = 'none', -- avoid clashing with the <space> leader inside the tree
      },
    },
    filesystem = {
      hijack_netrw = true, -- `nvim .` / `:Ex` open neo-tree instead of netrw
      follow_current_file = { enabled = true },
      use_libuv_file_watcher = true, -- auto-refresh on filesystem changes
    },
  }
  vim.keymap.set('n', '<leader>e', '<Cmd>Neotree toggle<CR>', { desc = '[E]xplorer (toggle)' })
  vim.keymap.set('n', '<leader>ge', '<Cmd>Neotree git_status toggle<CR>', { desc = '[G]it [E]xplorer' })
  vim.keymap.set('n', '<leader>be', '<Cmd>Neotree buffers toggle<CR>', { desc = '[B]uffer [E]xplorer' })
end

-- ============================================================
-- SECTION 5: SEARCH & NAVIGATION
-- Telescope (fuzzy finder) + keymaps + LSP picker mappings
-- ============================================================
do
  -- Telescope fuzzy-finds files, LSP results, help, grep, etc.
  -- Useful in-prompt keymaps: <C-/> (insert) / ? (normal) show all picker keys.
  ---@type (string|vim.pack.Spec)[]
  local telescope_plugins = {
    gh 'nvim-lua/plenary.nvim',
    gh 'nvim-telescope/telescope.nvim',
    gh 'nvim-telescope/telescope-ui-select.nvim',
  }
  if vim.fn.executable 'make' == 1 then
    table.insert(telescope_plugins, gh 'nvim-telescope/telescope-fzf-native.nvim')
  end

  vim.pack.add(telescope_plugins)

  require('telescope').setup {
    extensions = {
      ['ui-select'] = { require('telescope.themes').get_dropdown() },
    },
  }

  pcall(require('telescope').load_extension, 'fzf')
  pcall(require('telescope').load_extension, 'ui-select')

  -- See `:help telescope.builtin`
  local builtin = require 'telescope.builtin'
  vim.keymap.set('n', '<leader>sh', builtin.help_tags, { desc = '[S]earch [H]elp' })
  vim.keymap.set('n', '<leader>sk', builtin.keymaps, { desc = '[S]earch [K]eymaps' })
  vim.keymap.set('n', '<leader>sf', builtin.find_files, { desc = '[S]earch [F]iles' })
  vim.keymap.set('n', '<leader>ss', builtin.builtin, { desc = '[S]earch [S]elect Telescope' })
  vim.keymap.set({ 'n', 'v' }, '<leader>sw', builtin.grep_string, { desc = '[S]earch current [W]ord' })
  vim.keymap.set('n', '<leader>sg', builtin.live_grep, { desc = '[S]earch by [G]rep' })
  vim.keymap.set('n', '<leader>sd', builtin.diagnostics, { desc = '[S]earch [D]iagnostics' })
  vim.keymap.set('n', '<leader>sr', builtin.resume, { desc = '[S]earch [R]esume' })
  vim.keymap.set('n', '<leader>s.', builtin.oldfiles, { desc = '[S]earch Recent Files ("." for repeat)' })
  vim.keymap.set('n', '<leader>sc', builtin.commands, { desc = '[S]earch [C]ommands' })
  vim.keymap.set('n', '<leader><leader>', builtin.buffers, { desc = '[ ] Find existing buffers' })

  -- LSP pickers, added when an LSP attaches. (If you switch pickers, update here.)
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('telescope-lsp-attach', { clear = true }),
    callback = function(event)
      local buf = event.buf
      vim.keymap.set('n', 'grr', builtin.lsp_references, { buffer = buf, desc = '[G]oto [R]eferences' })
      vim.keymap.set('n', 'gri', builtin.lsp_implementations, { buffer = buf, desc = '[G]oto [I]mplementation' })
      vim.keymap.set('n', 'grd', builtin.lsp_definitions, { buffer = buf, desc = '[G]oto [D]efinition' })
      vim.keymap.set('n', 'gO', builtin.lsp_document_symbols, { buffer = buf, desc = 'Open Document Symbols' })
      vim.keymap.set('n', 'gW', builtin.lsp_dynamic_workspace_symbols, { buffer = buf, desc = 'Open Workspace Symbols' })
      vim.keymap.set('n', 'grt', builtin.lsp_type_definitions, { buffer = buf, desc = '[G]oto [T]ype Definition' })
    end,
  })

  -- Override default behavior/theme for buffer search
  vim.keymap.set('n', '<leader>/', function()
    builtin.current_buffer_fuzzy_find(require('telescope.themes').get_dropdown {
      winblend = 10,
      previewer = false,
    })
  end, { desc = '[/] Fuzzily search in current buffer' })

  vim.keymap.set('n', '<leader>s/', function()
    builtin.live_grep {
      grep_open_files = true,
      prompt_title = 'Live Grep in Open Files',
    }
  end, { desc = '[S]earch [/] in Open Files' })

  -- Shortcut to search your Neovim config files
  vim.keymap.set('n', '<leader>sn', function()
    builtin.find_files { cwd = vim.fn.stdpath 'config', follow = true }
  end, { desc = '[S]earch [N]eovim files' })
end

-- ============================================================
-- SECTION 6: LSP
-- LSP keymaps, server configuration, Mason tool installation
-- ============================================================
do
  -- LSP (Language Server Protocol) gives go-to-definition, references,
  -- completion, diagnostics, etc. Language servers are external tools installed
  -- separately from Neovim — Mason installs them automatically. See `:help lsp`.
  --
  -- To check/install tools manually: :Mason (press g? for help).

  -- Useful status updates for LSP
  vim.pack.add { gh 'j-hui/fidget.nvim' }
  require('fidget').setup {}

  -- Per-buffer setup when an LSP attaches
  vim.api.nvim_create_autocmd('LspAttach', {
    group = vim.api.nvim_create_augroup('kickstart-lsp-attach', { clear = true }),
    callback = function(event)
      local map = function(keys, func, desc, mode)
        mode = mode or 'n'
        vim.keymap.set(mode, keys, func, { buffer = event.buf, desc = 'LSP: ' .. desc })
      end

      map('grn', vim.lsp.buf.rename, '[R]e[n]ame')
      map('gra', vim.lsp.buf.code_action, '[G]oto Code [A]ction', { 'n', 'x' })
      map('grD', vim.lsp.buf.declaration, '[G]oto [D]eclaration')

      -- Highlight references of the word under the cursor when it rests
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if client and client:supports_method('textDocument/documentHighlight', event.buf) then
        local highlight_augroup = vim.api.nvim_create_augroup('kickstart-lsp-highlight', { clear = false })
        vim.api.nvim_create_autocmd({ 'CursorHold', 'CursorHoldI' }, {
          buffer = event.buf,
          group = highlight_augroup,
          callback = vim.lsp.buf.document_highlight,
        })
        vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
          buffer = event.buf,
          group = highlight_augroup,
          callback = vim.lsp.buf.clear_references,
        })
        vim.api.nvim_create_autocmd('LspDetach', {
          group = vim.api.nvim_create_augroup('kickstart-lsp-detach', { clear = true }),
          callback = function(event2)
            vim.lsp.buf.clear_references()
            vim.api.nvim_clear_autocmds { group = 'kickstart-lsp-highlight', buffer = event2.buf }
          end,
        })
      end

      -- Toggle inlay hints (<leader>th) if the server supports them
      if client and client:supports_method('textDocument/inlayHint', event.buf) then
        map('<leader>th', function()
          vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = event.buf })
        end, '[T]oggle Inlay [H]ints')
      end
    end,
  })

  -- Language servers to enable. Keys are lspconfig server names; each is also
  -- added to Mason's ensure_installed. See `:help lspconfig-all`.
  local servers = {
    -- Lua (for editing this config and Lua projects)
    stylua = {}, -- Lua formatter (installed via Mason; wired in conform below)

    lua_ls = {
      on_init = function(client)
        client.server_capabilities.documentFormattingProvider = false -- formatting via stylua
        if client.workspace_folders then
          local path = client.workspace_folders[1].name
          if path ~= vim.fn.stdpath 'config' and (vim.uv.fs_stat(path .. '/.luarc.json') or vim.uv.fs_stat(path .. '/.luarc.jsonc')) then
            return
          end
        end
        client.config.settings.Lua = vim.tbl_deep_extend('force', client.config.settings.Lua, {
          runtime = { version = 'LuaJIT', path = { 'lua/?.lua', 'lua/?/init.lua' } },
          workspace = {
            checkThirdParty = false,
            library = vim.tbl_extend('force', vim.api.nvim_get_runtime_file('', true), {
              '${3rd}/luv/library',
              '${3rd}/busted/library',
            }),
          },
        })
      end,
      settings = {
        Lua = { format = { enable = false } }, -- formatting via stylua
      },
    },

    -- Python: basedpyright for intelligence + diagnostics. Formatting/import
    -- sorting is handled by ruff (see SECTION 7).
    basedpyright = {},
  }

  vim.pack.add {
    gh 'neovim/nvim-lspconfig',
    gh 'mason-org/mason.nvim',
    gh 'mason-org/mason-lspconfig.nvim',
    gh 'WhoIsSethDaniel/mason-tool-installer.nvim',
  }

  require('mason').setup {}

  local ensure_installed = vim.tbl_keys(servers or {})
  vim.list_extend(ensure_installed, {
    'ruff', -- Python linter/formatter (used by conform.nvim)
  })

  require('mason-tool-installer').setup { ensure_installed = ensure_installed }

  for name, server in pairs(servers) do
    vim.lsp.config(name, server)
    vim.lsp.enable(name)
  end
end

-- ============================================================
-- SECTION 7: FORMATTING
-- conform.nvim setup + format keymap
-- ============================================================
do
  vim.pack.add { gh 'stevearc/conform.nvim' }
  require('conform').setup {
    notify_on_error = false,
    -- Format on save only for the filetypes listed here
    format_on_save = function(bufnr)
      local enabled_filetypes = {
        lua = true,
        python = true,
      }
      if enabled_filetypes[vim.bo[bufnr].filetype] then
        return { timeout_ms = 500 }
      else
        return nil
      end
    end,
    default_format_opts = {
      lsp_format = 'fallback', -- use external formatters if configured, else LSP
    },
    formatters_by_ft = {
      lua = { 'stylua' },
      python = { 'ruff_format', 'ruff_organize_imports' },
    },
  }

  vim.keymap.set({ 'n', 'v' }, '<leader>f', function()
    require('conform').format { async = true }
  end, { desc = '[F]ormat buffer' })
end

-- ============================================================
-- SECTION 8: AUTOCOMPLETE & SNIPPETS
-- blink.cmp + LuaSnip
-- ============================================================
do
  -- Snippet engine. See `:help luasnip`
  vim.pack.add { { src = gh 'L3MON4D3/LuaSnip', version = vim.version.range '2.*' } }
  require('luasnip').setup {}

  -- Autocomplete engine. See `:help blink-cmp`
  vim.pack.add { { src = gh 'saghen/blink.cmp', version = vim.version.range '1.*' } }
  require('blink.cmp').setup {
    keymap = {
      -- 'default' mirrors built-in completions. See `:help ins-completion`
      -- /<C-space>: open menu or docs; <Tab>/<S-Tab> or <C-n>/<C-p>: select; <C-e>: hide; <C-k>: signature
      preset = 'default',
    },
    appearance = { nerd_font_variant = 'mono' },
    completion = {
      documentation = { auto_show = false, auto_show_delay_ms = 500 },
    },
    sources = { default = { 'lsp', 'path', 'snippets' } },
    snippets = { preset = 'luasnip' },
    fuzzy = { implementation = 'lua' }, -- or 'prefer_rust_with_warning' for the rust matcher
    signature = { enabled = true },
  }
end

-- ============================================================
-- SECTION 9: TREESITTER
-- Parser installation, syntax highlighting, indentation
-- ============================================================
do
  -- Treesitter powers syntax highlighting, folding, and indentation.
  -- See `:help nvim-treesitter-intro`
  vim.pack.add { { src = gh 'nvim-treesitter/nvim-treesitter', version = 'main' } }

  -- Ensure basic parsers are installed
  local parsers = {
    'bash', 'c', 'diff', 'html', 'lua', 'luadoc', 'markdown', 'markdown_inline',
    'python', 'query', 'vim', 'vimdoc',
  }
  require('nvim-treesitter').install(parsers)

  ---@param buf integer
  ---@param language string
  local function treesitter_try_attach(buf, language)
    if not vim.treesitter.language.add(language) then
      return
    end
    vim.treesitter.start(buf, language)

    -- Enable treesitter-based indentation where an indent query exists
    local has_indent_query = vim.treesitter.query.get(language, 'indents') ~= nil
    if has_indent_query then
      vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end

  local available_parsers = require('nvim-treesitter').get_available()
  vim.api.nvim_create_autocmd('FileType', {
    callback = function(args)
      local buf, filetype = args.buf, args.match
      local language = vim.treesitter.language.get_lang(filetype)
      if not language then
        return
      end

      local installed_parsers = require('nvim-treesitter').get_installed 'parsers'
      if vim.tbl_contains(installed_parsers, language) then
        treesitter_try_attach(buf, language)
      elseif vim.tbl_contains(available_parsers, language) then
        require('nvim-treesitter').install(language):await(function()
          treesitter_try_attach(buf, language)
        end)
      else
        treesitter_try_attach(buf, language)
      end
    end,
  })
end

-- ============================================================
-- SECTION 10: OPTIONAL EXAMPLES / NEXT STEPS
-- Uncomment to enable additional kickstart-style plugins.
-- ============================================================
do
  -- Examples (originally in kickstart's repo under kickstart/plugins/):
  -- require 'kickstart.plugins.debug'        -- nvim-dap
  -- require 'kickstart.plugins.indent_line'  -- mini.indentscope
  -- require 'kickstart.plugins.lint'         -- nvim-lint
  -- require 'kickstart.plugins.autopairs'    -- mini.autopairs
  -- require 'kickstart.plugins.neo-tree'     -- file explorer
end

-- vim: ts=2 sts=2 sw=2 et
