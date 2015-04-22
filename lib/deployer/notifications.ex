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
  @spec send_hipchat(Map) :: :ok | :error
  def send_hipchat(msg) do
    do_send("notifications_hipchat", msg)
  end

  @doc """
  Sends messages to "deploy" queue.
  Returns :ok or :error.
  """
  @spec send_orchestrator(term) :: :ok | :error
  def send_orchestrator(msg) do
    do_send("deploy", msg)
  end

  @doc """
  Wraps do_deploy to allow sending messages to queues with dinamic names.
  Returns :ok or :erro
  """
  @spec send(String.t, term) :: :ok | :error
  def send(queue, msg) do
   do_send(queue, msg)
  end

  @doc false
  @spec do_send(String.t, term) :: :ok | :error
  defp do_send(queue_name, msg) do
    api                = ManagerApi.create!(Configuration.api_creds)
    exchange           = Configuration.current_exchange_id
    queue              = QueueBuilder.build(api, queue_name, exchange)
    connection_options =
      ConnectionOptionsResolver.get_for_broker(api, Configuration.current_broker_id)

    case Notifications.publish(connection_options, queue, msg) do
      :ok -> :ok
      _   -> :error
    end
  end
end
