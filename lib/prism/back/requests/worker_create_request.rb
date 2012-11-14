module Prism
  class WorkerCreateRequest < BusyOperationRequest
    include Logging

    process "workers:requests:create", :request_id, :instance_type, :image_id

    def busy_hash
      ["workers:busy", request_id, 'creating', instance_type: instance_type, expires_after: 180]
    end

    def perform_operation
      info "creating new box type:#{instance_type} req:#{request_id}"

      Box.create flavor_id:instance_type, image_id:image_id
    end

    def operation_succeeded box
      info "worker:#{box.instance_id} created"
      redis.store_running_box box
      redis.publish_json "workers:requests:create:#{request_id}", instance_id:box.instance_id, host:box.host
    end

    def operation_failed
      error "failed to create box type:#{instance_type} req:#{request_id}"
    end


  end
end