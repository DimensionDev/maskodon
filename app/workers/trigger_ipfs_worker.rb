# frozen_string_literal: true

class TriggerIpfsWorker
  include Sidekiq::Worker

  def perform(event, class_name, id)
    logger.debug("TriggerIpfsWorker perform  ipfs  deal  start")
    object = class_name.constantize.find(id)
    IpfsService.new.call(event, object)
    logger.debug("TriggerIpfsWorker perform  ipfs deal  end")
  rescue ActiveRecord::RecordNotFound
    true
  end
end
