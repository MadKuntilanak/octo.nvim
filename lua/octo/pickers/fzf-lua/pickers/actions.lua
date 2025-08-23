---@diagnostic disable
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"

local cfg = octo_config.values

return function(flattened_actions)
  local titles = {}
  local formatted_actions = {}

  for _, action in ipairs(flattened_actions) do
    local entry = entry_maker.gen_from_octo_actions(action)
    if entry ~= nil then
      formatted_actions[entry.ordinal] = entry
      table.insert(titles, entry.ordinal)
    end
  end

  table.sort(titles)

  fzf.fzf_exec(titles, {
    prompt = picker_utils.get_prompt "Actions",
    fzf_opts = {
      ["--no-multi"] = "",
    },
    winopts = vim.tbl_deep_extend("force", {}, cfg.picker_config.fzflua.winopts),
    actions = {
      ["default"] = function(selected)
        local entry = formatted_actions[selected[1]]
        entry.action.fun()
      end,
    },
  })
end
