module ApplicationHelper

  def format_number(num)
    number_to_human num, :units => {:unit => "", :thousand => "K", :million => "M"}, :precision => 1, :significant => false
  end

  def format_percent(pct)
    if pct.instance_of? Float
      number_to_percentage pct, :significant => true
    else
      pct
    end
  end

  def format_client(client)
    if client == "ios"
      "iOS"
    elsif client == "iphone"
      "iPhone"
    else
      client.capitalize
    end
  end

end
