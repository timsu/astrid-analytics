class AdminController < ApplicationController

  before_filter :validate_request
  
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
      $redis.set "#{account[:id]}:data", account.to_json
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
    
  def edit_test
    test = params[:test]
    account = params[:account]
    raise "No test or account specified" unless test and account

    $redis.set "#{account}:#{test}:description", params[:description] if params[:description]
    $redis.sadd "#{account}:archived", test if params[:archive]
    $redis.srem "#{account}:archived", test if params[:unarchive]

    render :json => {}
  end
  
end
