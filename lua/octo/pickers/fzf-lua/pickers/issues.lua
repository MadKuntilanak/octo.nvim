---@diagnostic disable
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local queries = require "octo.gh.queries"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

return function(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = { "OPEN" }
  end

  local repo = utils.pop_key(opts, "repo")
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  end

  if not repo then
    utils.error "Cannot find repo"
    return
  end

  local owner, name = utils.split_repo(repo)
  cfg = octo_config.values

  local repo_name = picker_utils.extract_repo_from_prompt(opts.prompt)
  local title
  if repo_name then
    title = string.format(" Issue in %s ", repo_name)
  else
    title = string.format(" Issue in %s ", repo)
  end

  local prompt_title = utils.pop_key(opts, "prompt_title")

  local cb = utils.pop_key(opts, "cb")

  local formatted_issues = {} ---@type table<string, table> entry.ordinal -> entry

  local function get_contents(fzf_cb)
    gh.api.graphql {
      query = queries.issues,
      F = {
        owner = owner,
        name = name,
        filter_by = opts,
        order_by = octo_config.values.issues.order_by,
      },
      paginate = true,
      jq = ".",
      opts = {
        stream_cb = function(data, err)
          if err and not utils.is_blank(err) then
            utils.error(err)
            fzf_cb()
          elseif data then
            local resp = utils.aggregate_pages(data, "data.repository.issues.nodes")
            local issues = resp.data.repository.issues.nodes

            for _, issue in ipairs(issues) do
              local entry = entry_maker.gen_from_issue(issue)

              if entry ~= nil then
                local icon_str = picker_utils.get_entry_icon(entry)
                local issue_idx = fzf.utils.ansi_from_hl("Comment", entry.value)
                local new_formatted_entry = issue_idx .. " " .. icon_str .. " " .. entry.obj.title

                entry.ordinal = fzf.utils.strip_ansi_coloring(new_formatted_entry)
                formatted_issues[entry.ordinal] = entry
                fzf_cb(new_formatted_entry)
              end
            end
          end
        end,
        cb = function()
          fzf_cb()
        end,
      },
    }
  end

  local actions
  if cb then
    actions = {
      ["default"] = function(selected)
        cb(formatted_issues[selected[1]])
      end,
    }
  else
    actions = fzf_actions.common_open_actions(formatted_issues)
  end

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(prompt_title),
    previewer = previewers.issue(formatted_issues),
    fzf_opts = {
      ["--header"] = opts.results_title,
      ["--info"] = "default",
    },
    winopts = vim.tbl_deep_extend("force", {
      title = title,
      title_pos = "center",
    }, octo_config.values.picker_config.fzflua.winopts),

    actions = actions,
  })
end
