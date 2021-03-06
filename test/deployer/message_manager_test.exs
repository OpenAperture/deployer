defmodule OpenAperture.Deployer.MessageManagerTests do
  use ExUnit.Case

  alias OpenAperture.Deployer.MessageManager

  alias OpenAperture.OverseerApi.Heartbeat
  
  # ===================================
  # track tests

  test "remove success" do
    :meck.new(Heartbeat, [:passthrough])
    :meck.expect(Heartbeat, :set_workload, fn _ -> :ok end)

    MessageManager.track(%{subscription_handler: %{}, delivery_tag: "delivery_tag"})
    message = MessageManager.remove("delivery_tag")
    assert message != nil
    assert message[:subscription_handler] == %{}
    assert message[:delivery_tag] == "delivery_tag"
  after
    :meck.unload(Heartbeat)
  end  
end