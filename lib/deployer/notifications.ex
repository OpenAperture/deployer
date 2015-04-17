defmodule OpenAperture.Deployer.Notifications do
  @moduledoc """
  Describes sending notification messages to an AMQP broker.
  """

  use OpenAperture.Messaging
  alias OpenAperture.Deployer.Configuration

  @doc """
  Sends an actual message.
  Returns :ok if succeffully sent or :error otherwise.
  """
  @spec send(Map) :: :ok | :error
  def send(msg) do
    case publish(Configuration.connection_options, "notifications_hipchat", msg) do
      :ok -> :ok
      _   -> :error
    end
  end
end
