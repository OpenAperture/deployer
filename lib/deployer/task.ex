defmodule OpenAperture.Deployer.Task do
  @moduledoc "Defines a single deployment task."

  require Logger

  alias OpenAperture.Deployer
  alias Deployer.DeploymentRepo
  alias Deployer.SourceRepo
  alias Deployer.EtcdCluster
  alias Deployer.Notifications
  alias OpenAperture.Messaging.AMQP.SubscriptionHandler

  @doc """
  Starts a new Deployment Task.
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec start_link(Map) :: {:ok, pid} | {:error, String.t}
  def start_link(details) do
    Logger.debug("Starting a new Deployment Task for #{details[:container_repo]}")
    details = details |> Dict.put(:deployment_repo, SourceRepo.create! details)
    Task.start_link(fn -> Deployer.Task.deploy(details) end)
  end

  @doc  """
  Deploys the Dockerized app to a CoreOS cluster.
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec deploy(Map) :: :ok | {:error, String.t}
  def deploy(options) do
    Logger.info("Beginning Fleet deployment...")
    unless options[:deployment_repo], do: raise "No deployment repo provided"

    case DeploymentRepo.download(options.deployment_repo) do
      :ok               -> start_deploy(options)
      {:errors, reason} -> {:error, reason}
    end
  end

  @doc "Re-deployes the Dockerized app to a CoreOS cluster."
  @spec redeploy(Map) :: :ok | {:error, String.t}
  def redeploy(options) do
    Logger.info("Beginnging Fleet re-deployment...")
    start_deploy(options)
  end

  def create_cluster(options) do
    if options[:product_cluster_etcd_token] == nil do
      # legacy (no product deployment info)
      DeploymentRepo.get_etcd_cluster(options.deployment_repo)
    else
      cluster = case EtcdCluster.create(options[:product_cluster_etcd_token]) do
        {:ok, etcd_cluster} -> etcd_cluster
        {:error, reason}    ->
          Logger.error("Failed to create etcd cluster:  #{reason}")
          nil
      end
    end
  end

  @doc false
  defp start_deploy(options) do
    deployment_repo = options.deployment_repo
    cluster         = create_cluster(options)
    host_cnt        = if cluster, do: EtcdCluster.get_host_count(cluster), else: 0

    Logger.debug("Parsing units...")
    new_units     = DeploymentRepo.get_units(deployment_repo)
    new_units_cnt = if new_units, do: length(new_units), else: 0

    cond do
      host_cnt      == 0 -> fail_w_no_hosts(options.source_repo)
      new_units_cnt == 0 -> fail_w_no_units(options.source_repo)
      true               -> do_deploy(cluster, host_cnt, new_units, options)
    end
  end

  defp fail_w_no_hosts(repo) do
    %{prefix:     "Deployment of #{repo} failed!",
      message:    "Unable to find hosts associated with the deployment repo!",
      is_success:  false} |> Notifications.send

    "Unable to complete deployment, no hosts associated with the repo!"
      |> Logger.error

    {:error, "no hosts associated with the repo"}
  end

  defp fail_w_no_units(repo) do
    # Workflow.step_failed(_workflow, "Unable to complete deployment, no valid Units were retrieved from the deployment repo!")
    %{prefix:     "Deployment of #{repo} failed!",
      message:    "Unable to find valid units for this repo!",
      is_success:  false} |> Notifications.send

    "Unable to complete deployemnt, no valid Units were retrieved from the deployment repo"
      |> Logger.error

    {:error, "No valid units were retrieved from the repo"}
  end


  defp do_deploy(cluster, requested_instance_cnt, new_units, options) do
    if options[:min_instance_cnt] && options[:min_instance_cnt] > requested_instance_cnt do
      requested_instance_cnt = options[:min_instance_cnt]
    end

    Logger.debug("Allocating #{requested_instance_cnt} ports on the cluster...");

    if options[:product_cluster] && options[:product_component] do
      # find all current port entries so we can remove them after the deploy units finishes
      Logger.debug("Allocating ports on the cluster...")
      # TODO: figure out where we store this stuff now after segregation
      # available_ports = ProductCluster.allocate_ports_for_component(
      #   options.product_cluster,
      #   options.product_component,
      #   requested_instance_cnt
      # )
    else
      # legacy (no product deployment info)
      # just create a bogus list of port 0s.  this won't be used by the old .service.eex files
      Logger.debug("Allocating ports bogus 0-ports on the cluster...")
      available_ports = create_port_list([], 0, requested_instance_cnt)
    end

    Logger.debug("Deploying units...")
    # Workflow.publish_success_notification(_workflow, "Preparing to deploy #{new_units_cnt} units onto #{host_cnt} hosts...")
    # deployed_units = EtcdCluster.deploy_units(cluster, new_units, available_ports)
    if EtcdCluster.deploy_units(cluster, new_units, available_ports) do
      :ok
    else
      {:error, "No units deployed"}
    end

    # ensure_router_configuration(options, cluster, deployed_units)
  end

  defp ensure_router_configuration(options, cluster, units) do
    case configure_router(options, cluster, units) do
      :ok ->
        Logger.info("Router configured")
        %{subscription_handler: handler, delivery_tag: tag} = options
        SubscriptionHandler.acknowledge(handler, tag)
      {:error, reason} ->
        Logger.error("Unable to configure Router: #{inspect reason}")
        {:error, reason}
    end
  end

  @doc false
  defp create_port_list(list, cur_idx, max_cnt) do
    if cur_idx == max_cnt do
      list
    else
      create_port_list(list ++ [0], cur_idx+1, max_cnt)
    end
  end

  @doc false
  defp configure_router(options, cluster, deployed_units) do
    if options[:openaperture_router] do
      case Router.validate_routing_options(options[:openaperture_router]) do
        :ok ->
          case update_router(options[:openaperture_router], cluster, deployed_units) do
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

  @doc false
  defp update_router(router, cluster, deployed_units) do
    if (deployed_units && length(deployed_units) > 0) do
      host_map   = %{}
      hosts      = EtcdCluster.get_hosts(cluster)
      etcd_token = EtcdCluster.get_token(cluster)

      if (hosts && length(hosts) > 0) do
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

        if host do
          Router.add_route(router, host["primaryIP"], dst_port)
        end
      end
    end

    Router.update_changes(router)
  end
end
