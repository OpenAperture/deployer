defmodule OpenAperture.Deployer do
  @moduledoc "Defines the Deployer application."
  require Logger
  use     Application

  @doc """
  Starts the application.

  Returns `:ok` or `{:error, explanation}` otherwise.
  """
  @spec start(atom, [any]) :: :ok | {:error, String.t}
  def start(_type, _args) do
    Logger.info("Starting Deployer...")
    OpenAperture.Deployer.Supervisor.start_link
  end
end
