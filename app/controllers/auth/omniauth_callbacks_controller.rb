# frozen_string_literal: true

class Auth::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  skip_before_action :check_self_destruct!
  skip_before_action :verify_authenticity_token

  def self.provides_callback_for(provider)
    define_method provider do
      @provider = provider
      # | =identity= | =current_user= | Action                          |
      # |------------+-----------------+---------------------------------|
      # | Exist      | Exist           | Report error                     |
      # | Exist      | Absence         | Login                           |
      # | Absence    | Exist           | Bind                            |
      # | Absence    | Absence         | Register or login (depend on ENV) |
      auth = request.env['omniauth.auth']
      if ENV['OAUTH_DISABLE_AUTO_REGISTER'] == 'true'
        uid = auth.uid
        uid = uid[0][:uid] || uid[0][:user] if uid.is_a? Hashie::Array
        identity = Identity.find_or_create_by(provider: provider, uid: uid)
        @user = identity&.user
        if @user.blank? # Identity is fresh: just created, no user binded yet
          if current_user.present?
            @user = current_user
            identity.user = @user
            identity.save!
          else
            identity.destroy!
            flash[:alert] = I18n.t('settings.identities.cannot_login_without_register') if is_navigational_format?
            return redirect_to new_user_session_url
          end
        end
      else
        @user = User.find_for_omniauth(auth, current_user)
      end

      if @user.persisted?
        record_login_activity
        sign_in_and_redirect @user, event: :authentication
        set_flash_message(:notice, :success, kind: label_for_provider) if is_navigational_format?
      else
        session["devise.#{provider}_data"] = auth
        redirect_to new_user_registration_url
      end
    rescue ActiveRecord::RecordInvalid
      flash[:alert] = I18n.t('devise.failure.omniauth_user_creation_failure') if is_navigational_format?
      redirect_to new_user_session_url
    end
  end

  Devise.omniauth_configs.each_key do |provider|
    provides_callback_for provider
  end

  def after_sign_in_path_for(resource)
    if resource.email_present?
      stored_location_for(resource) || root_path
    else
      auth_setup_path(missing_email: '1')
    end
  end

  private

  def record_login_activity
    LoginActivity.create(
      user: @user,
      success: true,
      authentication_method: :omniauth,
      provider: @provider,
      ip: request.remote_ip,
      user_agent: request.user_agent
    )
  end

  def label_for_provider
    provider_display_name || configured_provider_name
  end

  def provider_display_name
    Devise.omniauth_configs[@provider]&.strategy&.display_name.presence
  end

  def configured_provider_name
    I18n.t("auth.providers.#{@provider}", default: @provider.to_s.chomp('_oauth2').capitalize)
  end
end
