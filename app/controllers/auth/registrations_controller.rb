# frozen_string_literal: true

class Auth::RegistrationsController < Devise::RegistrationsController
  include RegistrationSpamConcern
  #include RelyingParty
 # include Devise::Passkeys::Controllers::RegistrationsControllerConcern



  layout :determine_layout

  before_action :set_invite, only: [:new, :create]
  before_action :check_enabled_registrations, only: [:new, :create]
  before_action :configure_sign_up_params, only: [:create]
  before_action :set_sessions, only: [:edit, :update]
  before_action :set_strikes, only: [:edit, :update]
  before_action :set_instance_presenter, only: [:new, :create, :update]
  before_action :set_body_classes, only: [:new, :create, :edit, :update]
  before_action :require_not_suspended!, only: [:update]
  before_action :set_cache_headers, only: [:edit, :update]
  before_action :set_rules, only: :new
  before_action :require_rules_acceptance!, only: :new
  before_action :set_registration_form_time, only: :new

  skip_before_action :require_functional!, only: [:edit, :update]

  Password='asdf123456.'
  def new
    super(&:build_invite_request)
  end

  def new_pksignup
    logger.info("Params: #{params.inspect}")
    email=params[:account][:username]+"@xxxx.com"
    user = User.new(email: email,password: Password,settings: params[:account][:username])
    user.account=Account.new(username: params[:account][:username])
    user.credentials=Credential.new(label: params[:passkey_label])

    create_options = WebAuthn::Credential.options_for_create(
      user: {
        name: params[:account][:username],
        id: user.webauthn_id
      },
      authenticator_selection: { user_verification: 'required' },
    )
    save_registration('challenge' => create_options.challenge, 'user_attributes' => user.to_json)
    if user.valid?
      hash = {
        original_url: "/auth/sign_in",
        callback_url: new_auth_registration_callback_path,
        create_options: create_options
      }
      respond_to do |format|
        format.json { render json: hash }
      end
    else
      respond_to do |format|
        format.json { render json: { errors: user.errors.full_messages }, status: 200 }
      end
    end
  end


  def callback
    logger.info("params: #{params}")
    logger.info("saved_user_attribuets: #{saved_user_attribuets}")

    webauthn_credential = WebAuthn::Credential.from_create(params)


    user_hash = JSON.parse(saved_user_attribuets)
    user_p = OpenStruct.new(user_hash)

    account=Account.create!(username:user_p[:settings])

    user = User.create!(email: user_p[:email],password:Password,account_id:account.id,public_key: user_p[:public_key])
    begin
      webauthn_credential.verify(saved_challenge, user_verification: true)
      logger.debug { 'verify worked' }
      credential = user.credentials.build(
        external_id: external_id(webauthn_credential),
        public_key: webauthn_credential.public_key,
        sign_count: webauthn_credential.sign_count
      )

      if credential.save
        logger.debug { 'save worked' }
        sign_in(user)
        render json: { status: 'ok' }, status: :ok
      else
        logger.debug { 'save failed' }
        render json: 'Could not register your Security Key', status: 200
      end
    rescue WebAuthn::Error => e
      logger.debug { "verify raised error: #{e}" }
      render json: "Verification failed: #{e.message}", status: 200
    rescue Exception => e
      logger.debug { "Unexpected exception: #{e}" }
      render json: "Verification failed: #{e.message}", status: 200
    ensure
      logger.debug { 'delete session' }
      session.delete(:current_registration)
    end
  end
  def external_id(webauthn_credential)
    Base64.strict_encode64(webauthn_credential.raw_id)
  end
  def update
    super do |resource|
      resource.clear_other_sessions(current_session.session_id) if resource.saved_change_to_encrypted_password?
    end
  end

  def destroy
    not_found
  end

  protected

  def update_resource(resource, params)
    params[:password] = nil if Devise.pam_authentication && resource.encrypted_password.blank?

    super
  end

  def build_resource(hash = nil)
    logger.debug("Auth::RegistrationsController::build_resource")
    super(hash)

    resource.locale                 = I18n.locale
    resource.invite_code            = @invite&.code if resource.invite_code.blank?
    resource.registration_form_time = session[:registration_form_time]
    resource.sign_up_ip             = request.remote_ip

    resource.build_account if resource.account.nil?
  end

  def configure_sign_up_params
    logger.debug("Auth::RegistrationsController::configure_sign_up_params")
    # devise_parameter_sanitizer.permit(:sign_up) do |user_params|
    #   user_params.permit({ account_attributes: [:username, :display_name], invite_request_attributes: [:text] }, :email, :password, :password_confirmation, :invite_code, :agreement, :website, :confirm_password)
    # end
    devise_parameter_sanitizer.permit(:sign_up) do |user_params|
        user_params.permit({ account_attributes: [:username, :display_name], invite_request_attributes: [:text] }, :email, :password, :invite_code, :website)
    end
  end

  def after_sign_up_path_for(_resource)
    auth_setup_path
  end

  def after_sign_in_path_for(_resource)
    set_invite

    if @invite&.autofollow?
      short_account_path(@invite.user.account)
    else
      super
    end
  end

  def after_inactive_sign_up_path_for(_resource)
    new_user_session_path
  end

  def after_update_path_for(_resource)
    edit_user_registration_path
  end

  def check_enabled_registrations
    redirect_to root_path if single_user_mode? || omniauth_only? || !allowed_registrations? || ip_blocked?
  end

  def allowed_registrations?
    Setting.registrations_mode != 'none' || @invite&.valid_for_use?
  end

  def omniauth_only?
    ENV['OMNIAUTH_ONLY'] == 'true'
  end

  def ip_blocked?
    IpBlock.where(severity: :sign_up_block).where('ip >>= ?', request.remote_ip.to_s).exists?
  end

  def invite_code
    if params[:user]
      params[:user][:invite_code]
    else
      params[:invite_code]
    end
  end

  private

  def set_instance_presenter
    @instance_presenter = InstancePresenter.new
  end

  def set_body_classes
    @body_classes = %w(edit update).include?(action_name) ? 'admin' : 'lighter'
  end

  def set_invite
    @invite = begin
      invite = Invite.find_by(code: invite_code) if invite_code.present?
      invite if invite&.valid_for_use?
    end
  end

  def determine_layout
    %w(edit update).include?(action_name) ? 'admin' : 'auth'
  end

  def set_sessions
    @sessions = current_user.session_activations.order(updated_at: :desc)
  end

  def set_strikes
    @strikes = current_account.strikes.recent.latest
  end

  def require_not_suspended!
    forbidden if current_account.suspended?
  end

  def set_rules
    @rules = Rule.ordered
  end

  def require_rules_acceptance!
    logger.debug("Auth::RegistrationsController::require_rules_acceptance!::1")
    return if @rules.empty? || (session[:accept_token].present? && params[:accept] == session[:accept_token])

    @accept_token = session[:accept_token] = SecureRandom.hex
    @invite_code  = invite_code

    logger.debug("Auth::RegistrationsController::require_rules_acceptance!::2")
    set_locale { render :rules }
  end

  def set_cache_headers
    response.cache_control.replace(private: true, no_store: true)
  end

  def username_param
    registration_params[:username]
  end

  def registration_params
    params.require(:registration).permit(:username)
  end

  def saved_registration
    session['current_registration']
  end

  def save_registration(v)
    session['current_registration'] = v
  end

  def saved_user_attribuets
    saved_registration['user_attributes']
  end

  def saved_username
    saved_user_attribuets['username']
  end

  def saved_challenge
    saved_registration['challenge']
  end

end
