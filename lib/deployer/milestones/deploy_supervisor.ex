defmodule OpenAperture.Deployer.Milestones.DeploySupervisor do
  require Logger
  use     Supervisor

  def start_link(opts \\ []) do
    Logger.debug("Starting #{__MODULE__}...")
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def deploy(deploy_request) do
    Supervisor.start_child(DeploySupervisor, [deploy_request])
  end

  def init(:ok) do
    children = [
      worker(OpenAperture.Deployer.Milestones.Deploy, [])
    ]
    supervise(children, strategy: :simple_one_for_one)
  end
end
