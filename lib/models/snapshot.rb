module Models
  class Snapshot < Model
    extend Prism::Mongo

    collection :snapshots

    %w(
       created_at
       url
    ).each do |field|
      define_method(:"#{field}") do
        @doc[field]
      end
    end
  end
end