defmodule OpenAperture.Deployer.Milestones.MonitorTest do
  use   ExUnit.Case

  alias OpenAperture.Deployer.Milestones.Monitor
  alias OpenAperture.Deployer.Request, as: DeployerRequest

  alias OpenAperture.Fleet.SystemdUnit
 
  # ==========================
  # verify_unit_status tests

  test "verify_unit_status - nothing to monitor" do
    assert Monitor.verify_unit_status([], "123abc", []) == []
  end

  test "verify_unit_status - launched and active" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)
    

    assert Monitor.verify_unit_status([%{}], "123abc", []) == []
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - loaded and active" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> {false, "loaded"} end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)
    

    assert Monitor.verify_unit_status([%{}], "123abc", []) == []
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - loaded and active 2" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> {false, "loaded"} end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)
    

    assert Monitor.verify_unit_status([%{}], "123abc", []) == []
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - inactive (launched) and active" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> {false, "inactive"} end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)
    

    assert Monitor.verify_unit_status([%{}], "123abc", []) == []
  after
    :meck.unload(SystemdUnit)
  end  

  test "verify_unit_status - unknown and active" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> {false, "unknown"} end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> true end)
    

    assert Monitor.verify_unit_status([%{}], "123abc", []) == []
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - launched and activating" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, "activating", nil, nil} end)
    

    assert Monitor.verify_unit_status([%{}], "123abc", []) == [%{}]
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - launched and not registered" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, nil, nil, nil} end)
    

    assert Monitor.verify_unit_status([%{}], "123abc", []) == [%{}]
  after
    :meck.unload(SystemdUnit)
  end  

  test "verify_unit_status - launched and unknown, successful journal" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, "unknown", "load_state", "sub_state"} end)
    :meck.expect(SystemdUnit, :get_journal, fn _ -> {:ok, "stdout", "stderr"} end) 

    assert Monitor.verify_unit_status([%{}], "123abc", []) == []
  after
    :meck.unload(SystemdUnit)
  end

  test "verify_unit_status - launched and unknown, unsuccessful journal" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, "unknown", "load_state", "sub_state"} end)
    :meck.expect(SystemdUnit, :get_journal, fn _ -> {:error, "stdout", "stderr"} end) 

    assert Monitor.verify_unit_status([%{}], "123abc", []) == []
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
    :meck.expect(DeployerRequest, :publish_success_notification, fn _,_ -> :deployer_request end)
    :meck.expect(DeployerRequest, :step_completed, fn _ -> deployer_request end)

    returned_request = Monitor.monitor(deployer_request, 0)
    assert returned_request != nil
  after
    :meck.unload(DeployerRequest)
  end

  test "monitor - remaining deployments, expired time" do
    :meck.new(SystemdUnit, [:passthrough])
    :meck.expect(SystemdUnit, :set_etcd_token, fn _,_ -> :ok end)
    :meck.expect(SystemdUnit, :refresh, fn _ -> :ok end)
    :meck.expect(SystemdUnit, :get_unit_name, fn _ -> "test unit" end)
    :meck.expect(SystemdUnit, :is_launched?, fn _ -> true end)
    :meck.expect(SystemdUnit, :is_active?, fn _ -> {false, nil, nil, nil} end)

    deployer_request = %DeployerRequest{
      etcd_token: "123abc",
      deployed_units: [%{}]
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
end