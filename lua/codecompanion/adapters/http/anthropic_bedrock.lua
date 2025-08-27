local anthropic = require("codecompanion.adapters.http.anthropic")

local bedrock_adapter = vim.deepcopy(anthropic)

bedrock_adapter.name = "anthropic_bedrock"
bedrock_adapter.formatted_name = "Anthropic (AWS Bedrock)"
bedrock_adapter.url = "https://bedrock-runtime.{region}.amazonaws.com/model/{model}/invoke-with-response-stream"

bedrock_adapter.env = {
  aws_access_key_id = "AWS_ACCESS_KEY_ID",
  aws_secret_access_key = "AWS_SECRET_ACCESS_KEY",
  aws_region = "AWS_REGION",
  model = "schema.model.default",
}

bedrock_adapter.headers = {
  ["content-type"] = "application/json",
}

bedrock_adapter.handlers.setup = function(self)
  if not self.env.aws_region and not os.getenv("AWS_REGION") then
    error("AWS_REGION environment variable is required for Bedrock adapter")
  end

  self.parameters = self.parameters or {}

  -- Only set default AWS URL if no custom URL provided
  if self.url == "https://bedrock-runtime.{region}.amazonaws.com/model/{model}/invoke-with-response-stream" then
    local region = self.env.aws_region or os.getenv("AWS_REGION") or "us-east-1"
    local model = self.schema.model.default
    self.url =
      string.format("https://bedrock-runtime.%s.amazonaws.com/model/%s/invoke-with-response-stream", region, model)
  end

  local model_opts = self.schema.model.choices[model]
  if model_opts and model_opts.opts then
    self.opts = vim.tbl_deep_extend("force", self.opts, model_opts.opts)
    if not model_opts.opts.has_vision then
      self.opts.vision = false
    end
  end

  return true
end

local original_form_parameters = bedrock_adapter.handlers.form_parameters
bedrock_adapter.handlers.form_parameters = function(self, params, messages)
  params = original_form_parameters(self, params, messages)

  params.anthropic_version = "bedrock-2023-05-31"
  params.model = nil
  params.stream = nil

  return params
end

local original_tokens = bedrock_adapter.handlers.tokens
bedrock_adapter.handlers.tokens = function(self, data)
  if not data then
    return nil
  end

  -- Handle table response format
  if type(data) == "table" then
    data = data.body or data.data
  end

  if type(data) ~= "string" or data == "" then
    return nil
  end

  -- Parse EventStream for token usage information
  for bytes_match in string.gmatch(data, '"bytes":"([^"]+)"') do
    local ok_decode, decoded = pcall(vim.base64.decode, bytes_match)
    if not ok_decode then
      goto continue
    end

    local ok_json, json = pcall(vim.json.decode, decoded, { luanil = { object = true } })
    if not ok_json then
      goto continue
    end

    -- Look for message_delta with usage information (like Anthropic)
    if json.type == "message_delta" and json.usage then
      local input_tokens = json.usage.input_tokens or 0
      local output_tokens = json.usage.output_tokens or 0
      return input_tokens + output_tokens
    -- Look for message_start with initial usage
    elseif json.type == "message_start" and json.message and json.message.usage then
      local input_tokens = json.message.usage.input_tokens or 0
      local output_tokens = json.message.usage.output_tokens or 0
      return input_tokens + output_tokens
    end

    ::continue::
  end

  return nil
end

local original_chat_output = bedrock_adapter.handlers.chat_output
bedrock_adapter.handlers.chat_output = function(self, data, tools)
  local log = require("codecompanion.utils.log")

  if not data then
    return
  end

  -- Extract body from HTTP response table
  if type(data) == "table" then
    data = data.body or data.data
    if not data then
      log:error("Bedrock: Missing body/data in response")
      return
    end
  end

  if type(data) ~= "string" or data == "" then
    return
  end

  -- Parse AWS EventStream format (base64-encoded JSON chunks)
  local content_parts = {}
  local role = nil

  for bytes_match in string.gmatch(data, '"bytes":"([^"]+)"') do
    local ok_decode, decoded = pcall(vim.base64.decode, bytes_match)
    if not ok_decode then
      log:error("Failed to decode EventStream bytes")
      goto continue
    end

    local ok_json, json = pcall(vim.json.decode, decoded, { luanil = { object = true } })
    if not ok_json then
      goto continue
    end

    -- Handle streaming events (same format as regular Anthropic)
    if json.type == "content_block_delta" then
      if json.delta and json.delta.text then
        table.insert(content_parts, json.delta.text)
      elseif json.delta and json.delta.type == "input_json_delta" and tools then
        -- Tool JSON streaming
        if json.index then
          for i, tool in ipairs(tools) do
            if tool._index == json.index then
              tool.input = tool.input .. (json.delta.partial_json or "")
              break
            end
          end
        end
      end
    elseif json.type == "content_block_start" then
      if json.content_block and json.content_block.type == "tool_use" and tools then
        table.insert(tools, {
          _index = json.index,
          id = json.content_block.id,
          name = json.content_block.name,
          input = "",
        })
      end
    elseif json.type == "message_start" then
      role = json.message.role
    end

    ::continue::
  end

  -- Return in same format as Anthropic adapter
  if #content_parts > 0 or role or (tools and #tools > 0) then
    return {
      status = "success",
      output = {
        role = role or "assistant",
        content = table.concat(content_parts, ""),
      },
    }
  end
end

bedrock_adapter.schema = vim.tbl_deep_extend("force", bedrock_adapter.schema, {
  model = {
    order = 1,
    mapping = "parameters",
    type = "enum",
    desc = "AWS Bedrock Anthropic model ID. See https://docs.aws.amazon.com/bedrock/latest/userguide/model-ids-arns.html for available models.",
    default = "us.anthropic.claude-3-5-sonnet-20241022-v1:0",
    choices = {
      ["us.anthropic.claude-opus-4-20250514-v1:0"] = { opts = { can_reason = true, has_vision = true } },
      ["us.anthropic.claude-sonnet-4-20250514-v1:0"] = { opts = { can_reason = true, has_vision = true } },
      ["us.anthropic.claude-3-5-sonnet-20241022-v1:0"] = { opts = { has_vision = true } },
      ["us.anthropic.claude-3-5-haiku-20241022-v1:0"] = { opts = { has_vision = true } },
      ["us.anthropic.claude-3-opus-20240229-v1:0"] = { opts = { has_vision = true } },
      ["us.anthropic.claude-3-sonnet-20240229-v1:0"] = { opts = { has_vision = true } },
      ["us.anthropic.claude-3-haiku-20240307-v1:0"] = { opts = { has_vision = true } },
      ["us.anthropic.claude-v2:1"] = {},
      ["us.anthropic.claude-v2"] = {},
    },
  },
  bedrock_mode = nil,
  bedrock_url = nil,
  aws_region = {
    order = 15,
    mapping = "env",
    type = "string",
    optional = true,
    default = "us-east-1",
    desc = "AWS region for Bedrock API calls",
  },
})

return bedrock_adapter

