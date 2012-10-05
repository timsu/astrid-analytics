AstridAnalytics::Application.routes.draw do
  # The priority is based upon order of creation:
  # first created -> highest priority.

  match "admin", :to => "admin#index"
  match "admin/:action", :controller => :admin

  match "reports/:account/:action", :controller => :reports
  match "reports/:account/ab_test/:test" => "reports#ab_test"
  match "reports/engineyard" => "reports#engineyard"

  match "api/:version/:action", :controller => :api

  root :to => "admin#root"

end
