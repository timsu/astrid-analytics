AstridAnalytics::Application.routes.draw do
  # The priority is based upon order of creation:
  # first created -> highest priority.

  match "admin", :to => "admin#index"
  match "admin/:action", :controller => :admin

  match "reports/:action", :controller => :reports

  match "api/1/:action", :controller => :api

end
