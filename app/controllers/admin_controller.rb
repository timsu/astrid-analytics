class AdminController < ApplicationController

  before_filter :validate_request
  
  ################################################################# REFERENCE

  # redis keys:

  # accounts - map of account ids 
  # apikeys:<apikey> - json of api key info [account, client, secret]

  # <account>:data - json of account data { id, name, email, salt, password }
  # <account>:apikeys - set of api keys
  # <account>:days - set of days we know about
  # <account>:tests - set of tests we know about
  # <account>:<test>:variants - set of variants for this test
  # <account>:<test>:dates - set of dates for this test
  # <account>:<test>:variants - set of variants for this test
  
  ################################################################# ACTIONS

  def index
    @accounts = $redis.smembers "accounts"
    
    @data = @accounts.reduce({}) do |data, account|      
      data[account] = JSON.parse($redis.get "#{account}:data")
      data
    end
    
    @apikeys = @accounts.reduce({}) do |data, account|      
      data[account] = $redis.smembers "#{account}:apikeys"
      data
    end
  end
  
  ################################################################# HELPERS
  
  protected
  def validate_request
    authenticate_or_request_with_http_basic do |username, password|
      username == "rockthe" && password == "casbah!"
    end
  end

end
