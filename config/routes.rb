AstridAnalytics::Application.routes.draw do
  # The priority is based upon order of creation:
  # first created -> highest priority.

  match "admin", :to => "admin#index"
  match "admin/:action", :controller => :admin

  match "reports/:account/:action", :controller => :reports
  match "reports/:account/ab_test/:test" => "reports#ab_test"
  match "reports/engineyard" => "reports#engineyard"
  match "reports/disk_space" => "reports#disk_space"

  match "api/:version/:action", :controller => :api

  root :to => "admin#root"

end
