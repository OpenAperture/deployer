defmodule OpenAperture.Deployer.Milestones.Deploy do
  @moduledoc "Defines a single deployment task."
  
  require Logger

  alias OpenAperture.Deployer.Milestones.Deploy
  alias OpenAperture.Deployer.Request, as: DeployerRequest
  alias OpenAperture.Deployer.Milestones.MonitorSupervisor

  alias OpenAperture.Fleet.EtcdCluster

  @doc """
  Starts a new Deployment Task.
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec start_link(Map) :: {:ok, pid} | {:error, String.t}
  def start_link(deploy_request) do
    Logger.debug("Starting a new Deployment task for Workflow #{deploy_request.workflow.id}...")
    Task.start_link(fn -> Deploy.deploy(deploy_request) end)
  end

  @doc """
  Deploys the Dockerized app to a CoreOS cluster.
  """
  @spec deploy(DeployerRequest) :: DeployerRequest
  def deploy(deploy_request) do
    Logger.info("Beginning Fleet deployment...")
    cluster = case EtcdCluster.create(deploy_request.etcd_token) do
      {:ok, cluster} -> cluster
      {:error, reason} -> 
        Logger.error("Unable to create EtcdCluster:  #{inspect reason}")
        nil
    end
    host_cnt = if cluster, do: EtcdCluster.get_host_count(cluster), else: 0

    Logger.debug("Reviewing units...")
    cond do
      host_cnt == 0 -> DeployerRequest.step_failed(deploy_request, "Deployment failed!", "Unable to find accessible hosts in cluster #{deploy_request.etcd_token}!")
      deploy_request.deployable_units == nil || length(deploy_request.deployable_units) == 0 -> DeployerRequest.step_failed(deploy_request.deployable_units, "Deployment failed!", "There are no valid units to deploy!")
      true -> do_deploy(deploy_request, cluster, host_cnt)
    end
  end

  @spec do_deploy(DeployerRequest, pid, term) :: DeployerRequest
  defp do_deploy(deploy_request, cluster, requested_instance_cnt) do
    #if details[:min_instance_cnt] && details[:min_instance_cnt] > requested_instance_cnt do
    #  requested_instance_cnt = details[:min_instance_cnt]
    #end

    Logger.debug("Allocating #{requested_instance_cnt} ports on the cluster...");

    Logger.debug("Allocating ports bogus 0-ports on the cluster...")
    available_ports = create_port_list([], 0, requested_instance_cnt)

    Logger.debug("Deploying units...")
    deploy_request = DeployerRequest.publish_success_notification(deploy_request, "Preparing to deploy #{length(deploy_request.deployable_units)} units onto #{requested_instance_cnt} hosts...")

    deploy_request = %{deploy_request | deployed_units: EtcdCluster.deploy_units(cluster, deploy_request.deployable_units, available_ports)}
    MonitorSupervisor.monitor(deploy_request)
    deploy_request
  end

  @doc false
  defp create_port_list(list, cur_idx, max_cnt) do
    if cur_idx == max_cnt do
      list
    else
      create_port_list(list ++ [0], cur_idx+1, max_cnt)
    end
  end
end
