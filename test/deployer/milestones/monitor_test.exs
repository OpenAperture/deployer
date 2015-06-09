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

  test "verify_unit_status - launched and failed" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, "unknown", "load_state", "failed"} end)
    :meck.expect(SystemdUnit, :get_journal, fn _ -> {:ok, "stdout", "stderr"} end) 

    {remaining_units_to_monitor, completed_units, failed_units} = Monitor.verify_unit_status([%SystemdUnit{}], "123abc", [], [], [])
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

    returned_request = Monitor.monitor_remaining_units(deployer_request, 30, [%SystemdUnit{}], [], [])
    assert returned_request != nil
  after
    :meck.unload(DeployerRequest)
    :meck.unload(SystemdUnit)
  end  
end