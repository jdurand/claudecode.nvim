---Tmux popup terminal provider for Claude Code.
---Opens Claude terminal in a tmux popup window.
---@module 'claudecode.terminal.tmux-popup'

local M = {}

local logger = require("claudecode.logger")
local utils = require("claudecode.utils")

local popup_session_name = nil
local tip_shown = false

---@type TerminalConfig
local config = require("claudecode.terminal").defaults

local function cleanup_state()
  popup_session_name = nil
end

local function is_tmux_available()
  local handle = io.popen("command -v tmux 2>/dev/null")
  if not handle then
    return false
  end
  local result = handle:read("*a")
  handle:close()
  return result and result:match("%S") ~= nil
end

local function is_in_tmux()
  return vim.env.TMUX ~= nil
end

local function get_tmux_version()
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

local function supports_popup()
  local major, minor = get_tmux_version()
  if not major or not minor then
    return false
  end
  -- Popup support was added in tmux 3.2
  return major > 3 or (major == 3 and minor >= 2)
end

local function popup_exists(session_name)
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

local function is_valid()
  return popup_session_name and popup_exists(popup_session_name)
end

local function generate_popup_session_name()
  return "claude-popup-" .. os.time() .. "-" .. math.random(1000, 9999)
end

local function create_tmux_popup(cmd_string, env_table, effective_config)
  if not is_in_tmux() then
    vim.notify("Must be inside a tmux session to use tmux-popup terminal provider", vim.log.levels.ERROR)
    return false
  end

  if not supports_popup() then
    vim.notify("tmux-popup provider requires tmux >= 3.2 for popup support", vim.log.levels.ERROR)
    return false
  end

  -- Build environment variables string for tmux
  local env_args = {}
  for key, value in pairs(env_table) do
    table.insert(env_args, key .. "=" .. value)
  end
  local env_string = table.concat(env_args, " ")

  -- Generate unique session name for the popup
  local session_name = generate_popup_session_name()

  -- Calculate popup dimensions (use config percentage but adapt for popup)
  local width_percent = math.floor((effective_config.split_width_percentage or 0.5) * 100)
  local height_percent = 80 -- Fixed height percentage for popup

  -- Create popup with new session
  local tmux_cmd = string.format(
    'tmux display-popup -d \'%s\' -w %d%% -h %d%% -E \'tmux new-session -d -s "%s" "%s %s" && tmux attach-session -t "%s"\'',
    vim.fn.getcwd(),
    width_percent,
    height_percent,
    session_name,
    env_string,
    cmd_string,
    session_name
  )

  local success = os.execute(tmux_cmd .. " 2>/dev/null") == 0

  if success then
    popup_session_name = session_name
    logger.debug("terminal", "Created tmux popup with session:", session_name)
    return true
  else
    vim.notify("Failed to create tmux popup", vim.log.levels.ERROR)
    return false
  end
end

local function focus_popup()
  if not is_valid() then
    return false
  end

  -- For popup, we need to recreate it to show again (tmux popups close when focus is lost)
  -- Check if session still exists but popup is closed
  if popup_exists(popup_session_name) then
    local width_percent = math.floor((config.split_width_percentage or 0.5) * 100)
    local height_percent = 80

    local cmd = string.format(
      "tmux display-popup -w %d%% -h %d%% -E 'tmux attach-session -t \"%s\"'",
      width_percent,
      height_percent,
      popup_session_name
    )

    local success = os.execute(cmd .. " 2>/dev/null") == 0

    if success then
      logger.debug("terminal", "Reopened tmux popup session:", popup_session_name)
    else
      logger.warn("terminal", "Failed to reopen tmux popup session:", popup_session_name)
    end

    return success
  end

  return false
end

local function close_popup()
  if not is_valid() then
    return
  end

  -- Kill the popup session
  local cmd = string.format("tmux kill-session -t '%s'", popup_session_name)
  local success = os.execute(cmd .. " 2>/dev/null") == 0

  if success then
    logger.debug("terminal", "Closed tmux popup session:", popup_session_name)
  else
    logger.warn("terminal", "Failed to close tmux popup session:", popup_session_name)
  end

  cleanup_state()
end

local function find_existing_claude_popup()
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
    -- Popup session exists
    if focus then
      focus_popup()
    end
    return
  end

  -- Check for existing Claude popup session we might have lost track of
  local existing_session = find_existing_claude_popup()
  if existing_session then
    popup_session_name = existing_session
    logger.debug("terminal", "Recovered existing Claude popup session")
    if focus then
      focus_popup()
    end
    return
  end

  -- Create new popup
  if not create_tmux_popup(cmd_string, env_table, effective_config) then
    vim.notify("Failed to create tmux popup for Claude terminal", vim.log.levels.ERROR)
    return
  end

  -- Popup is created with focus by default in tmux

  if config.show_native_term_exit_tip and not tip_shown then
    vim.notify("Tmux popup opened for Claude. Popup will close when focus is lost.", vim.log.levels.INFO)
    tip_shown = true
  end
end

function M.close()
  close_popup()
end

---Simple toggle: always show/hide terminal regardless of focus
---@param cmd_string string
---@param env_table table
---@param effective_config TerminalConfig
function M.simple_toggle(cmd_string, env_table, effective_config)
  if is_valid() then
    -- Popup session exists, close it
    close_popup()
  else
    -- Check for existing Claude popup session we might have lost track of
    local existing_session = find_existing_claude_popup()
    if existing_session then
      popup_session_name = existing_session
      logger.debug("terminal", "Recovered existing Claude popup session")
      focus_popup()
    else
      -- Create new popup
      if not create_tmux_popup(cmd_string, env_table, effective_config) then
        vim.notify("Failed to create tmux popup for Claude terminal", vim.log.levels.ERROR)
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
  -- For popup, focus_toggle behaves the same as simple_toggle since
  -- popups are either visible (focused) or completely hidden
  M.simple_toggle(cmd_string, env_table, effective_config)
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
  -- Tmux popups don't have Neovim buffer numbers
  -- Return nil to indicate no buffer is associated
  return nil
end

--- @return boolean
function M.is_available()
  return is_tmux_available() and is_in_tmux() and supports_popup()
end

---Ensures the Claude popup is visible (for compatibility with terminal interface)
function M.ensure_visible()
  if is_valid() then
    focus_popup()
  end
end

---Get terminal for testing (returns session info for popup)
---@return table|nil
function M._get_terminal_for_test()
  if is_valid() then
    return {
      popup_session_name = popup_session_name,
      session_exists = popup_exists(popup_session_name),
    }
  end
  return nil
end

--- @type TerminalProvider
return M
