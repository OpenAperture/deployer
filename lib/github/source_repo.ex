defmodule OpenAperture.Deployer.SourceRepo do
  @moduledoc """
  Interacts with a target application source code repo.
  """
  require Logger
  alias   OpenAperture.Deployer
  alias   Deployer.DeploymentRepo
  alias   Deployer.Github

  @doc """
  Creates a new Agent process for representing a source code repo of a target
  application.
  ## Options

  The `options` option defines the information needed to download and interact with a OpenAperture deployment repo.
  The following values are accepted:
    * repo - (required) String containing the repo org and name:  org/myapp-deploy
    * repo_branch - (optional) - String containing the commit/tag/branch to be used.  Defaults to 'master'

  ## Return values

  If the server is successfully created and initialized, the function returns
  `{:ok, pid}`, where pid is the pid of the server. If there already exists a
  process with the specified server name, the function returns
  `{:error, {:already_started, pid}}` with the pid of that process.

  If the `init/1` callback fails with `reason`, the function returns
  `{:error, reason}`. Otherwise, if it returns `{:stop, reason}`
  or `:ignore`, the process is terminated and the function returns
  `{:error, reason}` or `:ignore`, respectively.
  """
  @spec create(Map) :: {:ok, pid} | {:error, String.t()}
  def create(options) do
    request_id = "#{UUID.uuid1()}"
    output_dir = "/tmp/openaperture/source_repos/#{request_id}"
    options    = options |> Map.merge(%{output_dir: output_dir})

    cond do
      options[:request_id]  == nil ->
        options = options |> Map.merge(%{request_id: request_id})
      options[:repo_branch] == nil ->
        options = options |> Map.merge(%{repo_branch: "master"})
    end

    Agent.start_link(fn -> options end)
  end

  @doc """
  Method to generate a new source repo

  ## Options

  The `options` option defines the information needed to download and interact with a OpenAperture deployment repo.
  The following values are accepted:
    * repo - (required) String containing the repo org and name:  org/myapp-deploy
    * repo_branch - (optional) - String containing the commit/tag/branch to be used.  Defaults to 'master'

  ## Return Values

  pid
  """
  @spec create!(Map) :: pid
  def create!(options) do
    case create(options) do
      {:ok, source_repo} -> source_repo
      {:error, reason} -> raise "Failed to create OpenApertureBuildServer.Agents.SourceRepo:  #{reason}"
    end
  end

  @doc """
  Method to get the unique request id for the repository

  ## Return Values

  String
  """
  @spec get_request_id(pid) :: String.t()
  def get_request_id(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    repo_options[:request_id]
  end

  @doc """
  Method to cleanup any artifacts associated with the deploy repo PID

  ## Options

  The `repo` option defines the repo PID
  """
  @spec cleanup(pid) :: term
  def cleanup(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    File.rm_rf(repo_options[:output_dir])
  end

  @doc """
  Method to get the deploy repo name associated with the PID

  ## Return Values

  String
  """
  @spec get_repo_name(pid) :: String.t()
  def get_repo_name(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    repo_options[:repo]
  end

  @doc """
  Method to get the git ref (commit, branch, tag) associated with the repo

  ## Return Values

  String
  """
  @spec get_git_ref(pid) :: String.t()
  def get_git_ref(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    repo_options[:repo_branch]
  end

  @doc """
  Method to download a local copy of the deployment repo and checkout to the correct version.
  To prevent parallel downloads we store the download status in the Agent's repo storage

  ## Options

  The `repo` option defines the repo PID

  ## Return values

  :ok or tuple with {:error, reason}
  """
  @spec download(pid) :: :ok | {:error, String.t()}
  def download(repo) do
    repo_options = Agent.get(repo, fn options -> options end)

    case repo_options[:download_status] do
      nil ->
        try do
          repo_options = Map.merge(repo_options, %{download_status: :in_progress})
          Agent.update(repo, fn _ -> repo_options end)

          case Github.create(%{output_dir: repo_options[:output_dir], repo_url: Github.resolve_github_repo_url(repo_options[:repo]), branch: repo_options[:repo_branch]}) do
            {:ok, github} ->
              repo_options = Map.merge(repo_options, %{github: github})
              Agent.update(repo, fn _ -> repo_options end)

              case Github.clone(github) do
                :ok ->
                  case Github.checkout(github) do
                    :ok ->
                      downloaded_files = File.ls!(repo_options[:output_dir])
                      Logger.debug("Git clone and checkout of repository #{repo_options[:container_repo]} has downloaded the following files:  #{inspect downloaded_files}")
                      :ok
                    {:error, reason} ->
                      repo_options = Map.merge(repo_options, %{download_error: reason})
                      Agent.update(repo, fn _ -> repo_options end)
                      {:error, reason}
                  end
                {:error, reason} ->
                  repo_options = Map.merge(repo_options, %{download_error: reason})
                  Agent.update(repo, fn _ -> repo_options end)
                  {:error, reason}
              end
            {:error, reason} ->
              repo_options = Map.merge(repo_options, %{download_error: reason})
              Agent.update(repo, fn _ -> repo_options end)
              {:error, reason}
          end
        after
          # make sure that we have all of the options that were saved during recursion
          final_options = Agent.get(repo, fn options -> options end)
          final_options = %{final_options | download_status: :finished}
          Agent.update(repo, fn _ -> final_options end)
        end
      :in_progress ->
        Logger.debug("Download is already in progress. Sleeping for 1s...")
        :timer.sleep(1000)
        download(repo)
      :finished ->
        Logger.debug("The sources have already been downloaded")
        final_options = Agent.get(repo, fn options -> options end)
        if final_options[:download_error] == nil do
          :ok
        else
          {:error, final_options[:download_error]}
        end
    end
  end

  @doc """
  Method to retrieve OpenAperture repo info from the output directory

  ## Options

  The 'repo' option defines the repo PID

  ## Return values

  Map
  """
  @spec get_container_repo_info(pid) :: {:ok, pid} | {:error, String.t()}
  def get_container_repo_info(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    resolve_container_repo_info(repo_options[:output_dir])
  end

  @doc """
  Method to determine the OpenAperture deployment repo from the source repo.

  ## Options

  The `repo` option defines the repo PID

  ## Return values

  tuple with {:ok, pid} or {:error, reason}
  """
  @spec get_deployment_repo(pid) :: {:ok, pid} | {:error, String.t()}
  def get_deployment_repo(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    if (repo_options[:deployment_repo] != nil) do
      repo_options[:deployment_repo]
    else
      container_repo_info = resolve_container_repo_info(repo_options[:output_dir])

      if container_repo_info do
        container_repo = container_repo_info["deployments"]["container_repo"]
        container_repo_branch = container_repo_info["deployments"]["container_repo_branch"]
        if container_repo do
          #container_repo_branch will default to master if not present
          deployment_repo = DeploymentRepo.create(%{container_repo: container_repo, container_repo_branch: container_repo_branch})
          repo_options = Map.merge(repo_options, %{deployment_repo: deployment_repo})
          Agent.update(repo, fn _ -> repo_options end)
          deployment_repo
        else
          {:error, "container.json (aka cloudos.json) is invalid! Make sure both the repo and default branch are specified"}
        end
      else
        {:error, "container.json (aka cloudos.json) is either missing or invalid!"}
      end
    end
  end

  @spec resolve_container_repo_info(String.t()) :: Map
  defp resolve_container_repo_info(source_dir) do
    json_path =
      config_path(source_dir, "container.json") ||
      config_path(source_dir, "cloudos.json")

    Logger.info("Resolving continer repo info from #{json_path}...")
    if json_path do
      case File.read!(json_path) |> JSON.decode do
        {:ok, json} -> json
        {:error, reason} ->
          "An error occurred parsing deployment.json: #{inspect reason}"
            |> Logger.error
          nil
      end
    else
      nil
    end
  end

  defp config_path(source_dir, file) do
    Path.join(source_dir, file) |> File.exists?
  end
end
