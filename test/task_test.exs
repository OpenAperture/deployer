defmodule OpenAperture.Deployer.Task.Test do
  use   ExUnit.Case

  alias OpenAperture.Deployer
  alias Deployer.DeploymentRepo
  alias Deployer.EtcdCluster
  alias Deployer.GitHub
  alias Deployer.Notifications
  alias Deployer.Task.Supervisor
  alias OpenAperture.Messaging.AMQP.SubscriptionHandler

  setup do
    {:ok, sup} = Supervisor.start_link
    details    = %{
      source_commit_hash: "6441611f3ee2a3542b6b46ad7c82904d2cf24786",
      container_repo: "Perceptive-Cloud/cloudos-ui_docker",
      delivery_tag: 314,
      subscription_handler: fn -> end,
      reporting_queue: "orchestration",
      workflow_id: 314
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
    details = %{deployment_repo: repo, delivery_tag: 314, subscription_handler: fn -> end }

    [GitHub, File, Notifications] |> Enum.each(&:meck.new(&1, [:passthrough]))

    :meck.expect(GitHub, :resolve_repo_url, fn(_) -> "http://dummy.url" end)
    :meck.expect(GitHub, :clone, fn(_) -> :ok end)
    :meck.expect(GitHub, :checkout, fn(_) -> :ok end)
    :meck.expect(File, :ls!, fn(_) -> {:one, :two} end)
    :meck.expect(Notifications, :send_hipchat, fn(_) -> :ok end)

    assert Deployer.Task.deploy(details) ==
      {:error, "no hosts associated with the repo"}

    after
      [GitHub, File, Notifications] |> Enum.each(&:meck.unload(&1))
  end

  test "deploy() under normal conditions", %{details: details} do
    repo    = DeploymentRepo.create!(%{source_repo: "some_repo"})
    details = details |> Map.merge(%{deployment_repo: repo})

    [GitHub, File, EtcdCluster, DeploymentRepo, SubscriptionHandler,
      Notifications] |> Enum.each(&:meck.new(&1, [:passthrough]))

    :meck.expect(GitHub, :resolve_repo_url, fn(_) -> "http://dummy.url" end)
    :meck.expect(GitHub, :clone, fn(_) -> :ok end)
    :meck.expect(GitHub, :checkout, fn(_) -> :ok end)
    :meck.expect(File, :ls!, fn(_) -> {:one, :two} end)
    :meck.expect(EtcdCluster, :get_host_count, fn(_) -> 314 end)
    :meck.expect(EtcdCluster, :deploy_units, fn(_, _, _) -> :units end)
    :meck.expect(DeploymentRepo, :get_etcd_cluster, fn(_) -> :cluster end)
    :meck.expect(DeploymentRepo, :get_units, fn(_) -> [:one] end)
    :meck.expect(SubscriptionHandler, :acknowledge, fn(_, _) -> :ok end)
    :meck.expect(Notifications, :send_hipchat, fn(_) -> :ok end)
    :meck.expect(Notifications, :send, fn(_, _) -> :ok end)

    assert Deployer.Task.deploy(details) == :ok
  after
    [GitHub, File, EtcdCluster, DeploymentRepo, SubscriptionHandler]
      |> Enum.each &(:meck.unload(&1))
  end
end
