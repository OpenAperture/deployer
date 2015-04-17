defmodule OpenAperture.Deployer.DeploymentRepo do
  @moduledoc """
  Implements Repo Agent.
  """

  require Logger

  alias OpenAperture.Deployer
  alias Deployer.Docker
  alias Deployer.EtcdCluster
  alias Deployer.GitHub
  alias Deployer.SourceRepo

  @doc """
  Starts Repo Agent.

  Returns `{:ok, pid}` or `{:error, reason}` or other GenServer error msg.
  See corresponding docs for details.
  """
  @spec create(Map) :: {:ok, pid} | {:error, String.t()}
  def create(options \\ []) do
    request_id       = "#{UUID.uuid1()}"
    output_dir       = "/tmp/openaperture/deployment_repos/#{request_id}"
    resolved_options = Map.merge(options, %{output_dir: output_dir})

    unless resolved_options[:container_repo_branch] do
      resolved_options = resolved_options
                         |> Map.merge %{container_repo_branch: "master"}
    end

    unless resolved_options[:request_id] do
      resolved_options = resolved_options |> Map.merge %{request_id: request_id}
    end

    Logger.info("Starting #{__MODULE__}...")
    Agent.start_link(fn -> resolved_options end)
  end

  @doc """
  Method to generate a new deployment repo

  ## Options

  The `options` option defines the information needed to download and interact with a OpenAperture deployment repo.
  The following values are accepted:
    * container_repo - (required) String containing the repo org and name:  Perceptive-Cloud/myapp-deploy
    * container_repo_branch - (optional) - String containing the commit/tag/branch to be used.  Defaults to 'master'

  ## Return Values

  pid
  """
  @spec create!(Map) :: pid
  def create!(options) do
    case create(options) do
      {:ok, deployment_repo} -> deployment_repo
      {:error, reason} -> raise "Failed to create #{__MODULE__}:  #{reason}"
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
  Method to get the output directory

  ## Return Values

  String
  """
  @spec get_output_dir(pid) :: String.t()
  def get_output_dir(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    repo_options[:output_dir]
  end

  @doc """
  Method to cleanup any artifacts associated with the deploy repo PID

  ## Options

  The `repo` option defines the repo PID
  """
  @spec cleanup(pid) :: term
  def cleanup(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    if (repo_options[:output_dir] != nil && String.length(repo_options[:output_dir]) > 0) do
      File.rm_rf(repo_options[:output_dir])
    end
  end

  @doc """
  Method to get the deploy repo name associated with the PID

  ## Return Values

  String
  """
  @spec get_repo_name(pid) :: String.t()
  def get_repo_name(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    repo_options[:container_repo]
  end

  @doc """
  Method to get the git ref (commit, branch, tag) associated with the repo

  ## Return Values

  String
  """
  @spec get_git_ref(pid) :: String.t()
  def get_git_ref(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    repo_options[:container_repo_branch]
  end

  @doc """
  Method to download a local copy of the deployment repo and checkout to the correct version

  ## Options

  The `repo` option defines the repo PID

  ## Return values

  :ok or tuple with {:error, reason}
  """
  @spec download(pid) :: :ok | {:error, String.t()}
  def download(repo) do
    Logger.info("Beginning to download the container repo..." )

    repo_options = Agent.get(repo, fn options -> options end)

    # TODO refactor into small functions
    case repo_options[:download_status] do
      nil ->
        try do
          repo_options = Map.merge(repo_options, %{download_status: :in_progress})
          Agent.update(repo, fn _ -> repo_options end)

          case GitHub.create(%{output_dir: repo_options[:output_dir], repo_url: GitHub.resolve_repo_url(repo_options[:container_repo]), branch: repo_options[:container_repo_branch]}) do
            {:ok, github} ->
              repo_options = Map.merge(repo_options, %{github: github})
              Agent.update(repo, fn _ -> repo_options end)

              case GitHub.clone(github) do
                :ok ->
                  case GitHub.checkout(github) do
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
        Logger.debug("Nothing to download")
        final_options = Agent.get(repo, fn options -> options end)
        if final_options[:download_error] == nil do
          :ok
        else
          {:error, final_options[:download_error]}
        end
    end
  end

  @doc """

  Method to determine the source repo from the source.json file

  ## Options

  The `repo` option defines the Repo PID

  The `source_commit_hash` option allows the consumer to override what commit hash is used when creating the SourceRepo

  ## Return Values

  tuple with {:ok, pid} or {:error, reason}

  """
  def get_source_repo(repo, source_commit_hash \\ nil) do
    repo_options = Agent.get(repo, fn options -> options end)
    if (repo_options[:source_repo] != nil) do
      repo_options[:source_repo]
    else
      source_info  = resolve_source_info(repo_options[:output_dir])

      if (source_info != nil) do
        source_repo_option = source_info["source_repo"]

        #if source_commit_hash was passed in, override what's in the source.json (if present)
        if (source_commit_hash != nil) do
          source_repo_branch_option = source_commit_hash
        else
          source_repo_branch_option = source_info["source_repo_branch"]
        end

        if (source_repo_option != nil) do
          #source_repo_branch_option will default to master if not present
          source_repo  = SourceRepo.create(%{repo: source_repo_option, repo_branch: source_repo_branch_option})
          repo_options = Map.merge(repo_options, %{source_repo: source_repo})
          Agent.update(repo, fn _ -> repo_options end)
          source_repo
        else
          {:error, "source.json is invalid! Make sure both the repo and default branch are specified"}
        end
      else
        {:error, "source.json is either missing or invalid!"}
      end
    end
  end

  @doc false
  # Method to retrieve the source info from source repository
  #
  ## Options
  #
  # The `github` option defines the github PID
  #
  # The `source_dir` option defines where the source files exist
  #
  ## Return Values
  #
  # Map
  #
  @spec resolve_source_info(String.t()) :: Map
  defp resolve_source_info(source_dir) do
    output_path = "#{source_dir}/source.json"

    if File.exists?(output_path) do
      Logger.info("Resolving source info from #{output_path}...")
      source_json = case File.read!(output_path) |> JSON.decode do
        {:ok, json} -> json
        {:error, reason} ->
          Logger.error("An error occurred parsing source JSON! #{inspect reason}")
          nil
      end
      source_json
    else
      nil
    end
  end

  # Evaluates a templated file and compars the evaluated version to what is
  # already there. If it's different, replace the existing file with the new
  # version.
  defp update_file(template_path, output_path, template_options, github, type) do
    Logger.info("Resolving #{inspect type} from template #{template_path}...")

    if File.exists?(template_path) do
      new_version = EEx.eval_file(template_path, template_options)

      if File.exists?(output_path) do
        if new_version != File.read!(output_path) do
          # The new version is different from the existing file, so we need to
          # replace the existing file's contents with the new contents.
          File.write!(output_path, new_version)
          GitHub.add(github, output_path)
          true
        else
          # The template is the same as what's already there
          Logger.info("New version of #{inspect type} matches contents at #{inspect output_path}. File not updated.")
          false
        end
      else
        Logger.info("#{inspect output_path} doesn't exist. Creating it with template contents.")
        File.write!(output_path, new_version)
        GitHub.add(github, output_path)
        true
      end
    else
      Logger.info("Template #{template_path} does not exist!")
      false
    end
  end

  @doc """
  Method to run the templating engine against the templated Dockerfile.  If changes are made to the
  Dockerfile, a git commit will be executed.

  ## Options

  The `repo` option defines deployment repo agent.

  The `template_options` option defines the list of variables needed to resolve the template.

  ## Return values

  boolean; true if a git commit was required
  """
  @spec resolve_dockerfile_template(pid, List) :: term
  def resolve_dockerfile_template(repo, template_options) do
    repo_options = Agent.get(repo, fn options -> options end)
    github = repo_options[:github]
    output_dir = repo_options[:output_dir]

    updated_dockerfile? = update_file(output_dir <> "/Dockerfile.eex", output_dir <> "/Dockerfile", template_options, github, :dockerfile)

    updated_install? = update_file(output_dir <> "/install.sh.eex", output_dir <> "/install.sh", template_options, github, :install_sh)

    updated_update? = update_file(output_dir <> "/update.sh.eex", output_dir <> "/update.sh", template_options, github, :update_sh)

    updated_dockerfile? || updated_install? || updated_update?
  end

  @doc """
  Method to run the templating engine against any service files in the repo.  If changes are made to the
  files, a git commit will be executed.

  ## Options

  The `repo` option defines deployment repo agent.

  The `template_options` option defines the list of variables needed to resolve the template.

  ## Return values

  boolean; true if a git commit was required
  """
  @spec resolve_service_file_templates(pid, List) :: term
  def resolve_service_file_templates(repo, template_options) do
    repo_options = Agent.get(repo, fn options -> options end)
    github = repo_options[:github]
    output_dir = repo_options[:output_dir]

    case File.ls("#{output_dir}") do
      {:ok, files} ->
        resolve_service_file(files, github, output_dir, template_options, false)
      {:error, reason} ->
        Logger.error("Unable to find any service files in #{output_dir}:  #{reason}!")
        false
    end
  end

  @doc """
  Method to execute a git commit and push for any pending changes.

  ## Options

  The `repo` option defines the repo PID

  ## Return values

  :ok or tuple with {:error, reason}
  """
  @spec checkin_pending_changes(pid, String.t()) :: :ok | {:error, String.t()}
  def checkin_pending_changes(repo, message) do
    repo_options = Agent.get(repo, fn options -> options end)
    github = repo_options[:github]

    case GitHub.commit(github, message) do
      :ok ->
        case GitHub.push(github) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Method to retrieve the currently associated etcd token

  ## Options

  The `repo` option defines deployment repo agent.

  ## Return values

  String
  """
  @spec get_etcd_token(pid) :: String.t()
  def get_etcd_token(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    output_dir = repo_options[:output_dir]

    etcd_json = "#{output_dir}/etcd.json"

    if File.exists?(etcd_json) do
      Logger.info("Retrieving the etcd token...")

      etcd_json = case JSON.decode(File.read!(etcd_json)) do
        {:ok, json} -> json
        {:error, reason} ->
          Logger.error("An error occurred parsing etcd JSON!  #{reason}")
          {}
      end
      etcd_json["token"]
    else
      Logger.info("No etcd JSON file is present in this repository!")
      ""
    end
  end

  @doc """
  Method to retrieve the currently associated etcd cluster PID

  ## Options

  The `repo` option defines deployment repo agent.

  ## Return values

  PID
  """
  @spec get_etcd_cluster(pid) :: pid
  def get_etcd_cluster(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    if (repo_options[:etcd_cluster] == nil) do
      token = get_etcd_token(repo)
      Logger.debug("Creating an EtcdCluster for token #{token}")
      case EtcdCluster.create(token) do
        {:ok, etcd_cluster} ->
          repo_options = Map.merge(repo_options, %{etcd_cluster: etcd_cluster})
          Agent.update(repo, fn _ -> repo_options end)
          etcd_cluster
        {:error, reason} ->
          Logger.error("Failed to create etcd cluster:  #{reason}")
          nil
      end
    else
      repo_options[:etcd_cluster]
    end
  end

  @doc """
  Method to retrieve all of the currently associated Units

  ## Options

  The `repo` option defines deployment repo agent.

  ## Return values

  List of the units that were generated
  """
  @spec get_units(pid) :: List
  def get_units(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    output_dir = repo_options[:output_dir]

    Logger.debug("Retrieving Units for repo #{output_dir}...")
    case File.ls("#{output_dir}") do
      {:ok, files} ->
        get_unit(files, output_dir, [])
      {:error, reason} ->
        Logger.error("there are no service files in #{output_dir}:  #{reason}!")
        []
    end
  end

  @doc """
  Method to retrieve the name of the associated Docker image repository

  ## Options

  The `repo` option defines deployment repo agent.

  ## Return values

  String
  """
  @spec get_docker_repo_name(pid) :: String.t()
  def get_docker_repo_name(repo) do
    repo_options = Agent.get(repo, fn options -> options end)
    if repo_options[:docker_repo_name] != nil do
      repo_options[:docker_repo_name]
    else
      output_dir = repo_options[:output_dir]

      if File.exists?("#{output_dir}/docker.json") do
        case JSON.decode(File.read!("#{output_dir}/docker.json")) do
          {:ok, json} -> json["docker_url"]
          {:error, reason} ->
            Logger.error("An error occurred parsing docker JSON!  #{inspect reason}")
            ""
        end
      else
        Logger.error("Unable to get the docker repo name, #{output_dir}/docker.json does not exist!")
        ""
      end
    end
  end

  def set_docker_repo_name(repo, docker_repo_name) do
    repo_options = Agent.get(repo, fn options -> options end)

    repo_options = Map.delete(repo_options, :docker_repo_name)
    repo_options = Map.put(repo_options, :docker_repo_name, docker_repo_name)
    Agent.update(repo, fn _ -> repo_options end)
  end

  @doc """
  Method to create a docker image from the Deployment repository and store it in a
  remote docker repository

  ## Options

  The `repo` option defines deployment repo agent.

  ## Return values

  :ok or {:error, reason}
  """
  @spec create_docker_image(pid, List) :: :ok | {:error, String.t()}
  def create_docker_image(repo, tags) do
    repo_options = Agent.get(repo, fn options -> options end)
    output_dir = repo_options[:output_dir]

    docker_repo_name = get_docker_repo_name(repo)

    case Docker.create(%{output_dir: output_dir, docker_repo_url: docker_repo_name}) do
      {:ok, docker} ->
        repo_options = Map.merge(repo_options, %{docker: docker})
        Agent.update(repo, fn _ -> repo_options end)
        try do
          case Docker.build(docker) do
            {:ok, image_id} ->
              if (image_id != nil && image_id != "") do
                repo_options = Map.merge(repo_options, %{image_id: image_id})
                Agent.update(repo, fn _ -> repo_options end)
                case Docker.tag(repo_options[:docker], image_id, tags) do
                  {:ok, _} ->
                    case Docker.push(repo_options[:docker]) do
                      {:ok, _} -> :ok
                      {:error, reason} -> {:error, reason}
                    end
                  {:error, reason} -> {:error, reason}
                end
              else
                {:error,"docker build failed to produce a valid image!"}
              end
            {:error, reason} -> {:error,reason}
          end
        after
          Docker.cleanup_image_cache(repo_options[:docker])
        end
      {:error, reason} -> {:error,reason}
    end
  end

  @doc false
  # Method to retrieve Fleet service Units.
  #
  ## Options
  #
  # The `[filename|remaining_files]` options defines the list of file names to review
  #
  # The `source_dir` options defines where the source files exist
  #
  # The `resolved_units` options defines the list of Units that have been found.
  #
  ## Return Values
  #
  # List of the Units that were generated
  #
  @spec get_unit(List, String.t(), List) :: term
  defp get_unit([filename|remaining_files], source_dir, resolved_units) do
    if String.ends_with?(filename, ".service") do
      output_path = "#{source_dir}/#{filename}"

      Logger.info("Resolving service file #{output_path}...")
      unitOptions = OpenAperture.Fleet.ServiceFileParser.parse(output_path)
      unit = %{
        "name" => filename,
        "options" => unitOptions
      }
      resolved_units = resolved_units ++ [unit]
    else
      Logger.debug("#{filename} is not a service file")
    end

    get_unit(remaining_files, source_dir, resolved_units)
  end

  @doc false
  # Method to retrieve Fleet service Unit.  Ends recursion
  #
  ## Options
  #
  # The `[]` options defines the list of file names to review
  #
  # The `source_dir` options defines where the source files exist
  #
  # The `resolved_units` options defines the list of Units that have been found.
  #
  ## Return Values
  #
  # List of the units that were generated
  #
  @spec get_unit(List, String.t(), List) :: term
  defp get_unit([], _, resolved_units) do
    resolved_units
  end

  @doc false
  # Method to resolve a Fleet service files.
  #
  ## Options
  #
  # The `[filename|remaining_files]` options defines the list of file names to review
  #
  # The `source_dir` options defines where the source files exist
  #
  # The `replacements` options defines which values should be replaced.
  #
  ## Return Values
  #
  # boolean; true if file was replaced and a commit add was performed)
  #
  @spec resolve_service_file(List, term, String.t(), Map, term) :: term
  defp resolve_service_file([filename|remaining_files], github, source_dir, replacements, units_commit_required) do
    if String.ends_with?(filename, ".service.eex") do
      template_path = "#{source_dir}/#{filename}"
      output_path = "#{source_dir}/#{String.slice(filename, 0..-5)}"

      Logger.info("Resolving service file #{output_path} from template #{template_path}...")
      service_file = EEx.eval_file "#{source_dir}/#{filename}", replacements

      file_is_identical = false
      if File.exists?(output_path) do
        existing_service_file = File.read!(output_path)
        if (service_file == existing_service_file) do
          file_is_identical = true
        end
      end

      unless (file_is_identical) do
        File.rm_rf(output_path)
        File.write!(output_path, service_file)
        GitHub.add(github, output_path)
        units_commit_required = true
      end
    end

    resolve_service_file(remaining_files, github, source_dir, replacements, units_commit_required)
  end

  @doc false
  #Method to resolve a Fleet service files.  Recursive end to the resolution.
  #
  ## Options
  #
  # The `[filename|remaining_files]` options defines the list of file names to review
  #
  # The `source_dir` options defines where the source files exist
  #
  # The `replacements` options defines which values should be replaced.
  #
  ## Return Values
  #
  # boolean; true if file was replaced and a commit add was performed)
  #
  @spec resolve_service_file(List, term, String.t(), Map, term) :: term
  defp resolve_service_file([], _, _, _, units_commit_required) do
    units_commit_required
  end
end
