module ApplicationHelper

  def number(num)
    number_to_human num, :units => {:unit => "", :thousand => "K", :million => "M"}
  end

  def percent(pct)
    if pct.instance_of? Float
      number_to_percentage pct, :significant => true
    else
      pct
    end
  end

end
