class ReportsController < ApplicationController

  before_filter :validate_request
  
  ################################################################# ACTIONS

  def show
    @account = params[:account]
    @account_data = JSON.parse($redis.get "#{@account}:data")

    raise "Unknown account #{@account}" unless @account_data

    @tests = $redis.smembers "#{@account}:tests"
    @archived = $redis.smembers "#{@account}:archived"

    @test_data = @tests.reduce({}) do |result, test|
      variants = $redis.smembers("#{@account}:#{test}:variants")
      days = $redis.smembers("#{@account}:#{test}:days").map(&:to_i)
      days = (days + [0, 1, 3, 7, 14]).uniq.sort
      dates = $redis.smembers("#{@account}:#{test}:dates")
      dates = dates.map { |date| Date.parse(date) }.sort
      description = $redis.get("#{@account}:#{test}:description")
      null_variant = $redis.get("#{@account}:#{test}:null_variant")

      variants = [null_variant] + variants.reject { |v| v == null_variant } if null_variant
      
      result[test] = {
        :variants => variants,
        :days => days,
        :dates => dates,
        :description => description,
        :null_variant => null_variant,
      }
      result
    end

    @tests = @tests - @archived

    @variant_data = {}
    @test_data.each do |test, data|
      next if @archived.include? test
      variants = data[:variants]
      dates = data[:dates]
      days = data[:days]
      null_variant = data[:null_variant]

      test_results = {}

      # compute variant data
      variants.each do |variant|
        variant_results = {}

        [:new, :old].each do |user_status|
          user_results = {}
          
          days.each do |day|
            day_results = {}
            
            valid_dates = dates.select { |date| date <= Date.today - day }
            keys = generate_keys test, variant, user_status, 0, valid_dates
            sum = $redis.mget(*keys, nil).compact.map(&:to_i).sum
            day_results[:total] = sum

            keys = generate_keys test, variant, user_status, day, dates
            sum = $redis.mget(*keys, nil).compact.map(&:to_i).sum
            day_results[:opened] = sum

              day_results[:retained] = 0
              day_results[:error] = 0
            if day_results[:total] > 0
              day_results[:retained] = day_results[:opened] * 100.0 / day_results[:total]
              err_sqr = (day_results[:retained]/100 * (1 - day_results[:retained]/100)) / day_results[:total]
              if err_sqr >= 0
                day_results[:error] = Math.sqrt(err_sqr)
              else
                print "ERRSQR was < 0: #{err_sqr}, #{day_results[:retained]}, #{day_results[:total]}"
              end
            end

            user_results[day] = day_results
          end
          
          variant_results[user_status] = user_results
        end

        test_results[variant] = variant_results
      end

      # compute summary
      test_results[:summary] = {}
      [:new, :old].each do |user_status|
        user_results = {}
        
        days.each do |day|
          day_results = {}

          retained = variants.map { |variant| test_results[variant][user_status][day][:retained] }
          error = variants.map { |variant| test_results[variant][user_status][day][:error] }
          
          day_results[:delta] = retained.max - retained.min
          day_results[:zscore] = "-"
          day_results[:pvalue] = "-"
          day_results[:significant] = "-"

          if null_variant
            null_retained = test_results[null_variant][user_status][day][:retained]
            day_results[:delta] = variants.reject { |v| v == null_variant }.map { |v|
              test_results[v][user_status][day][:retained] - null_retained }.max
            day_results[:percent] = day_results[:delta] * 100 / null_retained if null_retained > 0
            day_results[:plusminus] = day_results[:delta] > 0 ? "plus" : (day_results[:delta] < 0 ? "minus" : "")
          end
          
          if day > 0 and retained.sum > 0
            day_results[:zscore] = day_results[:delta]/100/Math.sqrt(error.map { |e| e ** 2 }.sum)
            day_results[:pvalue] = Normdist::normdist(day_results[:zscore], 0, 1, false)
            day_results[:significant] = (day_results[:pvalue] < 0.05 || day_results[:pvalue] > 0.95) ? "YES" : "NO"            
          end

          user_results[day] = day_results
        end

        test_results[:summary][user_status] = user_results
      end 
      

      @variant_data[test] = test_results
    end
  end
  
  ################################################################# HELPERS

  protected
  def generate_keys(test, variant, user_status, day, valid_dates)
    valid_dates.reduce([]) do |r, date|
      if user_status == :new
        r += ["#{@account}:#{test}:#{variant}:nu:#{day}:#{date}",
              "#{@account}:#{test}:#{variant}:na:#{day}:#{date}"]
      else
        r += ["#{@account}:#{test}:#{variant}:oa:#{day}:#{date}"]
      end
      r
    end
  end
    
end
