defmodule OpenAperture.Deployer.Milestones.Deploy do
  @moduledoc "Defines a single deployment task."
  
  require Logger

  alias OpenAperture.Deployer.Milestones.Deploy
  alias OpenAperture.Deployer.Request, as: DeployerRequest
  alias OpenAperture.Deployer.Milestones.Monitor

  alias OpenAperture.Fleet.EtcdCluster

  @doc """
  Starts a new Deployment Task.
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec start_link(Map) :: {:ok, pid} | {:error, String.t}
  def start_link(deploy_request) do
    Logger.debug("[Milestones.Deploy] Starting a new Deployment task for Workflow #{deploy_request.workflow.id}...")
    Task.start_link(fn -> 
      deploy_request = DeployerRequest.publish_success_notification(deploy_request, "The deploy milestone has been received and is being processed by Deployer #{System.get_env("HOSTNAME")} in cluster #{deploy_request.etcd_token}")
      
      try do
        successful_deploy_request = Deploy.deploy(deploy_request)

        successful_deploy_request = DeployerRequest.publish_success_notification(successful_deploy_request, "The units has been deployed, starting deployment monitor...")
        Logger.debug("[Milestones.Deploy] Successfully completed the Deployment task for Workflow #{deploy_request.workflow.id}, requesting monitoring...")
        Monitor.start_link(successful_deploy_request)
      catch
        :exit, code   -> 
          Logger.error("[Milestones.Deploy] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Exited with code #{inspect code}")
          DeployerRequest.step_failed(deploy_request, "An unexpected error occurred executing deploy request", "Exited with code #{inspect code}")
        :throw, value -> 
          Logger.error("[Milestones.Deploy] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Throw called with #{inspect value}")
          DeployerRequest.step_failed(deploy_request, "An unexpected error occurred executing deploy request", "Throw called with #{inspect value}")
        what, value   -> 
          Logger.error("[Milestones.Deploy] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Caught #{inspect what} with #{inspect value}")
          DeployerRequest.step_failed(deploy_request, "An unexpected error occurred executing deploy request", "Caught #{inspect what} with #{inspect value}")
      end
    end)
  end

  @doc """
  Deploys the Dockerized app to a CoreOS cluster.
  """
  @spec deploy(DeployerRequest) :: DeployerRequest
  def deploy(deploy_request) do
    Logger.info("[Milestones.Deploy] Beginning Fleet deployment...")

    host_cnt = EtcdCluster.get_host_count(deploy_request.etcd_token)

    if  deploy_request.orchestrator_request != nil &&
        deploy_request.orchestrator_request.fleet_config != nil && 
        deploy_request.orchestrator_request.fleet_config["instance_cnt"] != nil do
          requested_instance_cnt = deploy_request.orchestrator_request.fleet_config["instance_cnt"]
    else
      requested_instance_cnt = EtcdCluster.get_host_count(deploy_request.etcd_token)
    end

    Logger.debug("[Milestones.Deploy] Reviewing units...")
    cond do
      host_cnt == 0 -> DeployerRequest.step_failed(deploy_request, "Deployment failed!", "Unable to find accessible hosts in cluster #{deploy_request.etcd_token}!")
      requested_instance_cnt == 0 -> DeployerRequest.step_failed(deploy_request, "Deployment failed!", "Cannot specify 0 instances of services to deploy!")
      deploy_request.deployable_units == nil || length(deploy_request.deployable_units) == 0 -> DeployerRequest.step_failed(deploy_request.deployable_units, "Deployment failed!", "There are no valid units to deploy!")
      true -> do_deploy(deploy_request, host_cnt, requested_instance_cnt)
    end
  end

  @spec do_deploy(DeployerRequest, term, term) :: DeployerRequest
  defp do_deploy(deploy_request, host_cnt, requested_instance_cnt) do
    Logger.debug("[Milestones.Deploy] Allocating #{requested_instance_cnt} ports on the cluster...");
    map_available_ports = build_port_map(deploy_request.deployable_units, requested_instance_cnt, %{})

    Logger.debug("[Milestones.Deploy] Deploying units...")
    deploy_request = DeployerRequest.publish_success_notification(deploy_request, "Preparing to deploy #{requested_instance_cnt} instance(s) of each of the #{length(deploy_request.deployable_units)} unit(s) onto #{host_cnt} host(s)...")

    %{deploy_request | deployed_units: EtcdCluster.deploy_units(deploy_request.etcd_token, deploy_request.deployable_units, map_available_ports)}
  end

  @spec build_port_map([], term, Map) :: Map
  defp build_port_map([], _, map_available_ports) do
    map_available_ports
  end

  @spec build_port_map(List, term, Map) :: Map
  defp build_port_map([deployable_unit | remaining_units], requested_instance_cnt, map_available_ports) do
    build_port_map(remaining_units, requested_instance_cnt, Map.put(map_available_ports, deployable_unit.name, create_port_list([], 0, requested_instance_cnt)))
  end

  @spec create_port_list(List, term, term) :: List
  defp create_port_list(list, cur_idx, max_cnt) do
    if cur_idx == max_cnt do
      list
    else
      create_port_list(list ++ [0], cur_idx+1, max_cnt)
    end
  end  
end
