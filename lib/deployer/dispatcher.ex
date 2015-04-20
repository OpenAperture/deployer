defmodule OpenAperture.Deployer.Dispatcher do
  @moduledoc """
  Receives AMQP messages and spawns individual deployment tasks, adding them
  under a supervisor dynamically.
  """

  require Logger

  use   GenServer
  use   OpenAperture.Messaging
  use   Timex

  alias OpenAperture.Deployer
  alias Deployer.Configuration
  alias Deployer.Task

  alias OpenAperture.ManagerApi

  alias OpenAperture.Messaging
  alias Messaging.AMQP.QueueBuilder
  alias Messaging.ConnectionOptionsResolver

  import Supervisor.Spec
  import OpenAperture.Messaging.AMQP.SubscriptionHandler, only: [acknowledge: 2]

  @doc """
  Starts the Dispatcher server.
  Returns `{:ok, pid}` or `{:error, reason}` or one of a bunch of regular
  GenServer error responses. See GenServer docs for more details.
  """
  @spec start_link(Dict) :: {:ok, pid} | {:error, String.t}
  def start_link(opts \\ [name: __MODULE__]) do
    Logger.debug("Starting Dispatcher...")
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Subscribes Dispatcher for AMQP "deploy" queue.
  Returns `{:ok, %{}}` or throws an exception if subscription was unsuccessful.
  """
  def init(:ok) do
    subscribe_for_queue("deploy", &spawn_deployment_task/3)
    {:ok, %{}}
  end

  @doc """
  Spawns a new supervised deployment task.
  Returns `:ok` or fails with an exception.
  """
  def spawn_deployment_task(details, _meta, async_info) do
    %{subscription_handler: subscription_handler,
      delivery_tag:         delivery_tag} = async_info

    handler = %{subscription_handler: async_info.subscription_handler}
    details = details |> Map.merge(handler)

    Task.Supervisor.execute_task(TaskSupervisor, details)
  end

  @doc false
  @spec subscribe_for_queue(String.t, Fun) :: :ok | {:error, String.t}
  defp subscribe_for_queue(name, handler) do
    if Mix.env != :test do
      api      = ManagerApi.create!(Configuration.api_creds)
      exchange = Configuration.current_exchange_id
      broker   = Configuration.current_broker_id
      queue    = QueueBuilder.build(api, name, exchange)
      options  = ConnectionOptionsResolver.get_for_broker(api, broker)
      subscribe(options, queue, handler)
    else
      :ok
    end
  end
end
