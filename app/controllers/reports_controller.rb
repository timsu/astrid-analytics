class ReportsController < ApplicationController

  before_filter :validate_request
  
  ################################################################# ACTIONS

  def retention
    @account = params[:account]
    @account_data = JSON.parse($redis.get "#{@account}:data")

    @retention = retention_read

    # build up user id union for minor graphs
    @retention[:last_week] = week_retention Time.now - 7.day
    @retention[:four_weeks] = week_retention Time.now - 28.day
  end

  def pirate
    @account = params[:account]
    @account_data = JSON.parse($redis.get "#{@account}:data")
    
    apikeys = $redis.smembers "#{@account}:apikeys"
    @clients = apikeys.map { |apikey| JSON.parse($redis.get("apikeys:" + apikey))[1] }

    @acquisition = pirate_read "acq", true
    @activation = pirate_read "atv"
    @retention = retention_read
    @referral = pirate_read "rfr", true
    @revenue = revenue_read
  end

  def ab
    @account = params[:account]
    @account_data = JSON.parse($redis.get "#{@account}:data")

    raise "Unknown account #{@account}" unless @account_data

    @tests = $redis.smembers("#{@account}:tests").sort
    @archived = $redis.smembers "#{@account}:archived"

    @test_data = @tests.reduce({}) do |result, test|
      variants = $redis.smembers("#{@account}:#{test}:variants")
      days = $redis.smembers("#{@account}:#{test}:days").map(&:to_i)
      days = (days + [0, 1, 3, 7, 14]).uniq.sort
      dates = $redis.smembers("#{@account}:#{test}:dates")
      dates = dates.map { |date| Date.parse(date) }.sort
      description = $redis.get("#{@account}:#{test}:description")
      null_variant = $redis.get("#{@account}:#{test}:null_variant")
      user_groups = $redis.get("#{@account}:#{test}:user_groups")
      metric_filter = $redis.get("#{@account}:#{test}:metric_filter")
      
      variants = [null_variant] + variants.reject { |v| v == null_variant } if null_variant
      user_groups = user_groups ? JSON.parse(user_groups).map(&:to_sym) : [:new, :ea]
      metric_filter = metric_filter ? JSON.parse(metric_filter).map(&:to_sym) : [:referral, :signup, :activation, :revenue]
      
      result[test] = {
        :variants => variants,
        :days => days,
        :dates => dates,
        :description => description,
        :null_variant => null_variant,
        :user_groups => user_groups,
        :metric_filter => metric_filter
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
      user_groups = data[:user_groups]
      metric_filter = data[:metric_filter]

      test_results = {}

      # compute variant data
      variants.each do |variant|
        variant_results = { :total_users => 0 }
        
        user_groups.each do |user_status|
          user_results = {}          
          days.each do |day|
            day_results = {}
            
            valid_dates = dates.select { |date| date <= Date.today - day }
            keys = generate_ab_keys test, variant, user_status, 0, valid_dates
            sum = $redis.mget(*keys + [nil]).compact.map(&:to_i).sum
            day_results[:total] = sum

            valid_dates = dates.select { |date| date <= Date.today }
            keys = generate_ab_keys test, variant, user_status, day, valid_dates
            sum = $redis.mget(*keys + [nil]).compact.map(&:to_i).sum
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
          variant_results[:total_users] += user_results[0][:total]
          variant_results[user_status] = user_results
        end
        ([:new, :ea, :eu] - user_groups).each do |user_status|
          valid_dates = dates.select { |date| date <= Date.today }
          keys = generate_ab_keys test, variant, user_status, 0, valid_dates
          sum = $redis.mget(*keys + [nil]).compact.map(&:to_i).sum
          variant_results[:total_users] += sum
        end

        metrics = map_variant test, variant
        metrics.each do |key, value|
          map_percent_and_total(value, key == :signup ? metrics[:referral][:users] : variant_results[:total_users])
        end          
        variant_results[:metrics] = metrics          

        test_results[variant] = variant_results
      end

      # compute summary
      test_results[:summary] = {}
      
      test_results[:summary][:metrics] = {}
      
      #metrics
      metric_filter.each do |key|
        percent = variants.map { |variant| test_results[variant][:metrics][key][:percent] }
        metric_results = {}
        metric_results[:delta] = percent.max - percent.min
        
        metric_results[:zscore] = "-"
        metric_results[:pvalue] = "-"
        metric_results[:significant] = "-"
        
        if null_variant
          null_percent = test_results[null_variant][:metrics][:percent]
          #percent = nil
          #finish this
        end
        if percent.sum > 0
          chi_sq = chi_squared(variants, test_results, :metrics, key, :users, :total)
        
          metric_results[:chisq] = chi_sq
          metric_results[:chisqp] = Distribution::ChiSquare.q_chi2(variants.size - 1, chi_sq)
          metric_results[:chisqsig] = metric_results  [:chisqp] < 0.05 ? "YES" : "NO"
        end
        
        test_results[:summary][:metrics][key] = metric_results
      end
      
      
      user_groups.each do |user_status|
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
            day_results[:pvalue] = Normdist::normdist(day_results[:zscore], 0, 1, true)
            day_results[:significant] = (day_results[:pvalue] < 0.05 || day_results[:pvalue] > 0.95) ? "YES" : "NO"     
            
            chi_sq = chi_squared(variants, test_results, user_status, day, :opened, :total)
                      
            day_results[:chisq] = chi_sq
            day_results[:chisqp] = Distribution::ChiSquare.q_chi2(variants.size - 1, chi_sq)
            day_results[:chisqsig] = day_results[:chisqp] < 0.05 ? "YES" : "NO"
         
          end
          user_results[day] = day_results
        end

        test_results[:summary][user_status] = user_results
      end 
      

      @variant_data[test] = test_results
    end
  end

  def engineyard
    @time = params[:time] || 1.hour
    
    @dna = JSON.load Rails.root.join "config/dna.json"
    instances = @dna["engineyard"]["environment"]["instances"]
    
    @app_master = instances.find { |instance| instance["role"] == "app_master" }
    @app_servers = instances.select { |instance| instance["role"] == "app" }

    @db_master = instances.find { |instance| instance["role"] == "db_master" }
    @db_slaves = instances.select { |instance| instance["role"] == "db_slave" }

    @memcache = instances.find { |instance| instance["name"] == "memcache01" }
    @solr = instances.find { |instance| instance["name"] == "solr01" }
  end
  
  ################################################################# HELPERS
  protected
  def map_percent_and_total(hash, total_users)
    hash[:total] = total_users
    hash[:percent] = total_users > 0 ? hash[:users] * 100.0 /total_users : 0
    hash
  end
  
  protected
  def map_variant(test, variant)
    referral = { :users => $redis.get("#{@account}:#{test}:#{variant}:rfr:referral").to_i }
    signup = { :users =>  $redis.get("#{@account}:#{test}:#{variant}:rfr:signup").to_i }
    revenue = { :users => $redis.get("#{@account}:#{test}:#{variant}:rev:revenue").to_i }
    activation = { :users => $redis.get("#{@account}:#{test}:#{variant}:atv:activation").to_i }
    { :referral => referral, :signup => signup,
      :revenue => revenue, :activation => activation }
  end
  
  protected
  def chi_squared(variants, test_results, first_hash_key, second_hash_key, stat_key, total_key)
    overall_total = variants.reduce(0) do |result, variant|
      result += test_results[variant][first_hash_key][second_hash_key][total_key]
    end
  
    overall_total_retained = variants.reduce(0) do |result, variant|
      result += test_results[variant][first_hash_key][second_hash_key][stat_key]
    end
    
    chi_sq = variants.reduce(0) do |result, variant|
      #expected total = row total * column total / table total
      exp_retained = test_results[variant][first_hash_key][second_hash_key][total_key] *
        overall_total_retained / overall_total.to_f
      exp_not_retained = (test_results[variant][first_hash_key][second_hash_key][total_key] *
                          (overall_total - overall_total_retained)) / overall_total.to_f
      
      obs_retained = test_results[variant][first_hash_key][second_hash_key][stat_key].to_f
      obs_not_retained = test_results[variant][first_hash_key][second_hash_key][total_key] -
        test_results[variant][first_hash_key][second_hash_key][stat_key].to_f
      
      ret_point = 0
      ret_point = ((obs_retained - exp_retained)**2) / exp_retained.to_f if exp_retained > 0
      
      not_ret_point = 0
      not_ret_point = ((obs_not_retained - exp_not_retained)**2) / exp_not_retained.to_f if
        exp_not_retained > 0
      
      result += (ret_point + not_ret_point)
    end
  end

  protected
  def week_retention(time)
    date = time.to_date
    key = "ret:#{@account}:weekval:#{date}"
    if $redis.exists key
      $redis.get key
    else
      sets = (0..6).map { |i| (date - i).to_s }
      keys = sets.map { |date| "ret:#{@account}:#{date}" }
      count = $redis.sunionstore(*["#{@account}:retention:result"] + keys)
      $redis.set key, count
      count
    end.to_i
  end

  # read dashboard stats for retention, where keys are sets
  protected
  def retention_read
    now = Time.now

    # build up user id union from hours today & 7 days ago + middle 5 days
    sets =
      (0..now.hour - 1).map { |i| Date.today.to_s + "T%02d" % i } +
      (now.hour..23).map { |i| (Date.today - 7).to_s + "T%02d" % i } +
      (1..6).map { |i| (Date.today - i).to_s }
    keys = sets.map { |date| "ret:#{@account}:#{date}" }
    total = $redis.sunionstore(*["#{@account}:retention:result"] + keys).to_i

    # build up user id union for minor graphs
    yesterday = week_retention now - 1.day
    p "#{yesterday.class} and #{total.class}"
    delta = yesterday == 0 ? "-" : (100.to_f * total / yesterday - 100)

    # build chart
    chart_dates = (-30..-1).map { |i| Date.today + i }
    chart_result_keys = chart_dates.map { |date| "ret:#{@account}:dayval:#{date}" }
    chart_result_values = $redis.mget *chart_result_keys
    chart_dates.each_with_index do |date, i|
      if chart_result_values[i].nil?
        count = $redis.scard "ret:#{@account}:#{date}"
        $redis.set "ret:#{@account}:dayval:#{date}", count
        chart_result_values[i] = count
      elsif chart_result_values[i].class != Fixnum
        chart_result_values[i] = chart_result_values[i].to_i
      end
    end

    chart = [{ :label => "# of users",
               :data => chart_dates.map { |date| date.to_time.httpdate }.zip(chart_result_values)
             }].to_json
    
    { :yesterday => yesterday, :total => total, :delta => delta, :chart => chart }
  end
  
  # read dashboard stats where keys are current totals
  protected
  def revenue_read
    now = Time.now

    dates = (-30..0).map { |i| Date.today + i }
    keys = dates.map { |date| "rvn:#{@account}:#{date}" }

    last = 0
    data = keys.zip($redis.mget(*keys)).map do |data|
      if data.last
        last = data.last.to_i
      else
        $redis.set data.first, last
        last
      end
    end
    p data

    total = last
    yesterday = data[-2]
    delta = yesterday == 0 ? "-" : 100.to_f * total / yesterday - 100

    chart_dates = dates[0..-2]
    chart_result_values = data[0..-2]
    chart = [{ :label => "# of users",
               :data => chart_dates.map { |date| date.to_time.httpdate }.zip(chart_result_values)
             }].to_json

    { :yesterday => yesterday, :total => total, :delta => delta, :chart => chart }
  end
    
  # read dashboard stats where keys are just numbers
  protected
  def pirate_read(stat, split_client = false)
    now = Time.now
    
    sets = (0..now.hour - 1).map { |i| Date.today.to_s + "T%02d" % i } +
      (now.hour..23).map { |i| (Date.today - 7).to_s + "T%02d" % i } +
      (1..6).map { |i| (Date.today - i).to_s }

    if split_client
      by_client = @clients.reduce({}) do |data, client|
        keys = sets.map { |date| "#{stat}:#{@account}:#{client}:#{date}" }
        data[client] = $redis.mget(*keys).compact.map(&:to_i).sum
        data
      end
      total = by_client.values.sum
    else
      keys = sets.map { |date| "#{stat}:#{@account}:#{date}" }
      total = $redis.mget(*keys).compact.map(&:to_i).sum
    end

    sets = (1..7).map { |i| (Date.today - i).to_s }
    keys = sets.map { |date| "#{stat}:#{@account}:#{date}" }
    yesterday = $redis.mget(*keys).compact.map(&:to_i).sum

    delta = yesterday == 0 ? "-" : 100.to_f * total / yesterday - 100

    chart_dates = (-30..-1).map { |i| Date.today + i }
    keys = chart_dates.map { |date| "#{stat}:#{@account}:#{date}" }
    chart_result_values = $redis.mget(*keys).map { |value| value || 0 }
    chart = [{ :label => "# of users",
               :data => chart_dates.map { |date| date.to_time.httpdate }.zip(chart_result_values)
             }].to_json

    { :by_client => by_client, :yesterday => yesterday, :total => total,
      :delta => delta, :chart => chart }
  end
  
  protected
  def generate_ab_keys(test, variant, user_status, day, valid_dates)
    valid_dates.reduce([]) do |r, date|
      if user_status == :new
        r += ["#{@account}:#{test}:#{variant}:nu:#{day}:#{date}",
              "#{@account}:#{test}:#{variant}:na:#{day}:#{date}"]
      elsif user_status == :ea
        r += ["#{@account}:#{test}:#{variant}:oa:#{day}:#{date}"]
      elsif user_status == :eu
        r += ["#{@account}:#{test}:#{variant}:ou:#{day}:#{date}"]
      end
      r
    end
  end
    
end
