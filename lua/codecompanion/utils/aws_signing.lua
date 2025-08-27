---AWS request signing utilities for Bedrock API
---Simple implementation using openssl command line
local M = {}

---Hash a string using SHA256
---@param data string
---@return string
local function sha256(data)
  local temp_file = vim.fn.tempname()
  local f = io.open(temp_file, "w")
  if not f then
    error("Failed to create temp file for SHA256")
  end
  f:write(data)
  f:close()
  
  local handle = io.popen("openssl dgst -sha256 -hex " .. temp_file)
  if not handle then
    os.remove(temp_file)
    error("Failed to execute openssl for SHA256")
  end
  local result = handle:read("*a"):match("(%w+)$"):lower()
  handle:close()
  os.remove(temp_file)
  return result
end

---HMAC-SHA256 function
---@param key string
---@param data string
---@return string
local function hmac_sha256(key, data)
  local key_file = vim.fn.tempname()
  local data_file = vim.fn.tempname()
  
  local f = io.open(key_file, "w")
  f:write(key)
  f:close()
  
  f = io.open(data_file, "w")
  f:write(data)
  f:close()

  local cmd = string.format("openssl dgst -sha256 -hmac \"$(cat %s)\" -hex %s", key_file, data_file)
  local handle = io.popen(cmd)
  if not handle then
    os.remove(key_file)
    os.remove(data_file)
    error("Failed to execute openssl for HMAC-SHA256")
  end
  local result = handle:read("*a"):match("(%w+)$"):lower()
  handle:close()
  os.remove(key_file)
  os.remove(data_file)
  return result
end

---HMAC-SHA256 with hex key
---@param hex_key string
---@param data string
---@return string
local function hmac_sha256_hex(hex_key, data)
  local key_file = vim.fn.tempname()
  local data_file = vim.fn.tempname()
  
  -- Convert hex to binary
  local cmd = string.format("echo '%s' | xxd -r -p > %s", hex_key, key_file)
  os.execute(cmd)
  
  local f = io.open(data_file, "w")
  f:write(data)
  f:close()

  cmd = string.format("openssl dgst -sha256 -hmac \"$(cat %s)\" -hex %s", key_file, data_file)
  local handle = io.popen(cmd)
  if not handle then
    os.remove(key_file)
    os.remove(data_file)
    error("Failed to execute openssl for HMAC-SHA256 hex")
  end
  local result = handle:read("*a"):match("(%w+)$"):lower()
  handle:close()
  os.remove(key_file)
  os.remove(data_file)
  return result
end

---Get AWS signing key
---@param secret_key string
---@param date_stamp string
---@param region string
---@param service string
---@return string
local function get_signature_key(secret_key, date_stamp, region, service)
  local k_date = hmac_sha256("AWS4" .. secret_key, date_stamp)
  local k_region = hmac_sha256_hex(k_date, region)
  local k_service = hmac_sha256_hex(k_region, service)
  local k_signing = hmac_sha256_hex(k_service, "aws4_request")
  return k_signing
end

---URL encode a string
---@param str string
---@return string
local function url_encode(str)
  return str:gsub("([^%w%-_.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

---Create canonical headers string
---@param headers table
---@return string, string
local function canonical_headers(headers)
  local canonical = {}
  local signed_headers = {}

  for k, v in pairs(headers) do
    local lower_key = k:lower()
    canonical[lower_key] = tostring(v):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    table.insert(signed_headers, lower_key)
  end

  table.sort(signed_headers)

  local header_lines = {}
  for _, key in ipairs(signed_headers) do
    table.insert(header_lines, key .. ":" .. canonical[key])
  end

  return table.concat(header_lines, "\n") .. "\n", table.concat(signed_headers, ";")
end

---Sign AWS request using Signature Version 4
---@param params table
---@return table Modified headers with Authorization
function M.sign_request(params)
  local service = params.service or "bedrock"
  local method = params.method:upper()

  -- Parse URL
  local host, path = params.url:match("^https?://([^/]+)(/.*)")
  if not host then
    host = params.url:match("^https?://([^/]+)")
    path = "/"
  end

  -- Create timestamp
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local date_stamp = timestamp:sub(1, 8)

  -- Prepare headers
  local headers = vim.tbl_deep_extend("force", params.headers or {}, {
    host = host,
    ["x-amz-date"] = timestamp,
  })

  -- Handle payload
  local payload_hash = sha256(params.payload or "")

  -- Create canonical request
  local canonical_request = table.concat({
    method,
    path,
    "", -- query string (empty for Bedrock)
    canonical_headers(headers),
    payload_hash,
  }, "\n")

  -- Create string to sign
  local credential_scope = table.concat({ date_stamp, params.region, service, "aws4_request" }, "/")
  local string_to_sign = table.concat({
    "AWS4-HMAC-SHA256",
    timestamp,
    credential_scope,
    sha256(canonical_request),
  }, "\n")

  -- Calculate signature
  local signing_key = get_signature_key(params.secret_key, date_stamp, params.region, service)
  local signature = hmac_sha256_hex(signing_key, string_to_sign)

  -- Create authorization header
  local _, signed_headers = canonical_headers(headers)
  local authorization = string.format(
    "AWS4-HMAC-SHA256 Credential=%s/%s, SignedHeaders=%s, Signature=%s",
    params.access_key,
    credential_scope,
    signed_headers,
    signature
  )

  headers["Authorization"] = authorization
  return headers
end

return M