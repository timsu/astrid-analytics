class ReportsController < ApplicationController

  before_filter :validate_request

  require 'samplesize'

  ################################################################# ACTIONS

  def acquisition
    @account = params[:account]
    @account_data = JSON.parse($redis.get "#{@account}:data")

    apikeys = $redis.smembers "#{@account}:apikeys"
    @clients = apikeys.map { |apikey| JSON.parse($redis.get("apikeys:" + apikey))[1] }

    @type = "Acquisition"
    @tag = "# of new users on"
    @color = "#0A1327"
    @data = pirate_read "acq", true

    @chart_start = params[:days] ? params[:days].to_i : 30
    chart_dates = (-@chart_start..-1).map { |i| Date.today + i }
    charts = []
    @clients.each do |client|
      keys = chart_dates.map { |date| "acq:#{@account}:#{client}:#{date}" }
      chart_result_values = $redis.mget(*keys).map { |value| value || 0 }
      charts << { :label => client + ": # of users",
                  :color => { "ios" => "#B7F2FB", "web" => "#FA6900", "android" => "#9AE14D" }[client],
                  :data => chart_dates.map { |date| date.to_time.httpdate }.zip(chart_result_values) }
    end
    @data[:chart] = charts.to_json
    @data[:last_week] = pirate_week "acq", Time.now - 7.days
    @data[:four_weeks] = pirate_week "acq", Time.now - 28.days

    render 'big_dashboard'
  end

  def retention
    @account = params[:account]
    @account_data = JSON.parse($redis.get "#{@account}:data")

    @type = "Retention"
    @tag = "# of activated users on"
    @color = "#150127"

    @chart_start = params[:days] ? params[:days].to_i : 30
    @data = retention_read @chart_start
    @data[:last_week] = week_retention Time.now - 7.day
    @data[:four_weeks] = week_retention Time.now - 28.day

    render 'big_dashboard'
  end

  def revenue
    @account = params[:account]
    @account_data = JSON.parse($redis.get "#{@account}:data")

    @type = "Revenue"
    @tag = "# of premium accounts on"
    @color = "#152701"

    @chart_start = params[:days] ? params[:days].to_i : 30
    chart_dates = (-@chart_start..-1).map { |i| Date.today + i }
    keys = chart_dates.map { |date| "rvn:#{@account}:#{date}" }
    chart_result_values = $redis.mget(*keys).map { |value| value || 0 }
    charts = [{ :label => "# of accounts",
                :color => "#9AE14D",
                :data => chart_dates.map { |date| date.to_time.httpdate }.zip(chart_result_values) }]

    @data = revenue_read
    @data[:chart] = charts.to_json
    @data[:last_week] = $redis.get("rvn:#{@account}:#{Date.today - 7.days}")
    @data[:four_weeks] = $redis.get("rvn:#{@account}:#{Date.today - 28.days}")

    render 'big_dashboard'
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

    show_test_data
  end

  def ab_test
    @account = params[:account]
    @account_data = JSON.parse($redis.get "#{@account}:data")

    raise "Unknown account #{@account}" unless @account_data

    @tests = [params[:test]]
    @archived = []

    show_test_data
  end

  def show_test_data
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
      if user_groups
        if user_groups["["]
          user_groups = JSON.parse(user_groups).map(&:to_sym)
        else
          user_groups = [user_groups.to_sym]
        end
      else
        user_groups = [:new, :ea]
      end

      selected_metrics = [:activation, :referrer, :revenue].select { |metric|
        metric_filter ? metric_filter[metric.to_s] : false }
      selected_metrics += [:referral, :signup] if selected_metrics.include? :referrer

      result[test] = {
        :variants => variants,
        :days => days,
        :dates => dates,
        :description => description,
        :null_variant => null_variant,
        :user_groups => user_groups,
        :selected_metrics => selected_metrics
      }
      result
    end

    @archived.sort! do |a, b|
      a_data = @test_data[a]
      b_data = @test_data[b]
      b_data[:dates].first.to_s <=> a_data[:dates].first.to_s
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
      selected_metrics = data[:selected_metrics]

      test_results = {}

      # compute variant data
      variants.each do |variant|
        variant_results = { :total_users => 0 }

        user_groups.each do |user_status|
          user_results = {}
          days.each do |day|
            day_results = {}

            valid_dates = dates.select { |date| date < Date.today - day }
            keys = generate_ab_keys test, variant, user_status, 0, valid_dates
            sum = $redis.mget(*keys + [nil]).compact.map(&:to_i).sum
            day_results[:total] = sum

            valid_dates = dates.select { |date| date < Date.today }
            keys = generate_ab_keys test, variant, user_status, day, valid_dates
            sum = $redis.mget(*keys + [nil]).compact.map(&:to_i).sum
            day_results[:opened] = sum

            day_results[:percent] = 0
            day_results[:error] = 0
            if day_results[:total] > 0
              day_results[:percent] = day_results[:opened] * 100.0 / day_results[:total]
              day_results[:percent] = 100.0 if day_results[:percent] > 100
              err_sqr = (day_results[:percent]/100 * (1 - day_results[:percent]/100)) / day_results[:total]
              if err_sqr >= 0
                day_results[:error] = Math.sqrt(err_sqr)
              else
                # print "ERRSQR was < 0: #{err_sqr}, #{day_results[:percent]}, #{day_results[:total]}"
              end
            end
            user_results[day] = day_results
          end
          variant_results[:total_users] += user_results[0][:total]
          variant_results[user_status] = user_results
        end
        ([:new, :ea, :eu] - user_groups).each do |user_status|
          valid_dates = dates.select { |date| date < Date.today }
          keys = generate_ab_keys test, variant, user_status, 0, valid_dates
          sum = $redis.mget(*keys + [nil]).compact.map(&:to_i).sum
          variant_results[:total_users] += sum
        end

        metrics = map_variant test, variant
        metrics.each do |key, value|
          total = key == :signup ? metrics[:referral][:users] : variant_results[:total_users]
          map_percent_and_total(value, total)
        end
        variant_results[:metrics] = metrics

        test_results[variant] = variant_results
      end

      test_results[:summary] = {}

      test_results[:summary][:metrics] = {}
      selected_metrics.each do |key|
        test_results[:summary][:metrics][key] = significance(test_results, variants, :metrics,
                                                            :percent, :users, :error, key, null_variant, :total)
      end

      user_groups.each do |user_status|
        user_results = {}
        days.each do |day|
          if day == 0
            user_results[day] = {}
          else
            user_results[day] = significance(test_results, variants, user_status,
                                            :percent, :opened, :error, day, null_variant, :total)
          end
        end
        test_results[:summary][user_status] = user_results
      end

      @variant_data[test] = test_results
    end

    render 'ab'
  end

  def engineyard
    @time = params[:time] || 4.hours

    @dna = JSON.load Rails.root.join "config/dna.json"
    instances = @dna["engineyard"]["environment"]["instances"]

    @app_master = instances.find { |instance| instance["role"] == "app_master" }
    @app_servers = instances.select { |instance| instance["role"] == "app" }

    @db_master = instances.find { |instance| instance["role"] == "db_master" }
    @db_slaves = instances.select { |instance| instance["role"] == "db_slave" }

    @memcache = instances.select { |instance| instance["name"].to_s["memcache"] }
    @util = instances.select { |instance| instance["role"] == "util" } - @memcache
  end

  def disk_space
    @time = params[:time] || 1.day
    engineyard
  end

  ################################################################# HELPERS
  protected
  def map_percent_and_total(hash, total_users)
    hash[:total] = total_users
    hash[:percent] = total_users > 0 ? hash[:users] * 100.0 /total_users : 0
    hash
  end

  protected
  def significance(test_results, variants, metrics, percent_success, count, variant_error, key, null_variant, total)

    results = {}
    percent = variants.map { |variant| test_results[variant][metrics][key][percent_success] }
    percent = [0] if percent.length == 0
    total_users = variants.map { |variant| test_results[variant][metrics][key][total] }.sum

    results[:delta] = percent.max - percent.min
    sig_test = (key == :referral or key == :signup) ? :normal_dist : :chi_squared
    error = variants.map { |variant| test_results[variant][metrics][key][variant_error] }

    if null_variant
      null_percent = test_results[null_variant][metrics][key][percent_success]
      results[:delta] = variants.reject { |v| v == null_variant }.map { |v|
        test_results[v][metrics][key][percent_success] - null_percent }.max
      results[percent_success] = results[:delta] * 100 / null_percent if null_percent > 0
      if sig_test == :chi_squared
        results[:plusminus] = results[:delta] > 0 ? "plus" : (results[:delta] < 0 ? "minus" : "")
      end
    end

    if total_users < 100
      results[:significance] = "-"
      return results
    end

    if percent.sum > 0 and sig_test == :chi_squared
      chi_sq = chi_squared(variants, test_results, metrics, key, count, total)
      results[:chisq] = chi_sq
      results[:pvalue] = Distribution::ChiSquare.q_chi2(variants.size - 1, chi_sq)
      results[:significance] = results[:pvalue] < 0.05 ? "YES" : "NO"
      results[:plusminus] = "" if results[:significance] != "YES"
    end

    if percent.sum > 0
      null_variant ||= variants[0]
      null_percent = test_results[null_variant][metrics][key][percent_success] / 100.0
      null_size = test_results[null_variant][metrics][key][total]
      delta = if results[:delta].abs > 0.001 then results[:delta] / 100.0 else 0.01 end
      results[:power] = num_subjects(0.05, 0.8, null_percent, delta)
      not_significant = variants.reduce(false) do |result, variant|
        size = test_results[variant][metrics][key][total]
        result || size < results[:power]
      end
      if not_significant
        results[:significance] = "WAIT"
      end
    end

    results
  end


  protected
  def map_variant(test, variant)
    referrer = { :users => $redis.scard("#{@account}:#{test}:#{variant}:rfr:referrer").to_i }
    referral = { :users => $redis.get("#{@account}:#{test}:#{variant}:rfr:referral").to_i }
    signup = { :users =>  $redis.get("#{@account}:#{test}:#{variant}:rfr:signup").to_i }
    revenue = { :users => $redis.get("#{@account}:#{test}:#{variant}:rev:revenue").to_i }
    activation = { :users => $redis.get("#{@account}:#{test}:#{variant}:atv:activation").to_i }
    { :referral => referral, :signup => signup, :referrer => referrer,
      :revenue => revenue, :activation => activation }
  end

  protected
  def chi_squared(variants, test_results, first_hash_key, second_hash_key, stat_key, total_key)
    overall_total = variants.reduce(0) do |result, variant|
      value = test_results[variant][first_hash_key][second_hash_key][total_key]
      result += value if value
      result
    end

    overall_total_retained = variants.reduce(0) do |result, variant|
      value = test_results[variant][first_hash_key][second_hash_key][stat_key]
      result += value if value
      result
    end

    chi_sq = variants.reduce(0) do |result, variant|
      next unless test_results[variant][first_hash_key][second_hash_key][total_key]
      # expected total = row total * column total / table total
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
  def retention_read(chart_start = 30)
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
    delta = yesterday == 0 ? "-" : (100.to_f * total / yesterday - 100)

    # build chart
    chart_dates = (-chart_start..-1).map { |i| Date.today + i }
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
  def pirate_week(stat, week_ending)
    sets = (0..6).map { |i| (week_ending.to_date - i).to_s }

    keys = sets.map { |date| "#{stat}:#{@account}:#{date}" }
    $redis.mget(*keys).compact.map(&:to_i).sum
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
