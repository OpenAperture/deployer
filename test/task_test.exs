defmodule OpenAperture.Deployer.Task.Test do
  use   ExUnit.Case

  alias OpenAperture.Deployer
  alias Deployer.DeploymentRepo
  alias Deployer.EtcdCluster
  alias Deployer.GitHub
  alias Deployer.Notifications
  alias Deployer.Task.Supervisor

  setup do
    {:ok, sup} = Supervisor.start_link
    details    = %{
      source_commit_hash: "6441611f3ee2a3542b6b46ad7c82904d2cf24786",
      container_repo: "Perceptive-Cloud/cloudos-ui_docker"
    }
    {:ok, supervisor: sup, details: details}
  end

  test "SV spawns a new deployment task", %{supervisor: sup, details: details} do
    assert {:ok, pid} = Supervisor.execute_task(sup, details)
  end

  test "deploy() crashes when no deployment_repo provided" do
    assert_raise RuntimeError, fn -> Deployer.Task.deploy(%{}) end
  end

  test "deploy() failes when the source repo is incorrect" do
    repo    = DeploymentRepo.create!(%{source_repo: "some_repo"})
    details = %{deployment_repo: repo}

    :meck.new(GitHub, [:passthrough])
    :meck.expect(GitHub, :resolve_repo_url, fn(_) -> "http://dummy.url" end)
    :meck.expect(GitHub, :clone, fn(_) -> :ok end)

    assert_raise CaseClauseError, fn -> Deployer.Task.deploy(details) end
  after
    :meck.unload(GitHub)
  end

  test "deploy() fails when no units are associated with the repo" do
    repo    = DeploymentRepo.create!(%{source_repo: "some_repo"})
    details = %{deployment_repo: repo}

    :meck.new(GitHub, [:passthrough])
    :meck.expect(GitHub, :resolve_repo_url, fn(_) -> "http://dummy.url" end)
    :meck.expect(GitHub, :clone, fn(_) -> :ok end)
    :meck.expect(GitHub, :checkout, fn(_) -> :ok end)

    :meck.new(File, [:passthrough])
    :meck.expect(File, :ls!, fn(_) -> {:one, :two} end)

    :meck.new(Notifications)
    :meck.expect(Notifications, :send, fn(_) -> :ok end)

    assert Deployer.Task.deploy(details) ==
      {:error, "no hosts associated with the repo"}

    after
      [GitHub, File, Notifications] |> Enum.each(&:meck.unload(&1))
  end

  test "deploy() under normal conditions" do
    repo    = DeploymentRepo.create!(%{source_repo: "some_repo"})
    details = %{deployment_repo: repo}

    :meck.new(GitHub, [:passthrough])
    :meck.expect(GitHub, :resolve_repo_url, fn(_) -> "http://dummy.url" end)
    :meck.expect(GitHub, :clone, fn(_) -> :ok end)
    :meck.expect(GitHub, :checkout, fn(_) -> :ok end)

    :meck.new(File, [:passthrough])
    :meck.expect(File, :ls!, fn(_) -> {:one, :two} end)

    :meck.new(EtcdCluster, [:passthrough])
    :meck.expect(EtcdCluster, :get_host_count, fn(_) -> 314 end)
    :meck.expect(EtcdCluster, :deploy_units, fn(_, _, _) -> :units end)

    :meck.new(DeploymentRepo, [:passthrough])
    :meck.expect(DeploymentRepo, :get_etcd_cluster, fn(_) -> :cluster end)
    :meck.expect(DeploymentRepo, :get_units, fn(_) -> [:one] end)

    assert Deployer.Task.deploy(details) == :ok
  after
    [GitHub, File, EtcdCluster, DeploymentRepo] |> Enum.each &(:meck.unload(&1))
  end
end
