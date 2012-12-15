brain: bundle exec bin/brain
worker: bundle exec rake resque:work QUEUE=pc TERM_CHILD=1 COUNT=${RESQUE_COUNT:-2} INTERVAL=${RESQUE_INTERVAL:-0.1}
