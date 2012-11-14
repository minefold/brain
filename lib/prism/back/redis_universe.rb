require 'eventmachine/multi'

module Prism
  class RedisUniverse
    def self.collect timeout = 10, *c, &b
      cb = EM::Callback(*c, &b)
      redis = Prism.redis

      @timeout = EM.add_periodic_timer(timeout) {
        puts "timeout collecting redis state"
        EM.stop
      }

      redis.keys("widget:*:heartbeat") do |heartbeats|
        multi = EventMachine::Multi.new
        multi.add :running_boxes,   redis.hgetall_json('workers:running')
        multi.add :busy_boxes,      redis.hgetall_json('workers:busy')
        multi.add :running_worlds,  redis.hgetall_json( 'worlds:running')
        multi.add :busy_worlds,     redis.hgetall_json( 'worlds:busy')
        multi.add :players,         redis.hgetall('players:playing')

        heartbeats.each {|key| multi.add key, redis.get(key) }

        multi.callback do |results|
         @timeout.cancel
         cb.call RedisUniverse.new results
        end
      end
      cb
    end

    attr_reader :boxes, :worlds, :players, :widgets, :widget_worlds

    def initialize results = {}
      @boxes = {
         running: results[:running_boxes],
            busy: results[:busy_boxes]
      }

      @worlds = {
        running: results[:running_worlds],
           busy: results[:busy_worlds]
      }

      @players = {}

      world_players = results[:players].each_with_object({}) do |(user_id, world_id), hash|
        @players[user_id] = world_id

        hash[world_id] ||= []
        hash[world_id] = hash[world_id] | [user_id]
      end

      @widgets = results.each_with_object({}) do |(key, heartbeat), h|
        key =~ /widget:(.*):heartbeat/
        if id = $1
          h[id] = JSON.parse heartbeat
        end
      end

      @widget_worlds = @widgets.each_with_object({}) do |(id, widget), h|
        widget['pi'].each do |world_id, world|
          h[world_id] = world
        end
      end

      @worlds[:running].each do |world_id, world|
        instance_id = world['instance_id']
        @worlds[:running][world_id][:players] = world_players[world_id] || []
        @worlds[:running][world_id][:box] = @boxes[:running][instance_id]
      end

      @boxes[:running].each do |instance_id, box|
        @boxes[:running][instance_id][:worlds]  = @worlds[:running].select {|world_id, world| world['instance_id'] == instance_id }
        @boxes[:running][instance_id][:players] = @boxes[:running][instance_id][:worlds].inject([]) do |acc, (world_id, world)|
          acc | world[:players]
        end
      end
    end
  end
end