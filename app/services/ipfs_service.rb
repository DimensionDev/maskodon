# frozen_string_literal: true
require 'net/http'
require 'uri'
require 'json'

class IpfsService < BaseService
  include Sidekiq::Worker
  def call(event, object)

    logger.debug("IpfsService ipfs  start")
    logger.debug("IpfsService ipfs  deal :#{object.to_json()} ")
    status_cid = upload_ipfs(object)
    object.update(cid: status_cid)
    logger.debug("IpfsService ipfs  dealing :#{object.to_json()} ")
  end

  private

  def upload_ipfs(object)
      logger.debug("upload_ipfs ipfs deal start")
      str_jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySW5mb3JtYXRpb24iOnsiaWQiOiJlODYxMThhYi0zZjgxLTQ4MDMtYmE1Yi1iZTQzZGY0ODI3ZjIiLCJlbWFpbCI6ImRldmVsb3BtZW50QG1hc2suaW8iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwicGluX3BvbGljeSI6eyJyZWdpb25zIjpbeyJpZCI6IkZSQTEiLCJkZXNpcmVkUmVwbGljYXRpb25Db3VudCI6MX0seyJpZCI6Ik5ZQzEiLCJkZXNpcmVkUmVwbGljYXRpb25Db3VudCI6MX1dLCJ2ZXJzaW9uIjoxfSwibWZhX2VuYWJsZWQiOmZhbHNlLCJzdGF0dXMiOiJBQ1RJVkUifSwiYXV0aGVudGljYXRpb25UeXBlIjoic2NvcGVkS2V5Iiwic2NvcGVkS2V5S2V5IjoiMDFlYjg2Y2EwYzkzNjZlYjYyNWYiLCJzY29wZWRLZXlTZWNyZXQiOiI2NmE5NmE1MDY2NmQzZWVhODZjMTljNDdjYTEyOGJjOGIyMWU2MjYxN2Q1ZGEwZGRjOTFiMWU4ZjU3ZDQ0MmNkIiwiaWF0IjoxNjk3NTEyNjMwfQ.-eUFGsPG0zOZkOcsCxh87uAQ8NBhUf9jG6XsPR3XMhg"
      file_name = "stastus_#{object.id}.json"
      str_json = object.to_json()
      endpoint = "https://api.pinata.cloud/pinning/"
      uri = URI.parse(endpoint + "pinFileToIPFS")
      boundary = "AaB03x"
      post_body = []
      # Add the file Data
      post_body << "--#{boundary}\r\n"
      post_body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{file_name}\"\r\n"
      post_body << "Content-Type: application/octet-stream\r\n\r\n"
      post_body << str_json
      post_body << "\r\n\r\n--#{boundary}--\r\n"
       
      logger.debug("upload_ipfs ipfs deal post request  body: #{post_body}")


      # Create the HTTP objects
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri.request_uri)
      request['content-type'] = "multipart/form-data; boundary=#{boundary}"
      request['Authorization'] ="Bearer #{str_jwt}"
      request.body = post_body.join

      # Send the request
      response = http.request(request)

      logger.debug("upload_ipfs ipfs deal post response.body: #{JSON.parse(response.body)}")

      logger.debug("upload_ipfs ipfs deal end: #{response.to_json()}")
      cid = JSON.parse(response.body)['IpfsHash']
      #return response.body['IpfsHash']
      return cid
  end
end
