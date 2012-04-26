class ReportsController < ApplicationController

  before_filter :validate_request
  
  ################################################################# ACTIONS

  def show
    @account = params[:account]
    @account_data = JSON.parse($redis.get "#{@account}:data")

    @tests = $redis.smembers "#{@account}:tests"

    @test_data = @tests.reduce({}) do |result, test|
      variants = $redis.smembers("#{@account}:#{test}:variants")
      days = $redis.smembers("#{@account}:#{test}:days").map(&:to_i)
      days = (days + [0, 3, 7, 14]).uniq.sort
      dates = $redis.smembers("#{@account}:#{test}:dates").sort
      
      result[test] = {
        :variants => variants,
        :days => days,
        :dates => dates,
      }
      result
    end
  end
  
  ################################################################# HELPERS
  
  protected
  def validate_request
    authenticate_or_request_with_http_basic do |username, password|
      return true if username == "rockthe" && password == "casbah!"

      # TODO authenticate by account data
    end
  end

end
