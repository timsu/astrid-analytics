# from Evan Miller's sample size websit
# http://www.evanmiller.org/ab-testing/sample-size.html

def ppnd(p)
  a0 = 2.50662823884;
  a1 = -18.61500062529;
  a2 = 41.39119773534;
  a3 = -25.44106049637;
  b1 = -8.47351093090;
  b2 = 23.08336743743;
  b3 = -21.06224101826;
  b4 = 3.13082909833;
  c0 = -2.78718931138;
  c1 = -2.29796479134;
  c2 = 4.85014127135;
  c3 = 2.32121276858;
  d1 = 3.54388924762;
  d2 = 1.63706781897;
  split = 0.42;

  # 0.08 < P < 0.92
  if (p - 0.5).abs <= split
    r = ( p - 0.5 ) * ( p - 0.5 );

    value = (p - 0.5) * ( ( (a3 * r + a2 ) * r + a1 ) * r + a0 ) /
      ( ( ( (b4   * r + b3 ) * r + b2 ) * r + b1 ) * r + 1.0 );

    
    # P < 0.08 or P > 0.92,
    # R = min ( P, 1-P )
  elsif 0.0 < p && p < 1.0
    if 0.5 < p
      r = Math.sqrt( 0 - Math.log( 1.0 - p ) );
    else
      r = Math.sqrt( 0 - Math.log( p ) );
    end

    value = ( ( (c3   * r + c2 ) * r + c1 ) * r + c0 ) /
      ( (d2   * r + d1 ) * r + 1.0 );
    
    if p < 0.5
      value = - value;
    end

    # P <= 0.0 or 1.0 <= P
  else
    value = nil;
  end

  return value
end

# alpha = Percent of the time a difference will be detected, assuming one
# does NOT exist
# beta - Percent of the time the minimum effect size will be detected,
# assuming it exists
# p - conversion rate
# delta - delta to measure
def num_subjects(alpha = 0.05, beta = 0.80, p = 0.40, delta = 0.01)
  t_alpha2 = ppnd(1.0-alpha/2);
  t_beta = ppnd(beta);

  sd1 = Math.sqrt(2 * p * (1.0 - p));
  sd2 = Math.sqrt(p * (1.0 - p) + (p + delta) * (1.0 - p - delta));

  result = (t_alpha2 * sd1 + t_beta * sd2) * (t_alpha2 * sd1 + t_beta * sd2) / (delta * delta);
  result.round
end
