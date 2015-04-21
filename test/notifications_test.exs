defmodule Notifications.Test do
  use ExUnit.Case

  alias OpenAperture.Deployer.Notifications

  alias OpenAperture.ManagerApi

  alias OpenAperture.Messaging
  alias Messaging.AMQP.QueueBuilder
  alias Messaging.ConnectionOptionsResolver

  test "send() properly sends the message out" do
    :meck.new(ManagerApi)
    :meck.expect(ManagerApi, :create!, fn(_) -> %{} end)

    :meck.new(QueueBuilder)
    :meck.expect(QueueBuilder, :build, fn(_, _, _) -> %{} end)

    :meck.new(ConnectionOptionsResolver)
    :meck.expect(ConnectionOptionsResolver, :get_for_broker, fn(_, _) -> %{} end)

    :meck.new(Notifications, [:passthrough])
    :meck.expect(Notifications, :publish, fn(_, _, _) -> :ok end)

    assert Notifications.send_hipchat("test") == :ok
  after
    :meck.unload(Notifications)
  end
end
