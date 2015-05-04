defmodule OpenAperture.Deployer.Milestones.Deploy do
  @moduledoc "Defines a single deployment task."
  
  require Logger

  alias OpenAperture.Deployer.Milestones.Deploy
  alias OpenAperture.Deployer.Request, as: DeployerRequest
  alias OpenAperture.Deployer.Milestones.MonitorSupervisor
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
      try do
        successful_deploy_request = Deploy.deploy(deploy_request)
        Logger.debug("[Milestones.Deploy] Successfully completed the Deployment task for Workflow #{deploy_request.workflow.id}, requesting monitoring...")
        #MonitorSupervisor.monitor(successful_deploy_request)
        Monitor.start_link(successful_deploy_request)
      catch
        :exit, code   -> 
          Logger.error("[Milestones.Deploy] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Exited with code #{inspect code}")
          DeployerRequest.acknowledge(deploy_request)
        :throw, value -> 
          Logger.error("[Milestones.Deploy] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Throw called with #{inspect value}")
          DeployerRequest.acknowledge(deploy_request)
        what, value   -> 
          Logger.error("[Milestones.Deploy] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Caught #{inspect what} with #{inspect value}")
          DeployerRequest.acknowledge(deploy_request)
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

    Logger.debug("[Milestones.Deploy] Reviewing units...")
    cond do
      host_cnt == 0 -> DeployerRequest.step_failed(deploy_request, "Deployment failed!", "Unable to find accessible hosts in cluster #{deploy_request.etcd_token}!")
      deploy_request.deployable_units == nil || length(deploy_request.deployable_units) == 0 -> DeployerRequest.step_failed(deploy_request.deployable_units, "Deployment failed!", "There are no valid units to deploy!")
      true -> do_deploy(deploy_request, host_cnt)
    end
  end

  @spec do_deploy(DeployerRequest, term) :: DeployerRequest
  defp do_deploy(deploy_request, requested_instance_cnt) do
    #if details[:min_instance_cnt] && details[:min_instance_cnt] > requested_instance_cnt do
    #  requested_instance_cnt = details[:min_instance_cnt]
    #end

    Logger.debug("[Milestones.Deploy] Allocating #{requested_instance_cnt} ports on the cluster...");

    Logger.debug("[Milestones.Deploy] Allocating ports bogus 0-ports on the cluster...")
    map_available_ports = nil

    Logger.debug("[Milestones.Deploy] Deploying units...")
    deploy_request = DeployerRequest.publish_success_notification(deploy_request, "Preparing to deploy #{length(deploy_request.deployable_units)} units onto #{requested_instance_cnt} hosts...")

    %{deploy_request | deployed_units: EtcdCluster.deploy_units(deploy_request.etcd_token, deploy_request.deployable_units, map_available_ports)}
  end
end
