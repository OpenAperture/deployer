defmodule OpenAperture.Deployer.Supervisor do
  @moduledoc "Defines the supervison tree of the application."
  require Logger
  use     Supervisor
  alias   OpenAperture.Deployer

  def start_link do
    Logger.info("Starting Deployer.Supervisor...")
    Supervisor.start_link(__MODULE__, :ok)
  end

  @dispatcher DeployDispatcher
  @task_sup   TaskSupervisor

  def init(:ok) do
    children = [
      worker(Deployer.Dispatcher, [[name: @dispatcher]]),
      supervisor(Deployer.Task.Supervisor, [[name: @task_sup]])
    ]
    supervise(children, strategy: :one_for_one)
  end
end
