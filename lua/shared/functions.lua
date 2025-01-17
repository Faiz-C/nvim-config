function require_user_config()
    local config_paths = {
        os.getenv("MSS_NEOVIM_USER_DIR") or "GARBAGE",
        "~/local/src/user.nvim/",
        "~/.config/user.nvim/",
        "~/.user.nvim/",
    }

    for _, path in ipairs(config_paths) do
        local expanded = vim.fn.expand(path)
        if vim.fn.filereadable(expanded .. "init.lua") == 1 then
            package.path = (expanded .. "?.lua;") .. (expanded .. "?/init.lua") .. ";" .. package.path
            require('init')

            vim.g.user_config_path = expanded
            break
        end
    end
end

function require_viml(vimlConfigPath)
    vim.cmd(string.format('source %s/viml/%s', vim.g.user_config_path, vimlConfigPath))
end

function open_toggle_term()
    vim.cmd(
        string.format("ToggleTerm ToggleTerm direction=vertical size=%d", vim.api.nvim_list_uis()[1].width * 0.4)
    )
end

function alt_buf_with_fallback()
    if vim.fn.bufnr('#') == -1 then
        vim.cmd('bnext')
    else
        vim.cmd('b#')
    end
end

function get_buf_dir()
    return vim.fn.expand("%:p:h")
end

function fzf_find_file(cwd)
    if cwd == nil then
        cwd = vim.loop.cwd()
    end
    local fzf = require('fzf-lua')
    fzf.files({
        cwd = cwd,
        fd_opts = '--color=never --hidden --follow --exclude .git --max-depth 1',
        actions = {
            ['default'] = function (selected, opts)
                local file = fzf.path.entry_to_file(selected[1], opts)

                if vim.fn.isdirectory(file.path) ~= 0 then
                    fzf_find_file(file.path)
                else
                    fzf.actions.file_edit(selected, opts)
                end
            end,
            ['ctrl-w'] = {
                function()
                    local new_cwd = vim.loop.fs_realpath(cwd .. '/..')
                    fzf_find_file(new_cwd)
                end
            },
        },
    })
end

function get_sourcegraph_url()
    local repo_root = vim.fn.finddir('.git/..', vim.fn.expand('%:p:h') .. ';'):gsub('.git/', '')
    local file_path = vim.fn.expand('%:p')
    local url = 'https://sourcegraph.pp.dropbox.com/' ..
        vim.fn.fnamemodify(repo_root, ':t') .. -- repo name
        '/-/blob' ..
        file_path:gsub(repo_root, '') .. -- relative file path
        '?L' ..
        vim.fn.line('.')

    vim.fn.setreg('+', url)
end

local function open_current_tsnode_in_scratch_buf()
    local ts_utils = require('nvim-treesitter.ts_utils')
    local node = ts_utils.get_node_at_cursor()

    while node do
        local type = node:type()
        if type == 'function_declaration' or
            type == 'function_definition' or
            type == 'function_item' or
            type == 'method_declaration' then
            break
        else
            node = node:parent()
        end
    end

    if not node then return end

    local start_row, start_col, end_row, end_col = vim.treesitter.get_node_range(node)
    -- Take entire first row to grab indentation
    local text = vim.api.nvim_buf_get_text(0, start_row, 0, end_row, end_col, {})
    -- local text = vim.treesitter.query.get_node_text(node, 0, { concat = false })

    -- Strip leading indent
    local indent = text[1]:match("^%s*")
    for k, v in pairs(text) do
        text[k] = v:sub(indent:len()+1, -1)
    end

    local original_buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo.filetype
    local cursor_row, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))

    local tmp_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_lines(tmp_buf, 0, -1, true, text)
    vim.api.nvim_buf_set_option(tmp_buf, 'filetype', ft)
    vim.api.nvim_set_current_buf(tmp_buf)
    vim.api.nvim_win_set_cursor(0, { cursor_row - start_row, cursor_col })
    vim.api.nvim_buf_set_name(tmp_buf, '*narrow-tmp*')

    vim.api.nvim_create_autocmd({'BufDelete'}, {
        pattern = {'<buffer>'},
        callback = function()
            local buffer_content = vim.api.nvim_buf_get_lines(tmp_buf, 0, -1, false)
            -- Reindent
            for k, v in pairs(buffer_content) do
                if v ~= "" then
                    buffer_content[k] = indent .. v
                end
            end

            vim.api.nvim_buf_set_text(original_buf, start_row, 0, end_row, end_col, buffer_content)
        end,
    })
end

function narrow_to_function()
    if string.find(vim.api.nvim_buf_get_name(0), '*narrow-tmp*', nil, true) then
        vim.api.nvim_buf_delete(0, {})
    else
        open_current_tsnode_in_scratch_buf()
    end
end

