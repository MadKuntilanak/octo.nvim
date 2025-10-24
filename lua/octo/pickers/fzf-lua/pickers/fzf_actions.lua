local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local octo_config = require "octo.config"
local utils = require "octo.utils"
local M = {}

local function format_entry_item(opts)
  local text

  if opts.obj then
    local title = opts.obj.title
    if title then
      text = title
    end

    local state = opts.obj.state
    if state then
      text = picker_utils.get_first_letter_uppercase(state) .. " " .. text
    end

    if opts.kind == "discussion" then
      local closed = opts.obj.closed and "[C]" or "[O]"
      if closed then
        text = closed .. " " .. text
      end
    end
  end

  local filename = opts.filename

  if text == nil then
    text = filename
  end

  return {
    filename = filename,
    lnum = 1,
    col = 1,
    text = text,
  }
end

---@param formatted_items table<string, table> entry.ordinal -> entry
local function build_items_qf(formatted_items, selected)
  local items = {}

  if #selected == 1 then
    local opts_sel = formatted_items[selected[1]]
    items[#items + 1] = format_entry_item(opts_sel)
  end

  if #selected > 1 then
    for _, sel in pairs(selected) do
      local opts_sel = formatted_items[sel]
      items[#items + 1] = format_entry_item(opts_sel)
    end
  end

  return items
end

---@param formatted_items table<string, table> entry.ordinal -> entry
---@return table<string, function>
function M.common_buffer_actions(formatted_items)
  return {
    ["default"] = function(selected)
      picker_utils.open("default", formatted_items[selected[1]])
    end,
    ["ctrl-v"] = function(selected)
      picker_utils.open("vertical", formatted_items[selected[1]])
    end,
    ["ctrl-s"] = function(selected)
      picker_utils.open("horizontal", formatted_items[selected[1]])
    end,
    ["ctrl-t"] = function(selected)
      picker_utils.open("tab", formatted_items[selected[1]])
    end,
    ["alt-q"] = function(selected)
      local items = build_items_qf(formatted_items, selected)
      picker_utils.open_in_qf_or_loc(false, items, "hello")
    end,
    ["alt-v"] = function(selected)
      local items = build_items_qf(formatted_items, selected)
      picker_utils.open_in_qf_or_loc(true, items, "hello")
    end,
    ["alt-Q"] = {
      prefix = "select-all+accept",
      fn = function(selected)
        local items = build_items_qf(formatted_items, selected)
        picker_utils.open_in_qf_or_loc(false, items, "hello")
      end,
    },
    ["alt-V"] = {
      prefix = "select-all+accept",
      fn = function(selected)
        local items = build_items_qf(formatted_items, selected)
        picker_utils.open_in_qf_or_loc(true, items, "hello")
      end,
    },
  }
end

---@param formatted_items table<string, table> entry.ordinal -> entry
---@return table<string, function>
function M.common_open_actions(formatted_items)
  local cfg = octo_config.values
  return vim.tbl_extend("force", M.common_buffer_actions(formatted_items), {
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.open_in_browser.lhs)] = function(selected)
      picker_utils.open_in_browser(formatted_items[selected[1]])
    end,
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.copy_url.lhs)] = function(selected)
      picker_utils.copy_url(formatted_items[selected[1]])
    end,
  })
end

return M
