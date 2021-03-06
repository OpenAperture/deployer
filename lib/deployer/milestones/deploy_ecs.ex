defmodule OpenAperture.Deployer.Milestones.DeployEcs do
  @moduledoc "Defines a single deployment task."

  require Logger

  alias OpenAperture.Deployer.Milestones.DeployEcs
  alias OpenAperture.Deployer.Request, as: DeployerRequest
  alias OpenAperture.Deployer.MilestoneMonitor

  alias OpenAperture.Deployer.Configuration
  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.SystemEvent

  @logprefix "[Milestones.DeployEcs]"

  @doc """
  Starts a new Deployment Task.
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec start_link(map) :: {:ok, pid} | {:error, String.t}
  def start_link(deploy_request) do
    Logger.debug("#{@logprefix} Starting a new Deployment task for Workflow #{deploy_request.workflow.id}...")

    Task.start_link(fn ->
      deploy_request = DeployerRequest.publish_success_notification(deploy_request, "The deploy_ecs milestone has been received and is being processed by Deployer #{System.get_env("HOSTNAME")} in cluster #{deploy_request.etcd_token}")
      deploy_request = DeployerRequest.save_workflow(deploy_request)

      try do
        deploy_request
        |> MilestoneMonitor.monitor(:deploy_ecs, fn -> DeployEcs.deploy(deploy_request) end)
        |> DeployerRequest.publish_success_notification("The units has been deployed.")
        |> DeployerRequest.step_completed
        Logger.debug("#{@logprefix} Successfully completed the ECS Deployment task for Workflow #{deploy_request.workflow.id}.")
      catch
        :exit, code -> create_system_event(deploy_request, "#{@logprefix} Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Exited with code #{inspect code}")
        value -> create_system_event(deploy_request, "#{@logprefix} Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Caught #{inspect value}")
      end
    end)
  end

  defp create_system_event(deploy_request, error_msg) do
    Logger.error(error_msg)
    DeployerRequest.step_failed(deploy_request, "An error occurred during ECS deployment", error_msg)
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
  Deploys the Dockerized app to ECS
  """
  @spec deploy(DeployerRequest) :: DeployerRequest
  def deploy(deploy_request) do
    Logger.info("#{@logprefix} Beginning ECS deployment...")
    aws = deploy_request.orchestrator_request.aws_config
    task_def = Poison.decode! deploy_request.orchestrator_request.ecs_task_definition
    case OpenAperture.Deployer.ECS.deploy_task(aws, task_def) do
      {:ok, status} ->
        Logger.debug("#{@logprefix} Deploy to ECS successful: #{status}")
        deploy_request
      {:error, reason} ->
        Logger.error("#{@logprefix} Deploy to ECS failed: #{inspect reason}")
        throw {"Deploy to ECS Failed", reason}
    end
  end
end
