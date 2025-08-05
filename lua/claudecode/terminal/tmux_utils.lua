---Common utilities for tmux-based terminal providers.
---@module 'claudecode.terminal.tmux_utils'

local M = {}

local logger = require("claudecode.logger")

---Check if tmux command is available
---@return boolean
function M.is_tmux_available()
  local handle = io.popen("command -v tmux 2>/dev/null")
  if not handle then
    return false
  end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("%S") ~= nil
end

---Check if we're currently inside a tmux session
---@return boolean
function M.is_in_tmux()
  return vim.env.TMUX ~= nil
end

---Get the current tmux session name
---@return string|nil
function M.get_current_session()
  if not M.is_in_tmux() then
    return nil
  end

  local handle = io.popen("tmux display-message -p '#S' 2>/dev/null")
  if not handle then
    return nil
  end
  local result = handle:read("*a")
  handle:close()

  if result then
    return result:gsub("%s+$", "") -- trim whitespace
  end
  return nil
end

---Get tmux version as major, minor numbers
---@return number|nil, number|nil
function M.get_tmux_version()
  local handle = io.popen("tmux -V 2>/dev/null")
  if not handle then
    return nil
  end
  local result = handle:read("*a")
  handle:close()

  if result then
    local version = result:match("tmux (%d+%.%d+)")
    if version then
      local major, minor = version:match("(%d+)%.(%d+)")
      return tonumber(major), tonumber(minor)
    end
  end
  return nil
end

---Check if tmux supports popup feature (>= 3.2)
---@return boolean
function M.supports_popup()
  local major, minor = M.get_tmux_version()
  if not major or not minor then
    return false
  end
  -- Popup support was added in tmux 3.2
  return major > 3 or (major == 3 and minor >= 2)
end

---Build environment variables string for tmux commands
---@param env_table table
---@return string
function M.build_env_string(env_table)
  local env_args = {}
  for key, value in pairs(env_table) do
    table.insert(env_args, key .. "=" .. value)
  end
  return table.concat(env_args, " ")
end

---Check if a tmux pane exists
---@param pane_id string
---@return boolean
function M.pane_exists(pane_id)
  if not pane_id then
    return false
  end

  local handle = io.popen("tmux list-panes -a -F '#{pane_id}' 2>/dev/null")
  if not handle then
    return false
  end

  local panes = handle:read("*a")
  handle:close()

  if not panes then
    return false
  end

  for pane in panes:gmatch("[^\r\n]+") do
    if pane == pane_id then
      return true
    end
  end
  return false
end

---Check if a tmux session exists
---@param session_name string
---@return boolean
function M.session_exists(session_name)
  if not session_name then
    return false
  end

  local handle = io.popen("tmux list-sessions -F '#{session_name}' 2>/dev/null")
  if not handle then
    return false
  end

  local sessions = handle:read("*a")
  handle:close()

  if not sessions then
    return false
  end

  for session in sessions:gmatch("[^\r\n]+") do
    if session == session_name then
      return true
    end
  end
  return false
end

---Find existing Claude panes by checking pane commands
---@return string|nil pane_id The pane ID if found
function M.find_existing_claude_pane()
  local handle = io.popen("tmux list-panes -a -F '#{pane_id} #{pane_current_command}' 2>/dev/null")
  if not handle then
    return nil
  end

  local panes = handle:read("*a")
  handle:close()

  if not panes then
    return nil
  end

  for line in panes:gmatch("[^\r\n]+") do
    local pane, command = line:match("^(%S+)%s+(.*)$")
    if pane and command and command:match("claude") then
      logger.debug("terminal", "Found existing Claude pane:", pane)
      return pane
    end
  end

  return nil
end

---Find existing Claude popup sessions by checking session names and commands
---@return string|nil session_name The session name if found
function M.find_existing_claude_popup()
  local handle = io.popen("tmux list-sessions -F '#{session_name}' 2>/dev/null")
  if not handle then
    return nil
  end

  local sessions = handle:read("*a")
  handle:close()

  if not sessions then
    return nil
  end

  for session in sessions:gmatch("[^\r\n]+") do
    if session:match("claude%-popup%-") then
      -- Check if this session has a Claude process
      local check_cmd = string.format("tmux list-panes -t '%s' -F '#{pane_current_command}' 2>/dev/null", session)
      local check_handle = io.popen(check_cmd)
      if check_handle then
        local command = check_handle:read("*a")
        check_handle:close()
        if command and command:match("claude") then
          logger.debug("terminal", "Found existing Claude popup session:", session)
          return session
        end
      end
    end
  end

  return nil
end

---Generate a unique popup session name
---@return string
function M.generate_popup_session_name()
  return "claude-popup-" .. os.time() .. "-" .. math.random(1000, 9999)
end

---Execute a tmux command safely
---@param cmd string The tmux command to execute
---@return boolean success Whether the command succeeded
function M.execute_tmux_command(cmd)
  return os.execute(cmd .. " 2>/dev/null") == 0
end

---Build environment variable assignments for shell execution
---@param env_table table
---@return string
function M.build_env_assignments(env_table)
  local env_assignments = {}
  for key, value in pairs(env_table) do
    -- Escape single quotes in the value for shell safety
    local escaped_value = value:gsub("'", "'\"'\"'")
    table.insert(env_assignments, string.format("%s=%s", key, vim.fn.shellescape(escaped_value)))
  end
  return table.concat(env_assignments, " ")
end

---Add tool permissions to Claude command
---@param base_command string The base Claude command
---@return string The command with permissions
local function add_permissions(base_command)
  -- Add common tools that are useful for development
  local allowed_tools = {
    "Bash",
    "Edit",
    "LS",
    "Grep",
    "Bash(git:*)",
    "Bash(gh:*)"
  }

  local tools_list = table.concat(allowed_tools, " ")
  return base_command .. " --allowedTools \"" .. tools_list .. "\""
end

---Create the full command with environment variables and delay
---@param cmd_string string The Claude command to execute
---@param env_table table Environment variables
---@param include_permissions boolean Whether to add tool permissions (optional)
---@return string The complete command string
function M.create_claude_command(cmd_string, env_table, include_permissions)
  local env_prefix = M.build_env_assignments(env_table)
  local claude_cmd = cmd_string

  -- Only add permissions if explicitly requested and not for popup (which has issues with long commands)
  if include_permissions then
    claude_cmd = add_permissions(cmd_string)
  end

  local delayed_command = string.format("sleep 0.5 && %s", claude_cmd)
  return env_prefix .. " " .. delayed_command
end

return M
