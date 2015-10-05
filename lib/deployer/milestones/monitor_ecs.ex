defmodule OpenAperture.Deployer.Milestones.MonitorEcs do
  @moduledoc "Defines a single deployment task."

  require Logger

  alias OpenAperture.Deployer.Milestones.MonitorEcs
  alias OpenAperture.Deployer.MilestoneMonitor
  alias OpenAperture.Deployer.Request, as: DeployerRequest

  alias OpenAperture.Deployer.Configuration
  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.SystemEvent 

  @logprefix "[Milestones.MonitorEcs]"

  @doc """
  Starts a new Deployment Task.
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec start_link(map) :: {:ok, pid} | {:error, String.t}
  def start_link(deploy_request) do
    Logger.debug("#{@logprefix} Starting a new ECS Deployment Monitoring task for Workflow #{deploy_request.workflow.id}...")
    Task.start_link(fn -> 
      deploy_request = DeployerRequest.publish_success_notification(deploy_request, "The deploy (monitor ecs) milestone has been received and is being processed by Deployer #{System.get_env("HOSTNAME")} in cluster #{deploy_request.etcd_token}")
      deploy_request = DeployerRequest.save_workflow(deploy_request)

      try do
        MilestoneMonitor.monitor(deploy_request, :monitor_ecs_deploy, fn -> MonitorEcs.monitor(deploy_request, 0)  end)
      catch
        :exit, code -> create_system_event(deploy_request, "#{@logprefix} Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Exited with code #{inspect code}")
        :throw, value -> create_system_event(deploy_request, "#{@logprefix} Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Throw called with #{inspect value}")
        what, value -> create_system_event(deploy_request, "#{@logprefix} Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Caught #{inspect what} with #{inspect value}")
      end
    end)
  end

  defp create_system_event(deploy_request, error_msg) do 
    Logger.error(error_msg)
    DeployerRequest.step_failed(deploy_request, error_msg)
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
  Monitors an in-progress Fleet deployment

  ## Options

  The `deploy_request` option contains the DeployerRequest

  The `monitoring_loop_cnt` option defines the current number of execution cycles
  """
  @spec monitor(DeployerRequest) :: DeployerRequest
  def monitor(deploy_request) do
    Logger.debug("[Milestones.Monitor] Monitoring the ECS deployment...")
    DeployerRequest.step_completed(deploy_request)
  end 
end
