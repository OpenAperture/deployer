defmodule OpenAperture.Deployer.ECS do

  def deploy_task(aws, task_definition) do
    client = %AWS.Client{access_key_id: aws["access_key_id"],
                     secret_access_key: aws["secret_access_key"],
                     region: aws["region"],
                     endpoint: aws["endpoint"]}

    case register_task_definition(client, task_definition) do
      {:error, reason}          -> {:error, reason}
      {:ok, {_family, _revision, arn}} ->
        case update_service(client, aws, arn) do
          {:error, reason} -> {:error, reason}
          {:ok, output}    -> {:ok, output}
        end
    end
  end

  def register_task_definition(client, task_definition) do
    client
    |> AWS.ECS.register_task_definition(task_definition)
    |> handle_response
    |> case do
      {:error, reason} -> {:error, reason}
      {:ok, %{"taskDefinition" => task_def}} -> {:ok, {task_def["family"], task_def["revision"], task_def["taskDefinitionArn"]}}
    end
  end

  def update_service(client, aws, task_arn, use_full_task_count \\ false) do
    task_count = cond do
      use_full_task_count -> aws["ecs"]["task-count"]
      true                -> aws["ecs"]["task-count"] - 1
    end
    updated_service = %{"cluster" => aws["ecs"]["cluster"],
                        "desiredCount" => task_count,
                        "service" => aws["ecs"]["service"],
                        "taskDefinition" => task_arn}
    IO.puts "Setting #{aws["ecs"]["service"]} to count of #{task_count}"
    client
    |> AWS.ECS.update_service(updated_service)
    |> handle_response
    |> case do
      {:error, reason} -> {:error, reason}
      {:ok, _output}    -> monitor_service(client, aws, task_arn)
    end
  end

  def monitor_service(client, aws, task_arn) do
    service = aws["ecs"]["service"]
    task_count = aws["ecs"]["task-count"]
    cluster = aws["ecs"]["cluster"]
    client
    |> AWS.ECS.describe_services(%{"cluster" => cluster, "services" => [service]})
    |> handle_response
    |> case do
      {:error, reason}             -> {:error, reason}
      {:ok, %{"services" => services}} ->
        services
        |> Enum.find(fn s -> s["serviceName"] == service end)
        |> case do
          nil -> {:error, "Service #{service} not found in cluster #{cluster}"}
          %{"deployments" => deployments} ->
            deployments
            |> Enum.find(fn d -> d["taskDefinition"] == task_arn end)
            |> case do
              %{"status" => "PRIMARY", "runningCount" => rc, "desiredCount" => dc} when rc == dc and dc == task_count  ->
                {:ok, "Task #{task_arn} running in service #{service} on cluster #{cluster}"}
              %{"status" => "PRIMARY", "runningCount" => rc, "desiredCount" => dc} when rc == dc and dc == task_count - 1 ->
                update_service(client, aws, task_arn, true)
              %{"status" => "ACTIVE"} ->
                {:ok, "Task #{task_arn} running in service #{service} on cluster #{cluster}"}
              %{"status" => "PRIMARY"} ->
                :timer.sleep(5000)
                monitor_service(client, aws, task_arn)
              nil ->
                IO.inspect deployments
                {:error, "Task #{task_arn} not found in service #{service}"}
              _ ->
                {:error, "Task #{task_arn} not ACTIVE or PRIMARY in service #{service} on cluster #{cluster}"}
            end
        end
    end
  end

  def handle_response({:ok, output, _response}), do: {:ok, output}
  def handle_response({:error, reason, _response}), do: {:error, "Invalid status code returned from AWS: #{inspect reason}"}
  def handle_response({:error, reason}), do: {:error, reason}

end