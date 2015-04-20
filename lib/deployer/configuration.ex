defmodule OpenAperture.Deployer.Configuration do
  @moduledoc "Retrieves configuration from either ENV variables or config.exs."

  alias OpenAperture.Messaging
  alias Messaging.Queue
  alias Messaging.AMQP

  @doc """
  Returns ID of the current Exchange.
  """
  @spec current_exchange_id :: String.t
  def current_exchange_id do
    config_value("EXCHANGE_ID", :notifications, :exchange_id)
  end

  def current_broker_id do
    config_value("BROKER_ID", :notifications, :broker_id)
  end

  def api_creds do
    %{
      manager_url:         config_value("MANAGER_URL",         :openaperture_manager_api, :manager_url),
      oauth_login_url:     config_value("OAUTH_LOGIN_URL",     :openaperture_manager_api, :oauth_login_url),
      oauth_client_id:     config_value("OAUTH_CLIENT_ID",     :openaperture_manager_api, :oauth_client_ud),
      oauth_client_secret: config_value("OAUTH_CLIENT_SECRET", :openaperture_manager_api, :oauth_client_secret)
    }
  end

  defp config_value(env_var, config, name) do
    case System.get_env(env_var) || Application.get_env(config, name) do
      nil ->
        raise "Unable to retrieve a crucial config parameter: #{name}"
      value -> value
    end
  end
end
