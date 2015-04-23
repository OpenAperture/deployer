defmodule OpenAperture.Deployer.Milestones.Monitor do
  @moduledoc "Defines a single deployment task."

  require Logger

  alias OpenAperture.Deployer.Milestones.Monitor
  alias OpenAperture.Deployer.Request, as: DeployerRequest

  alias OpenAperture.Fleet.SystemdUnit

  @doc """
  Starts a new Deployment Task.
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec start_link(Map) :: {:ok, pid} | {:error, String.t}
  def start_link(deploy_request) do
    Logger.debug("Starting a new Deployment Monitoring task for Workflow #{deploy_request.workflow.id}...")
    Task.start_link(fn -> Monitor.monitor(deploy_request, 0) end)
  end

  @doc """
  Monitors an in-progress Fleet deployment
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec monitor(DeployerRequest, term) :: :ok | {:error, String.t}
  def monitor(deploy_request, monitoring_loop_cnt) do
    etcd_token = deploy_request.etcd_token
    num_requested_monitoring_units = if deploy_request.deployed_units, do: length(deploy_request.deployed_units), else: 0

    Logger.debug("Monitoring the deployment of #{num_requested_monitoring_units} units on cluster #{etcd_token}...")
    units_to_monitor = OpenAperture.Deployer.Milestones.Monitor.verify_unit_status(deploy_request.deployed_units, etcd_token, [])
    units_to_monitor_cnt = length(units_to_monitor)

    if units_to_monitor_cnt > 0 do
      deploy_request = DeployerRequest.publish_success_notification(deploy_request, "There are #{units_to_monitor_cnt} units still deploying...")
      monitoring_loop_cnt = monitoring_loop_cnt + 1
      if (monitoring_loop_cnt < 30) do
        #sleep for a minute before recasting
        :timer.sleep(60000)
        monitor(deploy_request, monitoring_loop_cnt)    
      else
        DeployerRequest.step_failed(deploy_request, "Deployment has failed!", "Deployment has taken over 30 minutes to complete!  Monitoring will now discontinue.")
      end
    else
      DeployerRequest.publish_success_notification(deploy_request, "There are no remaining deployments to monitor")
      DeployerRequest.step_completed(deploy_request)
    end
  end

  @doc """
  Method to verify the state of a unit
  
  ## Options
  
  The `current_unit | remaining_units` option defines the github PID
  
  The `etcd_token` option defines the etcd cluster token

  The `units_to_monitor` option defines which units need to continue to be monitored
  
  ## Return Values
   
  Map
  """
  @spec verify_unit_status(List, String.t(), List) :: Map
  def verify_unit_status([current_unit| remaining_units], etcd_token, units_to_monitor) do    
    SystemdUnit.set_etcd_token(current_unit, etcd_token)
    SystemdUnit.refresh(current_unit)

    unit_name = SystemdUnit.get_unit_name(current_unit)
    case SystemdUnit.is_launched?(current_unit) do
      true -> Logger.debug("Requested service #{unit_name} on cluster #{etcd_token} has been launched")
      {false, "loaded"} -> 
        Logger.debug("Requested service #{unit_name} on cluster #{etcd_token} has been loaded and is being launched...")
      {false, "inactive"} -> 
        Logger.debug("Requested service #{unit_name} on cluster #{etcd_token} has been loaded (but not started), and is being launched...")
      {false, current_launch_state} -> 
        Logger.error("Requested service #{unit_name} on cluster #{etcd_token} is in an incorrect state:  #{current_launch_state}")
    end

    case SystemdUnit.is_active?(current_unit) do
      true -> Logger.debug("Requested service #{unit_name} on cluster #{etcd_token} is active")
      {false, "activating", _, _} -> 
        Logger.debug("Requested service #{unit_name} on cluster #{etcd_token} is starting up...")
        units_to_monitor = units_to_monitor ++ [current_unit]
      {false, nil, _, _} -> 
        Logger.debug("Requested service #{unit_name} on cluster #{etcd_token} has not registered a status yet...")
        units_to_monitor = units_to_monitor ++ [current_unit]
      {false, active_state, load_state, sub_state} -> 
        Logger.error("Requested service #{unit_name} on cluster #{etcd_token} is #{active_state}; load state:  #{load_state}, sub state:  #{sub_state}!")
        case SystemdUnit.get_journal(current_unit) do
          {:ok, stdout, stderr} ->
            Logger.error("Fleet Journal:\n#{stdout}\n\n#{stderr}")
          {:error, stdout, stderr} ->
            Logger.error("Logs were unable to be retrieved:\n#{stdout}\n\n#{stderr}")
        end
    end

    verify_unit_status(remaining_units, etcd_token, units_to_monitor)
  end

  @doc """
  Method to verify the state of a unit
  
  ## Options
  
  The `current_unit | remaining_units` option defines the github PID
  
  The `etcd_token` option defines the etcd cluster token

  The `units_to_monitor` option defines which units need to continue to be monitored
  
  ## Return Values
   
  Map
  """
  @spec verify_unit_status(List, String.t(), List) :: Map
  def verify_unit_status([], _, units_to_monitor) do
    units_to_monitor
  end  
end