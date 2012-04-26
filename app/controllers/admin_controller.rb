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

  def add_account
    if request.post?
      salt = rand(36**6).to_s(36)
      account = {
        :id => $redis.scard("accounts") + 1,
        :name => params[:name],
        :email => params[:email],
        :salt => salt,
        :password => Digest::MD5.hexdigest(params[:password] + salt)
      }
        
      $redis.sadd "accounts", account[:id]
      $redis.get "#{account[:id]}:data", account.to_json
    end

    redirect_to "/admin"
  end

  def add_client
    if request.post?
      account = params[:account]

      render :text => "Error: unknown account" unless $redis.sismember "accounts", account

      begin
        apikey = rand(36**6).to_s(36)
      end while $redis.get("apikeys:#{apikey}")
      client = params[:client]
      secret = rand(36**6).to_s(36)
        
      $redis.sadd "#{account}:apikeys", apikey
      $redis.set "apikeys:#{apikey}", [account, client, secret]
    end

    redirect_to "/admin"
  end
  
  ################################################################# HELPERS
  
  protected
  def validate_request
    authenticate_or_request_with_http_basic do |username, password|
      username == "rockthe" && password == "casbah!"
    end
  end

end
