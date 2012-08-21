Airbrake.configure do |config|
  config.api_key = 'e02d023139929e5d5561dffb7ca9683a'
  config.host = 'errors.astrid.com'
  config.port = 80
  config.secure = config.port == 443
end
