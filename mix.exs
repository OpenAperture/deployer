defmodule OpenAperture.Deployer.Mixfile do
  use Mix.Project

  def project do
    [app: :openaperture_deployer,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps]
  end

  def application do
    [
      applications: [
        :logger,
        :amqp,
        :fleet_api,
        :openaperture_fleet,
        :openaperture_messaging, 
        :openaperture_manager_api, 
        :openaperture_overseer_api,
        :openaperture_workflow_orchestrator_api
      ],
      mod: {OpenAperture.Deployer, []}
    ]
  end

  defp deps do
    [
      {:ex_doc, github: "elixir-lang/ex_doc", only: [:test]},
      {:markdown, github: "devinus/markdown", only: [:test]},    
      
      {:openaperture_messaging, git: "https://github.com/OpenAperture/messaging.git", ref: "dc50470d0f0026718913535c901aee1562868dbf", override: true},
      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git", ref: "ae629a4127acceac8a9791c85e5a0d3b67d1ad16", override: true},
      {:openaperture_overseer_api, git: "https://github.com/OpenAperture/overseer_api.git", ref: "4d65d2295f2730bc74ec695c32fa0d2478158182", override: true},
      {:openaperture_fleet, git: "https://github.com/OpenAperture/fleet.git", ref: "23bd6ac60d79be9ad01e065603c34499705f3576", override: true},
      {:openaperture_workflow_orchestrator_api, git: "https://github.com/OpenAperture/workflow_orchestrator_api.git", ref: "d91664c4c6b21f889cba40a623c8893f043f59c8", override: true},
      {:timex, "~> 0.12.9"},
      {:fleet_api, "~> 0.0.4"},

      #test dependencies
      {:exvcr, github: "parroty/exvcr", only: :test},
      {:meck, "0.8.2", only: :test}
    ]
  end
end
