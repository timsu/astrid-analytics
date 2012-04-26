class ApplicationController < ActionController::Base
  protect_from_forgery

  ################################################################# REFERENCE

  # redis keys:

  # accounts - map of account ids 
  # apikeys:<apikey> - json of api key info [account, client, secret]

  # <account>:data - json of account data { id, name, email, salt, password }
  # <account>:apikeys - set of api keys
  # <account>:tests - set of tests we know about
  # <account>:<test>:variants - set of variants for this test
  # <account>:<test>:days - set of days we know about (e.g. 0, 3, 7, 14)
  # <account>:<test>:dates - set of dates for this test
  # <account>:<test>:<variant>:<user_state>:<day>:<date> - # of events with this criteria


  ################################################################# AUTHENTICATION

  protected
  def validate_request
    authenticate_or_request_with_http_basic do |username, password|
      return true if username == "rockthe" && password == "casbah!"

      # TODO authenticate by account data
    end
  end

end

