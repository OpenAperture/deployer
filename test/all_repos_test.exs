defmodule OpenAperture.Deployer.AllRepos.Test do
  use ExUnit.Case, async: true

  alias OpenAperture.Deployer
  alias Deployer.Github
  alias Deployer.Docker
  alias Deployer.SourceRepo
  alias Deployer.DeploymentRepo

  setup do
    source_repo = SourceRepo.create!(%{
      repo: "OpenAperture/workflow_orchestrator",
      repo_branch: "master"
    })

    deployment_repo = DeploymentRepo.create!(%{
      container_repo: "OpenAperture/workflow_orchestrator_docker",
      container_repo_branch: "master"
    })

    {:ok, source_repo: source_repo, deployment_repo: deployment_repo}
  end

  test "get_deployment_repo(pid) returns proper JSON if container.json is OK", %{source_repo: source_repo} do
    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> JSON.encode!(%{
      deployments: %{
        container_repo: "OpenAperture/workflow_orchestrator_docker",
        container_repo_branch: "master"
      }
    }) end)
    :meck.expect(File, :ls!, fn _ -> [] end)

    {:ok, pid} = SourceRepo.get_deployment_repo(source_repo)
    assert is_pid pid
  after
    :meck.unload(File)
  end

  test "get_deployment_repo(source_repo) returns an error when container.json is invalid ", %{source_repo: source_repo} do
    :meck.new(File, [:unstick, :passthrough])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> "this isn't actually json" end)

    # bad json
    {result, message} = SourceRepo.get_deployment_repo(source_repo)
    assert result  == :error
    assert message == "container.json (aka cloudos.json) is either missing or invalid!"

  after
    :meck.unload(File)
  end

  test "get_deployment_repo(repo) returns an error when repo is missing ", %{source_repo: source_repo} do
    :meck.new(File, [:unstick, :passthrough])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> JSON.encode!(%{
      :deployments =>
        %{
          container_repo_branch: "master"
      }
    }) end)

    # no repo
    {result, message} = SourceRepo.get_deployment_repo(source_repo)
    assert result  == :error
    assert message == "container.json (aka cloudos.json) is invalid! Make sure both the repo and default branch are specified"
  after
    :meck.unload(File)
  end

  test "get_deployment_repo(repo) returns an error when file is missing ", %{source_repo: source_repo} do
    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> false end)

    # no file
    {result, message} = SourceRepo.get_deployment_repo(source_repo)
    assert result  == :error
    assert message == "container.json (aka cloudos.json) is either missing or invalid!"
  after
    :meck.unload(File)
  end

  test "get_deployment_repo(repo) returns ok when branch is missing ", %{source_repo: source_repo} do
    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> JSON.encode!(%{
      deployments: %{container_repo: "OpenAperture/workflow_orchestrator"}
    }) end)

    # no branch
    {result, deployment_repo} = SourceRepo.get_deployment_repo(source_repo)
    assert result  == :ok
    assert is_pid deployment_repo
  after
    :meck.unload(File)
  end

  test "get_deployment_repo(source_repo) returns ok", %{source_repo: source_repo} do
    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> JSON.encode!(%{
      deployments: %{
          container_repo: "OpenAperture/workflow_orchestrator",
          container_repo_branch: "dev"
      }
    }) end)

    {result, deployment_repo} = SourceRepo.get_deployment_repo(source_repo)
    assert result  == :ok
    assert is_pid deployment_repo
  after
    :meck.unload(File)
  end

  test "get_docker_repo_name(source_repo) already cached" do
    deployment_repo = DeploymentRepo.create!(%{
      container_repo: "OpenAperture/workflow_orchestrator_docker",
      container_repo_branch: "master",
      docker_repo_name: "testreponame"
    })
    assert DeploymentRepo.get_docker_repo_name(deployment_repo) == "testreponame"
  end

  test "get_docker_repo_name(repo) file does not exist" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> false end)

    deployment_repo = DeploymentRepo.create!(%{
      container_repo: "OpenAperture/workflow_orchestrator_docker",
      container_repo_branch: "master"
    })
    assert DeploymentRepo.get_docker_repo_name(deployment_repo) == ""
  after
    :meck.unload(File)
  end

  test "get_docker_repo_name(repo) bad json" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> "this is not json" end)

    deployment_repo = DeploymentRepo.create!(%{
      container_repo: "OpenAperture/workflow_orchestrator_docker",
      container_repo_branch: "master"
    })
    assert DeploymentRepo.get_docker_repo_name(deployment_repo) == ""
  after
    :meck.unload(File)
  end

  test "get_docker_repo_name(deployment_repo) success" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> JSON.encode!(%{docker_url: "testreponame"}) end)

    deployment_repo = DeploymentRepo.create!(%{
      container_repo: "OpenAperture/workflow_orchestrator_docker",
      container_repo_branch: "master"
    })
    assert DeploymentRepo.get_docker_repo_name(deployment_repo) == "testreponame"
  after
    :meck.unload(File)
  end

  test "get_docker_repo_name(deployment_repo) not in json" do
    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> false end)
    :meck.expect(File, :read!, fn _ -> JSON.encode!(%{}) end)

    deployment_repo = DeploymentRepo.create!(%{
      container_repo: "OpenAperture/workflow_orchestrator_docker",
      container_repo_branch: "master"
    })
    assert DeploymentRepo.get_docker_repo_name(deployment_repo) == ""
  after
    :meck.unload(File)
  end

  test "get_source_repo(deployment_repo) returns the PID of created SourceRepo
    instance when source.json is OK", %{deployment_repo: deployment_repo} do

    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> JSON.encode!(%{
      source_repo: "OpenAperture/workflow_orchestrator",
      source_repo_branch: "master"
    }) end)
    :meck.expect(File, :ls!, fn _ -> [] end)

    {:ok, pid} = DeploymentRepo.get_source_repo(deployment_repo)
    assert is_pid pid
  after
    :meck.unload(File)
  end

  test "get_source_repo(repo) returns an error when source.json is invalid json",
    %{deployment_repo: repo} do

    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> "this isn't actually json" end)

    # bad json
    {result, message} = DeploymentRepo.get_source_repo(repo)
    assert result  == :error
    assert message == "source.json is either missing or invalid!"
  after
    :meck.unload(File)
  end

  test "get_source_repo(repo) returns an error when source.json has no repo",
    %{deployment_repo: deployment_repo} do

    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> JSON.encode!(%{
      source_repo_branch: "master"
    }) end)

    # no repo
    {result, message} = DeploymentRepo.get_source_repo(deployment_repo)
    assert result  == :error
    assert message == "source.json is invalid! Make sure both the repo and default branch are specified"
  after
    :meck.unload(File)
  end

  test "get_source_repo(repo) returns :ok when source.json has no branch",
    %{deployment_repo: repo} do

    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> true end)
    :meck.expect(File, :read!, fn _ -> JSON.encode!(%{
      source_repo: "OpenAperture/workflow_orchestrator"
    }) end)

    # no branch
    {result, repo} = DeploymentRepo.get_source_repo(repo)
    assert result  == :ok
    assert is_pid repo
  after
    :meck.unload(File)
  end

  test "get_source_repo(repo) returns an error when source.json has no file",
    %{source_repo: source_repo} do

    :meck.new(File, [:unstick])
    :meck.expect(File, :exists?, fn _ -> false end)

    # no file
    {result, message} = DeploymentRepo.get_source_repo(source_repo)
    assert result  == :error
    assert message == "source.json is either missing or invalid!"
  after
    :meck.unload(File)
  end

  test "repo is downloaded for multiple times", %{deployment_repo: deployment_repo} do
    # nothing is getting downloaded
    assert Agent.get(deployment_repo, &(&1))[:download_status] == nil

    # run 1st downloading
    Task.async(fn -> DeploymentRepo.download(deployment_repo) end)
    :timer.sleep(100)

    github_pid = Agent.get(deployment_repo, fn options -> options end)[:github]
    assert is_pid github_pid

    # run the 2nd and ensure no github process has been started meanwhile
    assert Agent.get(deployment_repo, &(&1)).github == github_pid
    assert Agent.get(deployment_repo, &(&1)).download_status == :in_progress

    # complete downloading
    assert DeploymentRepo.download(deployment_repo) == :ok
    assert Agent.get(deployment_repo, &(&1))[:download_status] == :finished
  end
end
