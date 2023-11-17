# frozen_string_literal: true

# Define an application-wide content security policy
# For further information see the following documentation
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy

def host_to_url(str)
  "http#{Rails.configuration.x.use_https ? 's' : ''}://#{str.split('/').first}" if str.present?
end

base_host = Rails.configuration.x.web_domain

assets_host   = Rails.configuration.action_controller.asset_host
assets_host ||= host_to_url(base_host)

media_host   = host_to_url(ENV['S3_ALIAS_HOST'])
media_host ||= host_to_url(ENV['S3_CLOUDFRONT_HOST'])
media_host ||= host_to_url(ENV['AZURE_ALIAS_HOST'])
media_host ||= host_to_url(ENV['S3_HOSTNAME']) if ENV['S3_ENABLED'] == 'true'
media_host ||= host_to_url(ENV['IPFS_GATEWAY']) if ENV['IPFS_ENABLED'] == 'true'
media_host ||= assets_host

web3_modal_host   = 'https://api.web3modal.org'
relay_web3_host   = 'wss://relay.walletconnect.com'
wallet_link_host  = 'wss://www.walletlink.org'
wallet_connect_rpc = 'https://rpc.walletconnect.org'
trongrid_host = 'https://api.trongrid.io/'
mainnet_infura_rpc = 'https://mainnet.infura.io'
proof_service_test_host = 'https://proof-service.nextnext.id'
proof_service_host = 'https//proof-service.next.id'

def sso_host
  return unless ENV['ONE_CLICK_SSO_LOGIN'] == 'true'
  return unless ENV['OMNIAUTH_ONLY'] == 'true'
  return unless Devise.omniauth_providers.length == 1

  provider = Devise.omniauth_configs[Devise.omniauth_providers[0]]
  @sso_host ||= begin
    case provider.provider
    when :cas
      provider.cas_url
    when :saml
      provider.options[:idp_sso_target_url]
    when :openid_connect
      provider.options.dig(:client_options, :authorization_endpoint) || OpenIDConnect::Discovery::Provider::Config.discover!(provider.options[:issuer]).authorization_endpoint
    end
  end
end

Rails.application.config.content_security_policy do |p|
  p.base_uri        :none
  p.default_src     :none
  p.frame_ancestors :none
  p.font_src        :self, assets_host
  p.img_src         :self, :https, :data, :blob, assets_host, media_host
  p.style_src       :unsafe_inline, assets_host
  p.media_src       :self, :https, :data, assets_host, media_host
  p.frame_src       :self, :https
  p.manifest_src    :self, assets_host

  if sso_host.present?
    p.form_action     :self, sso_host
  else
    p.form_action     :self
  end

  p.child_src       :self, :blob, assets_host
  p.worker_src      :self, :blob, assets_host

  if Rails.env.development?
    webpacker_public_host = ENV.fetch('WEBPACKER_DEV_SERVER_PUBLIC', Webpacker.config.dev_server[:public])
    webpacker_urls = %w(ws http).map { |protocol| "#{protocol}#{Webpacker.dev_server.https? ? 's' : ''}://#{webpacker_public_host}" }

    p.connect_src :self, web3_modal_host, relay_web3_host, wallet_link_host, wallet_connect_rpc, trongrid_host, mainnet_infura_rpc, proof_service_test_host, proof_service_host, :data, :blob, assets_host, media_host, Rails.configuration.x.streaming_api_base_url, *webpacker_urls
    p.script_src  :self, :unsafe_inline, :unsafe_eval, assets_host, media_host, :blob
  else
    p.connect_src :self, web3_modal_host, relay_web3_host, wallet_link_host, wallet_connect_rpc, trongrid_host, mainnet_infura_rpc, proof_service_test_host, proof_service_host, :data, :blob, assets_host, media_host, Rails.configuration.x.streaming_api_base_url
    p.script_src  :self, :unsafe_inline, :unsafe_eval, assets_host, media_host, "'wasm-unsafe-eval'", :blob
  end
end

# Report CSP violations to a specified URI
# For further information see the following documentation:
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy-Report-Only
# Rails.application.config.content_security_policy_report_only = true

Rails.application.reloader.to_prepare do
  PgHero::HomeController.content_security_policy do |p|
    p.script_src :self, :unsafe_inline, assets_host
    p.style_src  :self, :unsafe_inline, assets_host
  end

  if Rails.env.development?
    LetterOpenerWeb::LettersController.content_security_policy do |p|
      p.child_src       :self
      p.connect_src     :none
      p.frame_ancestors :self
      p.frame_src       :self
      p.script_src      :unsafe_inline
      p.style_src       :unsafe_inline
      p.worker_src      :none
    end

  end
end
