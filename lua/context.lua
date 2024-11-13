local CONTEXT_SIZE_AROUND_CURSOR = 15

local context_cursor_line = 0
local context_file = ""

local function set_context_position()
    local current_line = vim.fn.line(".")
    local current_file = vim.fn.expand("%:p")

    context_cursor_line = current_line
    context_file = current_file
end

local function cursor_in_context()
    local current_line = vim.fn.line(".")
    local current_file = vim.fn.expand("%:p")

    local line_diff = math.abs(current_line - context_cursor_line)

    return line_diff <= 10 and current_file == context_file
end

local function get_current_context_content()
    -- Get the mark positions
    local line_before = vim.fn.getpos("'b")[2]
    local line_after = vim.fn.getpos("'a")[2]

    return vim.api.nvim_buf_get_lines(0, line_before - 1, line_after, false)
end

local function create_diff_file()
    -- Calculating the diff using the system diff command
    local diff = vim.fn.system("diff -U2 /tmp/what_next.before.txt /tmp/what_next.now.txt | tail +3")

    -- Checking if the diff is empty
    if diff:gsub("%s+", "") == "" then
        return
    end

    local diff_lines = vim.split(diff, "\n")

    if table.getn(diff_lines) > 25 then
        -- The diff is too long, there must be a problem...
        print("Diff is too long")
        print(diff)
        return
    end

    -- Storing the diff in a file
    local timestamp = os.time()
    local filename = "/tmp/what_next_diffs/" .. timestamp .. ".diff"

    -- Adding the file name at the top of the diff
    table.insert(diff_lines, 1, 'file_path: '..context_file)
    table.insert(diff_lines, 2, 'changes:')
    table.insert(diff_lines, 3, '```')
    table.insert(diff_lines, '```')

    vim.fn.writefile(diff_lines, filename)
end

local function cache_file()
    -- Saving the current version of the file
    vim.fn.writefile(
        vim.api.nvim_buf_get_lines(0, 0, -1, false),
        "/tmp/what_next.before.txt"
    )
end

local function file_changed()
    -- Saves the current buffer to '/tmp/what_next.now.txt'
    vim.fn.writefile(
        vim.api.nvim_buf_get_lines(0, 0, -1, false),
        "/tmp/what_next.now.txt"
    )
end

local function setup_autocmds()
    local augroup = vim.api.nvim_create_augroup("WhatNext", {})
    vim.api.nvim_create_autocmd("InsertEnter", {
        group = augroup,
        pattern = "*",
        callback = function()
            -- If we moved from the saved context, create diff & update the context
            if not cursor_in_context() then
                create_diff_file()
                set_context_position()
            end
        end,
    })

    vim.api.nvim_create_autocmd("InsertLeave", {
        group = augroup,
        pattern = "*",
        callback = function()
            -- Checking if we're still in the saved context.
            -- If not, cache the file, and update the context position
            -- If yes, save the content of the context after the edit.
            if cursor_in_context() then
                file_changed()
            else
                cache_file()
                set_context_position()
            end
        end,
    })

    vim.api.nvim_create_autocmd("TextChanged", {
        group = augroup,
        pattern = "*",
        callback = function()
            -- Same as InsertLeave
            if cursor_in_context() then
                file_changed()
            else
                set_context_position()
                file_changed()
            end
        end,
    })

    vim.api.nvim_create_autocmd("BufWritePost", {
        group = augroup,
        pattern = "*",
        callback = function()
            -- Calculate the diff
            -- Save the file content
            create_diff_file()
            cache_file()
        end,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = augroup,
        pattern = "*",
        callback = function()
            file_changed()
            cache_file()
            set_context_position()
        end,
    })
    vim.api.nvim_create_autocmd("FocusGained", {
        group = augroup,
        pattern = "*",
        callback = function()
            file_changed()
            cache_file()
            set_context_position()
        end,
    })
end

return {
    setup_autocmds = setup_autocmds,
    create_diff_file = create_diff_file,
}
