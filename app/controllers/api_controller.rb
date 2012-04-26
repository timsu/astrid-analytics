# Astrid Analytics JSON API
#
# Aside from parameters required for each method, the following parameters
# are required for every method:
# * app_id: API application id
# * time: seconds since epoch (UTC) timestamp
# * sig: signature, generated via the following:
#   - sort every parameter alphabetically by key first, then value
#   - concatenate keys and values (skip arrays and uploaded files)
#   - append your API secret
#   - take the MD5 digest
#
# For example, for params "app_id=1&title=baz&tag[]=foo&tag[]=bar&time=1297216408"
# your signature string will be: "app_id1tag[]bartag[]footime=1297216408titlebaz<APP_SECRET>",
# so your final param might look like:
#   app_id=1&title=baz&tag[]=foo&tag[]=bar&time=1297216408&sig=c7e14a38df42...
#
# SSEUTC <= seconds since epoch, UTC
#
class ApiController < ApplicationController

  API_VERSION = 1
  
  before_filter :validate_request
  
  rescue_from Exception, :with => :render_error

  ################################################################# REFERENCE

  # redis keys:

  # apikeys:<apikey> - map of api key to [account, client, secret]

  # <account>:data - hash of account data
  # <account>:apikeys - set of api keys
  # <account>:days - set of days we know about
  # <account>:tests - set of tests we know about
  # <account>:<test>:variants - set of variants for this test
  # <account>:<test>:dates - set of dates for this test
  # <account>:<test>:variants - set of variants for this test
  
  ################################################################# API METHODS

  def retention
    @payload = JSON.parse(params[:payload])

    @payload.each do |event|
      test = event[:test]
      raise ApiError, "Parameter required: 'test'" unless test
      $redis.sadd "#{@account}:tests", test

      variant = event[:variant]
      raise ApiError, "Parameter required: 'variant'" unless variant
      $redis.sadd "#{@account}:#{test}:variants", variant

      date = Date.today
      date = Time.at(event[:date]).to_date if event[:date]
      $redis.sadd "#{@account}:#{test}:dates", date

      new = event[:new]
      raise ApiError, "Parameter required: 'new'" unless new
      activated = event[:activated]
      raise ApiError, "Parameter required: 'activated'" unless activated

      new_activated = (new ? "n" : "o") + (activated ? "a" : "u")

      days = event[:days]
      days = [days] if days.instance_of? Fixnum
      raise ApiError, "Parameter required: 'days'" unless days

      days.each do |day|
        $redis.sadd "#{@account}:#{test}:days", day

        $redis.incrby "#{@account}:#{test}:#{variant}:#{new_activated}:#{day}:#{date}", 1
      end
    end

    render :json => { :status => "Success" }
  end
  
  ################################################################# HELPERS

  protected
  def render_error(e)
    raise e if Rails.env.test?
    log(e) if e.class != ApiError 
    render :format => :json, :text => { :status => :error,
      :message => e.to_s }.to_json
  end
  
  protected
  def validate_request
    @apikey = params[:apikey]
    raise ApiError, "Need to specify API key" unless @apikey
    
    value = JSON.parse $redis.get "apikeys:#{@apikey}"
    raise ApiError, "Unknown API key" unless value

    @account, @client, @secret = value

    sig = ApiController.generate_signature params, @secret    
    if sig != params[:sig]
      unless Rails.env.production?
        puts "Expected Signature: #{sig}"
      else
        raise ApiError, "signature was invalid, expected it to start with " + sig[0,3]
      end
    end
  end

  protected
  def self.generate_signature(params, secret)
    signature = params.sort do |a,b|
      a.to_s <=> b.to_s
    end.reduce("") do |result, pair|
      if pair[0] == "sig" or pair[0] == "action" or pair[0] == "controller"
        result
      elsif pair[1].class == Array
        "#{result}#{pair[0]}[]" + pair[1].join("#{pair[0]}[]")
      elsif pair[1].class == ActionDispatch::Http::UploadedFile
        result
      else
        "#{result}#{pair[0]}#{pair[1]}"
      end
    end + secret

    Digest::MD5.hexdigest(signature)
  end

end
