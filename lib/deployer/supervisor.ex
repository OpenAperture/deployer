defmodule OpenAperture.Deployer.Supervisor do
  @moduledoc "Defines the supervison tree of the application."
  require Logger
  use     Supervisor

  def start_link do
    Logger.info("Starting Deployer.Supervisor...")
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      worker(OpenAperture.Deployer.Dispatcher, [[name: DeployDispatcher]]),
      supervisor(OpenAperture.Deployer.Milestones.DeploySupervisor, [[name: DeploySupervisor]]),
      supervisor(OpenAperture.Deployer.Milestones.MonitorSupervisor, [[name: MonitorSupervisor]])
    ]
    supervise(children, strategy: :one_for_one)
  end
end
