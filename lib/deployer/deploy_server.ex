defmodule OpenAperture.Deployer.DeployServer do
  @moduledoc "Handles Fleet deployments for OpenAperture"
  require    Logger
  use        GenServer

  alias OpenAperture.Router
  alias OpenAperture.Deployer
  alias Deployer.Repo
  alias Deployer.EtcdCluster
  alias Deployer.SystemdUnit
  alias OpenAperture.Messaging
  # alias OpenApertureBuildServer.DB.Models.ProductCluster

  @doc """
  Starts DeployerServer process.

  Returns `{:ok, pid}` or `{:error, reason}` or another standard GenServer
  msg. See its docs for details.
  """
  @spec start_link :: {:ok, pid} | {:error, String.t}
  def start_link do
    Logger.info("Starting #{__MODULE__}")
    GenServer.start_link(__MODULE__, nil)
  end

  @doc  """
  Deploys the Dockerized app to a CoreOS cluster.
  Returns `:ok` or `{:error, reason}`
  """
  @spec deploy(Map) :: :ok | {:error, String.t}
  def deploy(%{deployment_repo: deployment_repo} = options) do
    Logger.info("Beginning Fleet re-deployment...")

    case Repo.download(deployment_repo) do
      # :ok -> redeploy(options)
      :ok -> do_deploy(options)
        # GenServer.call(pid, {:redeploy, options} )
        # handle_call({:redeploy, options}, nil)
        # Workflow.next_step(
        #   xxx, %{
        #     deployment_repo: deployment_repo,
        #     etcd_token: Repo.get_etcd_token(deployment_repo)
        #   }
        # )
      {:error, reason} -> :error
        # TODO replace this with something?
        # Workflow.step_failed(_workflow, reason)
    end
  end

  @doc """
  Implements the deploy request callback.
  Returns {:reply, state}
  """
  # @spec handle_call(pid, term) :: :ok
  # def handle_call({:deploy, options}, state) do
  #   deploy(options)
  #   {:reply, state}
  # end

  @doc """
  Redeploys the Dockerized app to a OpenAperture cluster.
  Returns :ok or {:error, reason}
  """
  @spec redeploy(Map) :: :ok | {:error, String.t}
  def redeploy(options) do
    Logger.info ("Beginning Fleet re-deployment...")
    do_deploy(options)
  end

  @doc """
  Sends the redeploy request to the server.
  Returns {:noreply, new_state}
  """
  @spec handle_call({:redeploy, Map}, term) :: :ok
  def handle_call({:redeploy, options}, _state) do
    {:reply, redeploy(options)}
  end

  defp create_port_list(list, cur_idx, max_cnt) do
    if cur_idx == max_cnt do
      list
    else
      create_port_list(list ++ [0], cur_idx+1, max_cnt)
    end
  end

  defp configure_router(options, cluster, deployed_units) do
    if options[:openaperture_router] do
      case Router.validate_routing_options(options[:openaperture_router]) do
        :ok ->
          case update_openaperture_router(options[:openaperture_router], cluster, deployed_units) do
            :ok -> :ok
            {:error, errors} ->
              {:error, "Router returned the following errors: #{JSON.encode!(errors)}"}
          end
        {:error, errors} ->
          {:error, "Routing options have been misconfigured: #{JSON.encode!(errors)}"}
      end
    else
      :ok
    end
  end

  @doc """
  Redeploys the Dockerized app to a OpenAperture cluster.
  Returns :ok or {:error, reason}
  """
  @spec do_deploy(Map) :: :ok | {:error, String.t}
  defp do_deploy(options) do
    deployment_repo = options.deployment_repo

    if options[:product_cluster_etcd_token] do
      cluster = case EtcdCluster.create(options[:product_cluster_etcd_token]) do
        {:ok, etcd_cluster} -> etcd_cluster
        {:error, reason}    ->
          Logger.error("Failed to create etcd cluster:  #{reason}")
          nil
      end
    else
      #legacy (no product deployment info)
      cluster = Repo.get_etcd_cluster(deployment_repo)
    end

    host_cnt = if cluster, do: EtcdCluster.get_host_count(cluster), else: 0

    Logger.debug("Parsing units...")
    new_units     = Repo.get_units(deployment_repo)
    new_units_cnt = if new_units, do: length(new_units), else: 0

    cond do
      host_cnt == 0 ->
        # Workflow.step_failed(_workflow, "Unable to complete deployment, unable to find hosts from the cluster associated with the deployment repo!")
        Logger.error("Unable to complete deployment, no hosts associated with the repo!")
        {:error, "no hosts associated with the repo"}
      new_units_cnt == 0 ->
        # Workflow.step_failed(_workflow, "Unable to complete deployment, no valid Units were retrieved from the deployment repo!")
        Logger.error("Unable to complete deployemnt, no valid Units were retrieved from the deployment repo")
        {:error, "No valid units were retrieved from the repo"}
      true ->
        requested_instance_cnt = host_cnt

        if options[:min_instance_cnt] && options[:min_instance_cnt] > requested_instance_cnt do
          requested_instance_cnt = options[:min_instance_cnt]
        end

        Logger.debug("Allocating #{requested_instance_cnt} ports on the cluster...");

        if options[:product_cluster] != nil && options[:product_component] != nil do
          Logger.debug("Allocating ports on the cluster...")
          # available_ports = ProductCluster.allocate_ports_for_component(options[:product_cluster], options[:product_component], requested_instance_cnt)

          #find all current port entries so we can remove then after the deploy units finishes
        else
          #legacy (no product deployment info)
          #just create a bogus list of port 0s.  this won't be used by the old .service.eex files
          Logger.debug("Allocating ports bogus 0-ports on the cluster...")
          available_ports = create_port_list([], 0, requested_instance_cnt)
        end

        Logger.debug("Deploying units...")
        # Workflow.publish_success_notification(_workflow, "Preparing to deploy #{new_units_cnt} units onto #{host_cnt} hosts...")
        deployed_units = EtcdCluster.deploy_units(cluster, new_units, available_ports)

        case configure_router(options, cluster, deployed_units) do
          :ok ->
            # Workflow.next_step(_workflow, %{deployed_units: deployed_units, etcd_cluster: cluster})
            Logger.info("Router configured")
          {:error, reason} ->
            # Workflow.step_failed(workflow, reason)
            Logger.error("Unable to configure Router: #{inspect reason}")
            {:error, reason}
        end
    end
  end

  defp update_openaperture_router(openaperture_router, cluster, deployed_units) do
    if (deployed_units && length(deployed_units) > 0) do
      host_map   = %{}
      hosts      = EtcdCluster.get_hosts(cluster)
      etcd_token = EtcdCluster.get_token(cluster)

      if (hosts != nil && length(hosts) > 0) do
        host_map = Enum.reduce hosts, host_map, fn(host, host_map) ->
          Map.put(host_map, host["id"], host)
        end
      end

      Enum.reduce deployed_units, nil, fn(deployed_unit, errors) ->
        dst_port   = SystemdUnit.get_assigned_port(deployed_unit)
        machine_id = SystemdUnit.get_machine_id(deployed_unit)
        host       = host_map[machine_id]

        SystemdUnit.set_etcd_token(deployed_unit, etcd_token)
        SystemdUnit.refresh(deployed_unit)

        if (host != nil) do
          Router.add_route(openaperture_router,host["primaryIP"], dst_port)
        end
      end
    end

    Router.update_changes(openaperture_router)
  end
end
