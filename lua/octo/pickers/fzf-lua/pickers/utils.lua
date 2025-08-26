---@diagnostic disable
local navigation = require "octo.navigation"
local utils = require "octo.utils"
local fzf_utils = require "fzf-lua.utils"

local M = {}

M.multi_dropdown_opts = {
  prompt = nil,
  winopts = {
    height = 15,
    width = 0.4,
  },
}

M.dropdown_opts = vim.tbl_deep_extend("force", M.multi_dropdown_opts, {
  fzf_opts = {
    ["--no-multi"] = "",
  },
})

---@param opts table<string, string>
---@param kind string
---@return string
function M.get_filter(opts, kind)
  local filter = ""
  local allowed_values = {}
  if kind == "issue" then
    allowed_values = { "since", "createdBy", "assignee", "mentioned", "labels", "milestone", "states" }
  elseif kind == "pull_request" then
    allowed_values = { "baseRefName", "headRefName", "labels", "states" }
  end

  for _, value in pairs(allowed_values) do
    if opts[value] then
      local val ---@type string|string[]
      local splitted_val = vim.split(opts[value], ",")
      if #splitted_val > 1 then
        -- list
        val = splitted_val
      else
        -- string
        val = opts[value]
      end
      val = vim.json.encode(val)
      val = string.gsub(val, '"OPEN"', "OPEN")
      val = string.gsub(val, '"CLOSED"', "CLOSED")
      val = string.gsub(val, '"MERGED"', "MERGED")
      filter = filter .. value .. ":" .. val .. ","
    end
  end

  return filter
end

---Open the entry in a buffer.
---
---@param command 'default' |'horizontal' | 'vertical' | 'tab'
---@param entry table
function M.open(command, entry)
  if command == "default" then
    vim.cmd [[:buffer %]]
  elseif command == "horizontal" then
    vim.cmd [[:sbuffer %]]
  elseif command == "vertical" then
    vim.cmd [[:vert sbuffer %]]
  elseif command == "tab" then
    vim.cmd [[:tab sb %]]
  end

  if not entry.kind then
    local buf = vim.api.nvim_create_buf(false, true)

    if entry.author and entry.ordinal then
      local lines = {}

      vim.list_extend(lines, { string.format("Commit: %s", entry.value) })
      vim.list_extend(lines, { string.format("Author: %s", entry.author) })
      vim.list_extend(lines, { string.format("Date: %s", entry.date) })
      vim.list_extend(lines, { "" })
      vim.list_extend(lines, vim.split(entry.msg, "\n"))
      vim.list_extend(lines, { "" })

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      vim.api.nvim_buf_set_option(buf, "filetype", "git")

      vim.api.nvim_buf_add_highlight(buf, -1, "OctoDetailsLabel", 0, 0, string.len "Commit:")
      vim.api.nvim_buf_add_highlight(buf, -1, "OctoDetailsLabel", 1, 0, string.len "Author:")
      vim.api.nvim_buf_add_highlight(buf, -1, "OctoDetailsLabel", 2, 0, string.len "Date:")

      local url = string.format("/repos/%s/commits/%s", entry.repo, entry.value)
      local cmd =
        table.concat({ "gh", "api", "--paginate", url, "-H", "'Accept: application/vnd.github.v3.diff'" }, " ")
      local proc = io.popen(cmd, "r")
      local output ---@type string
      if proc ~= nil then
        output = proc:read "*a"
        proc:close()
      else
        output = "Failed to read from " .. url
      end

      vim.api.nvim_buf_set_lines(buf, #lines, -1, false, vim.split(output, "\n"))
    end

    if entry.change and entry.change.patch then
      local diff = entry.change.patch
      if diff then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(diff, "\n"))
        vim.api.nvim_buf_set_option(buf, "filetype", "diff")
      end
    end

    vim.api.nvim_win_set_buf(0, buf)
    return
  end

  utils.get(entry.kind, entry.value, entry.repo)
end

local function save_to_qf(is_loc, items, title, winid)
  is_loc = is_loc or false

  if not is_loc then
    vim.fn.setqflist({}, " ", { items = items, title = title })
    return
  end

  winid = winid or vim.api.nvim_get_current_win()
  vim.fn.setloclist(winid, {}, " ", { items = items, title = title })
end

local function is_loclist(buf)
  buf = buf or 0
  return vim.fn.getloclist(buf, { filewinid = 1 }).filewinid ~= 0
end

function M.get_first_letter_uppercase(str)
  local first_word = str:match "%w+"
  if first_word then
    return "[" .. first_word:sub(1, 1):upper() .. "]"
  end
  return ""
end

function M.get_lowercase(str)
  return str:lower()
end

function M.get_uppercase_first_letter(str)
  str = M.get_lowercase(str)
  return (str:gsub("^%l", string.upper))
end

function M.open_in_qf_or_loc(is_loc, items, title)
  is_loc = is_loc or is_loclist()

  save_to_qf(is_loc, items, title)

  if is_loc then
    vim.cmd "lopen"
    return
  end

  vim.cmd "copen"
end

---Gets a consistent prompt.
---
---@param title string The original prompt title.
---@return string prompt A prompt smartly postfixed with "> ".
---
---> get_prompt(nil) == "> "
---> get_prompt("") == "> "
---> get_prompt("something") == "something> "
---> get_prompt("something else>") == "something else> "
---> get_prompt("penultimate thing > ") == "penultimate thing > "
---> get_prompt("last th> ing") == "last th> ing> "
function M.get_prompt(title)
  if title == nil or title == "" then
    return "> "
  elseif string.match(title, ">$") then
    return title .. " "
  elseif not string.match(title, "> $") then
    return title .. "> "
  end

  return title
end

---Opens the entry in your default browser.
---
---@param entry table
function M.open_in_browser(entry)
  local number ---@type integer
  local repo = entry.repo
  if entry.kind ~= "repo" then
    number = entry.value
  end
  navigation.open_in_browser(entry.kind, repo, number)
end

---Copies the entry url to the clipboard.
---
---@param entry table
function M.copy_url(entry)
  utils.copy_url(entry.obj.url)
end

---@param s string
---@param hexcol string
---@return string|nil
function M.color_string_with_hex(s, hexcol)
  local r, g, b = hexcol:match "#(..)(..)(..)"
  if not r or not g or not b then
    return
  end
  r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)

  -- Foreground code?
  local escseq = ("\27[%d;2;%d;%d;%dm"):format(38, r, g, b) -- \27 is the escape code of ctrl-[ and <esc>
  return ("%s%s%s"):format(escseq, s, fzf_utils.ansi_escseq.clear)
end

---@param s unknown
---@param length integer
---@return string
function M.pad_string(s, length)
  local string_s = tostring(s)
  return string.format("%s%" .. (length - #string_s) .. "s", string_s, " ")
end

function M.format_title(prefix_title, opts)
  prefix_title = prefix_title or "Octo Fzf-Lua"

  local title_fzf = prefix_title

  local opts_obj

  if type(opts) == "string" then
    opts_obj = { repo = opts }
  elseif type(opts) == "table" then
    opts_obj = opts
  end

  -- if opts_obj.type then
  --   title_fzf = title_fzf .. " <type:" .. opts_obj.type .. ">"
  -- end
  --
  -- if #opts_obj.prompt > 0 then
  --   title_fzf = title_fzf .. " <prompt:" .. opts_obj.prompt .. ">"
  -- end

  if opts_obj.type then
    title_fzf = M.get_uppercase_first_letter(opts_obj.type) .. " " .. title_fzf
  end

  if opts_obj.login then
    title_fzf = title_fzf .. " - " .. opts_obj.login
  end

  if opts_obj.prompt and opts.prompt:match "repo:" then
    local repo = string.match(opts_obj.prompt, "repo:([%w%-%._/]+)")
    title_fzf = title_fzf .. " - " .. repo
  end

  if opts_obj.repo then
    title_fzf = title_fzf .. " - " .. opts_obj.repo
  end

  return " " .. title_fzf .. " "
end

return M
