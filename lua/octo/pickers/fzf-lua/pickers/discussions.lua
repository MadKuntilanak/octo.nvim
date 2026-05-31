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
local navigation = require "octo.navigation"

return function(opts)
  opts = opts or {}

  local repo = utils.pop_key(opts, "repo")
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  end

  if not repo then
    utils.error "Cannot find repo"
    return
  end

  local cfg = octo_config.values

  local owner, name = utils.split_repo(repo)
  local order_by = cfg.discussions.order_by
  local formatted_discussions = {} ---@type table<string, table> entry.ordinal -> entry

  local repo_name = picker_utils.extract_repo_from_prompt(opts.prompt)
  local title
  if repo_name then
    title = string.format(" Discussions in %s ", repo_name)
  else
    title = string.format(" Discussions in %s ", repo)
  end

  local function get_contents(fzf_cb)
    utils.info "Fetching discussions (this may take a while) ..."
    gh.api.graphql {
      query = queries.discussions,
      fields = {
        owner = owner,
        name = name,
        states = { "OPEN" },
        orderBy = order_by.field,
        direction = order_by.direction,
      },
      paginate = true,
      jq = ".data.repository.discussions.nodes",
      opts = {
        cb = gh.create_callback {
          success = function(output)
            local discussions = utils.get_flatten_pages(output)

            if #discussions == 0 then
              utils.error(string.format("There are no matching discussions in %s.", opts.repo))
              fzf_cb()
              return
            end

            -- get padding
            local max_id_length = 1
            for _, discussion in ipairs(discussions) do
              local s = tostring(discussion.number)
              if #s > max_id_length then
                max_id_length = #s
              end
            end

            for _, discussion in ipairs(discussions) do
              -- local entry = entry_maker.gen_from_discussion(discussion)
              local entry = entry_maker.gen_from_issue(discussion)
              if entry ~= nil then
                local raw_number = picker_utils.pad_string(entry.obj.number, max_id_length)
                local number = fzf.utils.ansi_from_hl("Comment", raw_number)

                local icon_str = picker_utils.get_entry_icon(entry)

                -- category
                local category = ""
                if entry.obj.category and entry.obj.category.name then
                  category = fzf.utils.ansi_from_hl("OctoDetailsLabel", "[" .. entry.obj.category.name .. "]")
                end

                local ordinal_entry = fzf.utils.strip_ansi_coloring(
                  string.format(
                    "discussion %s %s %s %s %s %s",
                    owner,
                    name,
                    raw_number,
                    icon_str,
                    category,
                    entry.obj.title
                  )
                )
                local string_entry = string.format(
                  "discussion %s %s %s %s %s %s",
                  owner,
                  name,
                  number,
                  icon_str,
                  category,
                  entry.obj.title
                )

                entry.ordinal = ordinal_entry
                formatted_discussions[ordinal_entry] = entry
                fzf_cb(string_entry)
              end
            end

            fzf_cb()
          end,
        },
      },
    }
  end

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title or ""),
    previewer = previewers.discussion and previewers.discussion(formatted_discussions) or previewers.search(),
    fzf_opts = {
      ["--info"] = "default",
      ["--with-nth"] = "4..",
    },
    winopts = vim.tbl_deep_extend("force", {
      title = title,
      title_pos = "center",
    }, octo_config.values.picker_config.fzflua and octo_config.values.picker_config.fzflua.winopts or {}),

    actions = vim.tbl_deep_extend("force", fzf_actions.common_open_actions(formatted_discussions), {
      -- open_in_browser as fallback shortcut command
      ["ctrl-o"] = function(selected)
        local entry = formatted_discussions[fzf.utils.strip_ansi_coloring(selected[1])]
        if entry and entry.obj and entry.obj.url then
          navigation.open_in_browser_raw(entry.obj.url)
        end
      end,
    }),
  })
end
