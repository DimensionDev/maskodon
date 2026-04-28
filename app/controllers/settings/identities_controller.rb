# frozen_string_literal: true

class Settings::IdentitiesController < Settings::BaseController
  layout 'admin'
  before_action :authenticate_user!
  before_action :set_identity, only: [:destroy]

  content_security_policy do |p|
    p.form_action(false)
  end

  def index
    @identities = current_user.identities
    @all_providers = {}
    Devise.omniauth_configs.each_key do |platform|
      @all_providers[platform] = @identities.find { |i| i.provider == platform.to_s }
    end
  end

  def destroy
    if @identity&.destroy
      redirect_to({ action: :index }, success: t('settings.identities.oauth_binding_removed'))
    else
      redirect_to({ action: :index }, alert: t('settings.identities.oauth_binding_remove_failed'))
    end
  end

  private

  def set_identity
    @identity = current_user.identities.find(params[:id])
  end
end
