defmodule OpenAperture.Deployer.Dispatcher.Test do
  use   ExUnit.Case
  alias OpenAperture.Deployer.Dispatcher

  test "DeployDispatcher is already started by Supervisor" do
    assert {:error, {:already_started, _}} = Dispatcher.start_link(name: DeployDispatcher)
  end
end
