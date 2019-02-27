# Astrid Analytics

A/B Testing for Retention and other metrics

Astrid Analytics is a redis-based backend for collecting and displaying the results of A/B tests. Your application (web or mobile) makes HTTP POST calls to the server, which collects counting stats. It's a thin layer over redis, so it's highly scalable!

Created for Astrid, the world's best todo list (RIP).

**Features:**
- p-value calculator
- as many buckets as you want
- full-screen counting stats UI
- once a test is done, you can write a summary and archive the test

**Document your learnings, get smarter.**

Example of an A/B test of a feature on Android:

![image](https://user-images.githubusercontent.com/126260/53511372-27831f00-3a75-11e9-8663-957999579b93.png)

In this case, we learned that removing shortcuts for "Today", "Tomorrow", etc increased retention, helping show that a simpler UI was better.

Example of multi-variant A/B test of re-engagement emails (tracked on the backend)

![image](https://user-images.githubusercontent.com/126260/53511130-7a100b80-3a74-11e9-8976-b95d54c77874.png)

In this case, we learned that a particular version of email was better for re-engaging users.

Example of counting stats dashboard. We track the metric over the past 7 days (168 hours), and compare to last week and 4 weeks ago.

![screen shot 2019-02-27 at 09 58 23](https://user-images.githubusercontent.com/126260/53511874-3d451400-3a76-11e9-950d-d3dff2dae652.png)


## Getting Started

To set up the server:

1. Install redis and ruby

2. `bundle`

3. `bundle exec rake db:migrate`

4. `bundle exec rails s`

5. Visit http://localhost:3000

6. Log in with "admin" and "password" (see admin.rb for using environment variables)

7. Create a new environment (e.g. myapp)

8. Create a new client (e.g. web)

9. Make API calls

10. See results


## API Authentication

All API methods are in api_controller.rb

Aside from parameters required for each method, the following parameters are required for every method:
* apkikey: API application id
* sig: signature, generated via the following:
  - sort every parameter alphabetically by key first, then value
  - concatenate keys and values (skip arrays and uploaded files)
  - append your API secret
  - take the MD5 digest

For example, for params "apikey=1&title=baz&tag[]=foo&tag[]=bar&time=1297216408"
your signature string will be: "apikey1tag[]bartag[]footime=1297216408titlebaz<APP_SECRET>",
so your final param might look like:

`app_id=1&title=baz&tag[]=foo&tag[]=bar&time=1297216408&sig=c7e14a38df42...`

## API Commands

The analytics API is divided into two parts. The first part is the counting statistics, which produce pretty full-screen graphs that show the metric over the past week.

The second part is the A/B testing statistics, which track tests with metrics that you care about and will produce reports with statistical significance (see screenshot above).

This library does not include bucketing - you will need to handle bucketing on your own, either on the client or the server side. That's a whole other can of worms, but for independent, client-side tests, you can generally use persistent client-side random bucket.

## Counting API commands

### `POST api/2/acquisition` - record aquisition event

No parameters are required for this call. Please make sure to
send this only once for each new user

### `POST api/2/activation` - record activation event

No parameters are requried for this call. Please make sure to
send this only once for each activated user

### `POST api/2/retention` - record retention event

Parameters:
- user_id - unique user identifier for calculating unique retention

The minimum reporting threshold for this API is once per hour per user.


### `POST api/2/referral` - record referral event

 Send once per referral event

### `POST api/2/revenue` - record revenue event

Parameters
- delta - record a change in the # of paid users
- total - record the total # of paid users
- (one of delta or total is required)

If new subscriptions occur often, you can use the delta parameter
to send the number of new or removed subscriptions. To initialize
the count, or if subscription events are not visible to your system,
you can send the total.

## A/B API commands

### `POST api/2/ab_retention` - record a/b retention event

Parameters
- payload - array of events

Each event contains the following fields:
- test - name of A/B test
- variant - name of variant
- new - whether the user was a new user
- activated - whether user was activated (took whatever activation steps you require)
- days - array of days since signup that the user showed up (e.g. [1, 2, 3])

### `POST api/2/ab_referral` - record a/b referral event

Parameters
- payload - array of events

Each event contains the following fields:
- test - name of A/B test
- variant - name of variant
- referral - if true, this was a referral event
- signup - if true, this was a signup event

### `POST api/2/ab_revenue` - record a/b revenue event

Parameters
- payload - array of events

Each event contains the following fields:
- test - name of A/B test
- variant - name of variant
- initial - if true, the user showed up in the bucket
- revenue - if true, the user paid / subscribed


### `POST api/2/ab_activation` - record a/b activation event

Parameters
- payload - array of events

Each event contains the following fields:
- test - name of A/B test
- variant - name of variant
- initial - if true, the user showed up in the bucket
- activation - if true, the user became activated
