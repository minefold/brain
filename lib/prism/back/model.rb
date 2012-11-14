class Model
  extend Prism::Mongo

  attr_reader :doc

  DEFAULT_SCOPE = { deleted_at: nil }

  def self.collection collection
    @collection = collection.to_s
  end

  def self.mongo_collection
    mongo_connect.collection(@collection)
  end

  def self.find id, *a, &b
    find_one({_id: BSON::ObjectId(id.to_s), deleted_at: nil}, *a, &b)
  end

  def self.find_one options, *a, &b
    cb = EM::Callback *a, &b
    EM.defer(proc {
      doc = mongo_collection.find_one options
      new doc if doc
    }, proc { |model|
      cb.call model
    })
    cb
  end

  def self.find_all options = {}, *a, &b
    cb = EM::Callback *a, &b

    EM.defer(proc {
      mongo_collection.find options
    }, proc { |docs|
      cb.call docs.map{|doc| new(doc) }
    })

    cb
  end

  def self.insert document, options = {}
    EM.defer do
      mongo_collection.insert document, options
    end
  end

  def self.update selector, document, options = {}
    EM.defer do
      mongo_collection.update selector, document, options
    end
  end

  def self.find_and_modify options, *a, &b
    cb = EM::Callback *a, &b
    EM.defer(proc {
      doc = mongo_collection.find_and_modify options
      new doc if doc
    }, proc { |model|
      cb.call model
    })
    cb
  end

  def initialize doc
    @doc = doc
  end

  def collection
    self.class.mongo_collection
  end

  def update options
    collection.update({_id: id}, options)
  end

  def id
    @doc['_id']
  end
end