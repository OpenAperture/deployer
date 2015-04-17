defmodule OpenAperture.Deployer.Dispatcher.Test do
  use   ExUnit.Case
  alias OpenAperture.Deployer.Dispatcher

  @dispatcher DeployDispatcher

  test "DeployDispatcher is already started by Supervisor" do
    assert {:error, {:already_started, _}} = Dispatcher.start_link(name: @dispatcher)
  end
end
