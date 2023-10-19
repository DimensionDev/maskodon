# frozen_string_literal: true

class IpfsService < BaseService
  include Sidekiq::Worker
  def call(event, object)

    logger.debug("IpfsService ipfs  start")
    logger.debug("IpfsService ipfs  deal :#{object.to_json()} ")


     #logger.debug("api/v2 MediaController media iput parm:  #{media_attachment_params}")
    #@media_attachment = current_account.media_attachments.create!({ delay_processing: true }.merge(media_attachment_params))
   #logger.debug("api/v2 MediaController media ouput data  #{@media_attachment.to_json()}")
    file_url = "https://dddd.com/4566"

   if file_url.present?
     @url_arr = file_url.split("/").map(&:strip)
     @cid = @url_arr[@url_arr.length-1]
     logger.debug("IpfsService ipfs  deal  remote_url arr cid:  #{@cid}")
   end

   #if @media_attachment.file.url.present?
   #  @url_arr = @media_attachment.file.url.split("/").map(&:strip)
   #  logger.debug("api/v2 MediaController media remote_url arr  #{@arr[@arr.length-1]}")
   #end
   
   object.update(cid: @cid)
   logger.debug("IpfsService ipfs  dealing :#{object.to_json()} ")

   # @event  = Webhooks::EventPresenter.new(event, object)
   # @body   = serialize_event

   # webhooks_for_event.each do |webhook_id|
   #   Webhooks::DeliveryWorker.perform_async(webhook_id, @body)
   # end
  end

  #private

  #def webhooks_for_event
  #  Webhook.enabled.where('? = ANY(events)', @event.type).pluck(:id)
  #end

  #def serialize_event
  #  Oj.dump(ActiveModelSerializers::SerializableResource.new(@event, serializer: REST::Admin::WebhookEventSerializer, scope: nil, scope_name: :current_user).as_json)
  #end
end
