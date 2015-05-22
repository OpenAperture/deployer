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
      {:earmark, github: "pragdave/earmark", tag: "v0.1.8", only: [:test]},    
      
      {:openaperture_messaging, git: "https://github.com/OpenAperture/messaging.git", ref: "8c51d099ec79473b23b3c385c072e6bf2219fba7", override: true},
      {:openaperture_manager_api, git: "https://github.com/OpenAperture/manager_api.git", ref: "5d442cfbdd45e71c1101334e185d02baec3ef945", override: true},
      {:openaperture_overseer_api, git: "https://github.com/OpenAperture/overseer_api.git", ref: "4d65d2295f2730bc74ec695c32fa0d2478158182", override: true},
      {:openaperture_fleet, git: "https://github.com/OpenAperture/fleet.git", ref: "2e63b7889c76f4d3b749146f3ebceb01702cf012", override: true},
      {:openaperture_workflow_orchestrator_api, git: "https://github.com/OpenAperture/workflow_orchestrator_api.git", ref: "b5b027d860c367d34ec116292fd8e7e4ca07623f", override: true},
      {:timex, "~> 0.12.9"},
      {:fleet_api, "~> 0.0.5"},

      #test dependencies
      {:exvcr, github: "parroty/exvcr", only: :test},
      {:meck, "0.8.2", only: :test}
    ]
  end
end
