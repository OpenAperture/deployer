defmodule OpenAperture.Deployer.Dispatcher do
  @moduledoc """
  Receives AMQP messages and spawns individual deployment tasks, adding them
  under a supervisor dynamically.
  """

  require Logger

  @connection_options nil

  use   GenServer
  use   OpenAperture.Messaging
  use   Timex 

  alias OpenAperture.Deployer.Configuration

  alias OpenAperture.ManagerApi

  alias OpenAperture.Messaging.AMQP.QueueBuilder
  alias OpenAperture.Messaging.ConnectionOptionsResolver

  alias OpenAperture.Deployer.Request, as: DeployRequest
  alias OpenAperture.Deployer.Milestones.Deploy
  alias OpenAperture.Deployer.Milestones.DeployEcs
  alias OpenAperture.Deployer.MessageManager

  @doc """
  Starts the Dispatcher server.
  Returns `{:ok, pid}` or `{:error, reason}` or one of a bunch of regular
  GenServer error responses. See GenServer docs for more details.
  """
  @spec start_link(Dict.t) :: {:ok, pid} | {:error, String.t}
  def start_link(opts \\ [name: __MODULE__]) do
    Logger.debug("Starting Dispatcher...")
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Subscribes Dispatcher for AMQP "deploy" queue.
  Returns `{:ok, %{}}` or throws an exception if subscription was unsuccessful.
  """
  def init(:ok) do
    case subscribe_for_queue(Configuration.get_current_queue_name, &spawn_deployment_task/3) do
      {:ok, _} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Spawns a new supervised deployment task.
  Returns `:ok` or fails with an exception.
  """
  def spawn_deployment_task(payload, _meta, async_info) do
    MessageManager.track(async_info)
    deploy_request = DeployRequest.from_payload(payload, async_info)
    cond do 
      deploy_request.workflow.current_step == "deploy" || deploy_request.workflow.current_step == :deploy -> Deploy.start_link(deploy_request)
      deploy_request.workflow.current_step == "deploy_oa" || deploy_request.workflow.current_step == :deploy_oa -> Deploy.start_link(deploy_request)
      deploy_request.workflow.current_step == "deploy_ecs" || deploy_request.workflow.current_step == :deploy_ecs -> DeployEcs.start_link(deploy_request)
      true -> DeployRequest.step_failed(deploy_request, "An unknown milestone was passed into the Deployer:  #{inspect deploy_request.workflow.current_step}", "")
    end
  end

  @doc false
  @spec subscribe_for_queue(String.t, fun) :: :ok | {:error, String.t}
  defp subscribe_for_queue(name, handler) do
    if Mix.env == :test do
      {:ok, nil}
    else
      exchange = Configuration.get_current_exchange_id
      broker   = Configuration.get_current_broker_id
      queue    = QueueBuilder.build(ManagerApi.get_api, name, exchange)
      options  = ConnectionOptionsResolver.get_for_broker(ManagerApi.get_api, broker)
      subscribe(options, queue, handler)
    end
  end
end
