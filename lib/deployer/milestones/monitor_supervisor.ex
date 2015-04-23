defmodule OpenAperture.Deployer.Milestones.MonitorSupervisor do
  require Logger
  use     Supervisor

  def start_link(opts \\ []) do
    Logger.debug("Starting #{__MODULE__}...")
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def monitor(deploy_request) do
    Supervisor.start_child(MonitorSupervisor, [deploy_request])
  end

  def init(:ok) do
    children = [
      worker(OpenAperture.Deployer.Milestones.Monitor, [])
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end
