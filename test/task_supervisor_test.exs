defmodule OpenAperture.Deployer.Task.Supervisor.Test do
  use   ExUnit.Case
  alias OpenAperture.Deployer.Task.Supervisor

  @supervisor TaskSupervisor

  test "TaskSupervisor is already started by its SV" do
    assert {:error, {:already_started, _}} = Supervisor.start_link(name: @supervisor)
  end
end
