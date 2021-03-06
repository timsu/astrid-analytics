# Astrid Analytics JSON API
#
# Aside from parameters required for each method, the following parameters
# are required for every method:
# * apkikey: API application id
# * sig: signature, generated via the following:
#   - sort every parameter alphabetically by key first, then value
#   - concatenate keys and values (skip arrays and uploaded files)
#   - append your API secret
#   - take the MD5 digest
#
# For example, for params "apikey=1&title=baz&tag[]=foo&tag[]=bar&time=1297216408"
# your signature string will be: "apikey1tag[]bartag[]footime=1297216408titlebaz<APP_SECRET>",
# so your final param might look like:
#   app_id=1&title=baz&tag[]=foo&tag[]=bar&time=1297216408&sig=c7e14a38df42...
#
class ApiController < ApplicationController

  API_VERSION = 2

  before_filter :validate_request

  rescue_from Exception, :with => :render_error

  ################################################################# DASHBOARD API

  # api/acquisition - record aquisition event
  #
  # No parameters are required for this call. Please make sure to
  # send this only once for each new user
  def acquisition
    time_key = Time.now.strftime "%Y-%m-%dT%H"
    $redis.sadd "acq:#{@account}:days", t
    $redis.incr "acq:#{@account}:#{@client}:#{Date.today}"
    $redis.incr "acq:#{@account}:#{Date.today}"
    $redis.incr "acq:#{@account}:#{@client}:#{time_key}"
    $redis.expire "acq:#{@account}:#{time_key}", 3.weeks.to_i

    render :json => { :status => "Success" }
  end

  # api/activation - record activation event
  #
  # No parameters are requried for this call. Please make sure to
  # send this only once for each activated user
  def activation
    time_key = Time.now.strftime "%Y-%m-%dT%H"
    $redis.sadd "atv:#{@account}:days", Date.today
    $redis.incr "atv:#{@account}:#{Date.today}"
    $redis.incr "atv:#{@account}:#{time_key}"
    $redis.expire "atv:#{@account}:#{time_key}", 3.weeks.to_i

    render :json => { :status => "Success" }
  end

  # api/retention - record retention event
  #
  # Parameters:
  #   user_id - unique user identifier for calculating unique retention
  #
  # The minimum reporting threshold for this API is once per hour per user.
  def retention
    return ab_retention if @api == 1
    raise ApiError, "Parameter required: 'user_id'" if params[:user_id].blank?

    time_key = Time.now.strftime "%Y-%m-%dT%H"
    $redis.sadd "ret:#{@account}:days", Date.today
    $redis.sadd "ret:#{@account}:#{Date.today}", params[:user_id]
    $redis.sadd "ret:#{@account}:#{time_key}", params[:user_id]
    $redis.expire "ret:#{@account}:#{time_key}", 3.weeks.to_i

    render :json => { :status => "Success" }
  end

  # api/referral - record referral event
  #
  # Send once per referral event
  def referral
    time_key = Time.now.strftime "%Y-%m-%dT%H"
    $redis.sadd "rfr:#{@account}:days", Date.today
    $redis.incr "rfr:#{@account}:#{@client}:#{Date.today}"
    $redis.incr "rfr:#{@account}:#{Date.today}"
    $redis.incr "rfr:#{@account}:#{@client}:#{time_key}"
    $redis.expire "rfr:#{@account}:#{time_key}", 3.weeks.to_i

    render :json => { :status => "Success" }
  end

  # api/revenue - record revenue event
  #
  # Parameters
  #   delta - record a change in the # of paid users
  #   total - record the total # of paid users
  #   (one of delta or total is required)
  #
  # If new subscriptions occur often, you can use the delta parameter
  # to send the number of new or removed subscriptions. To initialize
  # the count, or if subscription events are not visible to your system,
  # you can send the total.
  def revenue
    time_key = Time.now.strftime "%Y-%m-%dT%H"
    raise ApiError, "Parameter required: 'delta' or 'total" unless params[:delta] or params[:total]
    raise ApiError, "Please send only one of: 'delta' or 'total" if params[:delta] and params[:total]

    $redis.sadd "rvn:#{@account}:days", Date.today
    if params[:total]
      $redis.set "rvn:#{@account}:#{Date.today}", params[:total].to_i
    elsif params[:delta]
      keys = (0..30).map { |i| "rvn:#{@account}:#{Date.today - i}" }
      current = $redis.mget(*keys).compact.first || 0
      $redis.set "rvn:#{@account}:#{Date.today}", current + params[:delta].to_i
    end

    render :json => { :status => "Success" }
  end

  ################################################################# AB TEST API

  def ab_retention
    raise ApiError, "Parameter required: 'payload'" if params[:payload].blank?

    @payload = JSON.parse(params[:payload])
    @payload = [@payload] if @payload.instance_of? Hash

    @payload.each do |event|
      update_from_event(event)

      date = Date.today
      $redis.sadd "#{@account}:#{@test}:dates", date

      is_new = event["new"]
      raise ApiError, "Valid parameter required: 'new'" unless is_new != nil
      is_activated = event["activated"]
      raise ApiError, "Valid parameter required: 'activated'" unless is_activated != nil

      new_activated = (is_new ? "n" : "o") + (is_activated ? "a" : "u")

      days = event["days"]
      days = [days] if days.instance_of? Fixnum
      raise ApiError, "Valid parameter required: 'days'" unless days.class == Array

      days.each do |day|
        $redis.sadd "#{@account}:#{@test}:days", day
        $redis.incr "#{@account}:#{@test}:#{@variant}:#{new_activated}:#{day}:#{date}"
      end
    end

    render :json => { :status => "Success" }
  end


  def ab_referral
    raise ApiError, "Parameter required: 'payload'" if params[:payload].blank?

    @payload = JSON.parse(params[:payload])
    @payload = [@payload] if @payload.instance_of? Hash

    @payload.each do |event|
      update_from_event(event)

      if event["referral"]
        $redis.incr "#{@account}:#{@test}:#{@variant}:rfr:referral"
        $redis.sadd "#{@account}:#{@test}:#{@variant}:rfr:referrer", event["user_id"] if event["user_id"]
      elsif event["signup"]
        $redis.incr "#{@account}:#{@test}:#{@variant}:rfr:signup"
      end
    end

    render :json => { :status => "Success" }
  end


  def ab_revenue
    raise ApiError, "Parameter required: 'payload'" if params[:payload].blank?

    @payload = JSON.parse(params[:payload])
    @payload = [@payload] if @payload.instance_of? Hash

    @payload.each do |event|
      update_from_event(event)

      if event["initial"]
        $redis.incr "#{@account}:#{@test}:#{@variant}:rev:initial"
      elsif event["revenue"]
        $redis.incr "#{@account}:#{@test}:#{@variant}:rev:revenue"
      end
    end

    render :json => { :status => "Success" }
  end

  def ab_activation
    raise ApiError, "Parameter required: 'payload'" if params[:payload].blank?

    @payload = JSON.parse(params[:payload])
    @payload = [@payload] if @payload.instance_of? Hash

    @payload.each do |event|
      update_from_event(event)

      if event["initial"]
        $redis.incr "#{@account}:#{@test}:#{@variant}:atv:initial"
      elsif event["activation"]
        $redis.incr "#{@account}:#{@test}:#{@variant}:atv:activation"
      end
    end

    render :json => { :status => "Success" }
  end


  ################################################################# HELPERS

  protected
  def update_from_event(event)
    test = event["test"]
    raise ApiError, "Valid parameter required: 'test'" unless test.class == String
    @test = test.gsub(/\s/, "_")
    $redis.sadd "#{@account}:tests", @test

    @variant = event["variant"]
    raise ApiError, "Valid parameter required: 'variant'" unless @variant.class == String
    $redis.sadd "#{@account}:#{@test}:variants", @variant
  end

  protected
  def render_error(e)
    raise e if e.class != ApiError
    render :format => :json, :text => { :status => :error,
      :message => e.to_s }.to_json
  end

  protected
  def validate_request
    @apikey = params[:apikey]
    raise ApiError, "Need to specify API key" unless @apikey
    key_data = $redis.get "apikeys:#{@apikey}"
    raise ApiError, "Invalid API key" unless key_data

    value = JSON.parse key_data
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

    @api = params[:version].to_i
    if @api > 0 and @api != API_VERSION
      $redis.incr "deprecated:#{@api}:#{Date.today}"
    end
  end

  protected
  def self.generate_signature(params, secret)
    signature = params.sort do |a,b|
      a.to_s <=> b.to_s
    end.reduce("") do |result, pair|
      if pair[0] == "sig" or pair[0] == "action" or pair[0] == "controller" or pair[0] == "version"
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
