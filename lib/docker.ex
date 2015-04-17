defmodule OpenAperture.Deployer.Docker do
  @moduledoc """
  Contains the logic for interacting with Docker.
  """
  require Logger
  alias OpenAperture.Deployer.Docker

  @doc """
  Creates a `GenServer` representing Docker.

  ## Options

  The `docker_options` option defines the Map of configuration options that should be
  passed to Docker.  The following values are required:
    * :docker_repo_url - the docker repo URL (i.e. perceptivecloud/<repo>)
    * :output_dir - the directory containing the Dockerfile
    * :docker_host - the host machine/port to use for connection

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
  def create(docker_options) do
    if (docker_options[:docker_host] == nil) do
      host_ip = OpenApertureBuildServer.Servers.Docker.Hosts.next_available()
      if host_ip == nil do
        {:error, "Unable to load Docker hosts from the build cluster!"}
      else
        resolved_options = Map.merge(docker_options, %{docker_host: "tcp://#{host_ip}:2375"})
        Agent.start_link(fn -> resolved_options end)
      end
    else
      resolved_options = docker_options
      Agent.start_link(fn -> resolved_options end)
    end
  end

  @doc """
  Method to generate a new docker agent

  ## Options

  The `docker_options` option defines the Map of configuration options that should be
  passed to Docker.  The following values are required:
    * :docker_repo_url - the docker repo URL (i.e. perceptivecloud/<repo>)
    * :output_dir - the directory containing the Dockerfile
    * :docker_host - the host machine/port to use for connection

  ## Return Values

  pid
  """
  @spec create!(Map) :: pid
  def create!(docker_options) do
    case OpenApertureBuildServer.Agents.Docker.create(docker_options) do
      {:ok, docker} -> docker
      {:error, reason} -> raise "Failed to create OpenApertureBuildServer.Agents.Docker:  #{reason}"
    end
  end

 @doc """
  Method to cleanup any Docker cache files that were generated during OpenAperture builds
  ## Options
  The `docker` option defines the Docker agent against which the commands should be executed.
  ## Return values
  :ok or :error
  """
  def cleanup_cache(docker) do
    Logger.info ("Cleaning up docker cache...")

    docker_options = get_options(docker)
    Logger.info ("Stopping containers..")
    case  execute_docker_cmd(docker, "docker stop $(DOCKER_HOST=#{docker_options[:docker_host]} docker ps -a -q)") do
      {:ok, stdout, stderr} ->
        Logger.debug ("Successfully stopped containers")
        Logger.debug("#{stdout}\n#{stderr}")
      {:error, _, _} ->
        Logger.debug("No containers to stop")
    end

    #http://jimhoskins.com/2013/07/27/remove-untagged-docker-images.html
    Logger.info ("Cleaning up stopped containers...")
    case  execute_docker_cmd(docker, "docker rm $(DOCKER_HOST=#{docker_options[:docker_host]} docker ps -a -q)") do
      {:ok, stdout, stderr} ->
        Logger.debug ("Successfully cleaned up stopped containers")
        Logger.debug("#{stdout}\n#{stderr}")
      {:error, _, _} ->
        Logger.debug("No containers to clean up")
    end

    Logger.info ("Cleaning up untagged images...")
    case  execute_docker_cmd(docker, "docker rmi $(DOCKER_HOST=#{docker_options[:docker_host]} docker images | grep \"^<none>\" | awk \"{print $3}\")") do
      {:ok, stdout, stderr} ->
        Logger.debug ("Successfully cleaned up untagged images")
        Logger.debug("#{stdout}\n#{stderr}")
      {:error, _, _} ->
        Logger.debug("No untagged images to clean up")
    end

    #http://jonathan.bergknoff.com/journal/building-good-docker-images
    Logger.info ("Cleaning up remaining images...")
    case  execute_docker_cmd(docker, "docker rmi $(DOCKER_HOST=#{docker_options[:docker_host]} docker images -q)") do
      {:ok, stdout, stderr} ->
        Logger.debug ("Successfully cleaned up remaining images")
        Logger.debug("#{stdout}\n#{stderr}")
      {:error, _, _} ->
        Logger.debug("No remaining images to clean up")
    end

    :ok
  end

  @doc """
  Method to cleanup any cache associated with an image id

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  The `image_id` option defins the image to clean up

  ## Return values

  :ok
  """
  @spec cleanup_image_cache(pid, String.t()) :: :ok
  def cleanup_image_cache(docker, image_id \\ nil) do
    try do
      docker_options = get_options(docker)

      cond do
        image_id != nil -> cleanup_image(docker, image_id)
        docker_options[:image_id] != nil -> cleanup_image(docker, docker_options[:image_id])
        true ->
          Logger.error("You must specify an image id to cleanup!")
          :ok
      end
    rescue e in _ ->
      Logger.error("An error occurred cleaning up cache for image #{image_id}:  {inspect e}")
    end
  end

  @doc """
  Method to cleanup any dangling images that remain on the host

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  The `image_id` option defins the image to clean up

  ## Return values

  :ok
  """
  @spec cleanup_image(pid, String.t()) :: :ok
  def cleanup_image(docker, image_id) do
    Logger.info ("Cleaning up image #{image_id}...")

    #cleanup containers
    all_containers = get_containers(docker)
    image_containers = find_containers_for_image(docker, image_id, all_containers)
    cleanup_container(docker, image_containers)

    #cleanup the image
    case  execute_docker_cmd(docker, "docker rmi #{image_id}") do
      {:ok, _, _} -> Logger.debug("Successfully removed image #{image_id}")
      {:error, stdout, stderr} -> {:error, "An error occurred removing image #{image_id}:  #{stdout}\n#{stderr}"}
    end

    #cleanup dangling images
    cleanup_dangling_images(docker)
  end

  @doc """
  Method to cleanup any dangling images that remain on the host

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  ## Return values

  :ok
  """
  @spec cleanup_dangling_images(pid) :: :ok
  def cleanup_dangling_images(docker) do
    Logger.debug("Disabled dangling image cleanup")
    :ok
#    cleanup_exited_containers(docker)
#
#    #http://jonathan.bergknoff.com/journal/building-good-docker-images
#    Logger.info ("Cleaning up dangling images...")
#    dangling_images = case  execute_docker_cmd(docker, "docker images -q --filter \"dangling=true\"") do
#      {:ok, stdout, _stderr} ->
#        if String.length(stdout) > 0 do
#          images = String.split(stdout, "\n")
#          if images == nil || length(images) == 0 do
#            nil
#          else
#            Enum.reduce images, "", fn(image, dangling_images) ->
#              "#{dangling_images} #{image}"
#            end
#          end
#        else
#          nil
#        end
#      {:error, stdout, stderr} ->
#        Logger.debug("An error occurred retrieving dangling images:  #{stdout}\n#{stderr}")
#        nil
#    end
#
#    if dangling_images != nil do
#      Logger.debug("Removing the following dangling images:  #{dangling_images}")
#      case  execute_docker_cmd(docker, "docker rmi #{dangling_images}") do
#        {:error, stdout, stderr} -> Logger.debug("An error occurred deleting dangling images:  #{stdout}\n#{stderr}")
#        _ -> Logger.debug("Successfully cleaned up dangling images")
#      end
#    end
#    :ok
  end

  @doc """
  Method to remove all exited containers

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  ## Return values

  List of containers
  """
  @spec cleanup_exited_containers(pid) :: List
  def cleanup_exited_containers(docker) do
    Logger.info ("Cleaning up existed containers...")

    exited_containers = get_exited_containers(docker)
    if length(exited_containers) > 0 do
      container_list = Enum.reduce exited_containers, "docker rm ", fn(container, container_list) ->
        "#{container_list} #{container}"
      end

      case  execute_docker_cmd(docker, container_list) do
        {:ok, _, _} -> Logger.debug("Successfully removed the stopped containers")
        {:error, stdout, stderr} -> Logger.debug("An error occurred stopping containers:  #{stdout}\n#{stderr}")
      end
    else
      Logger.debug("There are no exited containers to cleanup")
    end

    :ok
  end

  @doc """
  Method to retrieve all exited containers

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  ## Return values

  List of containers
  """
  @spec get_exited_containers(pid) :: List
  def get_exited_containers(docker) do
    Logger.info ("Retrieving all exited containers...")
    case  execute_docker_cmd(docker, "docker ps -a | grep Exited | awk '{print$1}'") do
      {:ok, stdout, _} ->
        if String.length(stdout) == 0 do
          []
        else
          containers = String.split(stdout, "\n")
          Logger.debug("The following exited containers were found:  #{inspect containers}")
          containers
        end
      {:error, stdout, stderr} ->
        Logger.error("An error occurred retrieving the containers:  #{stdout}\n#{stderr}")
      []
    end
  end

  @doc """
  Method to stop and remove the running containers

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  The 2nd option defines the lits of containers to stop

  ## Return values

  :ok
  """
  @spec cleanup_container(pid, List) :: :ok
  def cleanup_container(docker, [container|remaining_containers]) do
    Logger.debug("Stopping container #{container}...")
    case  execute_docker_cmd(docker, "docker stop #{container}") do
      {:ok, _, _} -> Logger.debug("Successfully stopped container #{container}")
      {:error, stdout, stderr} -> Logger.debug("An error occurred stopping container #{container}:  #{stdout}\n#{stderr}")
    end

    Logger.debug("Removing container #{container}...")
    case  execute_docker_cmd(docker, "docker rm #{container}") do
      {:ok, _, _} ->
        Logger.debug("Successfully removed container #{container}")
      {:error, stdout, stderr} ->
        Logger.error("An error occurred removing container #{container}:  #{stdout}\n#{stderr}")
    end
    cleanup_container(docker, remaining_containers)
  end

  @doc """
  Method to stop and remove the running containers

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  The 2nd option defines the lits of containers to stop

  ## Return values

  :ok
  """
  @spec cleanup_container(pid, List) :: :ok
  def cleanup_container(_docker, []) do
    Logger.debug("Successfully cleaned up all containers")
    :ok
  end

  @doc """
  Method to find all of the containers running on a docker host

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  ## Return values

  List
  """
  @spec get_containers(pid) :: List
  def get_containers(docker) do
    Logger.info ("Retrieving all containers...")
    case  execute_docker_cmd(docker, "docker ps -aq") do
      {:ok, stdout, _} ->
        if String.length(stdout) == 0 do
          []
        else
          containers = String.split(stdout, "\n")
          Logger.debug("The following containers were found:  #{inspect containers}")
          containers
        end
      {:error, stdout, stderr} ->
        Logger.error("An error occurred retrieving the containers:  #{stdout}\n#{stderr}")
      []
    end
  end

  @doc """
  Method to parse through a list of containers to determine if any are running against an image

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  The `image_id` option defines the image to search for

  The `containers` option defines the containers to review

  ## Return values

  List
  """
  @spec find_containers_for_image(pid, String.t(), List) :: List
  def find_containers_for_image(docker, image_id, containers) do
    Logger.info ("Finding containers for image #{image_id}...")
    if containers == nil || length(containers) == 0 do
      []
    else
      inspect_cmd = Enum.reduce containers, "docker inspect", fn(container, inspect_cmd) ->
        "#{inspect_cmd} #{container}"
      end

      case execute_docker_cmd(docker, inspect_cmd) do
        {:ok, stdout, _} ->
          Enum.reduce JSON.decode!(stdout), [], fn(container_info, containers_for_image) ->
            if (container_info["Image"] != nil && String.contains?(container_info["Image"], image_id)) do
              Logger.debug("Container #{container_info["Id"]} is using image #{image_id}")
              containers_for_image ++ [container_info["Id"]]
            else
              containers_for_image
            end
          end
        {:error, stdout, stderr} ->
          Logger.error("An error occurred retrieving the containers:  #{stdout}\n#{stderr}")
          []
      end
    end
  end

  @doc """
  Method to execute a docker build against a specified Docker agent.

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  The `tag` option defines the tag that will be used for the generated Docker image.

  ## Return values

  {:ok, image_id} or {:error, reason}
  """
  @spec build(pid) :: {:ok, String.t()} | {:error, String.t()}
  def build(docker) do
    docker_options = get_options(docker)

    Logger.info ("Requesting docker build...")
    case  execute_docker_cmd(docker, "docker build --force-rm=true --no-cache=true --rm=true -t #{docker_options[:docker_repo_url]} .") do
      {:ok, stdout, stderr} ->

        # Step 0 : FROM ubuntu
        # ---> 9cbaf023786c
        # ...
        # Successfully built 87793b8f30d9
        # stdout will look like the above!

        # ["Step 0 : FROM ubuntu\n ---> 9cbaf023786c ... ---> 87793b8f30d9\n", "87793b8f30d9\n"]
        parsed_output = String.split(stdout, "Successfully built ")
        # "87793b8f30d9"
        image_id = List.last(Regex.run(~r/^[a-zA-Z0-9]*/, List.last(parsed_output)))
        Agent.update(docker, fn _ -> Map.put(docker_options, :image_id, image_id) end)
        Logger.debug ("Successfully built docker image #{image_id}\nDocker Build Output:  #{stdout}\n\n#{stderr}")
        {:ok, image_id}
      {:error, stdout, stderr} ->
        error_msg = "Failed to build docker image:\n#{stdout}\n\n#{stderr}"
        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  @doc """
  Method to execute add a docker tag against a specified Docker agent.

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  ## Return values

  {:ok, ""} | {:error, reason}
  """
  #@spec tag(pid) :: {:ok, String.t()} | {:error, String.t()}
  def tag(docker, image_id, [tag|remaining_tags]) do
    Logger.info ("Requesting docker tag #{tag}...")
    case execute_docker_cmd(docker, "docker tag --force=true #{image_id} #{tag}") do
      {:ok, result, docker_output} ->
        Logger.debug ("Successfully tagged docker image #{result}\nDocker Tag Output:  #{docker_output}")
        Docker.tag(docker, image_id,remaining_tags)
      {:error, result, docker_output} ->
        error_msg = "Failed to tag docker image #{image_id}:\n#{result}\n\n#{docker_output}"
        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  @doc """
  Method to execute add a docker tag against a specified Docker agent.

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  ## Return values

  :ok or :error
  """
  #@spec tag(pid) :: :ok | :error
  def tag(_, _, []) do
    {:ok, ""}
  end

  @doc """
  Method to execute a docker push against a specified Docker agent.

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  ## Return values

  :ok or {:error, error_msg}
  """
  @spec push(pid) :: :ok | :error
  def push(docker) do
    docker_options = get_options(docker)

    Logger.info ("Requesting docker push...")
    case  execute_docker_cmd(docker, "docker push #{docker_options[:docker_repo_url]}") do
      {:ok, image_id, docker_output} ->
        Logger.debug ("Successfully pushed docker image\nDocker Push Output:  #{docker_output}")
        {:ok, image_id}
      {:error, result, docker_output} ->
        error_msg = "Failed to push docker image:\n#{result}\n\n#{docker_output}"
        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  @doc """
  Method to execute a docker pull against a specified Docker agent.

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  The `image_name` option defines the image that should be retrieved

  ## Return values

  :ok or {:error, error_msg}
  """
  @spec pull(pid, String.t()) :: :ok | {:error, String.t()}
  def pull(docker, image_name) do
    Logger.info ("Requesting docker pull...")
    case  execute_docker_cmd(docker, "docker pull #{image_name}") do
      {:ok, _, docker_output} ->
        Logger.debug ("Successfully pulled docker image\nDocker Pull Output:  #{docker_output}")
        :ok
      {:error, result, docker_output} ->
        error_msg = "Failed to pull docker image:\n#{result}\n\n#{docker_output}"
        Logger.error(error_msg)
        {:error, error_msg}
    end
  end

  @doc """
  Method to execute a docker login against a specified Docker agent.

  ## Options

  The `docker` option defines the Docker agent against which the commands should be executed.

  ## Return values

  :ok or {:error, error_msg}
  """
  @spec login(pid) :: :ok | :error
  def login(docker) do
    Logger.info ("Requesting docker login...")
    case dockerhub_login(docker) do
      {_, 0} -> :ok
      {login_message, _} -> {:error, "Docker login has failed:  #{login_message}"}
    end
  end

  @doc false
  # Method to get options from a Docker agent.
  #
  ## Options
  #
  # The `docker` option defines Docker agent.
  #
  ## Return values
  #
  # Map
  #
  @spec get_options(pid) :: Map
  defp get_options(docker) do
    Agent.get(docker, fn options -> options end)
  end

  @doc false
  # Method to execute a Docker login to Docker Hub
  #
  ## Return values
  #
  # Map
  #
  @spec dockerhub_login(pid) :: {Collectable.t, exit_status :: non_neg_integer}
  defp dockerhub_login(docker) do
    docker_options = get_options(docker)
    if docker_options[:authenticated] == true do
      {"Login Successful", 0}
    else
      docker_cmd = "DOCKER_HOST=#{docker_options[:docker_host]} docker login -e=#{System.get_env("DOCKER_EMAIL")} -u=#{System.get_env("DOCKER_USER")} -p=#{System.get_env("DOCKER_PASSWORD")}"
      Logger.debug ("Executing Docker command:  #{docker_cmd}")
      System.cmd("/bin/bash", ["-c", docker_cmd], [{:stderr_to_stdout, true}])
    end
  end

  @doc false
  # Method to execute a Docker command.  Will wrap the command with a Docker login and store stdout and stderr
  #
  ## Return values
  #
  # Tuple with status, stdout and stderr {:ok, String.t(), String.t()}
  #
  @spec execute_docker_cmd(pid, String.t()) :: {:ok, String.t(), String.t()} | {:error, String.t(), String.t()}
  defp execute_docker_cmd(docker, docker_cmd) do
    docker_options = get_options(docker)

    case dockerhub_login(docker) do
      {_, 0} ->
        File.mkdir_p("/tmp/openaperture/docker")

        stdout_file = "/tmp/openaperture/docker/#{UUID.uuid1()}.log"
        stderr_file = "/tmp/openaperture/docker/#{UUID.uuid1()}.log"
        resolved_cmd = "DOCKER_HOST=#{docker_options[:docker_host]} #{docker_cmd} 2> #{stderr_file} > #{stdout_file}"

        Logger.debug ("Executing Docker command:  #{resolved_cmd}")
        try do
          case System.cmd("/bin/bash", ["-c", resolved_cmd], [{:cd, "#{docker_options[:output_dir]}"}]) do
            {stdout, 0} ->
              {:ok, read_output_file(stdout_file), read_output_file(stderr_file)}
            {stdout, _} ->
              {:error, read_output_file(stdout_file), read_output_file(stderr_file)}
          end
        after
          File.rm_rf(stdout_file)
          File.rm_rf(stderr_file)
        end
      {login_message, _} ->
        {:error, "Dockerhub login has failed.", login_message}
    end
  end

  @doc false
  # Method to read in a file and return contents
  #
  ## Return values
  #
  # String
  #
  @spec read_output_file(String.t()) :: String.t()
  defp read_output_file(docker_output_file) do
    if File.exists?(docker_output_file) do
      File.read!(docker_output_file)
    else
      Logger.error("Unable to read docker output file #{docker_output_file} - file does not exist!")
      ""
    end
  end
end
