#!/bin/bash

echo "pulling git"
git pull
bundle
echo "precompiling assets"
rake RAILS_ENV=production assets:precompile
echo "restarting unicorn"
/etc/init.d/unicorn reload
