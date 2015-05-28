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

    if  deploy_request.orchestrator_request != nil &&
        deploy_request.orchestrator_request.fleet_config != nil && 
        deploy_request.orchestrator_request.fleet_config["instance_cnt"] != nil do
          host_cnt = deploy_request.orchestrator_request.fleet_config["instance_cnt"]
    else
      host_cnt = EtcdCluster.get_host_count(deploy_request.etcd_token)
    end

    Logger.debug("[Milestones.Deploy] Reviewing units...")
    cond do
      host_cnt == 0 -> DeployerRequest.step_failed(deploy_request, "Deployment failed!", "Unable to find accessible hosts in cluster #{deploy_request.etcd_token}!")
      deploy_request.deployable_units == nil || length(deploy_request.deployable_units) == 0 -> DeployerRequest.step_failed(deploy_request.deployable_units, "Deployment failed!", "There are no valid units to deploy!")
      true -> do_deploy(deploy_request, host_cnt)
    end
  end

  @spec do_deploy(DeployerRequest, term) :: DeployerRequest
  defp do_deploy(deploy_request, requested_instance_cnt) do
    Logger.debug("[Milestones.Deploy] Allocating #{requested_instance_cnt} ports on the cluster...");
    map_available_ports = nil

    Logger.debug("[Milestones.Deploy] Deploying units...")
    deploy_request = DeployerRequest.publish_success_notification(deploy_request, "Preparing to deploy #{length(deploy_request.deployable_units)} unit(s) onto #{requested_instance_cnt} host(s)...")

    %{deploy_request | deployed_units: EtcdCluster.deploy_units(deploy_request.etcd_token, deploy_request.deployable_units, map_available_ports)}
  end
end
