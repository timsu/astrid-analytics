#!/bin/bash

scp deploy@ec2-204-236-247-9.compute-1.amazonaws.com:/db/redis/redis_state.rdb dump.rdb
sudo mv dump.rdb /var/lib/redis-analytics
sudo chown redis:redis /var/lib/redis-analytics/dump.rdb
sudo /etc/init.d/redis-server stop
sudo redis-server /etc/redis/redis-analytics.conf
echo "redis-analytics server is running."
