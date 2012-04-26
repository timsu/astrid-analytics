CONFIG = YAML.load_file(Rails.root.join("config/redis.yml"))[Rails.env]

$redis = Redis.new(:host => CONFIG['host'] || "localhost", :port => CONFIG["port"] || 6379)

