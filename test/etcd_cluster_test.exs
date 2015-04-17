defmodule OpenAperture.Deployer.EtcdCluster.Test do
  use ExUnit.Case
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney

  alias OpenAperture.Deployer
  alias Deployer.EtcdCluster
  alias Deployer.SystemdUnit

  setup_all do
    ExVCR.Config.cassette_library_dir("fixture/vcr_cassettes", "fixture/custom_cassettes")
    :ok
  end

  # =======================
  # get_hosts Tests

  test "get_hosts success" do
    :meck.new(FleetApi.Machine, [:passthrough])
    :meck.expect(FleetApi.Machine, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    try do
      cluster = EtcdCluster.create!("123abc")
      assert EtcdCluster.get_hosts(cluster) == []
    after
      :meck.unload(FleetApi.Machine)
      :meck.unload(FleetApi.Discovery)
    end
  end

  test "get_hosts fail" do
    :meck.new(FleetApi.Machine, [:passthrough])
    :meck.expect(FleetApi.Machine, :list!, fn token -> raise FunctionClauseError end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    try do
      cluster = EtcdCluster.create!("123abc")
      assert EtcdCluster.get_hosts(cluster) == []
    after
      :meck.unload(FleetApi.Machine)
      :meck.unload(FleetApi.Discovery)
    end
  end

  # =======================
  # get_units Tests

  test "get_units success" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    try do
      cluster = EtcdCluster.create!("123abc")
      assert EtcdCluster.get_units(cluster) == []
    after
      :meck.unload(FleetApi.Unit)
      :meck.unload(FleetApi.Discovery)
    end
  end

  test "get_units fail" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> raise FunctionClauseError end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    try do
      cluster = EtcdCluster.create!("123abc")
      assert EtcdCluster.get_units(cluster) == nil
    after
      :meck.unload(FleetApi.Unit)
      :meck.unload(FleetApi.Discovery)
    end
  end

  # =======================
  # get_units Tests

  test "get_units_state success" do
    :meck.new(FleetApi.UnitState, [:passthrough])
    :meck.expect(FleetApi.UnitState, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    try do
      cluster = EtcdCluster.create!("123abc")
      assert EtcdCluster.get_units_state(cluster) == []
    after
      :meck.unload(FleetApi.UnitState)
      :meck.unload(FleetApi.Discovery)
    end
  end

  test "get_units_state fail" do
    :meck.new(FleetApi.UnitState, [:passthrough])
    :meck.expect(FleetApi.UnitState, :list!, fn token -> raise FunctionClauseError end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    try do
      cluster = EtcdCluster.create!("123abc")
      assert EtcdCluster.get_units_state(cluster) == []
    after
      :meck.unload(FleetApi.UnitState)
      :meck.unload(FleetApi.Discovery)
    end
  end

  # =======================
  # deploy_units

  test "deploy_units - no units" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    cluster = EtcdCluster.create!("123abc")
    new_units = []
    assert EtcdCluster.deploy_units(cluster, new_units) == []
  after
    :meck.unload(FleetApi.Unit)
    :meck.unload(FleetApi.Discovery)
  end

  test "deploy_units - no units and specify ports" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    cluster = EtcdCluster.create!("123abc")
    new_units = []
    ports = [1, 2, 3, 4, 5]
    assert EtcdCluster.deploy_units(cluster, new_units, ports) == []
  after
    :meck.unload(FleetApi.Unit)
    :meck.unload(FleetApi.Discovery)
  end

  test "deploy_units - unit without .service suffix" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}")
    new_units = [unit1]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == []
  after
    :meck.unload(FleetApi.Unit)
    :meck.unload(FleetApi.Discovery)
  end

  test "deploy_units - units with create failing" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:error, "bad news bears"} end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == []
  after
    :meck.unload(FleetApi.Unit)
    :meck.unload(FleetApi.Discovery)
    :meck.unload(SystemdUnit)
  end

  test "deploy_units - units with spinup failing" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> false end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == []
  after
    :meck.unload(FleetApi.Unit)
    :meck.unload(FleetApi.Discovery)
    :meck.unload(SystemdUnit)
  end

  test "deploy_units - success" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    :meck.new(FleetApi.Machine, [:passthrough])
    :meck.expect(FleetApi.Machine, :list!, fn token -> [%{}] end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_assigned_port, fn resolved_unit, port -> true end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == [%{}]
  after
    :meck.unload(FleetApi.Unit)
    :meck.unload(FleetApi.Discovery)
    :meck.unload(FleetApi.Machine)
    :meck.unload(SystemdUnit)
  end

  test "deploy_units - success with provided ports" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    :meck.new(FleetApi.Machine, [:passthrough])
    :meck.expect(FleetApi.Machine, :list!, fn token -> [%{}] end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_assigned_port, fn resolved_unit, port -> true end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    available_ports = [12345, 67890]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units, available_ports) == [%{}, %{}]
  after
    :meck.unload(FleetApi.Unit)
    :meck.unload(FleetApi.Discovery)
    :meck.unload(FleetApi.Machine)
    :meck.unload(SystemdUnit)
  end

  test "deploy_units - success with template options" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    :meck.new(FleetApi.Machine, [:passthrough])
    :meck.expect(FleetApi.Machine, :list!, fn token -> [%{}] end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_assigned_port, fn resolved_unit, port -> true end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit1 = Map.put(unit1, "options", [
      %{
        "value" => "<%= dst_port %>"
      }])

    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    available_ports = [12345, 67890]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units, available_ports) == [%{}, %{}]
  after
    :meck.unload(FleetApi.Unit)
    :meck.unload(FleetApi.Discovery)
    :meck.unload(FleetApi.Machine)
    :meck.unload(SystemdUnit)
  end

  test "deploy_units - teardown previous units" do
    :meck.new(FleetApi.Unit, [:passthrough])
    :meck.expect(FleetApi.Unit, :list!, fn token -> [Map.put(%{}, "name", "test_unit")] end)

    :meck.new(FleetApi.Discovery, [:passthrough])
    :meck.expect(FleetApi.Discovery, :discover_nodes, fn token -> nil end)

    :meck.new(FleetApi.Machine, [:passthrough])
    :meck.expect(FleetApi.Machine, :list!, fn token -> [%{}] end)

    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :create, fn resolved_unit -> {:ok, %{}} end)
    :meck.expect(SystemdUnit, :spinup_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_etcd_token, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :teardown_unit, fn resolved_unit, etcd_token -> true end)
    :meck.expect(SystemdUnit, :set_assigned_port, fn resolved_unit, port -> true end)

    unit1 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    unit2 = Map.put(%{}, "name", "#{UUID.uuid1()}.service")
    new_units = [unit1, unit2]
    cluster = EtcdCluster.create!("123abc")
    assert EtcdCluster.deploy_units(cluster, new_units) == [%{}]
  after
    :meck.unload(FleetApi.Unit)
    :meck.unload(FleetApi.Discovery)
    :meck.unload(FleetApi.Machine)
    :meck.unload(SystemdUnit)
  end
end
