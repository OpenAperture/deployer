require Logger
 
defmodule OpenAperture.Deployer.Request do

  alias OpenAperture.WorkflowOrchestratorApi.Workflow
  alias OpenAperture.Messaging.AMQP.SubscriptionHandler

  alias OpenAperture.Deployer.MessageManager
  
	@moduledoc """
	Methods and Request struct for Deployer requests
	"""

  defstruct workflow: nil, 
  					orchestrator_request: nil,
            etcd_token: nil,
            deployable_units: nil,
            deployed_units: nil,
	  				delivery_tag: nil,
            subscription_handler: nil,
            last_total_duration_warning: nil

  @type t :: %__MODULE__{}

  @doc """
  Method to convert a map into a Request struct

  ## Options

  The `payload` option defines the Map containing the request

  ## Return Values

  OpenAperture.WorkflowOrchestratorApi.Request.t
  """
  @spec from_payload(Map, Map) :: OpenAperture.Deployer.Request.t
  def from_payload(payload, %{subscription_handler: subscription_handler, delivery_tag: delivery_tag} = _async_info) do
  	orchestrator_request = OpenAperture.WorkflowOrchestratorApi.Request.from_payload(payload)

  	%OpenAperture.Deployer.Request{
  		workflow: orchestrator_request.workflow,
  		orchestrator_request: orchestrator_request,
      etcd_token: orchestrator_request.etcd_token,
      deployable_units: orchestrator_request.deployable_units,
      delivery_tag: delivery_tag,
      subscription_handler: subscription_handler,
    }
  end

  @doc """
  Convenience wrapper to publish a "success" notification to the associated Workflow

  ## Options
   
  The `deploy_request` option defines the Request

  The `message` option defines the message to publish

  ## Return values

  Request
  """
  @spec publish_success_notification(OpenAperture.Deployer.Request.t, String.t()) :: OpenAperture.Deployer.Request.t
  def publish_success_notification(deploy_request, message) do
    Logger.debug("[DeployRequest][#{deploy_request.workflow.id}] #{message}")
    orchestrator_request = Workflow.publish_success_notification(deploy_request.orchestrator_request, message)
    %{deploy_request | orchestrator_request: orchestrator_request, workflow: orchestrator_request.workflow}
  end

  @doc """
  Convenience wrapper to publish a "failure" notification to the associated Workflow

  ## Options
   
  The `deploy_request` option defines the Request

  The `message` option defines the message to publish

  ## Return values

  Request
  """
  @spec publish_failure_notification(OpenAperture.Deployer.Request.t, String.t(), String.t()) :: OpenAperture.Deployer.Request.t
  def publish_failure_notification(deploy_request, message, reason) do
    Logger.error("[DeployRequest][#{deploy_request.workflow.id}] #{message}\n\n#{reason}")
    orchestrator_request = Workflow.publish_failure_notification(deploy_request.orchestrator_request, "#{message}\n\n#{reason}")
    %{deploy_request | orchestrator_request: orchestrator_request, workflow: orchestrator_request.workflow}
  end

  @doc """
  Convenience wrapper to notify the WorkflowOrchestrator that a workflow step has failed

  ## Options
   
  The `deploy_request` option defines the Request

  The `message` option defines the message to publish

  The `reason` option defines an optional String description

  ## Return values

  Request
  """
  @spec step_failed(OpenAperture.Deployer.Request.t, String.t(), String.t()) :: OpenAperture.Deployer.Request.t
  def step_failed(deploy_request, message, reason) do
    acknowledge(deploy_request)
    orchestrator_request = Workflow.step_failed(deploy_request.orchestrator_request, message, reason)
    %{deploy_request | orchestrator_request: orchestrator_request, workflow: orchestrator_request.workflow}
  end

  @doc """
  Convenience wrapper to notify the WorkflowOrchestrator that a workflow step has completed

  ## Options

  The `request` option defines the Request

  ## Return Values

  Request
  """
  @spec step_completed(OpenAperture.Deployer.Request.t) :: OpenAperture.Deployer.Request.t
  def step_completed(deploy_request) do
    acknowledge(deploy_request)
    orchestrator_request = Workflow.step_completed(deploy_request.orchestrator_request)
    %{deploy_request | orchestrator_request: orchestrator_request, workflow: orchestrator_request.workflow}
  end

  @doc """
  Convenience wrapper to acknowledge messages

  ## Options

  The `request` option defines the Request
  """
  @spec acknowledge(OpenAperture.Deployer.Request.t) :: term
  def acknowledge(deploy_request) do
    try do
      message = MessageManager.remove(deploy_request.delivery_tag)
      if message != nil do 
        SubscriptionHandler.acknowledge(message[:subscription_handler], message[:delivery_tag])
      end
    catch
      :exit, code   -> 
        Logger.error("[DeployerRequest] Failed to acknowledge message #{deploy_request.delivery_tag} - Exited with code #{inspect code}")
      :throw, value -> 
        Logger.error("[DeployerRequest] Failed to acknowledge message #{deploy_request.delivery_tag} - Throw called with #{inspect value}")
      what, value   -> 
        Logger.error("[DeployerRequest] Failed to acknowledge message #{deploy_request.delivery_tag} - Caught #{inspect what} with #{inspect value}")
    end      
  end

  @doc """
  Convenience wrapper to save the updated Workflow
  ## Options
   
  The `builder_request` option defines the Request
  The `message` option defines the message to publish
  ## Return values
  Request
  """
  @spec save_workflow(OpenAperture.Deployer.Request.t) :: OpenAperture.Deployer.Request.t
  def save_workflow(deploy_request) do
    orchestrator_request = Workflow.save(deploy_request.orchestrator_request)
    %{deploy_request | orchestrator_request: orchestrator_request, workflow: orchestrator_request.workflow}
  end
end