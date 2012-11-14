# Brain

![The Brain](http://www.badhaven.com/wp-content/uploads/2012/07/the-brain.jpg)

# API

start_server
  - id                    # if ommitted will create new server_id
  - funpack_id
  - world_id              # optional
  - restart (bool)        # should the server restart if running
  - settings
  
  # returns
  - id

stop_server
  - id

import_world
  - url

# Callbacks

server_started
  - id
  - host

# TODO

Auth/user accounts. Currently the only user is Minefold