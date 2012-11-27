# Brain

[![Build Status](https://magnum.travis-ci.com/minefold/brain.png?token=yfARxv3oq7ZT3ZbmJWVN)](http://magnum.travis-ci.com/minefold/brain) © Mütli Corp. By [Dave Newman](http://github.com/whatupdave).

![The Brain](http://www.badhaven.com/wp-content/uploads/2012/07/the-brain.jpg)

## API

    start_server
      - id              # if ommitted will create new server_id
      - funpack_id
      - snapshot_id     # optional (will use last snapshot if left out)
      - restart (bool)  # should the server restart if running
      - settings

      # returns
      - id

    stop_server
      - id

    import_world
      - url
  
## Database

    servers
      created_at
      updated_at
      deleted_at
      
    worlds
      created_at
      updated_at
      deleted_at
      
      versions [
        created_at
        url
      ]
      

## Callbacks

    server_started
      - id
      - host

## Redis keys

      LIST partycloud:brain:in
       SET boxes
    STRING box:#{box_id}
       SET servers
       SET servers:shared
    STRING server:#{server_id}:state
       SET server:#{server_id}:players
    STRING server:#{server_id}:slots
      LIST server:events
       SET pinkies
    STRING pinky:#{pinky_id}:state
    STRING pinky:#{pinky_id}:heartbeat
       SET pinky:#{pinky_id}:servers
    STRING pinky:#{pinky_id}:server:#{server_id}
      LIST pinky:#{pinky_id}:in


## Usage

    foreman start

### Environment

*Required*

    BUGSNAG

*Optional*

    BRAIN_ENV (staging|production)
    BRAIN_ROOT

## Server reallocation

PartyUnit (PU):
  - 1 ECU
  - 512Mb RAM

### Scenario
brain allocates server with 1PU
brain starts funpack with 512Mb ram

funpack starts stressing
brain monitors
funpack stops stressing
brain forgets

funpack starts stressing
brain monitors
funpack still stressing after x minutes

**Party Cloud friendly game:**

brain ups allocation to 2PUs
if brain finds room on same box
  brain tells funpack to reallocate to 1024Mb
  
else
  brain tells pc-router that host is switching
  funpack detects change and messages connected clients to pause/buffer
  funpack exits
  brain starts funpack on new host
  funpack connects to pc-router and reconnects players

**non PC friendly game:**

brain ups allocation to 2PUs



## TODO

Auth/user accounts. Currently the only user is Minefold