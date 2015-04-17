defmodule OpenAperture.Deployer.Task.Supervisor do
  require Logger
  use     Supervisor
  alias   OpenAperture.Deployer

  def start_link(opts \\ []) do
    Logger.debug("Starting #{__MODULE__}...")
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  def execute_task(supervisor, details) do
    Supervisor.start_child(supervisor, [details])
  end

  def init(:ok) do
    children = [worker(Deployer.Task, [])]
    supervise(children, strategy: :simple_one_for_one)
  end
end
