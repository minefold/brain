module Models
  class Server < Model
    extend Prism::Mongo

    collection :servers

    %w(
       created_at
       updated_at
       allocation_slots
       versions
       snapshot_id
    ).each do |field|
      define_method(:"#{field}") do
        @doc[field]
      end
    end

    def self.upsert id, *a, &b
      cb = EM::Callback(*a, &b)

      oid = BSON::ObjectId(id)
      ts = Time.now

      query = { _id: oid }

      new_doc = {
        created_at: ts,
        updated_at: ts
      }

      existing_doc = {
        '$set' => {
          updated_at: ts,
        }
      }

      find_one(query) do |model|
        new_record = model.nil?
        properties = new_record ? new_doc : existing_doc

        find_and_modify(
          query: query,
          update: properties,
          upsert: true,
          new: true
        ) do |model|
          cb.call model, new_record
        end
      end

      cb
    end
  end
end