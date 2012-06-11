class AdminController < ApplicationController

  before_filter :validate_request
  
  ################################################################# ACTIONS

  def root
    @accounts = $redis.smembers "accounts"
    @data = @accounts.reduce({}) do |data, account|      
      data[account] = JSON.parse($redis.get "#{account}:data")
      data
    end
  end
  
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

    # for analytics internal use
    deprecated_api = 1..ApiController::API_VERSION - 1
    @deprecated = deprecated_api.reduce({}) do |r, version|
      count = 0
      ((Date.today-7)..Date.today).each do |day|
        count += $redis.get("deprecated:#{version}:#{day}").to_i
      end
      r[version] = count if count > 0
      r
    end
    @has_deprecated = @deprecated.length > 0
  end

  def add_account
    if request.post?
      account = {
        :id => $redis.scard("accounts") + 1,
        :name => params[:name],
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
    $redis.set "#{account}:#{test}:null_variant", params[:null_variant] if params[:null_variant]

    if params[:filter]
      $redis.set "#{account}:#{test}:user_groups", params[:filter].keys.compact
    end

    respond_to do |format|
      format.js   { render :json => {} }
      format.json { render :json => {} }
      format.html { redirect_to "/reports/#{account}/ab" }
    end
  end
  
end
