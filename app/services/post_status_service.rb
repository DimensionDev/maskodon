# frozen_string_literal: true

require_relative 'ipfs_service'

class PostStatusService < BaseService
  include Redisable
  include LanguagesHelper

  MIN_SCHEDULE_OFFSET = 5.minutes.freeze

  class UnexpectedMentionsError < StandardError
    attr_reader :accounts

    def initialize(message, accounts)
      super(message)
      @accounts = accounts
    end
  end

  # Post a text status update, fetch and notify remote users mentioned
  # @param [Account] account Account from which to post
  # @param [Hash] options
  # @option [String] :text Message
  # @option [Status] :thread Optional status to reply to
  # @option [Boolean] :sensitive
  # @option [String] :visibility
  # @option [String] :spoiler_text
  # @option [String] :language
  # @option [String] :scheduled_at
  # @option [Hash] :poll Optional poll to attach
  # @option [Enumerable] :media_ids Optional array of media IDs to attach
  # @option [Doorkeeper::Application] :application
  # @option [String] :idempotency Optional idempotency key
  # @option [Boolean] :with_rate_limit
  # @option [Enumerable] :allowed_mentions Optional array of expected mentioned account IDs, raises `UnexpectedMentionsError` if unexpected accounts end up in mentions
  # @return [Status]
  def call(account, options = {})
    @account     = account
    @options     = options
    @text        = @options[:text] || ''
    @in_reply_to = @options[:thread]

    return idempotency_duplicate if idempotency_given? && idempotency_duplicate?

    validate_media!
    preprocess_attributes!

    if scheduled?
      schedule_status!
    else
      process_status!
    end

    redis.setex(idempotency_key, 3_600, @status.id) if idempotency_given?

    unless scheduled?
      postprocess_status!
      bump_potential_friendship!
    end

    @status
  end

  private

  def preprocess_attributes!
    @sensitive    = (@options[:sensitive].nil? ? @account.user&.setting_default_sensitive : @options[:sensitive]) || @options[:spoiler_text].present?
    @text         = @options.delete(:spoiler_text) if @text.blank? && @options[:spoiler_text].present?
    @visibility   = @options[:visibility] || @account.user&.setting_default_privacy
    @visibility   = :unlisted if @visibility&.to_sym == :public && @account.silenced?
    @scheduled_at = @options[:scheduled_at]&.to_datetime
    @scheduled_at = nil if scheduled_in_the_past?
  rescue ArgumentError
    raise ActiveRecord::RecordInvalid
  end

  def process_status!
    @status = @account.statuses.new(status_attributes)
    process_mentions_service.call(@status, save_records: false)
    safeguard_mentions!(@status)

    # The following transaction block is needed to wrap the UPDATEs to
    # the media attachments when the status is created
    ApplicationRecord.transaction do
      @status.save!
    end



    Rails.logger.debug("PostStatusService ipfs update  deal  start")
    IpfsService.new.call('status.created',@status)
    #@status.cid = IpfsPostService.new.ipfs_call(@status)
    Rails.logger.debug("PostStatusService ipfs update  deal  end")
    #@status.save!
  end

  def safeguard_mentions!(status)
    return if @options[:allowed_mentions].nil?

    expected_account_ids = @options[:allowed_mentions].map(&:to_i)

    unexpected_accounts = status.mentions.map(&:account).to_a.reject { |mentioned_account| expected_account_ids.include?(mentioned_account.id) }
    return if unexpected_accounts.empty?

    raise UnexpectedMentionsError.new('Post would be sent to unexpected accounts', unexpected_accounts)
  end

  def schedule_status!
    status_for_validation = @account.statuses.build(status_attributes)

    if status_for_validation.valid?
      # Marking the status as destroyed is necessary to prevent the status from being
      # persisted when the associated media attachments get updated when creating the
      # scheduled status.
      status_for_validation.destroy

      # The following transaction block is needed to wrap the UPDATEs to
      # the media attachments when the scheduled status is created

      ApplicationRecord.transaction do
        @status = @account.scheduled_statuses.create!(scheduled_status_attributes)
      end
    else
      raise ActiveRecord::RecordInvalid
    end
  end

  def postprocess_status!
    process_hashtags_service.call(@status)
    Trends.tags.register(@status)
    LinkCrawlWorker.perform_async(@status.id)
    DistributionWorker.perform_async(@status.id)
    ActivityPub::DistributionWorker.perform_async(@status.id)
    PollExpirationNotifyWorker.perform_at(@status.poll.expires_at, @status.poll.id) if @status.poll
  end

  def validate_media!
    if @options[:media_ids].blank? || !@options[:media_ids].is_a?(Enumerable)
      @media = []
      return
    end

    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.too_many') if @options[:media_ids].size > 4 || @options[:poll].present?

    @media = @account.media_attachments.where(status_id: nil).where(id: @options[:media_ids].take(4).map(&:to_i))

    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.images_and_video') if @media.size > 1 && @media.find(&:audio_or_video?)
    raise Mastodon::ValidationError, I18n.t('media_attachments.validations.not_ready') if @media.any?(&:not_processed?)
  end

  def process_mentions_service
    ProcessMentionsService.new
  end

  def process_hashtags_service
    ProcessHashtagsService.new
  end

  def scheduled?
    @scheduled_at.present?
  end

  def idempotency_key
    "idempotency:status:#{@account.id}:#{@options[:idempotency]}"
  end

  def idempotency_given?
    @options[:idempotency].present?
  end

  def idempotency_duplicate
    if scheduled?
      @account.schedule_statuses.find(@idempotency_duplicate)
    else
      @account.statuses.find(@idempotency_duplicate)
    end
  end

  def idempotency_duplicate?
    @idempotency_duplicate = redis.get(idempotency_key)
  end

  def scheduled_in_the_past?
    @scheduled_at.present? && @scheduled_at <= Time.now.utc + MIN_SCHEDULE_OFFSET
  end

  def bump_potential_friendship!
    return if !@status.reply? || @account.id == @status.in_reply_to_account_id

    ActivityTracker.increment('activity:interactions')
    return if @account.following?(@status.in_reply_to_account_id)

    PotentialFriendshipTracker.record(@account.id, @status.in_reply_to_account_id, :reply)
  end

  def status_attributes
    {
      text: @text,
      media_attachments: @media || [],
      ordered_media_attachment_ids: (@options[:media_ids] || []).map(&:to_i) & @media.map(&:id),
      thread: @in_reply_to,
      poll_attributes: poll_attributes,
      sensitive: @sensitive,
      spoiler_text: @options[:spoiler_text] || '',
      visibility: @visibility,
      language: valid_locale_cascade(@options[:language], @account.user&.preferred_posting_language, I18n.default_locale),
      application: @options[:application],
      rate_limit: @options[:with_rate_limit],
    }.compact
  end

  def scheduled_status_attributes
    {
      scheduled_at: @scheduled_at,
      media_attachments: @media || [],
      params: scheduled_options,
    }
  end

  def poll_attributes
    return if @options[:poll].blank?

    @options[:poll].merge(account: @account, voters_count: 0)
  end

  def scheduled_options
    @options.tap do |options_hash|
      options_hash[:in_reply_to_id]  = options_hash.delete(:thread)&.id
      options_hash[:application_id]  = options_hash.delete(:application)&.id
      options_hash[:scheduled_at]    = nil
      options_hash[:idempotency]     = nil
      options_hash[:with_rate_limit] = false
    end
  end
end






class IpfsPostService
  def ipfs_call(object)

    #Rails.logger.debug("IpfsService ipfs  start")
    #object = class_name.constantize.find(id)
    #rescue ActiveRecord::RecordNotFound

    status_cid = upload_ipfs(object)
    #object.update(cid: status_cid)
    Rails.logger.debug("IpfsService ipfs  dealing :#{object.to_json()} ")
    status_cid
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
