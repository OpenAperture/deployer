defmodule OpenAperture.Deployer.Milestones.MonitorTest do
  use   ExUnit.Case

  alias OpenAperture.Deployer.Milestones.Monitor
  alias OpenAperture.Deployer.Request, as: DeployerRequest

  alias OpenAperture.Fleet.SystemdUnit

  # ==========================
  # verify_unit_status tests

  test "verify_unit_status - nothing to monitor" do
    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 0
    assert length(completed_units) == 0
    assert length(failed_units) == 0    
  end

  test "verify_unit_status - launched and active" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)
    

    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{}], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 0
    assert length(completed_units) == 1
    assert length(failed_units) == 0
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - loaded and active" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> {false, "loaded"} end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)
    
    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{}], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 0
    assert length(completed_units) == 1
    assert length(failed_units) == 0
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - loaded and active 2" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> {false, "loaded"} end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)   

    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{}], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 0
    assert length(completed_units) == 1
    assert length(failed_units) == 0
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - inactive (launched) and active" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> {false, "inactive"} end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)
    
    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{}], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 0
    assert length(completed_units) == 1
    assert length(failed_units) == 0    
  after
    :meck.unload(SystemdUnit)
  end  

  test "verify_unit_status - unknown and active" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> {false, "unknown"} end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)
    
    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{}], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 0
    assert length(completed_units) == 1
    assert length(failed_units) == 0
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - launched and activating" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, "activating", nil, nil} end)
    
    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{}], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 1
    assert length(completed_units) == 0
    assert length(failed_units) == 0    
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - launched and not registered" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, nil, nil, nil} end)
    
    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{}], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 1
    assert length(completed_units) == 0
    assert length(failed_units) == 0
  after
    :meck.unload(SystemdUnit)
  end  

  test "verify_unit_status - launched and unknown" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, "unknown", "load_state", "sub_state"} end)
    :meck.expect(SystemdUnit, :get_journal, fn _ -> {:ok, "stdout", "stderr"} end) 

    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{}], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 0
    assert length(completed_units) == 0
    assert length(failed_units) == 1
  after
    :meck.unload(SystemdUnit)
  end

  @tag timeout: 45_000
  test "verify_unit_status - launched and failed" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, "unknown", "load_state", "failed"} end)
    :meck.expect(SystemdUnit, :get_journal, fn _ -> {:ok, "stdout", "stderr"} end) 
    unit_name = "#{UUID.uuid1()}"
    :meck.expect(SystemdUnit, :get_units, fn _ -> [%SystemdUnit{name: unit_name, systemdActiveState: "failed"}] end)

    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{name: unit_name, systemdActiveState: "failed"}], "123abc", [], [], [])
    assert length(remaining_units_to_monitor) == 0
    assert length(completed_units) == 0
    assert length(failed_units) == 1
  after
    :meck.unload(SystemdUnit)
  end

  # ================================
  # monitor tests

  test "monitor - no remaining deployments" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)
    :meck.expect(DeployerRequest, :step_completed, fn _ -> deployer_request end)

    returned_request = Monitor.monitor(deployer_request, 0)
    assert returned_request != nil
  after
    :meck.unload(DeployerRequest)
  end

  test "monitor - remaining deployments, expired time" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :get_units, fn _ -> [%SystemdUnit{}] end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, nil, nil, nil} end)

    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: [%SystemdUnit{}]
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)
    :meck.expect(DeployerRequest, :step_failed, fn _,_,_ -> deployer_request end)    
    :meck.expect(DeployerRequest, :save_workflow, fn req -> req end)

    returned_request = Monitor.monitor(deployer_request, 30)
    assert returned_request != nil
  after
    :meck.unload(DeployerRequest)
    :meck.unload(SystemdUnit)
  end  

  # ================================
  # monitor_remaining_units tests

  test "monitor_remaining_units - no remaining deployments" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> :deployer_request end)
    :meck.expect(DeployerRequest, :step_completed, fn _ -> deployer_request end)

    returned_request = Monitor.monitor_remaining_units(deployer_request, 0, [], [], [])
    assert returned_request != nil
  after
    :meck.unload(DeployerRequest)
  end

  test "monitor_remaining_units - remaining deployments, expired time" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :get_units, fn _ -> [%SystemdUnit{}] end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, nil, nil, nil} end)

    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: [%SystemdUnit{}]
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)
    :meck.expect(DeployerRequest, :step_failed, fn _,_,_ -> deployer_request end)    
    :meck.expect(DeployerRequest, :save_workflow, fn req -> req end)

    returned_request = Monitor.monitor_remaining_units(deployer_request, 30, [%SystemdUnit{}], [], [])
    assert returned_request != nil
  after
    :meck.unload(DeployerRequest)
    :meck.unload(SystemdUnit)
  end  

  # ================================
  # log_failed_units tests

  test "log_failed_units - no failed units" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    returned_request = Monitor.log_failed_units(deployer_request, [])
    assert returned_request != nil
  end

  test "log_failed_units - single failed units" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :get_journal, fn _ -> {:ok, "stdout", "stderr"} end)

    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_failure_notification, fn _,_,_ -> deployer_request end)  
    
    failed_units = [
      %SystemdUnit{

      }
    ]

    returned_request = Monitor.log_failed_units(deployer_request, failed_units)
    assert returned_request != nil
  after
    :meck.unload(SystemdUnit)    
    :meck.unload(DeployerRequest)
  end  

  test "log_failed_units - multiple failed units" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :get_journal, fn _ -> {:ok, "stdout", "stderr"} end)

    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_failure_notification, fn _,_,_ -> deployer_request end)  
    
    failed_units = [
      %SystemdUnit{},
      %SystemdUnit{}
    ]

    returned_request = Monitor.log_failed_units(deployer_request, failed_units)
    assert returned_request != nil
  after
    :meck.unload(SystemdUnit)    
    :meck.unload(DeployerRequest)
  end

  test "log_failed_units - multiple failed units and journal failure" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :get_journal, fn _ -> {:error, "stdout", "stderr"} end)

    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_failure_notification, fn _,_,_ -> deployer_request end)  
    
    failed_units = [
      %SystemdUnit{},
      %SystemdUnit{}
    ]

    returned_request = Monitor.log_failed_units(deployer_request, failed_units)
    assert returned_request != nil
  after
    :meck.unload(SystemdUnit)    
    :meck.unload(DeployerRequest)
  end

  # ================================
  # log_completed_units tests

  test "log_completed_units - no units" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)  

    returned_request = Monitor.log_completed_units(deployer_request, [])
    assert returned_request != nil
  after  
    :meck.unload(DeployerRequest)    
  end

  test "log_completed_units - single unit" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)  
    
    completed_units = [
      %SystemdUnit{}
    ]

    returned_request = Monitor.log_completed_units(deployer_request, completed_units)
    assert returned_request != nil
  after  
    :meck.unload(DeployerRequest)
  end  

  test "log_completed_units - multiple units" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)  
    
    completed_units = [
      %SystemdUnit{},
      %SystemdUnit{}
    ]

    returned_request = Monitor.log_completed_units(deployer_request, completed_units)
    assert returned_request != nil
  after
  
    :meck.unload(DeployerRequest)
  end  

  # ================================
  # log_monitoring_result tests

  test "log_monitoring_result - success with no units" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }
    
    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :step_completed, fn _ -> deployer_request end)  

    completed_units = []
    num_requested_monitoring_units = 0
    returned_request = Monitor.log_monitoring_result(deployer_request, :ok, completed_units, num_requested_monitoring_units)
    assert returned_request != nil
  after  
    :meck.unload(DeployerRequest)    
  end  

  test "log_monitoring_result - failed with no units" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }
    
    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :step_failed, fn _,_,_ -> deployer_request end)  

    completed_units = []
    num_requested_monitoring_units = 0
    returned_request = Monitor.log_monitoring_result(deployer_request, {:error, "bad news bears"}, completed_units, num_requested_monitoring_units)
    assert returned_request != nil
  after  
    :meck.unload(DeployerRequest)    
  end    

  test "log_monitoring_result - failed with expected units" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }
    
    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :step_failed, fn _,_,_ -> deployer_request end)  

    completed_units = []
    num_requested_monitoring_units = 10
    returned_request = Monitor.log_monitoring_result(deployer_request, :ok, completed_units, num_requested_monitoring_units)
    assert returned_request != nil
  after  
    :meck.unload(DeployerRequest)    
  end      

  # ================================
  # log_requested_units tests

  test "log_requested_units - no units" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: []
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)  

    returned_request = Monitor.log_requested_units(deployer_request, 0)
    assert returned_request != nil
  after  
    :meck.unload(DeployerRequest)    
  end

  test "log_requested_units - single unit" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: [%SystemdUnit{}]
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)  
    
    returned_request = Monitor.log_requested_units(deployer_request, 1)
    assert returned_request != nil
  after  
    :meck.unload(DeployerRequest)
  end  

  test "log_requested_units - multiple units" do
    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: [%SystemdUnit{},
      %SystemdUnit{}]
    }

    :meck.new(DeployerRequest, [:passthrough])
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> deployer_request end)  
    
    returned_request = Monitor.log_requested_units(deployer_request, 2)
    assert returned_request != nil
  after
  
    :meck.unload(DeployerRequest)
  end 


end