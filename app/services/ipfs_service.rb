# frozen_string_literal: true
require 'net/http'
require 'uri'
require 'json'

class IpfsService < BaseService
  include Sidekiq::Worker
  def call(event, object)

   # if event == 'status.update' && !updated_fields(object)
   #   return false
   # end

    logger.debug("IpfsService ipfs  start")
    logger.debug("IpfsService ipfs  deal :#{object.to_json()} ")
    status_cid = upload_ipfs(object)
    #object.update(cid: status_cid)
    object.update_column(:cid, status_cid)
    logger.debug("IpfsService ipfs  dealing :#{object.to_json()} ")
  end

  private

  def updated_fields(object)
    #fields = self.changed
    fields = object.previous_changes
    logger.debug("updated_fields  ipfs cid  deal #{fields}")
    logger.debug("updated_fields  ipfs cid  deal #{fields.include?('cid')}")
    bl_cid = false
    if fields.size()>0 && !fields.include?('cid')
      bl_cid = true
    end
    logger.debug("updated_fields  ipfs cid  deal end #{bl_cid}")
    return bl_cid
  end

  def upload_ipfs(object)
      Rails.logger.debug("upload_ipfs ipfs deal start")
      endpoint=ENV['IPFS_PIN_ENDPOINT']
      str_jwt=ENV['PINATA_KEY']
      file_name = "stastus_#{object.id}.json"
      str_json = object.to_json()
      uri = URI.parse(endpoint + "pinFileToIPFS")
      boundary = "AaB03x"
      post_body = []
      # Add the file Data
      post_body << "--#{boundary}\r\n"
      post_body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{file_name}\"\r\n"
      post_body << "Content-Type: application/octet-stream\r\n\r\n"
      post_body << str_json
      post_body << "\r\n\r\n--#{boundary}--\r\n"

      Rails.logger.debug("upload_ipfs ipfs deal post request  body: #{post_body}")


      # Create the HTTP objects
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri.request_uri)
      request['content-type'] = "multipart/form-data; boundary=#{boundary}"
      request['Authorization'] ="Bearer #{str_jwt}"
      request.body = post_body.join

      # Send the request
      response = http.request(request)
      cid = ""
      if response.code
       body = JSON.parse(response.body)
        if body.has_key?('IpfsHash')
          cid = body['IpfsHash']
        end
      end

      Rails.logger.debug("upload_ipfs ipfs deal post response.body: #{body}")
      Rails.logger.debug("upload_ipfs ipfs deal end: #{response.code}")
    return cid
  end
end
