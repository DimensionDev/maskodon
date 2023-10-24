# frozen_string_literal: true
require 'uri'
require 'net/http'
require_relative "ipfs/version"
require 'paperclip/storage/ipfs/ipfs'

module Paperclip
  module Storage
    module Ipfs
      class Error < StandardError; end
      # Your code goes here...
    end
  end
end
