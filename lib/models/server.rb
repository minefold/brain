module Models
  class Server < Model
    extend Prism::Mongo

    collection :servers

    %w(
       created_at
       updated_at
       slots
       funpack_id
       settings
       versions
       snapshot_id
    ).each do |field|
      define_method(:"#{field}") do
        @doc[field]
      end
    end

    def self.upsert id, funpack_id, settings, *a, &b
      cb = EM::Callback(*a, &b)

      ts = Time.now
      
      query = {_id: BSON::ObjectId(id)}

      upserted = proc {
        find_one(query) do |model|
          cb.call model
        end
      }

      find_one(query) do |model|
        if model.nil?
          insert({
            _id: BSON::ObjectId(id),
            created_at: ts,
            updated_at: ts,
            funpack_id: funpack_id,
            settings: settings
          }, upserted)
        else
          doc = {
            '$set' => {
              updated_at: ts
            }
          }

          doc['$set'].merge!(funpack_id: funpack_id) if funpack_id
          doc['$set'].merge!(setttings: settings) if settings

          update(query, doc, upserted)
        end
      end

      cb
    end
  end
end