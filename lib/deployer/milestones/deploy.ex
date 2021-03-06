defmodule OpenAperture.Deployer.Milestones.Deploy do
  @moduledoc "Defines a single deployment task."
  
  require Logger

  alias OpenAperture.Deployer.Milestones.Deploy
  alias OpenAperture.Deployer.Request, as: DeployerRequest
  alias OpenAperture.Deployer.Milestones.Monitor
  alias OpenAperture.Deployer.MilestoneMonitor

  alias OpenAperture.Fleet.EtcdCluster

  alias OpenAperture.Deployer.Configuration
  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.SystemEvent  

  @logprefix "[Milestones.Deploy]"

  @doc """
  Starts a new Deployment Task.
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec start_link(map) :: {:ok, pid} | {:error, String.t}
  def start_link(deploy_request) do
    Logger.debug("#{@logprefix} Starting a new Deployment task for Workflow #{deploy_request.workflow.id}...")

    Task.start_link(fn -> 
      deploy_request = DeployerRequest.publish_success_notification(deploy_request, "The deploy milestone has been received and is being processed by Deployer #{System.get_env("HOSTNAME")} in cluster #{deploy_request.etcd_token}")
      deploy_request = DeployerRequest.save_workflow(deploy_request)

      try do
        successful_deploy_request = MilestoneMonitor.monitor(deploy_request, :deploy, fn -> Deploy.deploy(deploy_request) end)

        successful_deploy_request = DeployerRequest.publish_success_notification(successful_deploy_request, "The units has been deployed, starting deployment monitor...")
        Logger.debug("#{@logprefix} Successfully completed the Deployment task for Workflow #{deploy_request.workflow.id}, requesting monitoring...")
        Monitor.start_link(successful_deploy_request)
      catch
        :exit, code -> create_system_event(deploy_request, "[Milestones.Deploy] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Exited with code #{inspect code}")
        :throw, value -> create_system_event(deploy_request, "[Milestones.Deploy] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Throw called with #{inspect value}")
        what, value -> create_system_event(deploy_request, "[Milestones.Deploy] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Caught #{inspect what} with #{inspect value}")
      end
    end)
  end

  defp create_system_event(deploy_request, error_msg) do 
    Logger.error(error_msg)
    DeployerRequest.step_failed(deploy_request, "An error occurred during deployment", error_msg)
    event = %{
      unique: true,
      type: :unhandled_exception, 
      severity: :error, 
      data: %{
        component: :deployer,
        exchange_id: Configuration.get_current_exchange_id,
        hostname: System.get_env("HOSTNAME")
      },
      message: error_msg
    }       
    SystemEvent.create_system_event!(ManagerApi.get_api, event)     
  end

  @doc """
  Deploys the Dockerized app to a CoreOS cluster.
  """
  @spec deploy(DeployerRequest) :: DeployerRequest
  def deploy(deploy_request) do
    Logger.info("#{@logprefix} Beginning Fleet deployment...")

    host_cnt = EtcdCluster.get_host_count(deploy_request.etcd_token)

    if  deploy_request.orchestrator_request != nil &&
        deploy_request.orchestrator_request.fleet_config != nil && 
        deploy_request.orchestrator_request.fleet_config["instance_cnt"] != nil do
          requested_instance_cnt = deploy_request.orchestrator_request.fleet_config["instance_cnt"]
    else
      requested_instance_cnt = EtcdCluster.get_host_count(deploy_request.etcd_token)
    end

    Logger.debug("#{@logprefix} Reviewing units...")
    cond do
      host_cnt == 0 -> DeployerRequest.step_failed(deploy_request, "Deployment failed!", "Unable to find accessible hosts in cluster #{deploy_request.etcd_token}!")
      requested_instance_cnt == 0 -> DeployerRequest.step_failed(deploy_request, "Deployment failed!", "Cannot specify 0 instances of services to deploy!")
      deploy_request.deployable_units == nil || length(deploy_request.deployable_units) == 0 -> DeployerRequest.step_failed(deploy_request.deployable_units, "Deployment failed!", "There are no valid units to deploy!")
      true -> do_deploy(deploy_request, host_cnt, requested_instance_cnt)
    end
  end

  @spec do_deploy(DeployerRequest, term, term) :: DeployerRequest
  defp do_deploy(deploy_request, host_cnt, requested_instance_cnt) do
    Logger.debug("#{@logprefix} Allocating #{requested_instance_cnt} ports on the cluster...");
    map_available_ports = build_port_map(deploy_request.deployable_units, requested_instance_cnt, %{})

    Logger.debug("#{@logprefix} Deploying units...")
    deploy_request = DeployerRequest.publish_success_notification(deploy_request, "Preparing to deploy #{requested_instance_cnt} instance(s) of each of the #{length(deploy_request.deployable_units)} unit(s) onto #{host_cnt} host(s)...")

    %{deploy_request | deployed_units: EtcdCluster.deploy_units(deploy_request.etcd_token, deploy_request.deployable_units, map_available_ports)}
  end

  @spec build_port_map([], term, map) :: map
  defp build_port_map([], _, map_available_ports) do
    map_available_ports
  end

  @spec build_port_map(list, term, map) :: map
  defp build_port_map([deployable_unit | remaining_units], requested_instance_cnt, map_available_ports) do
    build_port_map(remaining_units, requested_instance_cnt, Map.put(map_available_ports, deployable_unit.name, create_port_list([], 0, requested_instance_cnt)))
  end

  @spec create_port_list(list, term, term) :: list
  defp create_port_list(list, cur_idx, max_cnt) do
    if cur_idx == max_cnt do
      list
    else
      create_port_list(list ++ [0], cur_idx+1, max_cnt)
    end
  end  
end
