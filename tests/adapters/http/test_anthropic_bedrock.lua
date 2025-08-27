local h = require("tests.helpers")
local transform = require("codecompanion.utils.tool_transformers")
local adapter

local new_set = MiniTest.new_set
T = new_set()

T["Anthropic Bedrock adapter"] = new_set({
  hooks = {
    pre_case = function()
      local codecompanion = require("codecompanion")
      adapter = require("codecompanion.adapters").resolve("anthropic_bedrock")
    end,
  },
})

T["Anthropic Bedrock adapter"]["inherits from anthropic adapter"] = function()
  h.eq("anthropic_bedrock", adapter.name)
  h.eq("Anthropic (AWS Bedrock)", adapter.formatted_name)
  h.eq("us.anthropic.claude-sonnet-4-20250514-v1:0", adapter.schema.model.default)
end

T["Anthropic Bedrock adapter"]["has correct URL format"] = function()
  h.eq("https://bedrock-runtime.{region}.amazonaws.com/model/{model}/invoke-with-response-stream", adapter.url)
end

T["Anthropic Bedrock adapter"]["has correct environment variables"] = function()
  h.eq("AWS_ACCESS_KEY_ID", adapter.env.aws_access_key_id)
  h.eq("AWS_SECRET_ACCESS_KEY", adapter.env.aws_secret_access_key)
  h.eq("AWS_REGION", adapter.env.aws_region)
end

T["Anthropic Bedrock adapter"]["has bedrock-specific headers"] = function()
  h.eq("application/json", adapter.headers["content-type"])
  h.eq(nil, adapter.headers["x-api-key"]) -- Should not have anthropic api key
end

T["Anthropic Bedrock adapter"]["setup"] = new_set()

T["Anthropic Bedrock adapter"]["setup"]["sets URL with region and model"] = function()
  local test_adapter = vim.deepcopy(adapter)
  test_adapter.env.aws_region = "us-west-2"
  test_adapter.schema.model.default = "us.anthropic.claude-sonnet-4-20250514-v1:0"
  
  test_adapter.handlers.setup(test_adapter)
  
  h.eq("https://bedrock-runtime.us-west-2.amazonaws.com/model/us.anthropic.claude-sonnet-4-20250514-v1:0/invoke-with-response-stream", test_adapter.url)
end

T["Anthropic Bedrock adapter"]["setup"]["uses environment variable for region"] = function()
  vim.env.AWS_REGION = "eu-west-1"
  local test_adapter = vim.deepcopy(adapter)
  test_adapter.env.aws_region = nil
  
  test_adapter.handlers.setup(test_adapter)
  
  h.expect_match("eu%-west%-1", test_adapter.url)
  vim.env.AWS_REGION = nil
end

T["Anthropic Bedrock adapter"]["setup"]["errors without region"] = function()
  vim.env.AWS_REGION = nil
  local test_adapter = vim.deepcopy(adapter)
  test_adapter.env.aws_region = nil
  
  h.expect_error(function()
    test_adapter.handlers.setup(test_adapter)
  end, "AWS_REGION environment variable is required")
end

T["Anthropic Bedrock adapter"]["setup"]["sets up custom request function"] = function()
  local test_adapter = vim.deepcopy(adapter)
  test_adapter.env.aws_region = "us-west-2"
  
  test_adapter.handlers.setup(test_adapter)
  
  h.eq("function", type(test_adapter.opts.request))
end

T["Anthropic Bedrock adapter"]["credentials"] = new_set()

T["Anthropic Bedrock adapter"]["credentials"]["requires AWS credentials"] = function()
  -- Clear all AWS env vars
  vim.env.AWS_ACCESS_KEY_ID = nil
  vim.env.AWS_SECRET_ACCESS_KEY = nil
  vim.env.AWS_REGION = nil
  
  local test_adapter = vim.deepcopy(adapter)
  test_adapter.env.aws_access_key_id = nil
  test_adapter.env.aws_secret_access_key = nil
  test_adapter.env.aws_region = nil
  
  h.expect_error(function()
    test_adapter.handlers.setup(test_adapter)
  end, "AWS_REGION environment variable is required")
end

T["Anthropic Bedrock adapter"]["credentials"]["uses environment variables for credentials"] = function()
  vim.env.AWS_ACCESS_KEY_ID = "test_access_key"
  vim.env.AWS_SECRET_ACCESS_KEY = "test_secret_key" 
  vim.env.AWS_REGION = "us-west-2"
  
  local test_adapter = vim.deepcopy(adapter)
  test_adapter.env.aws_access_key_id = nil
  test_adapter.env.aws_secret_access_key = nil
  test_adapter.env.aws_region = nil
  
  -- Should not error when env vars are set
  local ok = pcall(function()
    test_adapter.handlers.setup(test_adapter)
  end)
  
  h.eq(true, ok)
  
  -- Clean up
  vim.env.AWS_ACCESS_KEY_ID = nil
  vim.env.AWS_SECRET_ACCESS_KEY = nil
  vim.env.AWS_REGION = nil
end

T["Anthropic Bedrock adapter"]["form_parameters"] = new_set()

T["Anthropic Bedrock adapter"]["form_parameters"]["modifies parameters for bedrock"] = function()
  local params = {
    model = "us.anthropic.claude-sonnet-4-20250514-v1:0",
    stream = true,
    temperature = 0.5,
  }
  local messages = {}
  
  local result = adapter.handlers.form_parameters(adapter, params, messages)
  
  h.eq("bedrock-2023-05-31", result.anthropic_version)
  h.eq(nil, result.model) -- Should be removed
  h.eq(nil, result.stream) -- Should be removed
end

T["Anthropic Bedrock adapter"]["form_parameters"]["disables thinking for bedrock"] = function()
  local params = {
    thinking = {
      type = "enabled",
      budget_tokens = 1000,
    },
    temperature = 1,
  }
  local messages = {}
  
  local result = adapter.handlers.form_parameters(adapter, params, messages)
  
  h.eq(nil, result.thinking) -- Should be removed
  h.eq(nil, result.temperature) -- Should be reset
end

T["Anthropic Bedrock adapter"]["tokens"] = new_set()

T["Anthropic Bedrock adapter"]["tokens"]["parses bedrock eventstream format"] = function()
  local eventstream_data = '{"body":"{\\"bytes\\":\\"eyJ0eXBlIjoibWVzc2FnZV9zdGFydCIsIm1lc3NhZ2UiOnsiaWQiOiJtc2dfMDFGWGFXYlZUaXlWQk5IdUZ3RkFQeE5uIiwidHlwZSI6Im1lc3NhZ2UiLCJyb2xlIjoiYXNzaXN0YW50IiwibW9kZWwiOiJjbGF1ZGUtMy01LXNvbm5ldC0yMDI0MTAyMiIsImNvbnRlbnQiOltdLCJzdG9wX3JlYXNvbiI6bnVsbCwic3RvcF9zZXF1ZW5jZSI6bnVsbCwidXNhZ2UiOnsiaW5wdXRfdG9rZW5zIjo0NTUsImNhY2hlX2NyZWF0aW9uX2lucHV0X3Rva2VucyI6MCwiY2FjaGVfcmVhZF9pbnB1dF90b2tlbnMiOjAsIm91dHB1dF90b2tlbnMiOjF9fX0=\\"}"}'
  
  local tokens = adapter.handlers.tokens(adapter, eventstream_data)
  
  h.eq(456, tokens) -- 455 input + 1 output
end

T["Anthropic Bedrock adapter"]["tokens"]["handles message_delta with usage"] = function()
  local eventstream_data = '{"body":"{\\"bytes\\":\\"eyJ0eXBlIjoibWVzc2FnZV9kZWx0YSIsImRlbHRhIjp7InN0b3BfcmVhc29uIjoiZW5kX3R1cm4iLCJzdG9wX3NlcXVlbmNlIjpudWxsfSwidXNhZ2UiOnsib3V0cHV0X3Rva2VucyI6MTh9fQ==\\"}"}'
  
  local tokens = adapter.handlers.tokens(adapter, eventstream_data)
  
  h.eq(18, tokens) -- Only output tokens from delta
end

T["Anthropic Bedrock adapter"]["chat_output"] = new_set()

T["Anthropic Bedrock adapter"]["chat_output"]["can output streamed data"] = function()
  local output = ""
  local lines = {
    '{"body":"{\\"bytes\\":\\"eyJ0eXBlIjoibWVzc2FnZV9zdGFydCIsIm1lc3NhZ2UiOnsiaWQiOiJtc2dfMDFGWGFXYlZUaXlWQk5IdUZ3RkFQeE5uIiwidHlwZSI6Im1lc3NhZ2UiLCJyb2xlIjoiYXNzaXN0YW50IiwibW9kZWwiOiJjbGF1ZGUtMy01LXNvbm5ldC0yMDI0MTAyMiIsImNvbnRlbnQiOltdLCJzdG9wX3JlYXNvbiI6bnVsbCwic3RvcF9zZXF1ZW5jZSI6bnVsbCwidXNhZ2UiOnsiaW5wdXRfdG9rZW5zIjo0NTUsImNhY2hlX2NyZWF0aW9uX2lucHV0X3Rva2VucyI6MCwiY2FjaGVfcmVhZF9pbnB1dF90b2tlbnMiOjAsIm91dHB1dF90b2tlbnMiOjF9fX0=\\"}"}',
    '{"body":"{\\"bytes\\":\\"eyJ0eXBlIjoiY29udGVudF9ibG9ja19zdGFydCIsImluZGV4IjowLCJjb250ZW50X2Jsb2NrIjp7InR5cGUiOiJ0ZXh0IiwidGV4dCI6IiJ9fQ==\\"}"}',
    '{"body":"{\\"bytes\\":\\"eyJ0eXBlIjoiY29udGVudF9ibG9ja19kZWx0YSIsImluZGV4IjowLCJkZWx0YSI6eyJ0eXBlIjoidGV4dF9kZWx0YSIsInRleHQiOiJEeW5hbWljIn19\\"}"}',
    '{"body":"{\\"bytes\\":\\"eyJ0eXBlIjoiY29udGVudF9ibG9ja19kZWx0YSIsImluZGV4IjowLCJkZWx0YSI6eyJ0eXBlIjoidGV4dF9kZWx0YSIsInRleHQiOiIgZWxlZ2FuY2UifX0=\\"}"}'
  }
  
  for _, line in ipairs(lines) do
    local chat_output = adapter.handlers.chat_output(adapter, line)
    if chat_output and chat_output.output and chat_output.output.content then
      output = output .. chat_output.output.content
    end
  end
  
  h.expect_starts_with("Dynamic elegance", output)
end

T["Anthropic Bedrock adapter"]["chat_output"]["can process tool streaming"] = function()
  local tools = {}
  local lines = {
    '{"body":"{\\"bytes\\":\\"eyJ0eXBlIjoiY29udGVudF9ibG9ja19zdGFydCIsImluZGV4IjowLCJjb250ZW50X2Jsb2NrIjp7InR5cGUiOiJ0b29sX3VzZSIsImlkIjoidG9vbHVfMDFRUlRoeXpLdDZOaWJLM20xRGpVVGtFIiwibmFtZSI6IndlYXRoZXIifX0=\\"}"}',
    '{"body":"{\\"bytes\\":\\"eyJ0eXBlIjoiY29udGVudF9ibG9ja19kZWx0YSIsImluZGV4IjowLCJkZWx0YSI6eyJ0eXBlIjoiaW5wdXRfanNvbl9kZWx0YSIsInBhcnRpYWxfanNvbiI6InsgXFwibG9jYXRpb25cXCI6IFxcIkxvbmRvbn0ifX0=\\"}"}'
  }
  
  for _, line in ipairs(lines) do
    adapter.handlers.chat_output(adapter, line, tools)
  end
  
  h.eq(1, #tools)
  h.eq("toolu_01QRThyzKt6NibK3m1DjUTkE", tools[1].id)
  h.eq("weather", tools[1].name)
  h.expect_match("London", tools[1].input)
end

T["Anthropic Bedrock adapter"]["chat_output"]["handles invalid base64 gracefully"] = function()
  local invalid_data = '{"body":"{\\"bytes\\":\\"invalid_base64\\"}"}' 
  
  local result = adapter.handlers.chat_output(adapter, invalid_data)
  
  h.eq(nil, result) -- Should return nil for invalid data
end

return T