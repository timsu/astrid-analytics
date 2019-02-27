# Astrid Analytics

A/B Testing for Retention and other metrics

Astrid Analytics is a redis-based backend for collecting and displaying the results of A/B tests. Your application (web or mobile) makes HTTP POST calls to the server, which collects counting stats. It's a thin layer over redis, so it's highly scalable!

Created for Astrid, the world's best todo list (RIP).


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
