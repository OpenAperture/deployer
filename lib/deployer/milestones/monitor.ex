defmodule OpenAperture.Deployer.Milestones.Monitor do
  @moduledoc "Defines a single deployment task."

  require Logger

  alias OpenAperture.Deployer.Milestones.Monitor
  alias OpenAperture.Deployer.MilestoneMonitor
  alias OpenAperture.Deployer.Request, as: DeployerRequest

  alias OpenAperture.Fleet.SystemdUnit

  alias OpenAperture.Deployer.Configuration
  alias OpenAperture.ManagerApi
  alias OpenAperture.ManagerApi.SystemEvent 

  @doc """
  Starts a new Deployment Task.
  Returns `{:ok, pid}` or `{:error, reason}`
  """
  @spec start_link(Map) :: {:ok, pid} | {:error, String.t}
  def start_link(deploy_request) do
    Logger.debug("[Milestones.Monitor] Starting a new Deployment Monitoring task for Workflow #{deploy_request.workflow.id}...")
    Task.start_link(fn -> 
      deploy_request = DeployerRequest.publish_success_notification(deploy_request, "The deploy (monitor) milestone has been received and is being processed by Deployer #{System.get_env("HOSTNAME")} in cluster #{deploy_request.etcd_token}")
      deploy_request = DeployerRequest.save_workflow(deploy_request)

      try do
        MilestoneMonitor.monitor(deploy_request, :monitor_deploy, fn -> Monitor.monitor(deploy_request, 0)  end)
      catch
        :exit, code   -> 
          error_msg = "[Milestones.Monitor] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Exited with code #{inspect code}"
          Logger.error(error_msg)
          DeployerRequest.step_failed(deploy_request, "An unexpected error occurred executing deploy (monitor) request", "Exited with code #{inspect code}")
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
        :throw, value -> 
          error_msg = "[Milestones.Monitor] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Throw called with #{inspect value}"
          Logger.error(error_msg)
          DeployerRequest.step_failed(deploy_request, "An unexpected error occurred executing deploy (monitor) request", "Throw called with #{inspect value}")
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
        what, value   -> 
          error_msg = "[Milestones.Monitor] Message #{deploy_request.delivery_tag} (workflow #{deploy_request.workflow.id}) Caught #{inspect what} with #{inspect value}"
          Logger.error(error_msg)
          DeployerRequest.step_failed(deploy_request, "An unexpected error occurred executing deploy (monitor) request", "Caught #{inspect what} with #{inspect value}")
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
    end)
  end

  @doc """
  Monitors an in-progress Fleet deployment

  ## Options

  The `deploy_request` option contains the DeployerRequest

  The `monitoring_loop_cnt` option defines the current number of execution cycles
  """
  @spec monitor(DeployerRequest, term) :: :ok | {:error, String.t}
  def monitor(deploy_request, monitoring_loop_cnt) do
    num_requested_monitoring_units = if deploy_request.deployed_units, do: length(deploy_request.deployed_units), else: 0
    Logger.debug("[Milestones.Monitor] Monitoring the deployment of #{num_requested_monitoring_units} units on cluster #{deploy_request.etcd_token}...")
    deploy_request = log_requested_units(deploy_request, num_requested_monitoring_units)

    {monitoring_result, updated_deploy_request, _units_to_monitor, completed_units, failed_units} = monitor_remaining_units(deploy_request, monitoring_loop_cnt, deploy_request.deployed_units, [], [])

    updated_deploy_request = log_failed_units(updated_deploy_request, failed_units)
    updated_deploy_request = log_completed_units(updated_deploy_request, completed_units)

    log_monitoring_result(updated_deploy_request, monitoring_result, completed_units, num_requested_monitoring_units)
  end

  @doc """
  Method to update the DeployerRequest with the requested units to monitor

  ## Options

  The `deploy_request` option contains the DeployerRequest

  The `num_requested_monitoring_units` option contains a Integer number of requested units to monitor

  ## Return Value

  The updated DeployerRequest
  """
  @spec log_requested_units(DeployerRequest, term) :: DeployerRequest
  def log_requested_units(deploy_request, num_requested_monitoring_units) do
    unit_names = if num_requested_monitoring_units > 0 do
      Enum.reduce deploy_request.deployed_units, [], fn(deployable_unit, unit_names) ->
        unit_names ++ [deployable_unit.name]
      end
    else
      []
    end
    DeployerRequest.publish_success_notification(deploy_request, "Monitoring deployment of the following unit(s):  #{inspect unit_names}")    
  end


  @doc """
  Method to update the DeployerRequest with the failed unit journal logs

  ## Options

  The `deploy_request` option contains the DeployerRequest

  The `failed_units` option contains a list of units that have failed to started up

  ## Return Value

  The updated DeployerRequest
  """
  @spec log_failed_units(DeployerRequest, term) :: DeployerRequest
  def log_failed_units(deploy_request, failed_units) do
    if length(failed_units) == 0 do      
      Logger.debug("[Milestones.Monitor] There were no failed units")
      deploy_request
    else      
      Logger.debug("[Milestones.Monitor] Resolving failed unit names from:  #{inspect failed_units}")
      {unit_names, deploy_request} =  Enum.reduce failed_units, {[], deploy_request}, fn(failed_unit, {unit_names, deploy_request}) ->
        if failed_unit != nil do
          deploy_request = case SystemdUnit.get_journal(failed_unit) do
            {:ok, stdout, stderr} -> DeployerRequest.publish_failure_notification(deploy_request, "Unit #{failed_unit.name} has failed to startup", "#{stdout}\n\n#{stderr}")
            {:error, stdout, stderr} -> DeployerRequest.publish_failure_notification(deploy_request, "Unit #{failed_unit.name} has failed to startup; an error occurred retrieving the journal", "#{stdout}\n\n#{stderr}")
          end          
          {unit_names ++ [failed_unit.name], deploy_request}
        else
          {unit_names ++ ["Unknown Unit"], deploy_request}
        end
      end
      DeployerRequest.publish_failure_notification(deploy_request, "The following unit(s) have failed to deploy:  #{inspect unit_names}", "")
    end    
  end

  @doc """
  Method to update the DeployerRequest with the the units that have started successfully

  ## Options

  The `deploy_request` option contains the DeployerRequest

  The `completed_units` option contains a list of units that have started up

  ## Return Value

  The updated DeployerRequest
  """
  @spec log_completed_units(DeployerRequest, term) :: DeployerRequest
  def log_completed_units(deploy_request, completed_units) do
    Logger.debug("[Milestones.Monitor] Resolving completed unit names from:  #{inspect completed_units}")
    
    unit_names = if length(completed_units) > 0 do
      Enum.reduce completed_units, [], fn(completed_unit, unit_names) ->
        if completed_unit != nil do
          unit_names ++ [completed_unit.name]
        else
          unit_names ++ ["Unknown Unit"]
        end
      end
    else
      []
    end
    DeployerRequest.publish_success_notification(deploy_request, "The following unit(s) have deployed successfully:  #{inspect unit_names}")   
  end

  @doc """
  Method to update the DeployerRequest with the the units that have started successfully

  ## Options

  The `deploy_request` option contains the DeployerRequest

  The `monitoring_result` option contains the atom result

  The `completed_units` option contains a list of units that have started up

  The `num_requested_monitoring_units` option contains a Integer number of requested units to monitor

  ## Return Value

  The updated DeployerRequest
  """
  @spec log_monitoring_result(DeployerRequest, term, List, term) :: DeployerRequest
  def log_monitoring_result(deploy_request, monitoring_result, completed_units, num_requested_monitoring_units) do
    Logger.debug("[Milestones.Monitor] Resolving if ny units have successfully deployed, num_requested_monitoring_units - #{inspect num_requested_monitoring_units}, completed_units - #{inspect completed_units}")
    if num_requested_monitoring_units > 0 && length(completed_units) == 0 do
      DeployerRequest.step_failed(deploy_request, "Deployment has failed!", "None of the units have deployed successfully")
    else
      case monitoring_result do
        {:error, reason} -> DeployerRequest.step_failed(deploy_request, "Deployment has failed!", reason)
        :ok -> DeployerRequest.step_completed(deploy_request)        
      end      
    end   
  end

  @doc """
  Monitors a set of Fleet units until they start, fail to start, or timeout

  ## Options

  The `deploy_request` option contains the DeployerRequest

  The `monitoring_loop_cnt` option defines the current number of execution cycles

  The `units_to_monitor` option contains a list of units to monitor

  The `completed_units` option contains a list of units that have successfully started up  

  The `failed_units` option contains a list of units that have failed to started up
  """
  @spec monitor(DeployerRequest, term) :: :ok | {:error, String.t}
  def monitor_remaining_units(deploy_request, monitoring_loop_cnt, units_to_monitor, completed_units, failed_units) do
    num_requested_monitoring_units = if units_to_monitor, do: length(units_to_monitor), else: 0
    if num_requested_monitoring_units == 0 do
      deploy_request = DeployerRequest.publish_success_notification(deploy_request, "There are no remaining units to monitor")
      {:ok, deploy_request, units_to_monitor, completed_units, failed_units}
    else
      deploy_request = DeployerRequest.publish_success_notification(deploy_request, "Starting to monitor #{num_requested_monitoring_units} units...")
      refreshed_units = refresh_systemd_units(deploy_request.etcd_token, units_to_monitor)
      if refreshed_units == nil || length(refreshed_units) == 0 do
        Logger.error("Invalid units were returned from refresh_systemd_units!")
      end

      {remaining_units, returned_completed_units, returned_failed_units} = verify_unit_status(refreshed_units, deploy_request.etcd_token, [], [], [])
      remaining_units_cnt = length(remaining_units)

      deploy_request = DeployerRequest.publish_success_notification(deploy_request, "After review, there are #{remaining_units_cnt} units still deploying...")
      deploy_request = DeployerRequest.save_workflow(deploy_request)
      if remaining_units_cnt > 0 do
        monitoring_loop_cnt = monitoring_loop_cnt + 1
        if (monitoring_loop_cnt < 30) do
          #sleep for a minute before retrying
          :timer.sleep(60000)
          monitor_remaining_units(deploy_request, monitoring_loop_cnt, remaining_units, completed_units ++ returned_completed_units, failed_units ++ returned_failed_units)    
        else
          deploy_request = DeployerRequest.step_failed(deploy_request, "Deployment has failed!", "Deployment has taken over 30 minutes to complete!  Monitoring will now discontinue.")
          {{:error, "Deployment has taken over 30 minutes to complete!"}, deploy_request, remaining_units, completed_units ++ returned_completed_units, failed_units ++ returned_failed_units}
        end
      else
        monitor_remaining_units(deploy_request, monitoring_loop_cnt, remaining_units, completed_units ++ returned_completed_units, failed_units ++ returned_failed_units)            
      end
    end
  end

  @doc """
  Method to retrieve the latest state of SystemdUnits
  
  ## Options
    
  The `etcd_token` option defines the etcd cluster token

  The `old_systemd_units` option defines a List of units to retrieve
  
  ## Return Values
   
  List
  """
  @spec refresh_systemd_units(String.t(), List) :: List
  def refresh_systemd_units(etcd_token, old_systemd_units) do
    if old_systemd_units == nil do
      Logger.debug("[Milestones.Monitor] There are no units to refresh")
      []
    else
      Logger.debug("[Milestones.Monitor] Refreshing SystemdUnits...")
      unit_map = Enum.reduce old_systemd_units, %{}, fn deployed_unit, unit_map ->
        if deployed_unit == nil do
          Logger.error("[Milestones.Monitor] Unable to refresh all SystemdUnits, an invalid Unit was found in deployed_unit!")
          unit_map
        else
          Map.put(unit_map, deployed_unit.name, deployed_unit)
        end
      end

      all_units = SystemdUnit.get_units(etcd_token)
      if all_units == nil do
        Logger.error("[Milestones.Monitor] Refreshing all SystemdUnits has failed!  SystemdUnit.get_units returned an invalid array of units")
        []
      else
        Enum.reduce all_units, [], fn refreshed_unit, refreshed_units ->
          if Map.has_key?(unit_map, refreshed_unit.name) do
            refreshed_units ++ [refreshed_unit]
          else
            refreshed_units
          end
        end
      end
    end
  end

  @doc """
  Method to verify the state of a unit
  
  ## Options
  
  The `current_unit | remaining_units` option defines the SystemdUnit
  
  The `etcd_token` option defines the etcd cluster token

  The `remaining_units_to_monitor` option contains a list of units to monitor

  The `completed_units` option contains a list of units that have successfully started up  

  The `failed_units` option contains a list of units that have failed to started up
  
  ## Return Values
   
  {remaining_units_to_monitor, completed_units, failed_units}
  """
  @spec verify_unit_status([], String.t(), List, List, List) :: {List, List, List}
  def verify_unit_status([], _, remaining_units_to_monitor, completed_units, failed_units) do
    {remaining_units_to_monitor, completed_units, failed_units}
  end 

  @doc """
  Method to verify the state of a unit
  
  ## Options
  
  The `current_unit | remaining_units` option defines the SystemdUnit
  
  The `etcd_token` option defines the etcd cluster token

  The `remaining_units_to_monitor` option contains a list of units to monitor

  The `completed_units` option contains a list of units that have successfully started up  

  The `failed_units` option contains a list of units that have failed to started up
  
  ## Return Values
   
  {remaining_units_to_monitor, completed_units, failed_units}
  """
  @spec verify_unit_status(List, String.t(), List, List, List) :: {List, List, List}
  def verify_unit_status([current_unit| remaining_units] = all_units, etcd_token,  remaining_units_to_monitor, completed_units, failed_units, failure_count \\ 0) do    
    case SystemdUnit.is_launched?(current_unit) do
      true -> Logger.debug("[Milestones.Monitor] Requested service #{current_unit.name} on cluster #{etcd_token} has been launched")
      {false, "loaded"} -> 
        Logger.debug("[Milestones.Monitor] Requested service #{current_unit.name} on cluster #{etcd_token} has been loaded and is being launched...")
      {false, "inactive"} -> 
        Logger.debug("[Milestones.Monitor] Requested service #{current_unit.name} on cluster #{etcd_token} has been loaded (but not started), and is being launched...")
      {false, current_launch_state} -> 
        Logger.error("[Milestones.Monitor] Requested service #{current_unit.name} on cluster #{etcd_token} is in an incorrect state:  #{current_launch_state}")
    end
    retry = false
    case SystemdUnit.is_active?(current_unit) do
      true -> 
        Logger.debug("[Milestones.Monitor] Requested service #{current_unit.name} on cluster #{etcd_token} is active")
        completed_units = completed_units ++ [current_unit]
      {false, "activating", _, _} -> 
        Logger.debug("[Milestones.Monitor] Requested service #{current_unit.name} on cluster #{etcd_token} is starting up...")
        remaining_units_to_monitor = remaining_units_to_monitor ++ [current_unit]
      {false, nil, _, _} -> 
        Logger.debug("[Milestones.Monitor] Requested service #{current_unit.name} on cluster #{etcd_token} has not registered a status yet...")
        remaining_units_to_monitor = remaining_units_to_monitor ++ [current_unit]
      {false, active_state, load_state, "failed"} ->
        cond do
          failure_count >= 3 ->
            Logger.error("[Milestones.Monitor] Requested service #{current_unit.name} on cluster #{etcd_token} has failed to start:  #{active_state}; load state:  #{load_state}!")
            failed_units = failed_units ++ [current_unit]
          true ->
            :timer.sleep(10_000)
            retry = true
        end
      {false, active_state, load_state, sub_state} ->
        Logger.error("[Milestones.Monitor] Requested service #{current_unit.name} on cluster #{etcd_token} is #{active_state}; load state:  #{load_state}, sub state:  #{sub_state}!")
        failed_units = failed_units ++ [current_unit]
    end
    if retry do
      verify_unit_status(all_units, etcd_token, remaining_units_to_monitor, completed_units, failed_units, failure_count + 1)
    else
      verify_unit_status(remaining_units, etcd_token, remaining_units_to_monitor, completed_units, failed_units)
    end
  end 
end