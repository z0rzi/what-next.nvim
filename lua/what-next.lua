local M = {
    context_range = {0, 0, 0}, -- {line_before, line_after, current_line}
    context_file = "",
    current_file_content = {},
}

local Context = require("context")

function M.setup(opts)
    Context.setup_autocmds()

    -- Creating diffs directory if it doesn't exist
    local diffs_dir = "/tmp/what_next_diffs"
    if vim.fn.isdirectory(diffs_dir) == 0 then
        vim.fn.mkdir(diffs_dir, "p")
    end
end

function M.get_last_diffs()
    -- no more than 2 minutes old
    local timeout = 2 * 60

    local all_files_raw = vim.fn.glob("/tmp/what_next_diffs/*.diff")

    local all_files = vim.split(all_files_raw, "\n")

    -- Removing empty lines
    all_files = vim.tbl_filter(function(x) return x ~= "" end, all_files)

    local current_epoch = os.time()

    local valid_files = {}

    for _, file in ipairs(all_files) do
        -- Getting the file age from its name
        local file_epoch = tonumber(string.match(file, "/tmp/what_next_diffs/(%d+).diff"))

        local file_age = current_epoch - file_epoch

        if file_age > timeout then
            vim.fn.delete(file)
        else
            -- reading file and joining lines with newline
            local file_content = vim.fn.readfile(file)

            table.insert(valid_files, {
                diff = table.concat(file_content, '\n'),
                age = file_age,
            })
        end
    end

    return valid_files
end

function edit_code(modif)
    local current_buffer = vim.api.nvim_get_current_buf()

    local from_line_number = modif.input.from_line_number
    local to_line_number = modif.input.to_line_number
    local code = modif.input.code

    if from_line_number < to_line_number then
        vim.fn.deletebufline(current_buffer, from_line_number, to_line_number - 1)
    end
    if code:len() > 0 then
        vim.fn.append(from_line_number - 1, vim.split(code, "\n"))
    end
end

function get_lines_around_cursor()
    local LINES_AROUND_CURSOR = 30

    -- Get the current context
    local current_line = vim.fn.line(".")
    local last_line = vim.fn.line("$")
    local line_before = current_line - 50

    if line_before < 1 then line_before = 1 end
    local line_after = current_line + 30
    if line_after > last_line then line_after = last_line end
    local current_context_lines = vim.api.nvim_buf_get_lines(0, line_before - 1, line_after, false)

    -- Adding line numbers to the context
    local current_context_lines_with_numbers = {}
    local line_count = line_before
    for i, line in ipairs(current_context_lines) do
        if current_line == line_count then
            line = line .. ' <CURSOR_POSITION>'
        end
        table.insert(current_context_lines_with_numbers, line_count .. ': ' .. line)
        line_count = line_count + 1
    end

    return table.concat(current_context_lines_with_numbers, '\n')
end

function get_selected_lines()
    local line_before = vim.fn.getpos("'<")[2]
    local line_after = vim.fn.getpos("'>")[2]

    if line_before == line_after then
        return ''
    end

    local current_context_lines = vim.api.nvim_buf_get_lines(0, line_before - 1, line_after, false)

    -- Adding line numbers to the context
    local current_context_lines_with_numbers = {}
    local line_count = line_before
    for i, line in ipairs(current_context_lines) do
        table.insert(current_context_lines_with_numbers, line_count .. ': ' .. line)
        line_count = line_count + 1
    end

    return table.concat(current_context_lines_with_numbers, '\n')
end

function escape_message(message)
    -- Escaping the backslashes
    message = message:gsub('\\', '\\\\')
    -- Escaping the single quotes
    message = message:gsub("'", "\\'")
    -- Escaping the double quotes
    message = message:gsub('"', '\\"')
    -- Escaping the newlines
    message = message:gsub('\n', '\\n')

    return message
end

function queryLLM(select_mode)
    -- Getting the anthropic key from environment variables
    local api_key = os.getenv("ANTHROPIC_API_KEY")
    if api_key == nil then
        print("ANTHROPIC_API_KEY environment variable not set")
        return
    end

    local files = M.get_last_diffs()

    if table.getn(files) == 0 then
        print('Couldn\'t find any recent changes...')
        return
    end

    local messages = {};

    for _, file in ipairs(files) do
        table.insert(messages, '{"role":"user","content":"type: file_change\\ntime_ago: ' .. file.age .. ' seconds\\n' .. escape_message(file.diff) .. '"}')
    end

    local current_context = ''
    if select_mode then
        current_context = get_selected_lines()
    else
        current_context = get_lines_around_cursor()
    end
    local current_file = vim.fn.expand("%:p")

    local system_message = [[
You are an intelligent coding assistant capable of working with various programming languages and file types. Your goal is to predict and suggest the user's next code edits based on their recent changes and current context. Follow these guidelines:

1. Analyze the current file context and recent modifications across all changed files.
2. Identify the programming language and file type of the current file being edited.
3. Consider best practices and common patterns for the identified language/framework.
4. Focus on continuing the user's current task or pattern of edits.
5. Suggest logical next steps based on the code structure and recent changes.

The user is currently editing the file: ]] .. current_file .. [[

Current context around cursor:
]] .. '\n' .. current_context .. [[

When predicting changes:
- Continue the pattern of recent edits made by the user
- Complete incomplete structures (functions, classes, etc.) if applicable
- Maintain consistency with the existing code style and conventions
- Prioritize changes at or near the cursor position
- Consider the context of recent changes in other files if relevant

Use the `edit-code` tool to suggest specific changes, use it as many times as necessary to apply all the necessary changes. Focus on small, incremental edits that logically follow the user's recent actions.
    ]]

    system_message = escape_message(system_message)

    local command = [[
        curl https://api.anthropic.com/v1/messages \
             --header "x-api-key: $ANTHROPIC_API_KEY" \
             --header "anthropic-version: 2023-06-01" \
             --header "content-type: application/json" \
             --data \
        '{
            "model": "claude-3-5-sonnet-20241022",
            "temperature": 0.2,
            "max_tokens": 1024,
            "tool_choice": {
                "type": "tool",
                "name": "edit-code",
                "disable_parallel_tool_use": false
            },
            "system": "]] .. system_message .. [[",
            "messages": [ ]] .. table.concat(messages, ',') .. [[ ],
            "tools": [
                {
                    "name": "edit-code",
                    "description": "Removes the code at the provided range, and remplaces it with the provided code. Be sure to provide the changes ordered from bottom to top",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "from_line_number": {
                                "type": "integer",
                                "description": "The line number from which the code should be replaced (inclusive)"
                            },
                            "to_line_number": {
                                "type": "integer",
                                "description": "The line number to which the code should be replaced (exclusive)"
                            },
                            "code": {
                                "type": "string",
                                "description": "The code to insert. (leave empty to just remove)"
                            }
                        }
                    }
                },
                {
                    "name": "edits-purpose",
                    "description": "Provides a small description of the purpose of the edits. The description should be less than 100 characters, to display it in the status bar of the editor.",
                    "input_schema": {
                        "type": "object",
                        "properties": {
                            "purpose": {
                                "type": "string",
                                "description": "The purpose of the edits"
                            }
                        }
                    }
                }
            ]
        }' \
        2> /dev/null
    ]]

    vim.fn.writefile(vim.split(command, "\n"), '/tmp/what_next.log')
    
    local response = vim.fn.system(command)
    
    local json = vim.fn.json_decode(response)
    if json == nil then
        print("Error parsing JSON response")
        return
    end

    if json.type == "error" then
        print("[ERROR] - " .. json.error.message)
        -- Storing the command in a log file
        local log_file = "/tmp/what_next.log"
        vim.fn.writefile(vim.split(command, "\n"), log_file)
        print('Command written to ' .. log_file)
        return
    end
    
    if json.content == nil then
        print("No content in the response...")
        print(response)
        return
    end
    
    -- Printing the response
    for _, content in ipairs(json.content) do
        if content.type == "text" then
            -- print(content.text)
        end
        if content.type == "tool_use" then
            local tool_name = content.name
            if tool_name == "edit-code" then
                edit_code(content)
            elseif tool_name == "edits-purpose" then
                print(content.input.purpose)
            end
        end
    end
end

function M.predict_next_edit(select_mode)
    Context.create_diff_file()

    queryLLM(select_mode)
end

return M
