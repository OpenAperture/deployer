defmodule Notifications.Test do
  use ExUnit.Case

  alias OpenAperture.Deployer.Notifications

  test "send() properly sends the message out" do
    :meck.new(Notifications, [:passthrough])
    :meck.expect(Notifications, :publish, fn(_, _, _) -> :ok end)

    assert Notifications.send("sdkfjh") == :ok
  after
    :meck.unload(Notifications)
  end
end
