defmodule OpenAperture.Deployer.Notifications do
  @moduledoc """
  Wraps sending notification messages to an AMQP broker.
  """

  use OpenAperture.Messaging

  alias OpenAperture.Deployer
  alias Deployer.Configuration
  alias Deployer.Notifications

  alias OpenAperture.ManagerApi

  alias OpenAperture.Messaging
  alias Messaging.AMQP.QueueBuilder
  alias Messaging.ConnectionOptionsResolver

  @doc """
  Sends an actual message to a the `notifications_hipchat` queue.
  Returns :ok if succeffully sent or :error otherwise.
  """
  @spec send(Map) :: :ok | :error
  def send(msg) do
    api                = ManagerApi.create!(Configuration.api_creds)
    exchange           = Configuration.current_exchange_id
    queue              = QueueBuilder.build(api, "noitification_hipchat", exchange)
    connection_options =
      ConnectionOptionsResolver.get_for_broker(api, Configuration.current_broker_id)

    case Notifications.publish(connection_options, queue, msg) do
      :ok -> :ok
      _   -> :error
    end
  end
end
