---Tmux pane terminal provider for Claude Code.
---Opens Claude terminal in a tmux vertical split to the right.
---@module 'claudecode.terminal.tmux-pane'

local M = {}

local logger = require("claudecode.logger")
local tmux_utils = require("claudecode.terminal.tmux_utils")
local utils = require("claudecode.utils")

local session_name = nil
local pane_id = nil
local tip_shown = false

---@type TerminalConfig
local config = require("claudecode.terminal").defaults

local function cleanup_state()
  session_name = nil
  pane_id = nil
end

local function is_valid()
  if not session_name or not pane_id then
    return false
  end

  return tmux_utils.pane_exists(pane_id)
end

local function create_tmux_pane(cmd_string, env_table, focus)
  if not tmux_utils.is_in_tmux() then
    vim.notify("Must be inside a tmux session to use tmux-pane terminal provider", vim.log.levels.ERROR)
    return false
  end

  local current_session = tmux_utils.get_current_session()
  if not current_session then
    vim.notify("Could not determine current tmux session", vim.log.levels.ERROR)
    return false
  end

  -- Build environment variables string for tmux
  local env_string = tmux_utils.build_env_string(env_table)

  -- Calculate 30% width of terminal
  local total_width = vim.fn.system("tmux display-message -p '#{window_width}'"):gsub("%s+$", "")
  local pane_width = math.floor(tonumber(total_width) * 0.3)

  -- Create vertical split to the right with specific width
  -- Remove -d flag to focus the pane, add -l flag for specific width
  local focus_flag = focus and "" or "-d"

  -- Build environment variables for tmux (using -e flag for each variable)
  local env_flags = {}
  for key, value in pairs(env_table) do
    table.insert(env_flags, string.format("-e %s='%s'", key, value))
  end
  local env_flags_str = table.concat(env_flags, " ")

  local tmux_cmd = string.format(
    "tmux split-window -h %s -l %d %s -c '%s' '%s'",
    focus_flag,
    pane_width,
    env_flags_str,
    vim.fn.getcwd(),
    cmd_string
  )

  local handle = io.popen(tmux_cmd .. " && tmux display-message -p '#{pane_id}' 2>/dev/null")
  if not handle then
    vim.notify("Failed to create tmux pane", vim.log.levels.ERROR)
    return false
  end

  local result = handle:read("*a")
  handle:close()

  if result and result:match("%S") then
    session_name = current_session
    pane_id = result:gsub("%s+$", "") -- trim whitespace
    logger.debug("terminal", "Created tmux pane:", pane_id, "in session:", session_name, "with width:", pane_width)
    return true
  else
    vim.notify("Failed to get tmux pane ID", vim.log.levels.ERROR)
    return false
  end
end

local function focus_pane()
  if not is_valid() then
    return false
  end

  local cmd = string.format("tmux select-pane -t '%s'", pane_id)
  local success = tmux_utils.execute_tmux_command(cmd)

  if success then
    logger.debug("terminal", "Focused tmux pane:", pane_id)
  else
    logger.warn("terminal", "Failed to focus tmux pane:", pane_id)
  end

  return success
end

local function close_pane()
  if not is_valid() then
    return
  end

  local cmd = string.format("tmux kill-pane -t '%s'", pane_id)
  local success = tmux_utils.execute_tmux_command(cmd)

  if success then
    logger.debug("terminal", "Closed tmux pane:", pane_id)
  else
    logger.warn("terminal", "Failed to close tmux pane:", pane_id)
  end

  cleanup_state()
end

---Setup the terminal module
---@param term_config TerminalConfig
function M.setup(term_config)
  config = term_config
end

--- @param cmd_string string
--- @param env_table table
--- @param effective_config table
--- @param focus boolean|nil
function M.open(cmd_string, env_table, effective_config, focus)
  focus = utils.normalize_focus(focus)

  if is_valid() then
    -- Pane already exists
    if focus then
      focus_pane()
    end
    return
  end

  -- Check for existing Claude pane we might have lost track of
  local existing_pane = tmux_utils.find_existing_claude_pane()
  if existing_pane then
    session_name = tmux_utils.get_current_session()
    pane_id = existing_pane
    logger.debug("terminal", "Recovered existing Claude pane")
    if focus then
      focus_pane()
    end
    return
  end

  -- Create new pane
  if not create_tmux_pane(cmd_string, env_table, focus) then
    vim.notify("Failed to create tmux pane for Claude terminal", vim.log.levels.ERROR)
    return
  end

  if config.show_native_term_exit_tip and not tip_shown then
    vim.notify("Tmux pane opened for Claude. Use tmux keybindings to navigate.", vim.log.levels.INFO)
    tip_shown = true
  end
end

function M.close()
  close_pane()
end

---Simple toggle: always show/hide terminal regardless of focus
---@param cmd_string string
---@param env_table table
---@param effective_config TerminalConfig
function M.simple_toggle(cmd_string, env_table, effective_config)
  if is_valid() then
    -- Pane exists, close it
    close_pane()
  else
    -- Check for existing Claude pane we might have lost track of
    local existing_pane = tmux_utils.find_existing_claude_pane()
    if existing_pane then
      session_name = tmux_utils.get_current_session()
      pane_id = existing_pane
      logger.debug("terminal", "Recovered existing Claude pane")
      focus_pane()
    else
      -- Create new pane
      if not create_tmux_pane(cmd_string, env_table, true) then
        vim.notify("Failed to create tmux pane for Claude terminal", vim.log.levels.ERROR)
        return
      end
    end
  end
end

---Smart focus toggle: switches to terminal if not focused, hides if currently focused
---@param cmd_string string
---@param env_table table
---@param effective_config TerminalConfig
function M.focus_toggle(cmd_string, env_table, effective_config)
  if is_valid() then
    -- Check if we're currently in the Claude pane
    local handle = io.popen("tmux display-message -p '#{pane_id}' 2>/dev/null")
    local current_pane = nil
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result then
        current_pane = result:gsub("%s+$", "")
      end
    end

    if current_pane == pane_id then
      -- We're in the Claude pane, close it
      close_pane()
    else
      -- We're not in the Claude pane, focus it
      focus_pane()
    end
  else
    -- Check for existing Claude pane we might have lost track of
    local existing_pane = tmux_utils.find_existing_claude_pane()
    if existing_pane then
      session_name = tmux_utils.get_current_session()
      pane_id = existing_pane
      logger.debug("terminal", "Recovered existing Claude pane")
      focus_pane()
    else
      -- Create new pane
      if not create_tmux_pane(cmd_string, env_table, true) then
        vim.notify("Failed to create tmux pane for Claude terminal", vim.log.levels.ERROR)
        return
      end
    end
  end
end

--- Legacy toggle function for backward compatibility (defaults to simple_toggle)
--- @param cmd_string string
--- @param env_table table
--- @param effective_config TerminalConfig
function M.toggle(cmd_string, env_table, effective_config)
  M.simple_toggle(cmd_string, env_table, effective_config)
end

--- @return number|nil
function M.get_active_bufnr()
  -- Tmux panes don't have Neovim buffer numbers
  -- Return nil to indicate no buffer is associated
  return nil
end

--- @return boolean
function M.is_available()
  return tmux_utils.is_tmux_available() and tmux_utils.is_in_tmux()
end

---Ensures the Claude pane is visible (for compatibility with terminal interface)
function M.ensure_visible()
  if is_valid() then
    focus_pane()
  end
end

---Get terminal for testing (returns nil for tmux as there's no buffer)
---@return table|nil
function M._get_terminal_for_test()
  if is_valid() then
    return {
      session_name = session_name,
      pane_id = pane_id,
    }
  end
  return nil
end

--- @type TerminalProvider
return M
