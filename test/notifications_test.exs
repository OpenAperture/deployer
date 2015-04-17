defmodule Notifications.Test do
  use ExUnit.Case

  alias OpenAperture.Deployer.Notifications

  test "send() properly sends the message out" do
    assert Notifications.send("sdkfjh") == :ok
  end
end
