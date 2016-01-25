local auto_ssl = require "resty.auto-ssl"
local lock = require "resty.lock"
local resty_random = require "resty.random"
local start_sockproc = require "resty.auto-ssl.utils.start_sockproc"
local str = require "resty.string"

-- Generate a secret token used for the letsencrypt.sh bash hook script to
-- communicate with the internal HTTP API hook server.
--
-- The internal HTTP API should only be listening on a private port on
-- 127.0.0.1, so it should only be accessible internally already, but this
-- secret token is an extra precaution to ensure the server is not accidentally
-- opened up or proxied to the outside world.
local function generate_hook_sever_secret()
  -- Skip if secret is already generated by another worker.
  if ngx.shared.auto_ssl:get("hook_server:secret") then
    return
  end

  -- Generate the secret token.
  local random = resty_random.bytes(32)
  ngx.shared.auto_ssl:set("hook_server:secret", str.to_hex(random))
end

local function generate_config()
  os.execute("mkdir -p " .. auto_ssl.dir .. "/letsencrypt/conf.d")
  os.execute("mkdir -p " .. auto_ssl.dir .. "/letsencrypt/.acme-challenges")
  os.execute("mkdir -p " .. auto_ssl.dir .. "/storage/file")
  os.execute("chmod 700 " .. auto_ssl.dir .. "/storage/file")

  local file, err = io.open(auto_ssl.dir .. "/letsencrypt/.config.sh", "w")
  if err then
    ngx.log(ngx.ERR, "auto-ssl: failed to open letsencrypt config file")
  else
    file:write('CONFIG_D="' .. auto_ssl.dir .. '/letsencrypt/conf.d"')
    file:close()
  end
end

local function setup()
  -- Use a lock to ensure setup tasks don't overlap (even if multiple workers
  -- are starting).
  local generate_lock, new_lock_err = lock:new("auto_ssl", { ["timeout"] = 0 })
  if new_lock_err then
    ngx.log(ngx.ERR, "auto-ssl: failed to create lock: ", new_lock_err)
    return
  end

  local _, lock_err = generate_lock:lock("init_worker_setup")
  if lock_err then
    return
  end

  generate_hook_sever_secret()
  generate_config()

  local ok, unlock_err = generate_lock:unlock()
  if not ok then
    ngx.log(ngx.ERR, "auto-ssl: failed to unlock: ", unlock_err)
  end
end

return function()
  start_sockproc()
  setup()
end