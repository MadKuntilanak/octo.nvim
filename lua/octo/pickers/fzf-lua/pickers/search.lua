---@diagnostic disable
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local octo_config = require "octo.config"
local utils = require "octo.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"

---@param fzf_cb fzf-lua.fzfCb
---@param issue table
---@param max_id_length integer
---@param formatted_issues table<string, table> entry.ordinal -> entry
local function handle_entry(fzf_cb, issue, max_id_length, formatted_issues)
  local entry = entry_maker.gen_from_issue(issue)
  if entry == nil then
    return
  end

  local owner, name = utils.split_repo(entry.repo)
  local icon_str = picker_utils.get_entry_icon(entry)
  local ordinal_entry, string_entry

  -- only kind repository
  if entry.kind == "repo" then
    local repo_label = fzf.utils.ansi_from_hl("OctoDetailsLabel", entry.obj.nameWithOwner)
    local stars = fzf.utils.ansi_from_hl("Comment", " s:" .. tostring(entry.obj.stargazerCount or 0))
    local forks = fzf.utils.ansi_from_hl("Comment", " f:" .. tostring(entry.obj.forkCount or 0))

    ordinal_entry = fzf.utils.strip_ansi_coloring(
      string.format("%s %s %s %s %s %s", entry.kind, owner, name, icon_str, repo_label, forks .. stars)
    )
    string_entry = string.format("%s %s %s %s %s %s", entry.kind, owner, name, icon_str, repo_label, forks .. stars)
  else
    -- issue, pull_request, discussion
    local raw_number = picker_utils.pad_string(entry.obj.number, max_id_length)
    local number = fzf.utils.ansi_from_hl("Comment", raw_number)

    ordinal_entry = fzf.utils.strip_ansi_coloring(
      string.format("%s %s %s %s %s %s", entry.kind, owner, name, raw_number, icon_str, entry.obj.title)
    )
    string_entry = string.format("%s %s %s %s %s %s", entry.kind, owner, name, number, icon_str, entry.obj.title)
  end

  entry.ordinal = ordinal_entry
  formatted_issues[ordinal_entry] = entry
  fzf_cb(string_entry)
end

return function(opts)
  opts = opts or {}
  opts.type = opts.type or "PULL REQUEST"

  local repo_name = picker_utils.extract_repo_from_prompt(opts.prompt)
  local title
  if repo_name then
    title = string.format(" Search %s in %s ", opts.type, repo_name)
  else
    title = string.format(" Search %s ", opts.type)
  end

  local formatted_items = {} ---@type table<string, table> entry.ordinal -> entry

  ---@type fzf-lua.shell.data2
  local function contents(args)
    local query = args[1] or ""

    return coroutine.wrap(
      ---@param fzf_cb fzf-lua.fzfCb
      function(fzf_cb)
        local co = coroutine.running()

        if not opts.prompt and utils.is_blank(query) then
          fzf_cb()
          return
        end

        if type(opts.prompt) == "string" then
          opts.prompt = { opts.prompt }
        end

        for _, val in ipairs(opts.prompt) do
          local _prompt = query
          if val then
            _prompt = string.format("%s %s", val, _prompt)
          end
          local output ---@type string

          gh.api.graphql {
            query = queries.search,
            -- fields = { prompt = _prompt, type = opts.type },
            f = { prompt = _prompt, type = opts.type },
            F = { last = 50 },
            jq = ".data.search.nodes",
            opts = {
              cb = gh.create_callback {
                success = function(stdout)
                  output = stdout
                  coroutine.resume(co)
                end,
                failure = function(stderr)
                  utils.error(stderr)
                  coroutine.resume(co)
                end,
              },
            },
          }

          coroutine.yield()

          if utils.is_blank(output) then
            fzf_cb()
            return
          end

          local issues = vim.json.decode(output)

          local max_id_length = 1
          for _, issue in ipairs(issues) do
            local s = tostring(issue.number)
            if #s > max_id_length then
              max_id_length = #s
            end
          end

          for _, issue in ipairs(issues) do
            handle_entry(fzf_cb, issue, max_id_length, formatted_items)
          end
        end

        fzf_cb()
      end
    )
  end

  -- TODO this is still not as fast as I would like.
  fzf.fzf_live(contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    exec_empty_query = true,
    previewer = previewers.search(),
    query_delay = 500,
    fzf_opts = {
      ["--info"] = "default",
      ["--delimiter"] = " ",
      ["--with-nth"] = "4..",
    },
    winopts = vim.tbl_deep_extend("force", {
      title = title,
      title_pos = "center",
    }, octo_config.values.picker_config.fzflua.winopts or {}),

    actions = fzf_actions.common_open_actions(formatted_items),
  })
end
