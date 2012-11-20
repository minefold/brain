# Brain

[![Build Status](https://magnum.travis-ci.com/minefold/brain.png?token=yfARxv3oq7ZT3ZbmJWVN)](http://magnum.travis-ci.com/minefold/brain) © Mütli Corp. By [Dave Newman](http://github.com/whatupdave).

![The Brain](http://www.badhaven.com/wp-content/uploads/2012/07/the-brain.jpg)

## API

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
    STRING server:#{box_id}:state
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
    
## Prism workflow
* Player connects to prism (username, target_host)
* load server from Minefold Db
* 


## TODO

Auth/user accounts. Currently the only user is Minefold