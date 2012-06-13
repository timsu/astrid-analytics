module Admin
  USERNAME = ENV['ADMIN_USER'] || "admin"
  PASSWORD = ENV['ADMIN_PASS'] || "password"
  REV_PRICE = ENV['REV_PRICE'].try(:to_f) || 50
end

